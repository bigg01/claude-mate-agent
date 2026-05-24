<p align="center">
  <img src="docs/assets/logo.svg" alt="Claude Mate Agent" width="140"/>
</p>

<h1 align="center">Claude Mate Agent</h1>

<p align="center">
  <em>Enterprise-grade <a href="https://claude.ai/code">Claude Code</a> agent platform for Kubernetes and Red Hat OpenShift.</em>
</p>

<p align="center">
  <img alt="Kubernetes" src="https://img.shields.io/badge/Kubernetes-CNCF-326CE5?logo=kubernetes"/>
  <img alt="OpenShift" src="https://img.shields.io/badge/OpenShift-compatible-EE0000?logo=redhatopenshift"/>
  <img alt="Helm" src="https://img.shields.io/badge/Helm-0.1.0-5B21B6?logo=helm"/>
  <img alt="Node.js" src="https://img.shields.io/badge/Node.js-22%20LTS-339933?logo=nodedotjs"/>
  <img alt="Python" src="https://img.shields.io/badge/Python-3.12-3776AB?logo=python"/>
  <img alt="OCI" src="https://img.shields.io/badge/OCI-ubi9--minimal-EE0000?logo=redhat"/>
  <img alt="Trivy" src="https://img.shields.io/badge/CVE--scan-Trivy-1904DA?logo=aqua"/>
  <img alt="DORA" src="https://img.shields.io/badge/DORA-instrumented-F46800?logo=grafana"/>
</p>

---

