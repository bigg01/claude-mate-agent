# Monitoring

## Prometheus metrics

The `/metrics` endpoint is always available on the agent HTTP port. It returns Prometheus text format version 0.0.4. All metrics carry `namespace` and `pod` labels for multi-replica filtering.

| Metric | Type | Description |
|---|---|---|
| `claude_mate_agent_up` | Gauge | `1` while the process is running |
| `claude_mate_agent_start_timestamp_seconds` | Gauge | Unix timestamp of process start |
| `claude_mate_agent_uptime_seconds` | Gauge | Seconds since process start |
| `claude_mate_agent_http_requests_total` | Counter | Total HTTP requests received |
| `claude_mate_agent_task_executions_total{result}` | Counter | On-demand task executions labelled `result=ok\|error\|timeout` |
| `claude_mate_agent_task_cost_usd_total` | Counter | Cumulative Claude API cost in USD |
| `claude_mate_agent_task_last_duration_seconds` | Gauge | Wall-clock duration of the most recent task |

Cost and duration metrics are populated by on-demand (`--once`) executions. They are always present in the output (value `0` until a task runs), so Prometheus scrape rules never produce absent-metric gaps.

## Claude API cost tracking

Every on-demand task invokes the Claude CLI with `--output-format json`. The structured JSON response includes `cost_usd` and `duration_ms` fields which are:

1. Added to the Prometheus counters above.
2. Sent as OTEL counters when OTEL is enabled.
3. Included in the structured audit log event `task_cost_summary`.

### Pipeline cost report

Every pipeline execution emits a `task_cost_summary` log line. CI systems can surface this in job summaries.

**GitHub Actions** — add a step after the container run:

```yaml
- name: Cost summary
  if: always()
  run: |
    echo "### Claude API Cost" >> $GITHUB_STEP_SUMMARY
    docker logs ${{ steps.run.outputs.container-id }} 2>&1 \
      | grep '"message":"task_cost_summary"' \
      | python3 -c "
    import sys, json
    for line in sys.stdin:
        d = json.loads(line)
        print(f'- **Total cost:** \${d[\"cost_usd\"]:.6f} USD')
        print(f'- **Executions:** {d[\"task_executions\"]}')
    " >> $GITHUB_STEP_SUMMARY
```

**GitLab CI** — add to the `after_script` block and save as a dotenv artifact:

```yaml
after_script:
  - |
    docker logs $CONTAINER_ID 2>&1 | grep 'task_cost_summary' | \
      python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(f'CLAUDE_COST_USD={d[\"cost_usd\"]:.6f}')" \
      > cost.env
artifacts:
  reports:
    dotenv: cost.env
```

## Prometheus Operator ServiceMonitor

Enable in `values.yaml`:

```yaml
serviceMonitor:
  enabled: true
  labels:
    release: prometheus   # match your Prometheus Operator selector
  interval: 30s
  scrapeTimeout: 10s
```

The ServiceMonitor is only rendered when the `monitoring.coreos.com/v1/ServiceMonitor` API is present in the cluster.

## Grafana dashboards

Five pre-built dashboards live in `grafana/dashboards/` and auto-provision via `grafana/provisioning/dashboards/default.yml` whenever Grafana starts.

| Dashboard | UID | Purpose |
|---|---|---|
| `claude-mate-agent.json` | `claude-mate-agent` | Agent health, task execution, API cost summary, task performance |
| `dora-metrics.json` | `dora-metrics` | DORA — deployment frequency, lead time, change failure rate, MTTR |
| `anthropic-cost.json` | `anthropic-cost` | FinOps view: spend per persona / namespace, burn rate, projected monthly cost, budget %, leaderboard |
| `vllm.json` | `vllm-serving` | vLLM throughput, queue depth, KV-cache, TTFT/TPOT/e2e latency, token rate |
| `ollama.json` | `ollama-local` | Local Ollama health, LiteLLM proxy latency/throughput per model, Go runtime memory |

### Anthropic cost dashboard (FinOps)

Tracks live spend against a budget. Key panels:

- **Cost stats** — 1h / 24h / 7d totals, current burn rate (USD/h), 30-day projection.
- **Budget %** — coloured gauge keyed to the `monthly_budget_usd` dashboard variable (default `$1000`).
- **Burn rate by persona** — spot which role is consuming the budget.
- **Cost share donut** — 7-day proportional view across personas.
- **Cost-per-task trend** — surface expensive prompts: rising USD/task at constant task volume = longer or more expensive completions.
- **Leaderboard table** — namespace × role sorted by 7-day spend.

All panels use `claude_mate_agent_task_cost_usd_total` emitted by the agent on every on-demand task — no extra exporters needed.

### vLLM dashboard

Drives off vLLM's native `vllm:*` Prometheus metrics. Requires a Prometheus scrape job pointed at the vLLM OpenAI-compatible server (`/metrics` on the same port as the API). Panels:

- **Stats row** — requests running / waiting, GPU KV-cache usage, success / failure counts, preemptions.
- **Latency** — end-to-end (p50/p95/p99), time-to-first-token (TTFT), time-per-output-token (TPOT).
- **Throughput** — prompt + generation tokens/sec by model.
- **Queue depth** — running vs waiting over time.

