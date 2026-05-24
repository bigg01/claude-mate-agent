# Claude Mate Agent

<p align="center">
  <img src="assets/logo.svg" alt="Claude Mate Agent" width="120"/>
</p>

<p align="center">
  <em>Enterprise-grade <a href="https://claude.ai/code">Claude Code</a> agent platform for Kubernetes and Red Hat OpenShift.</em>
</p>

Claude Mate Agent packages the [Claude Code CLI](https://claude.ai/code) as a production-grade Kubernetes and OpenShift workload, with defense-in-depth security, multi-provider LLM routing, full DORA-metric telemetry, and an SDLC quality-gate pipeline.

---

## Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Pod / Container (ubi9-minimal)               │
│                                                                 │
│  ┌─────────────────────────────┐   ┌─────────────────────────┐  │
│  │   agent  (PyInstaller bin)  │   │  claude CLI (Node 22)   │  │
│  │                             │   │                         │  │
│  │  /healthz  /readyz          │──▶│  claude --print --json  │  │
│  │  /metrics  (Prometheus)     │   │  --system-prompt        │  │
│  │  OTEL OTLP export (opt-in)  │   │  --allowedTools         │  │
│  └─────────────────────────────┘   └─────────────────────────┘  │
│                  │                              │               │
│                  ▼                              ▼               │
│           Audit logs            ANTHROPIC_BASE_URL ──▶ Provider │
│           (stdout JSON)              (Anthropic / Kong /        │
│                                       LiteLLM / OpenRouter /    │
│                                       Azure / Vertex AI / NIM)  │
└─────────────────────────────────────────────────────────────────┘
                                                  │
                  ┌───────────────────────────────┘
                  ▼
   Prometheus ─▶ Grafana ─▶ DORA dashboard + agent dashboard
                  ▲
   CI deploy ─────┴── Pushgateway ◀── scripts/dora-emit.sh
```

The **agent** binary is a compiled Python process supervisor. It contains no AI logic — it provides the Kubernetes-compatible wrapper (probes, metrics, structured logging, audit events, persona routing, cost tracking) around the `claude` CLI. The provider behind the API is interchangeable; the agent image is provider-agnostic.

## Key capabilities

| Pillar | What you get |
|---|---|
| **Execution** | Static long-running Deployment · on-demand CI/CD Job · isolated [sandbox](sandbox.md) (one-shot K8s Job with gVisor/Kata, ephemeral workspace, TTL cleanup) |
| **Connectivity** | [LLM Gateway](llm-gateway.md) routing: Anthropic · Kong AI Gateway · LiteLLM · OpenRouter · Azure AI Foundry · Vertex AI · NVIDIA NIM. Swap providers with one Helm value, no image rebuild. |
| **Personas** | [Architect · Security · DevOps · SRE](personas.md) — each with a curated system prompt and a Claude CLI tool allow-list (security persona is read-only) |
| **Routing** | Kubernetes Ingress · OpenShift Route · Gateway API HTTPRoute — same chart, capability-gated templates |
| **GitOps** | ArgoCD `Application` and FluxCD `HelmRelease` examples with automated sync, pruning, and self-heal |
| **Observability** | Always-on Prometheus `/metrics` · opt-in OTEL OTLP export · auto-provisioned [agent](monitoring.md) and [DORA](dora-metrics.md) Grafana dashboards · structured JSON audit logs |
| **Quality gates** | [Trivy · Bandit · Semgrep · Gitleaks · SBOM · pytest coverage](security-scanning.md) gated in CI; local `make security` runs them all |
| **DORA telemetry** | [Deployment Frequency · Lead Time · Change Failure Rate · MTTR](dora-metrics.md) emitted from every CI deploy job |
| **Enterprise infra** | Artifactory mirrors for Docker/PyPI/npm/Helm · NVIDIA Container Runtime for GPU · Vault Agent Injector + Secrets Operator · cert-manager integration |

## Defense-in-depth protection

Six independent security layers, each useful even if every other layer is breached:

| # | Layer | Controls |
|---|---|---|
| 1 | **Image** | `ubi9-minimal` base — no pip/npm/dnf/python in runtime · PyInstaller-compiled single binary · Renovate-tracked base/dep versions |
| 2 | **Container** | `readOnlyRootFilesystem: true` · `runAsNonRoot` + arbitrary UID for OpenShift SCC · `capabilities.drop: ALL` · seccomp `RuntimeDefault` · pinned Claude Code CLI version |
| 3 | **Network** | NetworkPolicy enabled by default · operator-defined egress allow-list · sandbox NetworkPolicy blocks all ingress · RFC 1918 excluded from default sandbox egress |
| 4 | **Sandbox** | One-shot K8s Job · `automountServiceAccountToken: false` · optional gVisor / Kata `runtimeClassName` · `activeDeadlineSeconds` hard cap · `ttlSecondsAfterFinished` auto-cleanup · ephemeral `/workspace` volume |
| 5 | **Identity** | API key from K8s Secret (never image-baked) · persona-bound Claude tool allow-list (`security` is read-only) · OpenShell pod annotations for shell-access audit · Vault Agent Injector option |
| 6 | **Supply chain** | Trivy `image`/`fs`/`config` (fixed CRITICAL/HIGH blocks merge) · Bandit + Semgrep SAST (SARIF → Code Scanning) · Gitleaks secret scan · Syft CycloneDX SBOM (90-day retention) · `.trivyignore` + `.gitleaks.toml` allowlists with rationale |

Read the full controls catalogue in [Security & Compliance](security.md) and [Security Scanning](security-scanning.md).

## Operating modes

| Mode | Lifecycle | Best for |
|---|---|---|
| **Static** | Long-running Deployment with HPA + PDB | Always-on service with continuous telemetry |
| **On-demand** | Short-lived CI job | Manual or scheduled tasks via CI/CD UI/API |
| **Sandbox** | One-shot K8s Job with kernel isolation | Untrusted prompts, contractor work, per-request isolation |

All three modes share the same image, the same persona definitions, and the same audit-log schema — switching modes is a Helm value change, not an image rebuild.

## Transparency through DORA

Every deploy emits the four DORA metrics to a Prometheus Pushgateway:

- **Deployment Frequency** — successful deploys per day, computed over 7- and 30-day windows
- **Lead Time for Changes** — wall-clock seconds from commit timestamp to successful deploy (P50 + P95)
- **Change Failure Rate** — rollout failures + post-deploy rollbacks ÷ total deploys (30 days)
- **Mean Time to Restore** — wall-clock seconds between incident open and service restoration

The pipeline also emits `pipeline_quality_gate_pass_total` and `pipeline_test_coverage_percent`, surfaced on the same dashboard so engineers see security + reliability + flow in one place.

## Quick navigation

- [Getting Started](getting-started.md) — build, run, first task
- [Architecture](architecture.md) — design decisions and component interaction
- [Container Build](container.md) — multi-stage Dockerfile, PyInstaller, OTEL bundling
- [Helm Chart](helm-chart.md) — values reference, routing, secrets
- [Personas](personas.md) — Architect / Security / DevOps / SRE roles
- [LLM Gateway](llm-gateway.md) — provider routing matrix
- [Sandboxes](sandbox.md) — one-shot isolated Jobs
- [Monitoring](monitoring.md) — metrics reference, OTEL setup
- [Security & Compliance](security.md) — RBAC, SCC, NetworkPolicy, audit
- [Security Scanning](security-scanning.md) — Trivy, Bandit, Semgrep, Gitleaks, SBOM
- [Quality Gates](quality-gates.md) — SDLC stage → gate matrix
- [DORA Metrics](dora-metrics.md) — definitions, targets, dashboard, alerting
- [GitLab CI/CD](gitlab-ci.md) — pipeline jobs and required variables
- [GitHub Actions](github-actions.md) — workflows and required secrets
