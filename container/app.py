#!/usr/bin/env python3
import argparse
import json
import os
import signal
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import guardrails


START_TIME = time.time()
REQUEST_COUNT = 0
SHUTTING_DOWN = False

# Accumulated task metrics — updated by run_once(), read by /metrics
TASK_EXECUTIONS = {"ok": 0, "error": 0, "timeout": 0}
TASK_COST_USD_TOTAL = 0.0
TASK_LAST_DURATION_SECONDS = 0.0

_otel_request_counter = None
_otel_task_counter = None
_otel_cost_counter = None
_otel_meter_provider = None

# ── Persona configuration ─────────────────────────────────────────────────────

# Persona files live at PERSONAS_DIR/<role>.md in the container.
# Override via env var for local development: PERSONAS_DIR=./container/personas
PERSONAS_DIR = os.getenv("PERSONAS_DIR", "/opt/claude-mate/personas")

# Allowed Claude Code tools per persona.
# None = no --allowedTools flag (all tools permitted).
# Security is read-only + Bash (for scanning); all others allow writes/edits.
_PERSONA_TOOLS: dict[str, str | None] = {
    "architect":  "Read,Write,Edit,MultilineEdit,Glob,Grep,LS,Bash,WebFetch,WebSearch",
    "security":   "Read,Glob,Grep,LS,Bash",
    "devops":     "Read,Write,Edit,MultilineEdit,Glob,Grep,LS,Bash,WebFetch",
    "sre":        "Read,Write,Edit,MultilineEdit,Glob,Grep,LS,Bash,WebFetch",
    "operations": None,
}


def _load_persona_prompt(role: str) -> str | None:
    """Return the system-prompt text for *role*, or None if no persona file exists."""
    path = os.path.join(PERSONAS_DIR, f"{role}.md")
    try:
        with open(path) as fh:
            content = fh.read().strip()
            return content if content else None
    except OSError:
        return None


def _build_claude_cmd(task: str, role: str) -> list[str]:
    """Build the claude CLI invocation for the given task and persona role."""
    cmd = ["claude", "--print", "--output-format", "json"]

    prompt = _load_persona_prompt(role)
    if prompt:
        cmd += ["--system-prompt", prompt]

    tools = _PERSONA_TOOLS.get(role)
    if tools:
        cmd += ["--allowedTools", tools]

    cmd.append(task)
    return cmd


# ── OTEL setup ────────────────────────────────────────────────────────────────

def _setup_otel():
    global _otel_request_counter, _otel_task_counter, _otel_cost_counter, _otel_meter_provider
    if os.getenv("OTEL_ENABLED", "").lower() != "true":
        return
    try:
        from opentelemetry import metrics as otel_metrics
        from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
        from opentelemetry.sdk.metrics import MeterProvider
        from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader

        reader = PeriodicExportingMetricReader(
            OTLPMetricExporter(),
            export_interval_millis=int(os.getenv("OTEL_EXPORT_INTERVAL_MILLIS", "60000")),
        )
        _otel_meter_provider = MeterProvider(metric_readers=[reader])
        otel_metrics.set_meter_provider(_otel_meter_provider)
        meter = otel_metrics.get_meter("claude-mate-agent", version=os.getenv("APP_VERSION", "dev"))
        _otel_request_counter = meter.create_counter(
            "claude_mate_agent_http_requests_total",
            description="HTTP requests handled by the agent",
        )
        _otel_task_counter = meter.create_counter(
            "claude_mate_agent_task_executions_total",
            description="On-demand Claude Code task executions",
        )
        _otel_cost_counter = meter.create_counter(
            "claude_mate_agent_task_cost_usd_total",
            description="Cumulative Claude API cost in USD",
            unit="USD",
        )
        log("INFO", "otel_initialized",
            endpoint=os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318"))
    except Exception as exc:
        log("ERROR", "otel_initialization_failed", error=str(exc))


# ── Logging ───────────────────────────────────────────────────────────────────

def log(level, message, **fields):
    record = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "severity": level,
        "component": os.getenv("APP_NAME", "claude-mate-agent"),
        "message": message,
        "namespace": os.getenv("POD_NAMESPACE", "unknown"),
        "pod": os.getenv("POD_NAME", "unknown"),
        "container": os.getenv("CONTAINER_NAME", "claude-mate-agent"),
        "correlation_id": os.getenv("CORRELATION_ID", ""),
    }
    record.update(fields)
    stream = sys.stderr if level in ("ERROR", "CRITICAL") else sys.stdout
    print(json.dumps(record, separators=(",", ":")), flush=True, file=stream)


