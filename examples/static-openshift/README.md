# Example: Static OpenShift deployment

Deploys on Red Hat OpenShift with an auto-assigned Route, edge TLS, OpenShell protection, and SCC-compliant security context.
No `runAsUser` is set — OpenShift assigns an arbitrary UID from the namespace range.

## Prerequisites

- OpenShift 4.11+ with `restricted-v2` SCC available
- Internal image registry or external registry accessible from the cluster
- `claude-mate-api-key` Secret in the `claude-mate` project

## Create the API key Secret

```bash
oc new-project claude-mate
oc create secret generic claude-mate-api-key \
  --from-literal=ANTHROPIC_API_KEY=sk-ant-... \
  -n claude-mate
```

## Deploy

```bash
helm upgrade --install claude-mate-agent charts/claude-mate-agent \
  --namespace claude-mate --create-namespace \
  -f examples/static-openshift/values.yaml \
  --set image.repository=image-registry.openshift-image-registry.svc:5000/claude-mate/claude-mate-agent \
  --set image.tag=latest \
  --api-versions route.openshift.io/v1/Route
```

## Verify

```bash
oc get pods -n claude-mate
oc get route -n claude-mate
curl https://$(oc get route claude-mate-agent -n claude-mate -o jsonpath='{.spec.host}')/healthz
```
