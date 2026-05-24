# Component Examples

Ready-to-use `values.yaml` overlays for common deployment scenarios. Each example lives under `examples/` with a `README.md` explaining prerequisites and verification steps.

## Static: Kubernetes (AKS / nginx Ingress)

**Path:** `examples/static-kubernetes/`

Deploys two replicas with an nginx Ingress, HPA (2–10 replicas), PodDisruptionBudget (`minAvailable: 1`), and a restricted NetworkPolicy.

```bash
helm upgrade --install claude-mate-agent charts/claude-mate-agent \
  --namespace claude-mate --create-namespace \
  -f examples/static-kubernetes/values.yaml \
  --set image.repository=ghcr.io/your-org/claude-mate-agent \
  --set image.tag=latest \
  --set claudeCode.apiKeySecretName=claude-mate-api-key \
  --set ingress.hosts[0].host=claude-mate.example.com \
  --set ingress.tls[0].hosts[0]=claude-mate.example.com \
  --set ingress.tls[0].secretName=claude-mate-tls
```

Key values set by this example:

| Value | Setting |
|---|---|
| `replicaCount` | `2` |
| `ingress.enabled` | `true` |
| `ingress.className` | `nginx` |
| `autoscaling.enabled` | `true` |
| `podDisruptionBudget.enabled` | `true` |
| `networkPolicy.enabled` | `true` |

---

## Static: OpenShift

**Path:** `examples/static-openshift/`

Deploys on Red Hat OpenShift using an OpenShift `Route` for external exposure. SCC-compliant: arbitrary UID, no root, read-only root filesystem.

```bash
helm upgrade --install claude-mate-agent charts/claude-mate-agent \
  --namespace claude-mate \
  -f examples/static-openshift/values.yaml \
  --set image.repository=image-registry.openshift-image-registry.svc:5000/claude-mate/claude-mate-agent \
  --set image.tag=latest \
  --set claudeCode.apiKeySecretName=claude-mate-api-key \
  --set route.host=claude-mate.apps.cluster.example.com
```

Key values set by this example:

| Value | Setting |
|---|---|
| `route.enabled` | `true` |
| `route.tls.termination` | `edge` |
| `podSecurityContext.runAsNonRoot` | `true` |
| `containerSecurityContext.readOnlyRootFilesystem` | `true` |

---

## Gateway API (HTTPRoute)

**Path:** `examples/gateway-api/`

Attaches an `HTTPRoute` to a shared Gateway. Requires `gateway.networking.k8s.io/v1` CRDs installed in the cluster (Envoy Gateway, Cilium, NGINX Gateway Fabric, Azure AGFC, etc.).

```bash
helm upgrade --install claude-mate-agent charts/claude-mate-agent \
  --namespace claude-mate --create-namespace \
  -f examples/gateway-api/values.yaml \
  --set image.repository=ghcr.io/your-org/claude-mate-agent \
  --set image.tag=latest \
  --set claudeCode.apiKeySecretName=claude-mate-api-key \
  --api-versions gateway.networking.k8s.io/v1/HTTPRoute
```

Key values set by this example:

| Value | Setting |
|---|---|
| `gateway.enabled` | `true` |
| `gateway.gatewayNamespace` | `infra` |
| `gateway.gatewayName` | `shared-gateway` |
| `gateway.hostname` | `claude-mate.example.com` |
| `ingress.enabled` | `false` |
| `route.enabled` | `false` |

To create a dedicated Gateway instead of attaching to a shared one, set `gateway.createGateway: true` and configure `gateway.gatewayClassName`.

---

## GitOps: ArgoCD

**Path:** `examples/argocd/`

Deploys the Helm chart from the git repository using ArgoCD `Application` with automated sync, pruning, and self-healing.

```bash
kubectl apply -f examples/argocd/Application.yaml
argocd app sync claude-mate-agent
```

Key settings in `Application.yaml`:

| Setting | Value |
|---|---|
| `syncPolicy.automated.prune` | `true` |
| `syncPolicy.automated.selfHeal` | `true` |
| `syncOptions` | `CreateNamespace=true`, `ServerSideApply=true` |
| `ignoreDifferences` | `/spec/replicas` (allows HPA to override) |

