# Claude Sandboxes on Kubernetes

A *sandbox* is a one-shot, ephemeral, isolated Kubernetes Job that runs the Claude Code agent against a single task and disappears. It complements the always-on Deployment with a stronger isolation profile suited to untrusted prompts, contractor work, CI/CD triggers, or anything that should not share state with other runs.

## Design

```
                     ┌──────────────────────────────────────┐
   CI / kubectl ───▶ │           Sandbox Job                │
                     │  Job (restartPolicy: Never)          │
                     │  ├─ activeDeadlineSeconds: 1800      │
                     │  ├─ ttlSecondsAfterFinished: 3600    │
                     │  ├─ automountServiceAccountToken: ❌ │
                     │  ├─ runtimeClassName: gvisor (opt.)  │
                     │  ├─ NetworkPolicy: egress allow-list │
                     │  ├─ emptyDir /tmp                    │
                     │  └─ ephemeral /workspace             │
                     └──────────────────────────────────────┘
                                    │
                          Anthropic / Gateway
```

Each sandbox is independent — there is no shared filesystem, no shared network namespace, no shared service-account token, and no shared Job retry budget.

## Helm values

`charts/claude-mate-agent/values.yaml` exposes a complete `sandbox:` block. Highlights:

| Value | Default | Purpose |
|---|---|---|
| `sandbox.enabled` | `false` | Render the sandbox Job and NetworkPolicy |
| `sandbox.task` | `""` | Required prompt; chart `fail`s without it |
| `sandbox.teamMateRole` | `operations` | Persona for the run |
| `sandbox.runtimeClassName` | `""` | gVisor / Kata RuntimeClass name |
| `sandbox.maxDurationSeconds` | `1800` | Hard wall-clock cap |
| `sandbox.ttlSecondsAfterFinished` | `3600` | Auto-cleanup window |
| `sandbox.backoffLimit` | `0` | No retry |
| `sandbox.workspace.size` | `1Gi` | Ephemeral workspace volume |
| `sandbox.workspace.storageClass` | `""` | PVC storage class (empty = emptyDir) |
| `sandbox.networkPolicy.egress` | DNS + 0.0.0.0/0:443 | Tighten in production |
| `sandbox.resources` | 250m / 256Mi → 1000m / 1Gi | CPU/memory caps |

## Submitting a sandbox

The sandbox manifest uses `generateName`, so each submission creates a uniquely-named Job:

```bash
helm template claude-mate-agent charts/claude-mate-agent \
  -f examples/sandbox/values.yaml \
  --set sandbox.task="Find race conditions in container/app.py" \
  --set sandbox.teamMateRole=security \
  --set claudeCode.apiKeySecretName=claude-mate-api-key \
  | kubectl create -n claude-mate-sandbox -f -
```

To submit only the Job (no NetworkPolicy, no extra resources), use `--show-only`:

```bash
helm template ... --show-only templates/sandbox-job.yaml | kubectl create -f -
```

## Isolation levels

| Mechanism | Strength | Cost |
|---|---|---|
| Default runtime (containerd/CRI-O) | Process-level isolation only | Free, ships everywhere |
| gVisor (`runsc`) | User-space kernel, blocks most syscalls | ~10% perf overhead |
| Kata Containers | Per-pod lightweight VM | Higher memory floor, longer cold start |

Recommended baseline for untrusted prompts: **gVisor**. Recommended for regulated/multi-tenant workloads: **Kata** + dedicated nodes + PodSecurity `restricted`.

## Lifecycle and cleanup

1. `kubectl create` submits the Job → API server schedules a Pod
2. Pod pulls the image (cached on warm nodes), runs `agent --once` with the task
3. Agent emits structured logs to stdout, including `task_cost_summary`
4. Container exits → Job condition becomes `Complete` (or `Failed` on error/timeout)
5. After `ttlSecondsAfterFinished`, the Job controller deletes the Job and its Pod

`activeDeadlineSeconds` is enforced server-side; an over-running Pod is killed even if the container ignores `SIGTERM`.

## CI/CD integration

Two ready-made triggers ship with the repository:

- **GitHub Actions**: `.github/workflows/sandbox.yml` exposes a `workflow_dispatch` form (task prompt, persona, optional gVisor flag). It uses the runner's kubeconfig secret to create the Job, then streams logs back to the workflow.
- **GitLab CI**: `run:sandbox-agent` runs in the `on-demand` stage, accepts `CLAUDE_TASK` and `TEAM_MATE_ROLE` CI variables, and follows the same render-and-create flow.

Both rely on the chart being checked into the repository — they `helm template` against the local copy, so chart changes ship with the code that triggers them.

## Audit and cost

- Each sandbox Pod logs structured JSON to stdout (collected by the cluster log pipeline).
- The `task_cost_summary` line carries `cost_usd`, `duration_ms`, `role`, and pod identifiers — the same shape as on-demand mode, enabling unified dashboards.
- Sandbox runs carry the label `claude-mate.io/sandbox=true` and an OTEL resource attribute `claude.sandbox=true` for query filtering.

## What sandboxes are *not*

- Not a long-lived service — use the Deployment for `/healthz`, `/metrics`, persistent OTEL streams.
- Not a substitute for proper LLM auth — they still need a valid API key Secret.
- Not a substitute for prompt review — kernel isolation does not prevent the model from generating undesirable *output*; pair sandboxes with a content/policy gate at the gateway.

See [`examples/sandbox/README.md`](https://github.com/your-org/claude-mate-agent/tree/main/examples/sandbox) for runnable commands and tightening recipes.
