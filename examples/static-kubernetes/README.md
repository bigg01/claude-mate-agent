# Example: Static Kubernetes deployment

Deploys two replicas with Nginx Ingress, HPA (2–5 replicas), PDB, and a restricted NetworkPolicy.

## Prerequisites

- Kubernetes cluster with `ingress-nginx` installed
- `claude-mate-api-key` Secret in the `claude-mate` namespace

## Create the API key Secret

```bash
kubectl create namespace claude-mate
kubectl create secret generic claude-mate-api-key \
  --from-literal=ANTHROPIC_API_KEY=sk-ant-... \
  --namespace claude-mate
```

## Deploy

```bash
helm upgrade --install claude-mate-agent charts/claude-mate-agent \
  --namespace claude-mate --create-namespace \
  -f examples/static-kubernetes/values.yaml \
  --set image.repository=ghcr.io/your-org/claude-mate-agent \
  --set image.tag=latest
```

## Verify

```bash
kubectl get pods -n claude-mate
kubectl get ingress -n claude-mate
curl https://claude-mate-agent.example.com/healthz
curl https://claude-mate-agent.example.com/metrics
```