# ── Output parsing ────────────────────────────────────────────────────────────

def _parse_claude_output(stdout):
    """Extract cost and duration from claude --output-format json response."""
    if not stdout:
        return 0.0, 0
    try:
        data = json.loads(stdout.strip())
        cost = float(data.get("cost_usd") or data.get("total_cost_usd") or 0)
        duration_ms = int(data.get("duration_ms") or 0)
        return cost, duration_ms
    except (json.JSONDecodeError, ValueError, TypeError):
        return 0.0, 0


# ── HTTP server ───────────────────────────────────────────────────────────────

class Handler(BaseHTTPRequestHandler):
    server_version = "ClaudeMateAgent/1.0"

    def do_GET(self):
        global REQUEST_COUNT
        REQUEST_COUNT += 1
        if _otel_request_counter is not None:
            _otel_request_counter.add(1, {"path": self.path})

        if self.path in ("/healthz", "/livez"):
            self.respond_json(200, {"status": "ok"})
            return

        if self.path == "/readyz":
            status = 503 if SHUTTING_DOWN else 200
            self.respond_json(status, {"ready": not SHUTTING_DOWN})
            return

        if self.path == "/metrics":
            self._serve_metrics()
            return

        self.respond_json(404, {"error": "not_found"})

    def _serve_metrics(self):
        ns = os.getenv("POD_NAMESPACE", "unknown")
        pod = os.getenv("POD_NAME", "unknown")
        role = os.getenv("TEAM_MATE_ROLE", "operations")
        labels = f'namespace="{ns}",pod="{pod}",role="{role}"'

        lines = [
            "# HELP claude_mate_agent_up Agent process availability.",
            "# TYPE claude_mate_agent_up gauge",
            f"claude_mate_agent_up{{{labels}}} 1",
            "# HELP claude_mate_agent_start_timestamp_seconds Unix timestamp when the agent process started.",
            "# TYPE claude_mate_agent_start_timestamp_seconds gauge",
            f"claude_mate_agent_start_timestamp_seconds{{{labels}}} {START_TIME:.3f}",
            "# HELP claude_mate_agent_uptime_seconds Agent process uptime in seconds.",
            "# TYPE claude_mate_agent_uptime_seconds gauge",
            f"claude_mate_agent_uptime_seconds{{{labels}}} {int(time.time() - START_TIME)}",
            "# HELP claude_mate_agent_http_requests_total HTTP requests handled by the agent.",
            "# TYPE claude_mate_agent_http_requests_total counter",
            f"claude_mate_agent_http_requests_total{{{labels}}} {REQUEST_COUNT}",
            "# HELP claude_mate_agent_task_executions_total On-demand task executions by result.",
            "# TYPE claude_mate_agent_task_executions_total counter",
        ]
        for result, count in TASK_EXECUTIONS.items():
            lines.append(
                f'claude_mate_agent_task_executions_total{{result="{result}",{labels}}} {count}'
            )
        lines += [
            "# HELP claude_mate_agent_task_cost_usd_total Cumulative Claude API cost in USD.",
            "# TYPE claude_mate_agent_task_cost_usd_total counter",
            f"claude_mate_agent_task_cost_usd_total{{{labels}}} {TASK_COST_USD_TOTAL:.6f}",
            "# HELP claude_mate_agent_task_last_duration_seconds Duration of the most recent task in seconds.",
            "# TYPE claude_mate_agent_task_last_duration_seconds gauge",
            f"claude_mate_agent_task_last_duration_seconds{{{labels}}} {TASK_LAST_DURATION_SECONDS:.3f}",
            "",
        ]
        body = "\n".join(lines)
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.end_headers()
        self.wfile.write(body.encode("utf-8"))

    def respond_json(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        log("INFO", "http_request", client=self.client_address[0], path=self.path)


# ── CI audit context ──────────────────────────────────────────────────────────

def _ci_audit_context():
    if os.getenv("GITHUB_ACTIONS") == "true":
        return dict(
            ci_system="github_actions",
            ci_project=os.getenv("GITHUB_REPOSITORY", ""),
            ci_run=os.getenv("GITHUB_RUN_ID", ""),
            ci_job=os.getenv("GITHUB_JOB", ""),
            ci_commit=os.getenv("GITHUB_SHA", ""),
            ci_branch=os.getenv("GITHUB_REF_NAME", ""),
            ci_runner=os.getenv("RUNNER_NAME", ""),
            ci_user=os.getenv("GITHUB_ACTOR", ""),
            ci_workflow=os.getenv("GITHUB_WORKFLOW", ""),
            teammate_role=os.getenv("TEAM_MATE_ROLE", "unknown"),
        )
    return dict(
        ci_system="gitlab_ci",
        ci_project=os.getenv("CI_PROJECT_PATH", ""),
        ci_run=os.getenv("CI_PIPELINE_ID", ""),
        ci_job=os.getenv("CI_JOB_ID", ""),
        ci_commit=os.getenv("CI_COMMIT_SHA", ""),
        ci_branch=os.getenv("CI_COMMIT_REF_NAME", ""),
        ci_runner=os.getenv("CI_RUNNER_ID", ""),
        ci_user=os.getenv("GITLAB_USER_LOGIN", ""),
        ci_workflow="",
        teammate_role=os.getenv("TEAM_MATE_ROLE", "unknown"),
    )


# ── On-demand execution ───────────────────────────────────────────────────────

def run_once():
    global TASK_EXECUTIONS, TASK_COST_USD_TOTAL, TASK_LAST_DURATION_SECONDS
    _setup_otel()
    ctx = _ci_audit_context()
    role = os.getenv("TEAM_MATE_ROLE", "operations")
    work_dir = os.getenv("WORK_DIR", os.getcwd())

    # Log persona context so the audit trail includes what skills are active
    persona_prompt_loaded = _load_persona_prompt(role) is not None
    log("INFO", "agent_started", operating_mode="on-demand",
        role=role, persona_loaded=persona_prompt_loaded,
        tools_restricted=_PERSONA_TOOLS.get(role) is not None,
        work_dir=work_dir, **ctx)

    task = os.getenv("CLAUDE_TASK", "").strip()
    if not task:
        log("ERROR", "on_demand_agent_execution_failed", operating_mode="on-demand",
            error="CLAUDE_TASK environment variable is required", result="error", **ctx)
        raise ValueError("CLAUDE_TASK is required for on-demand execution")

    # ── Guardrails: pre-flight checks ─────────────────────────────────────
    # Each block is a no-op when its env flag is unset, so the entire section
    # has negligible cost when guardrails.enabled=false at the chart level.

    cost_ok, cost_reason = guardrails.check_cost_budget()
    if not cost_ok:
        TASK_EXECUTIONS["error"] += 1
        log("ERROR", "guardrail_blocked", type="cost", reason=cost_reason,
            role=role, **ctx)
        raise RuntimeError(f"cost guardrail blocked task: {cost_reason}")

    intent_ok, intent_hits = guardrails.check_intent(task, role)
    if intent_hits and not intent_ok:
        TASK_EXECUTIONS["error"] += 1
        log("ERROR", "guardrail_blocked", type="intent",
            patterns=intent_hits, role=role, **ctx)
        raise RuntimeError("intent guardrail blocked task")
    if intent_hits:
        log("WARN", "guardrail_warning", type="intent",
            patterns=intent_hits, role=role, **ctx)

    task, input_hits, input_blocked = guardrails.scrub_input(task)
    if input_blocked:
        TASK_EXECUTIONS["error"] += 1
        log("ERROR", "guardrail_blocked", type="input",
            patterns=input_hits, role=role, **ctx)
        raise RuntimeError("input guardrail blocked task")
    if input_hits:
        log("WARN", "guardrail_redacted", type="input",
            patterns=input_hits, count=len(input_hits), role=role, **ctx)

    workspace_patterns = guardrails.write_claudeignore(work_dir)
    if workspace_patterns > 0:
        log("INFO", "guardrail_workspace_ignore_written",
            patterns=workspace_patterns, path=os.path.join(work_dir, ".claudeignore"),
            role=role, **ctx)

    timeout = int(os.getenv("CLAUDE_TIMEOUT_SECONDS", "1800"))
    cmd = _build_claude_cmd(task, role)
    log("INFO", "on_demand_agent_execution", operating_mode="on-demand",
        result="starting", timeout_seconds=timeout, role=role, **ctx)
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=work_dir,
        )
        # Output guardrail runs before parsing — the parser sees redacted text
        # if a leak pattern lands inside a JSON value. Cost / duration may
        # round to 0 in that case; this is the correct safety/utility tradeoff.
        stdout_text, output_hits, output_blocked = guardrails.scrub_output(proc.stdout)
        if output_hits:
            log("WARN", "guardrail_redacted" if not output_blocked else "guardrail_blocked",
                type="output", patterns=output_hits, count=len(output_hits),
                role=role, **ctx)

        cost_usd, duration_ms = _parse_claude_output(stdout_text)
        duration_seconds = duration_ms / 1000.0

        result_label = "ok" if proc.returncode == 0 and not output_blocked else "error"
        TASK_EXECUTIONS[result_label] += 1
        TASK_COST_USD_TOTAL += cost_usd
        TASK_LAST_DURATION_SECONDS = duration_seconds

        # Post-task cost guardrail: log threshold breaches (record_cost is a
        # no-op when GUARDRAILS_COST_ENABLED is unset).
        for event_name, event_data in guardrails.record_cost(cost_usd).items():
            log("WARN", f"guardrail_cost_{event_name}",
                **event_data, role=role, **ctx)

        if _otel_task_counter is not None:
            _otel_task_counter.add(1, {"result": result_label, "role": role})
        if _otel_cost_counter is not None and cost_usd > 0:
            _otel_cost_counter.add(cost_usd, {"result": result_label, "role": role})

        if proc.returncode == 0:
            log("INFO", "on_demand_agent_execution", operating_mode="on-demand",
                result="ok", exit_code=proc.returncode, role=role,
                cost_usd=round(cost_usd, 6), duration_seconds=round(duration_seconds, 3), **ctx)
        else:
            log("ERROR", "on_demand_agent_execution_failed", operating_mode="on-demand",
                result="error", exit_code=proc.returncode, role=role,
                cost_usd=round(cost_usd, 6), duration_seconds=round(duration_seconds, 3), **ctx)
            raise RuntimeError(f"claude exited with code {proc.returncode}")

    except subprocess.TimeoutExpired:
        TASK_EXECUTIONS["timeout"] += 1
        if _otel_task_counter is not None:
            _otel_task_counter.add(1, {"result": "timeout", "role": role})
        log("ERROR", "on_demand_agent_execution_failed", operating_mode="on-demand",
            error="claude execution timed out", result="timeout", role=role,
            timeout_seconds=timeout, **ctx)
        raise
    except Exception as exc:
        if "claude exited" not in str(exc):
            TASK_EXECUTIONS["error"] += 1
            if _otel_task_counter is not None:
                _otel_task_counter.add(1, {"result": "error", "role": role})
        log("ERROR", "on_demand_agent_execution_failed", operating_mode="on-demand",
            error=str(exc), result="error", role=role, **ctx)
        raise
    finally:
        if _otel_meter_provider is not None:
            _otel_meter_provider.force_flush()
        log("INFO", "task_cost_summary",
            cost_usd=round(TASK_COST_USD_TOTAL, 6),
            task_executions=TASK_EXECUTIONS,
            role=role, operating_mode="on-demand", **ctx)
        log("INFO", "agent_stopped", operating_mode="on-demand", role=role, **ctx)


# ── Static server ─────────────────────────────────────────────────────────────

def serve():
    global SHUTTING_DOWN
    _setup_otel()
    port = int(os.getenv("PORT", "8080"))
    role = os.getenv("TEAM_MATE_ROLE", "operations")
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)

    def stop(signum, frame):
        global SHUTTING_DOWN
        SHUTTING_DOWN = True
        log("INFO", "shutdown_signal_received", signal=signum)
        server.shutdown()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    try:
        ver = subprocess.check_output(["claude", "--version"], text=True, timeout=10).strip()
    except Exception:
        ver = "unknown"

    persona_prompt_loaded = _load_persona_prompt(role) is not None
    log("INFO", "agent_started", operating_mode=os.getenv("OPERATING_MODE", "static"),
        port=port, claude_code_version=ver, role=role,
        persona_loaded=persona_prompt_loaded,
        tools_restricted=_PERSONA_TOOLS.get(role) is not None)
    server.serve_forever()
    log("INFO", "agent_stopped")


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--once", action="store_true",
                        help="run one on-demand pipeline execution and exit")
    args = parser.parse_args()

    if args.once:
        try:
            run_once()
        except Exception:
            return 1
        return 0

    serve()
    return 0


if __name__ == "__main__":
    sys.exit(main())
