# Example: FluxCD GitOps deployment

Deploys the Claude Mate Agent via Flux HelmRelease from a Helm repository.

## Prerequisites

- Flux v2 installed (`flux check`)
- A `HelmRepository` source pointing at the chart registry
- A Kubernetes Secret with the Anthropic API key in the `claude-mate` namespace

```bash
kubectl create namespace claude-mate
kubectl create secret generic claude-mate-api-key \
  --namespace claude-mate \
  --from-literal=ANTHROPIC_API_KEY=sk-ant-...
```

## Deploy

```bash
# 1 — Register the chart source
kubectl apply -f examples/fluxcd/HelmRepository.yaml

# 2 — Deploy the release
kubectl apply -f examples/fluxcd/HelmRelease.yaml

# 3 — Watch reconciliation
flux get helmrelease -n claude-mate claude-mate-agent
```

## Image automation

To let Flux update the image tag automatically from GHCR, add Flux image automation controllers and an `ImageRepository` + `ImagePolicy` + `ImageUpdateAutomation` resource. The `HelmRelease.yaml` `image.tag` field is the target for policy substitution.

## Secrets as Helm values

The `valuesFrom` block references an optional `claude-mate-helm-values` Secret. You can store sensitive values there (OTEL endpoint credentials, etc.) as a YAML payload. For the API key itself, use `claudeCode.apiKeySecretName` which reads the key from a separate Secret at runtime.

## Customise the chart version

Change `version` in the `HelmRelease` `chart.spec` to pin to an exact release:

```yaml
version: "0.3.1"
```

Remove the range and pin for production; use `>=0.x.x` only in pre-production environments where you want automatic patch updates.
