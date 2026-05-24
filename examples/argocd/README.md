# Example: ArgoCD GitOps deployment

Deploys the Claude Mate Agent via ArgoCD from the Helm chart in this repository.

## Prerequisites

- ArgoCD installed in your cluster (`kubectl get ns argocd`)
- The target namespace `claude-mate` does not need to exist — `CreateNamespace=true` in the `syncOptions` creates it
- A Kubernetes Secret named `claude-mate-api-key` in the `claude-mate` namespace containing the Anthropic API key:

```bash
kubectl create secret generic claude-mate-api-key \
  --namespace claude-mate \
  --from-literal=ANTHROPIC_API_KEY=sk-ant-...
```

## Deploy

```bash
# Apply the Application manifest
kubectl apply -f examples/argocd/Application.yaml

# Watch sync status
argocd app get claude-mate-agent
argocd app sync claude-mate-agent   # trigger manual sync if auto-sync is not yet reconciled
```

## Customise the source

Edit `Application.yaml` before applying:

| Field | What to change |
|---|---|
| `source.repoURL` | Your fork or internal mirror |
| `source.targetRevision` | Pin to a tag (e.g. `v1.0.0`) for production |
| `source.helm.valueFiles` | Use `values-openshift.yaml` for OpenShift |
| `source.helm.values` | Override `image.tag`, `replicaCount`, etc. |
| `destination.server` | Change for remote cluster |

## Handling HPA

The `ignoreDifferences` block on `/spec/replicas` prevents ArgoCD from reverting the replica count when HPA is active. Remove it if you do not use the HPA.

## RBAC

If your ArgoCD project restricts destination namespaces or cluster resources, add `claude-mate` to the allowed destinations and permit the resource kinds used by the chart (`Deployment`, `Service`, `ServiceMonitor`, `HPA`, `PDB`, `NetworkPolicy`, `ServiceAccount`, `Role`, `RoleBinding`).
