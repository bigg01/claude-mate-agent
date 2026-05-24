# Example: Full observability stack

Enables both the Prometheus Operator `ServiceMonitor` and the OpenTelemetry OTLP metric exporter.

## Prerequisites

- Prometheus Operator installed with a `Prometheus` resource that selects `release: prometheus`
- An OTEL Collector reachable at `http://otel-collector.monitoring.svc.cluster.local:4318`
  (adjust the endpoint in `values.yaml` if your collector is elsewhere)

## Deploy

```bash
helm upgrade --install claude-mate-agent charts/claude-mate-agent \
  --namespace claude-mate --create-namespace \
  -f examples/monitoring/values.yaml \
  --set image.repository=ghcr.io/your-org/claude-mate-agent \
  --set image.tag=latest \
  --set claudeCode.apiKeySecretName=claude-mate-api-key
```

## Verify Prometheus scraping

```bash
kubectl get servicemonitor -n claude-mate
# Check Prometheus targets UI — claude-mate/claude-mate-agent should be Up
```

## Verify OTEL export

```bash
kubectl logs -n claude-mate -l app.kubernetes.io/name=claude-mate-agent | grep otel_initialized
# Expected: {"message":"otel_initialized","endpoint":"http://otel-collector..."}
```

## Available metrics

| Metric | Type |
|---|---|
| `claude_mate_agent_up` | Gauge |
| `claude_mate_agent_start_timestamp_seconds` | Gauge |
| `claude_mate_agent_uptime_seconds` | Gauge |
| `claude_mate_agent_http_requests_total` | Counter |
| `claude_mate_agent_task_executions_total{result}` | Counter (OTEL) |
