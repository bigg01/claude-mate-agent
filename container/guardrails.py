"""Guardrails — optional, opt-in input/output/cost/intent/workspace controls.

All five guardrail families are independently gated by env vars. When a family
is disabled (the default), its public function is an early-return no-op with
negligible overhead. Helm renders the env vars only when the corresponding
values.yaml flags are true, so a chart install with `guardrails.enabled: false`
sends no GUARDRAILS_* vars to the container at all.

Public API:
    enabled()                       — True if any guardrail family is active
    check_cost_budget()             — pre-flight cost cap (refuse new task)
    record_cost(cost_usd)           — post-task cost accounting + events
    scrub_input(prompt)             — redact / block sensitive prompt content
    scrub_output(stdout)            — redact / block sensitive response content
    check_intent(prompt, role)      — per-persona denylist match
    write_claudeignore(work_dir)    — emit .claudeignore from env-configured patterns
"""
import os
import re
import time
from collections import deque


# ── Built-in pattern groups ──────────────────────────────────────────────────
# Each group is a list of (compiled-at-runtime) regex strings. Patterns are
# chosen for high precision; loose patterns (e.g. bare emails) must be opted
# into via `extraPatterns` so the default config doesn't redact benign content.

_PATTERN_GROUPS: dict[str, list[str]] = {
    "api-keys": [
        r"sk-ant-[A-Za-z0-9_\-]{20,}",                # Anthropic
        r"sk-or-v1-[A-Za-z0-9]{32,}",                  # OpenRouter
        r"sk-[A-Za-z0-9]{32,}",                        # OpenAI / generic
        r"AKIA[0-9A-Z]{16}",                           # AWS access key
        r"AIza[0-9A-Za-z_\-]{35}",                     # Google
        r"ghp_[A-Za-z0-9]{36}",                        # GitHub PAT
        r"glpat-[A-Za-z0-9_\-]{20}",                   # GitLab PAT
        r"xox[abprs]-[A-Za-z0-9-]{10,}",               # Slack
    ],
    "credentials": [
        r"-----BEGIN [A-Z ]+PRIVATE KEY-----[\s\S]*?-----END [A-Z ]+PRIVATE KEY-----",
    ],
    "pii": [
        r"\b\d{3}-\d{2}-\d{4}\b",                                              # US SSN
        r"\b(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|3[47][0-9]{13})\b",     # CC (Visa/MC/Amex)
    ],
    "network": [
        r"\b10\.(?:[0-9]{1,3}\.){2}[0-9]{1,3}\b",
        r"\b172\.(?:1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}\b",
        r"\b192\.168\.[0-9]{1,3}\.[0-9]{1,3}\b",
    ],
}


# ── Helpers ──────────────────────────────────────────────────────────────────

def _flag(name: str) -> bool:
    return os.getenv(name, "").lower() == "true"


def _csv(name: str) -> list[str]:
    raw = os.getenv(name, "")
    return [x.strip() for x in raw.split(",") if x.strip()]


def _compile_patterns(groups: list[str], extras: list[str]) -> list[re.Pattern]:
    out: list[re.Pattern] = []
    for g in groups:
        for p in _PATTERN_GROUPS.get(g, []):
            out.append(re.compile(p))
    for raw in extras:
        try:
            out.append(re.compile(raw))
        except re.error:
            # Silently ignore invalid user-supplied regex; logging is the
            # caller's responsibility once they discover the regex doesn't fire.
            continue
    return out


def _scrub(text: str, patterns: list[re.Pattern], action: str) -> tuple[str, list[str], bool]:
    """Return (possibly-redacted text, list of pattern strings that matched,
    blocked-flag). action='redact' replaces matches with [REDACTED];
    action='block' returns blocked=True and leaves text unchanged."""
    if not text or not patterns:
        return text, [], False
    hits: list[str] = []
    blocked = False
    for p in patterns:
        if p.search(text):
            hits.append(p.pattern)
            if action == "block":
                blocked = True
            else:
                text = p.sub("[REDACTED]", text)
    return text, hits, blocked


# ── Cost guardrail ───────────────────────────────────────────────────────────

class _CostWindow:
    """Sliding 1-hour cost ledger. Thread-safe enough for the single-shot
    `--once` invocation; not safe for the static server (which is fine — the
    static server never runs claude tasks)."""

    def __init__(self) -> None:
        self._ledger: deque[tuple[float, float]] = deque()

    def _prune(self, now: float) -> None:
        cutoff = now - 3600
        while self._ledger and self._ledger[0][0] < cutoff:
            self._ledger.popleft()

    def total(self, now: float | None = None) -> float:
        now = now if now is not None else time.time()
        self._prune(now)
        return sum(c for _, c in self._ledger)

    def add(self, cost: float, now: float | None = None) -> None:
        now = now if now is not None else time.time()
        self._ledger.append((now, cost))


