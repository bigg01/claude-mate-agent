# Claude Sandbox Example

Run a single Claude Code task in an ephemeral, isolated Kubernetes Job — no long-lived pod, no shared state, strict network egress, auto-cleanup.

## What you get

| Constraint | Value |
|---|---|
| Lifecycle | One-shot Kubernetes `Job` (`restartPolicy: Never`) |
| Wall-clock cap | `activeDeadlineSeconds` (default 30 min) |
| Cleanup | `ttlSecondsAfterFinished` (default 1 h) |
| Filesystem | Read-only root; `emptyDir` `/tmp` + ephemeral `/workspace` |
| Network | Sandbox-only `NetworkPolicy`, no ingress, egress allow-list |
| Kernel isolation | Optional `runtimeClassName: gvisor` / `kata` |
| Service-account token | Not mounted (`automountServiceAccountToken: false`) |

## Submit a sandbox

```bash
# One-liner: render and apply
helm template claude-mate-agent charts/claude-mate-agent \
  -f examples/sandbox/values.yaml \
  --set sandbox.task="Review for OWASP Top 10 issues" \
  --set sandbox.teamMateRole=security \
  --set claudeCode.apiKeySecretName=claude-mate-api-key \
  --set image.repository=ghcr.io/your-org/claude-mate-agent \
  --set image.tag=latest \
  | kubectl create -n claude-mate-sandbox -f -
```

The `generateName` field assigns a unique name; multiple submissions create distinct Jobs.

## Watch a sandbox run

```bash
# Find the most recent sandbox job
JOB=$(kubectl get jobs -n claude-mate-sandbox \
  -l claude-mate.io/sandbox=true \
  --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{.items[-1].metadata.name}')

# Stream logs (waits for the pod if not started yet)
kubectl logs -n claude-mate-sandbox -f job/$JOB

# Wait for completion
kubectl wait --for=condition=Complete -n claude-mate-sandbox \
  --timeout=30m job/$JOB
```

## Kernel-level isolation

If your cluster has gVisor installed:

```bash
# Verify the RuntimeClass exists
kubectl get runtimeclass gvisor

# Submit with gVisor sandboxing
helm template ... \
  --set sandbox.runtimeClassName=gvisor \
  | kubectl create -n claude-mate-sandbox -f -
```

Kata Containers (KVM-based isolation) works the same way:

```bash
--set sandbox.runtimeClassName=kata-qemu
```

## Tightening egress

The default egress allow-list permits HTTPS to any public IP. For production, tighten it to your specific LLM provider:

```yaml
sandbox:
  networkPolicy:
    egress:
      - to:
          - namespaceSelector:
              matchLabels:
                kubernetes.io/metadata.name: kube-system
        ports:
          - protocol: UDP
            port: 53
      # Restrict to in-cluster LiteLLM
      - to:
          - namespaceSelector:
              matchLabels:
                kubernetes.io/metadata.name: litellm
        ports:
          - protocol: TCP
            port: 4000
```

## CI/CD integration

The repository ships ready-to-use sandbox triggers:

- **GitHub Actions**: `.github/workflows/sandbox.yml` — `workflow_dispatch` input → Kubernetes Job → log stream.
- **GitLab CI**: `run:sandbox-agent` stage in `.gitlab-ci.yml` — same flow.

Both require the runner to have `kubectl` configured against the target cluster (kubeconfig in CI secret).

## Cleanup

Jobs auto-delete `ttlSecondsAfterFinished` seconds after completion. Force-delete in-flight:

```bash
kubectl delete job -n claude-mate-sandbox -l claude-mate.io/sandbox=true
```
