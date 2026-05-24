# Helm Chart

The chart is at `charts/claude-mate-agent`. Use `values-aks.yaml` or `values-openshift.yaml` as overlays on top of the base `values.yaml`.

## Key values

### Image

```yaml
image:
  repository: registry.example.com/claude-mate-agent
  tag: "0.1.0"
  pullPolicy: IfNotPresent
```

### Claude Code

```yaml
claudeCode:
  apiKeySecretName: ""        # name of the Secret holding ANTHROPIC_API_KEY
  apiKeySecretKey: "ANTHROPIC_API_KEY"
  task: ""                    # static CLAUDE_TASK for static mode (optional)
  timeoutSeconds: 1800        # on-demand subprocess timeout
```

Create the Secret before deploying:

```bash
kubectl create secret generic claude-mate-api-key \
  --from-literal=ANTHROPIC_API_KEY=sk-ant-... \
  -n claude-mate
```

Then set `claudeCode.apiKeySecretName: claude-mate-api-key`.

### Routing — choose one

=== "Ingress (AKS)"

    ```yaml
    ingress:
      enabled: true
      className: ""
      hosts:
        - host: claude-mate-agent.example.com
          paths:
            - path: /
              pathType: Prefix
      tls: []
    ```

=== "OpenShift Route"

    ```yaml
    route:
      enabled: true
      host: ""         # leave empty for OpenShift auto-assignment
      tls:
        enabled: true
        termination: edge
        insecureEdgeTerminationPolicy: Redirect
    ```

=== "Gateway API"

    Attach to an existing Gateway:

    ```yaml
    gateway:
      enabled: true
      createGateway: false
      parentRefs:
        - name: my-gateway
          namespace: gateway-system
      hostnames:
        - claude-mate-agent.example.com
    ```

    Create a dedicated Gateway:

    ```yaml
    gateway:
      enabled: true
      createGateway: true
      gatewayClassName: nginx
      hostnames:
        - claude-mate-agent.example.com
      listeners:
        - name: http
          port: 80
          protocol: HTTP
    ```

### Scaling and availability

```yaml
replicaCount: 2

autoscaling:
  enabled: false
  minReplicas: 2
  maxReplicas: 5
  targetCPUUtilizationPercentage: 70

podDisruptionBudget:
  enabled: true
  minAvailable: 1

terminationGracePeriodSeconds: 30

topologySpreadConstraints: []   # set to spread across zones for HA
```

### Monitoring

```yaml
serviceMonitor:
  enabled: false          # set true when Prometheus Operator is installed
  labels: {}              # labels to match your Prometheus selector
  interval: 30s
  scrapeTimeout: 10s

otel:
  enabled: false
  endpoint: "http://otel-collector.monitoring.svc.cluster.local:4318"
  exportIntervalMillis: 60000
```

### OpenShell protection

```yaml
openshell:
  enabled: true
  protectionMode: restricted
  annotations:
    openshell.io/protection: restricted
    openshell.io/audit: enabled
```

When enabled, the annotations are added to the pod template, triggering the enterprise OpenShell admission webhook.

### Network policy

```yaml
networkPolicy:
  enabled: true
  ingressNamespaceSelector: {}   # {} = allow from any namespace; restrict to monitoring/ingress ns
  egress: []                     # [] = allow all egress; restrict per environment
```

## Rendering locally

```bash
# AKS
helm template claude-mate-agent charts/claude-mate-agent \
  -f charts/claude-mate-agent/values-aks.yaml

# OpenShift (pass Route API so the Route template renders)
helm template claude-mate-agent charts/claude-mate-agent \
  -f charts/claude-mate-agent/values-openshift.yaml \
  --api-versions route.openshift.io/v1/Route

# Gateway API
helm template claude-mate-agent charts/claude-mate-agent \
  --set gateway.enabled=true \
  --api-versions gateway.networking.k8s.io/v1/HTTPRoute \
  --api-versions gateway.networking.k8s.io/v1/Gateway
```

Or use `make render` to run all three.

## Upgrade and rollback

```bash
helm upgrade claude-mate-agent charts/claude-mate-agent \
  --namespace claude-mate \
  --set image.tag=<new-tag>

# rollback to previous revision
helm rollback claude-mate-agent 0 --namespace claude-mate
```

`revisionHistoryLimit: 5` is set in the Deployment, keeping the last five ReplicaSets available for rollback.