See `examples/argocd/README.md` for RBAC, project configuration, and secret prerequisites.

---

## GitOps: FluxCD

**Path:** `examples/fluxcd/`

Deploys the Helm chart from a `HelmRepository` source using a Flux `HelmRelease`.

```bash
kubectl apply -f examples/fluxcd/HelmRepository.yaml
kubectl apply -f examples/fluxcd/HelmRelease.yaml
flux get helmrelease -n claude-mate claude-mate-agent
```

Key settings in `HelmRelease.yaml`:

| Setting | Value |
|---|---|
| `upgrade.remediation.retries` | `3` |
| `rollback.cleanupOnFail` | `true` |
| `valuesFrom` | Optional Secret for sensitive values |

See `examples/fluxcd/README.md` for image automation, secret management, and version pinning.

---

## Full Observability (ServiceMonitor + OTEL)

**Path:** `examples/monitoring/`

Enables the Prometheus Operator `ServiceMonitor` for automatic scrape registration and the OpenTelemetry OTLP exporter.

```bash
helm upgrade --install claude-mate-agent charts/claude-mate-agent \
  --namespace claude-mate --create-namespace \
  -f examples/monitoring/values.yaml \
  --set image.repository=ghcr.io/your-org/claude-mate-agent \
  --set image.tag=latest \
  --set claudeCode.apiKeySecretName=claude-mate-api-key
```

**Prerequisites:**

- Prometheus Operator installed with a `Prometheus` resource that selects `release: prometheus`
- An OTEL Collector reachable at the endpoint configured in `values.yaml`

Key values set by this example:

| Value | Setting |
|---|---|
| `serviceMonitor.enabled` | `true` |
| `serviceMonitor.labels.release` | `prometheus` |
| `otel.enabled` | `true` |
| `otel.endpoint` | `http://otel-collector.monitoring.svc.cluster.local:4318` |
| `networkPolicy.enabled` | `true` |

Available metrics exposed via both `/metrics` and OTLP:

| Metric | Type |
|---|---|
| `claude_mate_agent_up` | Gauge |
| `claude_mate_agent_start_timestamp_seconds` | Gauge |
| `claude_mate_agent_uptime_seconds` | Gauge |
| `claude_mate_agent_http_requests_total` | Counter |
| `claude_mate_agent_task_executions_total{result}` | Counter |

---

## On-Demand: GitLab CI

**Path:** `examples/on-demand-gitlab/`

Two job snippets for triggering the agent from a GitLab pipeline — one for manual runs from the CI/CD UI, one for API-triggered pipelines.

Copy the desired job from `examples/on-demand-gitlab/snippet.yml` into your `.gitlab-ci.yml`:

```yaml
include:
  - local: examples/on-demand-gitlab/snippet.yml
```

Or copy the job block directly. Required CI/CD variables:

| Variable | Where to set |
|---|---|
| `ANTHROPIC_API_KEY` | Masked + protected CI/CD variable |
| `CLAUDE_TASK` | Pipeline variable or trigger parameter |

Every execution emits structured JSON audit lines including `ci_system: gitlab_ci`, project, pipeline ID, job ID, commit, branch, runner, and user.

---

## Claude Sandbox (one-shot Kubernetes Job)

**Path:** `examples/sandbox/`

Submits a single Claude task as an ephemeral, isolated Kubernetes Job — `activeDeadlineSeconds`, `ttlSecondsAfterFinished`, ephemeral workspace, ingress-blocked NetworkPolicy, no service-account token, optional gVisor/Kata `runtimeClassName`.

```bash
helm template claude-mate-agent charts/claude-mate-agent \
  -f examples/sandbox/values.yaml \
  --set sandbox.task="Review the auth middleware for OWASP issues" \
  --set sandbox.teamMateRole=security \
  --set claudeCode.apiKeySecretName=claude-mate-api-key \
  --set image.repository=ghcr.io/your-org/claude-mate-agent \
  --set image.tag=latest \
  | kubectl create -n claude-mate-sandbox -f -
```

