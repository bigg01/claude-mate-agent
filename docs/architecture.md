# Architecture

## Two-layer design

The container runs two distinct programs:

```
┌──────────────────────────────────────────────────────────────────┐
│  agent  (compiled Python — container/app.py)                     │
│                                                                  │
│  • ThreadingHTTPServer on $PORT (default 8080)                  │
│  • /healthz  /livez  /readyz  /metrics                          │
│  • SIGTERM handler → sets SHUTTING_DOWN, drains readiness       │
│  • Optional OTEL MeterProvider (OTEL_ENABLED=true)              │
│  • In --once mode: subprocess.run(["claude","--print",$TASK])   │
└───────────────────────────────────┬─────────────────────────────┘
                                    │ subprocess
┌───────────────────────────────────▼─────────────────────────────┐
│  claude  (Node.js — @anthropic-ai/claude-code)                  │
│                                                                  │
│  • Reads ANTHROPIC_API_KEY from environment                     │
│  • Executes the task, writes output to stdout                   │
│  • Exits 0 on success, non-zero on failure                      │
└─────────────────────────────────────────────────────────────────┘
```

The agent binary is the only process for the pod's lifetime in static mode. In on-demand mode it spawns `claude` as a child process, captures the result, and exits.

## Operating modes

### Static mode (default)

The pod runs indefinitely as a Kubernetes `Deployment`. The HTTP server handles probes from kubelet, exposes metrics to Prometheus, and logs a startup event with the detected Claude Code version.

Graceful shutdown sequence:

1. Kubernetes sends `SIGTERM`
2. `preStop` hook sleeps 5 s (allows kube-proxy to drain connections)
3. SIGTERM handler sets `SHUTTING_DOWN = True`
4. `/readyz` returns `503` — load balancer removes the pod
5. `server.shutdown()` — in-flight requests complete
6. Process exits cleanly

### On-demand mode (`--once`)

Used in GitLab CI pipeline jobs. The full execution sequence:

1. `_setup_otel()` — initialise OTEL if enabled
2. Validate `CLAUDE_TASK` is non-empty
3. Emit `agent_started` audit log with full GitLab context (project, pipeline, job, commit, branch, runner, user)
4. `subprocess.run(["claude", "--print", task], timeout=CLAUDE_TIMEOUT_SECONDS)`
5. Emit `on_demand_agent_execution` with `result=ok|error|timeout`
6. `_otel_meter_provider.force_flush()` — ensures OTEL data is exported before exit
7. Emit `agent_stopped`
8. Exit `0` (success) or `1` (failure)

## Observability

```
/metrics ──► Prometheus scrape (ServiceMonitor)
              │
              └── Grafana dashboards / Alertmanager

OTEL_ENABLED=true
              │
              └── OTLPMetricExporter ──► OTEL Collector ──► SIEM / Observability platform
```

Prometheus and OTEL expose the same metrics. OTEL adds `k8s.namespace.name` and `k8s.pod.name` as resource attributes so metrics can be correlated across the observability platform.

## Helm chart routing

The chart generates exactly one routing resource per deployment:

```
ingress.enabled: true   →  networking.k8s.io/v1  Ingress
route.enabled: true     →  route.openshift.io/v1  Route     (requires Route API)
gateway.enabled: true   →  gateway.networking.k8s.io/v1  HTTPRoute  (requires Gateway API)
```

Route and HTTPRoute templates are guarded by `.Capabilities.APIVersions.Has` so the same chart renders on plain Kubernetes (no Route API present) and OpenShift without needing different flag sets.

## Security boundary

```
NetworkPolicy (ingress)              NetworkPolicy (egress)
     │                                      │
     ▼                                      ▼
  Pod ──► ServiceAccount (least-privilege RBAC: get/list/watch pods)
     │
     └── readOnlyRootFilesystem: true
         /tmp emptyDir (writable — PyInstaller extraction + Claude config)
         ANTHROPIC_API_KEY from Secret (never in image or logs)
```

The root filesystem is read-only. The only writable path is `/tmp`, which is mounted as an emptyDir. `HOME=/tmp` redirects Node.js's `os.homedir()` so Claude Code writes its config there rather than failing under an arbitrary UID.