Claude Mate Agent packages the [Claude Code CLI](https://claude.ai/code) as a production-grade Kubernetes workload with defense-in-depth security, multi-provider LLM routing, full DORA-metric telemetry, and an SDLC quality-gate pipeline. The runtime image is built from `ubi9-minimal` with no package managers, no Python interpreter, and no build tools in the final layer.

## Key capabilities

| Pillar | What you get |
|---|---|
| **Execution** | Static long-running Deployment · on-demand CI/CD Job · isolated [sandbox](docs/sandbox.md) (one-shot K8s Job with gVisor/Kata, ephemeral workspace, TTL cleanup) |
| **Connectivity** | Direct Anthropic · Kong AI Gateway · LiteLLM · OpenRouter · Azure AI Foundry · Vertex AI · NVIDIA NIM — switch with one Helm value, no image rebuild ([details](docs/llm-gateway.md)) |
| **Personas** | Architect · Security · DevOps · SRE — each with a curated system prompt and Claude CLI tool allow-list (security persona is read-only) |
| **Routing** | Kubernetes Ingress · OpenShift Route · Gateway API HTTPRoute — same chart, capability-gated templates |
| **GitOps** | ArgoCD `Application` and FluxCD `HelmRelease` examples with automated sync, pruning, and self-heal |
| **Observability** | Always-on Prometheus `/metrics` · opt-in OTEL OTLP · Grafana **agent** + **DORA** dashboards auto-provisioned · structured JSON audit logs |
| **Quality gates** | Trivy CVE + IaC scan · Bandit + Semgrep SAST · Gitleaks · CycloneDX SBOM · pytest coverage with `--cov-fail-under` floor · Renovate for deps |
| **DORA telemetry** | Deployment Frequency, Lead Time, Change Failure Rate, MTTR — emitted from every CI deploy job ([details](docs/dora-metrics.md)) |
| **Enterprise infra** | Artifactory mirrors for Docker/PyPI/npm/Helm · NVIDIA Container Runtime for GPU · Vault Agent Injector + Secrets Operator · cert-manager integration |

## Defense-in-depth protection

Six independent security layers, each useful even if every other layer is breached:

| # | Layer | Controls |
|---|---|---|
| 1 | **Image** | `ubi9-minimal` base · no pip/npm/dnf/python in runtime · PyInstaller-compiled single binary · Renovate-tracked base/dep versions |
| 2 | **Container** | `readOnlyRootFilesystem: true` · `runAsNonRoot` + arbitrary UID for OpenShift SCC · `capabilities.drop: ALL` · seccomp `RuntimeDefault` · pinned Claude Code CLI version |
| 3 | **Network** | NetworkPolicy enabled by default · operator-defined egress allow-list · sandbox NetworkPolicy blocks all ingress · RFC 1918 excluded from default sandbox egress |
| 4 | **Sandbox** | One-shot K8s Job · `automountServiceAccountToken: false` · optional gVisor/Kata `runtimeClassName` · `activeDeadlineSeconds` hard cap · `ttlSecondsAfterFinished` auto-cleanup · ephemeral `/workspace` volume |
| 5 | **Identity** | API key from K8s Secret (never image-baked) · persona-bound Claude tool allow-list (`security` is read-only) · OpenShell pod annotations for shell-access audit · Vault Agent Injector option |
| 6 | **Supply chain** | Trivy `image` + `fs` + `config` (fixed CRITICAL/HIGH blocks merge) · Bandit + Semgrep SAST (SARIF → Code Scanning) · Gitleaks secret scan · Syft CycloneDX SBOM (90-day retention) · `.trivyignore` + `.gitleaks.toml` allowlists with rationale |

See [Security & Compliance](docs/security.md) and [Security Scanning](docs/security-scanning.md) for the full controls catalogue.

## Quick start

```bash
# Build the image (auto-detects podman or docker)
make build

# Run the static server (health + metrics on :8080)
make run

# Run an on-demand Claude task locally
export ANTHROPIC_API_KEY=sk-ant-...
export CLAUDE_TASK="summarise the open issues in this repo"
make run-once

# Spin up the full observability stack (agent + Prometheus + Grafana + Pushgateway)
docker compose up
```

Grafana opens at <http://localhost:3000> with the **Claude Mate Agent** and **DORA Metrics** dashboards pre-loaded.

## Local quality gates

```bash
make test          # pytest + coverage (50% floor)
make sast          # Bandit Python SAST
make scan          # Trivy filesystem + IaC + image
make secrets       # Gitleaks
make sbom          # Syft → sbom.cyclonedx.json
make security      # all of the above, sequentially
```

## What's inside

| Component | Description |
|---|---|
| `container/app.py` | Python wrapper — health/readiness/metrics server, persona-aware Claude subprocess runner, cost-tracking + audit |
| `container/tests/` | pytest unit tests + coverage config (50% floor) |
| `Dockerfile` | 3-stage multi-stage build: `python-builder` (uv + PyInstaller) → `node-builder` (npm + claude CLI) → `ubi9-minimal` runtime |
| `charts/claude-mate-agent` | Helm chart — Ingress · Route · Gateway API HTTPRoute · sandbox Job · NetworkPolicy · cert-manager · Vault · NVIDIA GPU |
| `examples/` | Eight ready-to-use overlays: static-kubernetes, static-openshift, gateway-api, monitoring, on-demand-gitlab, on-demand-github, argocd, fluxcd, **personas**, **llm-gateway** (7 providers), **sandbox**, **nvidia-gpu** |
| `grafana/dashboards/` | `claude-mate-agent.json` + `dora-metrics.json` — auto-provisioned |
| `prometheus/` | Scrape config + `dora_rules.yml` (recording + alerting) |
| `scripts/dora-emit.sh` | Canonical DORA event emitter (deploy / failure / restore) |
| `.github/workflows/` | `ci.yml` (test + build + push) · `security.yml` (Trivy + Bandit + Semgrep + Gitleaks + SBOM → SARIF) · `deploy.yml` · `sandbox.yml` · `on-demand.yml` |
| `.gitlab-ci.yml` | `validate → test → build → scan → package → deploy → on-demand` with full quality-gate gating |
| `.github/renovate.json` | Renovate config for Python, Node, Dockerfile, Helm, Compose, Actions |

## Operating modes

| Mode | Lifecycle | When to use | How it runs |
|---|---|---|---|
| **Static** | Long-running Deployment | Always-on service with continuous metrics/health endpoints | `make run` / `helm upgrade --install` |
| **On-demand** | Short-lived CI job | Manual or scheduled tasks triggered from CI/CD | GitHub Actions `on-demand.yml` / GitLab `run:on-demand-agent` |
| **Sandbox** | One-shot K8s Job | Untrusted prompts, contractor work, per-request isolation | `helm template ... \| kubectl create -f -` ([details](docs/sandbox.md)) |

## Observability

The platform emits three classes of telemetry:

1. **Service metrics** — `claude_mate_agent_*` on `/metrics` (always on) and OTLP (opt-in via `OTEL_ENABLED=true`)
2. **Cost + audit** — structured JSON with `task_cost_summary`, role, CI system, commit SHA, pod identifiers
3. **DORA** — `dora_deployments_total`, `dora_lead_time_seconds`, `dora_change_failures_total`, `dora_restore_seconds` emitted via Pushgateway, surfaced on the Grafana DORA dashboard

DORA failure definition is codified in CI: rollout timeout, probe failure, or explicit `dora-emit.sh failure` within 24 h of deploy. Targets and alerting rules are in [`docs/dora-metrics.md`](docs/dora-metrics.md).

## Documentation

Full docs in [`docs/`](docs/), served with MkDocs Material:

```bash
make docs-serve        # live preview at http://localhost:8000
make docs-build        # build static site to site/
```

| Page | Purpose |
|---|---|
| [Getting Started](docs/getting-started.md) | Build, run, first task |
| [Architecture](docs/architecture.md) | Component layout, two-layer design |
| [Solution Architecture](docs/solution-architecture.md) | End-to-end reference architecture |
| [Container Build](docs/container.md) | Multi-stage Dockerfile, PyInstaller, OTEL bundling |
| [Helm Chart](docs/helm-chart.md) | Values reference, routing, secrets |
| [Personas](docs/personas.md) | Architect / Security / DevOps / SRE roles |
| [LLM Gateway](docs/llm-gateway.md) | Provider routing — Anthropic, Kong, LiteLLM, OpenRouter, Azure, Vertex AI, NVIDIA |
| [Sandboxes](docs/sandbox.md) | Ephemeral one-shot Job execution with kernel-level isolation |
| [Monitoring](docs/monitoring.md) | Metrics reference, OTEL setup, ServiceMonitor |
| [Security & Compliance](docs/security.md) | RBAC, SCC, NetworkPolicy, audit |
| [Security Scanning](docs/security-scanning.md) | Trivy, Bandit, Semgrep, Gitleaks, SBOM |
| [Quality Gates](docs/quality-gates.md) | SDLC stage → gate matrix, pipeline DAG |
| [DORA Metrics](docs/dora-metrics.md) | Definitions, targets, dashboard, alerting |
| [GitLab CI/CD](docs/gitlab-ci.md) | Pipeline jobs and required variables |
| [GitHub Actions](docs/github-actions.md) | Workflows and required secrets |

## Requirements

See [`requirement.md`](requirement.md) for the full enterprise requirements catalogue covering Kubernetes/OpenShift support, container hardening, monitoring, logging, OpenShell protection, audit trail, remote log sync, team-mate roles, LLM gateways, GPU support, Artifactory mirrors, Claude sandboxes, security scanning, SAST, code coverage, SDLC quality gates, and DORA metrics.
