# Getting Started

## Prerequisites

| Tool | Minimum version | Purpose |
|---|---|---|
| Docker or Podman | 24+ | Build and run the container locally |
| Helm | 3.14+ | Lint and render the chart |
| GNU Make | any | Convenience targets |
| Python 3 | any | Syntax check only (`py_compile`) |

## Build the image

```bash
make build
# Overrides: IMAGE=myrepo/claude-mate-agent TAG=1.0.0
```

The build has three stages. Expect a few minutes on first run due to PyInstaller compilation and the npm install of Claude Code. Subsequent builds use the Docker layer cache.

## Run the static server

```bash
make run
```

The agent starts on `http://localhost:8080`. Verify the endpoints:

```bash
curl http://localhost:8080/healthz    # {"status":"ok"}
curl http://localhost:8080/readyz     # {"ready":true}
curl http://localhost:8080/metrics    # Prometheus text format
```

## Run an on-demand task

Set the required environment variables in your shell, then:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
export CLAUDE_TASK="list the files in /opt/claude-mate and describe their purpose"
make run-once
```

The container runs `claude --print "$CLAUDE_TASK"`, emits structured JSON audit logs to stdout/stderr, and exits. A non-zero exit code means the task failed.

!!! warning "ANTHROPIC_API_KEY and CLAUDE_TASK are required"
    `make run-once` will exit immediately with an error message if either variable is unset.

## Lint and render the Helm chart

```bash
make lint          # helm lint
make render        # renders AKS + OpenShift + Gateway API variants
make render-aks
make render-openshift
make render-gateway
```

Always run `make render` after chart changes — `lint` does not exercise the capability-gated templates (Route, HTTPRoute).

## View all targets

```bash
make help
```

## Deploy to a cluster

```bash
# AKS
helm upgrade --install claude-mate-agent charts/claude-mate-agent \
  --namespace claude-mate --create-namespace \
  -f charts/claude-mate-agent/values-aks.yaml \
  --set image.repository=<your-registry>/claude-mate-agent \
  --set image.tag=<tag> \
  --set claudeCode.apiKeySecretName=claude-mate-api-key

# OpenShift
helm upgrade --install claude-mate-agent charts/claude-mate-agent \
  --namespace claude-mate --create-namespace \
  -f charts/claude-mate-agent/values-openshift.yaml \
  --set image.repository=<your-registry>/claude-mate-agent \
  --set image.tag=<tag> \
  --set claudeCode.apiKeySecretName=claude-mate-api-key
```

Create the API key secret before deploying:

```bash
kubectl create secret generic claude-mate-api-key \
  --from-literal=ANTHROPIC_API_KEY=sk-ant-... \
  --namespace claude-mate
```
