# Example: Gateway API HTTPRoute

Deploys an `HTTPRoute` that attaches to an existing shared `Gateway`. Works with any CNCF-conformant Gateway implementation: Envoy Gateway, NGINX Gateway Fabric, Cilium, or Azure Application Gateway for Containers.

## Prerequisites

- Kubernetes 1.28+ with Gateway API CRDs installed (`gateway.networking.k8s.io/v1`)
- An existing `Gateway` resource (update `gateway.parentRefs[0].name` and `namespace` to match)
- `claude-mate-api-key` Secret in the `claude-mate` namespace

## Install Gateway API CRDs (if not already installed)

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml
```

## Deploy

```bash
helm upgrade --install claude-mate-agent charts/claude-mate-agent \
  --namespace claude-mate --create-namespace \
  -f examples/gateway-api/values.yaml \
  --set image.repository=ghcr.io/your-org/claude-mate-agent \
  --set image.tag=latest \
  --set 'gateway.parentRefs[0].name=shared-gateway' \
  --set 'gateway.parentRefs[0].namespace=gateway-system' \
  --api-versions gateway.networking.k8s.io/v1/HTTPRoute \
  --api-versions gateway.networking.k8s.io/v1/Gateway
```

## Verify

```bash
kubectl get httproute -n claude-mate
kubectl get httproute claude-mate-agent -n claude-mate -o jsonpath='{.status.parents}'
```
