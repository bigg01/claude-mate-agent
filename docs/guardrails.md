# Guardrails

Five independently-toggled controls that sit in front of and behind the Claude Code CLI invocation. Each is opt-in; with `guardrails.enabled: false` the agent emits no extra env vars and pays zero runtime cost.

## Family overview

| # | Family | What it does | When it fires |
|---|---|---|---|
| 1 | **Cost** | Refuses tasks once the rolling-hour spend reaches the cap; logs an audit event on per-task overage | Pre-flight (refuse) + post-task (alert) |
| 2 | **Input** | Scans `CLAUDE_TASK` for sensitive patterns; redacts or blocks | Pre-flight, before `claude` is invoked |
| 3 | **Output** | Scans `claude`'s stdout for sensitive patterns; redacts or blocks before logging / parsing | Post-`claude`, before audit log |
| 4 | **Workspace** | Writes `.claudeignore` in `WORK_DIR` from a configured pattern list | Once per task, before `claude` runs |
| 5 | **Intent** | Per-persona regex denylist on the task prompt; blocks or warns | Pre-flight |

Each fires independently — you can enable any subset.

## Built-in pattern groups

Input + output scrubbing share the same library:

| Group | Catches |
|---|---|
| `api-keys` | `sk-ant-…` · `sk-or-v1-…` · `sk-…` (OpenAI) · `AKIA…` (AWS) · `AIza…` (Google) · `ghp_…` (GitHub) · `glpat-…` (GitLab) · `xox[abprs]-…` (Slack) |
| `credentials` | PEM private-key blocks (`-----BEGIN … PRIVATE KEY-----`) |
| `pii` | US SSN, Visa / MC / Amex card numbers |
| `network` | RFC 1918 IPv4 (10/8, 172.16/12, 192.168/16) |

Custom patterns go in `extraPatterns` as regex strings. Invalid regex is silently dropped (the test suite covers this).

## Minimal example

```yaml
# values-guardrails.yaml
guardrails:
  enabled: true

  cost:
    enabled: true
    maxUsdPerTask: 0.50
    maxUsdPerHour: 5.00

  input:
    enabled: true
    patterns: [api-keys, credentials]
    action: redact

  output:
    enabled: true
    patterns: [api-keys, credentials]
    action: redact

  workspace:
    enabled: true
    ignorePatterns:
      - "**/.env*"
      - "**/secrets/**"
      - "**/.aws/credentials"

  intent:
    enabled: true
    action: block
    perPersona:
      security:
        deny: ["\\bdeploy\\b", "rm\\s+-rf"]
```

Apply with:

```bash
helm upgrade --install claude-mate-agent charts/claude-mate-agent \
  --namespace claude-mate -f values-guardrails.yaml
```

## Modes — redact vs. block

| Mode | Behaviour | When to choose |
|---|---|---|
| `redact` | Replaces matched substrings with `[REDACTED]`; task continues | Sensitive content is *expected* and should not leak to the model / logs |
| `block` | Refuses the task entirely; emits `guardrail_blocked` audit event | Sensitive content is *unexpected* and the task should not run at all |

Start with `redact` on input/output — easy to reason about, no false-positive task rejections. Move sub-patterns to `block` once you've watched real traffic.

## Audit events

Every guardrail fire emits a structured JSON event:

```json
{"severity":"WARN", "message":"guardrail_redacted",
 "type":"input", "patterns":["sk-ant-[A-Za-z0-9_\\-]{20,}"],
 "count":1, "role":"security", "pod":"agent-abc", "namespace":"claude-mate"}
```

Event names:

| Event | Meaning |
|---|---|
| `guardrail_redacted` | Pattern matched, content was redacted, task continued |
| `guardrail_blocked` | Pattern matched, task refused |
| `guardrail_warning` | Intent denylist matched, action=warn, task continued |
| `guardrail_cost_per_task_exceeded` | Single task cost > `maxUsdPerTask` |
| `guardrail_cost_hourly_exceeded` | Rolling-hour total ≥ `maxUsdPerHour` |
| `guardrail_workspace_ignore_written` | `.claudeignore` materialised in `WORK_DIR` |

All events ship with `role`, pod identifiers, and CI context — they aggregate into the same Grafana dashboards as DORA + audit data.

## Iterating on what works

The intent of shipping all five as toggles is so you can A/B different combinations against real traffic before settling on a posture. A pragmatic path:

1. **Week 1** — `guardrails.enabled=true` with everything `enabled: false` except logging via env var observation. Watch for surprising prompts.
2. **Week 2** — Turn on `cost.enabled` + `input.enabled` (redact mode). Cheapest, almost no false-positive risk.
3. **Week 3** — Add `output.enabled` (redact). Verify nothing user-facing breaks (the audit log will show redactions).
4. **Week 4** — Add `workspace.enabled` if you mount real repositories. The `.claudeignore` defaults catch the common landmines.
5. **Week 5+** — Tune `intent.enabled` per persona using the prompts you actually see. Start with `action: warn` so nothing breaks; promote to `block` once you trust the regex.

## What guardrails are *not*

- **Not a substitute for a gateway.** For multi-agent / multi-tenant deployments, put Kong AI Gateway or LiteLLM in front (see [LLM Gateway](llm-gateway.md)) — guardrails belong at the choke point, not duplicated in every pod.
- **Not a prompt-injection defender.** These controls look for *data* leakage, not for adversarial prompts. Pair with a policy gate at the gateway for prompt-injection defence.
- **Not a replacement for the persona tool allow-list.** The `security` persona is read-only at the *tool* level; guardrails are an additional content-aware layer on top.

See [`requirement.md` §28](https://github.com/bigg01/claude-mate-agent/blob/main/requirement.md#28-guardrail-requirements) for the formal requirements.