Template variables `$model` and `$instance` let you filter across multi-model / multi-replica deployments.

### Ollama dashboard

Ollama's native Prometheus surface is sparse (mostly Go runtime + process metrics), so this dashboard blends three sources:

- **Ollama process** — Go memory, up/down state.
- **LiteLLM proxy** (sitting in front of Ollama) — request latency p50/p95/p99 per model, throughput by status code, token usage.
- **Agent's view** — `claude_mate_agent_task_*` filtered to confirm zero cost (local inference) and surface failures.

### Load a dashboard

**Docker Compose (local dev):** All dashboards auto-provision when you run `make compose-up` (or any of the overlay variants). Open Grafana at `http://localhost:3000`.

**Existing Grafana instance:** Import the JSON via **Dashboards → Import → Upload JSON file**.

**Grafana Operator / Helm provisioning:** Mount the JSON files via a ConfigMap and reference them in your `GrafanaDashboard` CR or the Grafana sidecar's provisioning volume.

### Prometheus scrape configs for the new dashboards

The vLLM and Ollama dashboards need additional scrape jobs. Templates are commented in `prometheus/prometheus.yml`:

```yaml
- job_name: ollama
  static_configs:
    - targets: ['ollama:11434']
- job_name: litellm
  static_configs:
    - targets: ['litellm:4000']
- job_name: vllm
  static_configs:
    - targets: ['vllm:8000']
```

### Dashboard variables

| Dashboard | Variable | Description |
|---|---|---|
| claude-mate-agent | `namespace` | Filter by Kubernetes namespace |
| claude-mate-agent | `pod` | Filter by individual pod (multi-select) |
| anthropic-cost | `namespace`, `role` | Filter by namespace and persona |
| anthropic-cost | `monthly_budget_usd` | Drives the budget % gauge (default `1000`) |
| vllm | `model`, `instance` | Filter by served model name and vLLM replica |
| ollama | `instance` | Filter by Ollama or LiteLLM instance |

## OpenTelemetry export

OTEL metrics export is disabled by default. Enable it per deployment:

```yaml
otel:
  enabled: true
  endpoint: "http://otel-collector.monitoring.svc.cluster.local:4318"
  exportIntervalMillis: 60000
```

When enabled, the agent:

1. Initialises a `MeterProvider` with `OTLPMetricExporter` (HTTP/protobuf) at startup
2. Exports metrics every `exportIntervalMillis` ms to the configured endpoint
3. Sets `OTEL_SERVICE_NAME` to the Helm release name and adds `k8s.namespace.name` and `k8s.pod.name` as resource attributes
4. In on-demand mode, calls `force_flush()` before exit to prevent data loss
5. Exports the `claude_mate_agent_task_cost_usd_total` counter so cost data reaches backends like Grafana Cloud, Datadog, or any OTEL-compatible collector

OTEL initialisation failure is logged as `ERROR` to stderr but does not prevent the agent from starting.

### Required environment variables (set by Helm chart)

| Variable | Example | Description |
|---|---|---|
| `OTEL_ENABLED` | `true` | Activates the OTEL provider |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://otel-collector:4318` | Collector HTTP endpoint |
| `OTEL_EXPORT_INTERVAL_MILLIS` | `60000` | Export interval in ms |
| `OTEL_SERVICE_NAME` | `claude-mate-agent` | Service name resource attribute |
| `OTEL_RESOURCE_ATTRIBUTES` | `k8s.namespace.name=...,k8s.pod.name=...` | Downward API values |

## OpenShell protection monitoring

When `openshell.enabled: true`, the Helm chart adds annotations to pods that enable the enterprise OpenShell protection layer. This layer:

- Restricts `kubectl exec` and shell access to approved break-glass workflows
- Captures session keystrokes and forwards them to the centralized audit trail
- Enforces session timeouts and inactivity limits

OpenShell session events (access granted, commands executed, session ended) should be collected by the enterprise security monitoring system alongside the agent metrics. Configure Alertmanager or your SIEM to alert on:

- Unexpected OpenShell session starts outside approved maintenance windows
- Commands executed via OpenShell that match security policy patterns
- OpenShell access denied events indicating potential unauthorized access attempts

## Alerting recommendations

Configure alerts for these conditions in Alertmanager or your enterprise tool:

| Condition | Expression |
|---|---|
| Pod unavailable | `kube_deployment_status_replicas_unavailable{namespace="claude-mate"} > 0` |
| Crash loop | `rate(kube_pod_container_status_restarts_total[15m]) > 0` |
| No scrape data | `absent(claude_mate_agent_up{namespace="claude-mate"})` |
| High task failure rate | `rate(claude_mate_agent_task_executions_total{result="error"}[5m]) > 0.1` |
| Task timeout spike | `increase(claude_mate_agent_task_executions_total{result="timeout"}[1h]) > 2` |
| Cost spike | `increase(claude_mate_agent_task_cost_usd_total[1h]) > 5` |
| Remote log sync failure | alert on `remote_log_sync_failed` audit event |
