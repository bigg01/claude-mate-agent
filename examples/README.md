# Examples

Ready-to-use configurations for common deployment patterns.

| Example | Description |
|---|---|
| [static-kubernetes](static-kubernetes/) | Minimal static deployment on plain Kubernetes with Nginx Ingress |
| [static-openshift](static-openshift/) | Static deployment on OpenShift with Route and SCC compliance |
| [gateway-api](gateway-api/) | HTTPRoute via Kubernetes Gateway API (Envoy Gateway / NGINX Gateway Fabric) |
| [on-demand-gitlab](on-demand-gitlab/) | GitLab CI job snippet for on-demand Claude Code tasks |
| [on-demand-github](on-demand-github/) | Reusable GitHub Actions workflow for on-demand tasks |
| [monitoring](monitoring/) | Full observability stack: ServiceMonitor + OTEL export enabled |
| [mcp-deploy](mcp-deploy/) | Drive `kubernetes-mcp-server` from Claude Code (or any MCP client) for interactive deploys |

Each example folder contains a `values.yaml` override file and a `README.md` with deployment steps.
All examples assume the base chart at `charts/claude-mate-agent` and override only the values that differ.