The Job uses `generateName`, so submit with `kubectl create` (not `apply`); multiple submissions create distinct Jobs.

CI/CD triggers:

- **GitHub Actions** — `.github/workflows/sandbox.yml` (`workflow_dispatch` form with task / persona / RuntimeClass)
- **GitLab CI** — `run:sandbox-agent` job in the `on-demand` stage, parameterised via `CLAUDE_TASK` / `TEAM_MATE_ROLE` CI variables

See the [Sandboxes](sandbox.md) page for design, isolation levels, and tightening guidance.

---

## LLM Gateway / Alternative Providers

**Path:** `examples/llm-gateway/`

Seven Helm values overlays for pointing the agent at non-default backends — Anthropic direct, Kong AI Gateway, LiteLLM, OpenRouter, Azure AI Foundry, Google Vertex AI / Gemini, and NVIDIA NIM (free tier).

| File | Provider | Notes |
|---|---|---|
| `values-anthropic-direct.yaml` | Anthropic | Default, lowest latency |
| `values-kong.yaml` | Kong AI Gateway | Central auth / rate-limit / audit |
| `values-litellm.yaml` | LiteLLM proxy | Mix backends behind one config |
| `values-openrouter.yaml` | OpenRouter | Pay-as-you-go, model fallbacks |
| `values-azure.yaml` | Microsoft Azure AI Foundry | Enterprise compliance, private networking |
| `values-gemini.yaml` | Google Vertex AI / Gemini | Direct (Vertex Claude) or proxied (native Gemini) |
| `values-nvidia.yaml` | NVIDIA NIM | Free open-source models via LiteLLM translation |

```bash
helm upgrade --install claude-mate-agent charts/claude-mate-agent \
  --namespace claude-mate --create-namespace \
  -f examples/llm-gateway/values-openrouter.yaml \
  --set image.repository=ghcr.io/your-org/claude-mate-agent \
  --set image.tag=latest
```

See the [LLM Gateway](llm-gateway.md) page for routing diagrams, cost-telemetry caveats, and credential rotation guidance.

---

## Persona-based deployments

**Path:** `examples/personas/`

Four Helm values overlays — one per persona — plus a `README.md` with Docker, GitHub Actions, and GitLab CI patterns.

| File | Persona | Tool scope |
|---|---|---|
| `values-architect.yaml` | Solution Architect | All tools + WebSearch |
| `values-security.yaml` | Security Engineer | Read-only (Bash for scanning) |
| `values-devops.yaml` | DevOps Engineer | All tools + writes |
| `values-sre.yaml` | SRE | Read + Bash + WebFetch |

```bash
# Run a security review against your repository
ANTHROPIC_API_KEY=sk-ant-... \
CLAUDE_TASK="Review for OWASP Top 10 and hardcoded secrets." \
TEAM_MATE_ROLE=security \
  docker run --rm \
    -v $(pwd):/workspace \
    -e ANTHROPIC_API_KEY \
    -e CLAUDE_TASK \
    -e TEAM_MATE_ROLE \
    -e WORK_DIR=/workspace \
    claude-mate-agent:dev --once
```

See the [Personas](personas.md) page for a full reference on how each persona activates its system prompt and tool restrictions.

---

## On-Demand: GitHub Actions

**Path:** `examples/on-demand-github/`

A `workflow_dispatch` workflow for triggering the agent from the GitHub Actions UI or the GitHub API.

The file is a standalone reference copy. The deployed workflow lives at `.github/workflows/on-demand.yml`.

**Setup:** Add `ANTHROPIC_API_KEY` to repository secrets (**Settings → Secrets and variables → Actions**).

**Run a task:**

1. Go to **Actions → On-Demand Claude Code Task → Run workflow**
2. Fill in the **task** prompt
3. Select **team_mate_role** for the audit trail
4. Click **Run workflow**

Every execution emits structured JSON audit lines including `ci_system: github_actions`, repository, run ID, job, commit, branch, actor, and workflow name.

To restrict execution, create an `on-demand` environment in **Settings → Environments** with required reviewers and scope `ANTHROPIC_API_KEY` to that environment.