_COST_WINDOW = _CostWindow()


def check_cost_budget() -> tuple[bool, str]:
    """Pre-flight check before invoking claude. Return (allowed, reason)."""
    if not _flag("GUARDRAILS_COST_ENABLED"):
        return True, ""
    cap_raw = os.getenv("GUARDRAILS_COST_MAX_USD_PER_HOUR", "0") or "0"
    try:
        cap = float(cap_raw)
    except ValueError:
        return True, ""
    if cap <= 0:
        return True, ""
    spent = _COST_WINDOW.total()
    if spent >= cap:
        return False, f"hourly cost cap reached: ${spent:.4f} >= ${cap:.2f}"
    return True, ""


def record_cost(cost_usd: float) -> dict:
    """Post-task: add to ledger and return any threshold-exceeded events."""
    events: dict[str, dict] = {}
    if not _flag("GUARDRAILS_COST_ENABLED"):
        return events
    if cost_usd > 0:
        _COST_WINDOW.add(cost_usd)
    try:
        per_task = float(os.getenv("GUARDRAILS_COST_MAX_USD_PER_TASK", "0") or "0")
    except ValueError:
        per_task = 0
    if per_task > 0 and cost_usd > per_task:
        events["per_task_exceeded"] = {
            "limit_usd": per_task,
            "actual_usd": round(cost_usd, 6),
        }
    try:
        hourly = float(os.getenv("GUARDRAILS_COST_MAX_USD_PER_HOUR", "0") or "0")
    except ValueError:
        hourly = 0
    if hourly > 0:
        spent = _COST_WINDOW.total()
        if spent >= hourly:
            events["hourly_exceeded"] = {
                "limit_usd": hourly,
                "rolling_hour_usd": round(spent, 6),
            }
    return events


# ── Input / output scrubbing ─────────────────────────────────────────────────

def scrub_input(prompt: str) -> tuple[str, list[str], bool]:
    if not _flag("GUARDRAILS_INPUT_ENABLED"):
        return prompt, [], False
    patterns = _compile_patterns(
        _csv("GUARDRAILS_INPUT_PATTERNS"),
        _csv("GUARDRAILS_INPUT_EXTRA_PATTERNS"),
    )
    action = os.getenv("GUARDRAILS_INPUT_ACTION", "redact").lower()
    return _scrub(prompt, patterns, action)


def scrub_output(stdout: str) -> tuple[str, list[str], bool]:
    if not _flag("GUARDRAILS_OUTPUT_ENABLED"):
        return stdout, [], False
    patterns = _compile_patterns(
        _csv("GUARDRAILS_OUTPUT_PATTERNS"),
        _csv("GUARDRAILS_OUTPUT_EXTRA_PATTERNS"),
    )
    action = os.getenv("GUARDRAILS_OUTPUT_ACTION", "redact").lower()
    return _scrub(stdout, patterns, action)


# ── Intent guardrail ─────────────────────────────────────────────────────────

def check_intent(prompt: str, role: str) -> tuple[bool, list[str]]:
    """Per-role denylist. GUARDRAILS_INTENT_DENY_<ROLE> is a csv of regex
    patterns (case-insensitive). Returns (allowed, matched-patterns)."""
    if not _flag("GUARDRAILS_INTENT_ENABLED"):
        return True, []
    key = f"GUARDRAILS_INTENT_DENY_{role.upper()}"
    raw = os.getenv(key, "")
    if not raw:
        return True, []
    hits: list[str] = []
    for pat in (p.strip() for p in raw.split(",") if p.strip()):
        try:
            if re.search(pat, prompt, re.IGNORECASE):
                hits.append(pat)
        except re.error:
            continue
    if not hits:
        return True, []
    action = os.getenv("GUARDRAILS_INTENT_ACTION", "block").lower()
    return (action != "block"), hits


# ── Workspace guardrail ──────────────────────────────────────────────────────

def write_claudeignore(work_dir: str) -> int:
    """Write .claudeignore in work_dir from env-configured patterns. Returns
    the number of patterns written (0 if disabled or empty)."""
    if not _flag("GUARDRAILS_WORKSPACE_ENABLED"):
        return 0
    patterns = _csv("GUARDRAILS_WORKSPACE_IGNORE_PATTERNS")
    if not patterns:
        return 0
    try:
        path = os.path.join(work_dir, ".claudeignore")
        with open(path, "w") as fh:
            fh.write("# Auto-generated by claude-mate-agent guardrails — do not edit.\n")
            for p in patterns:
                fh.write(p + "\n")
        return len(patterns)
    except OSError:
        return 0


# ── Master check ─────────────────────────────────────────────────────────────

def enabled() -> bool:
    return _flag("GUARDRAILS_ENABLED")
