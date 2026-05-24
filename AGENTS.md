# AGENTS.md

## Repo State

- This repo contains a minimal runnable Claude Mate agent container, Helm chart, GitLab CI and GitHub Actions pipelines, component examples, and requirements document.
- `container/pyproject.toml` is the authoritative Python dependency manifest; `uv` is the package manager (`pip` is not used anywhere in the build pipeline).
- `container/uv.lock` is the fully resolved lock file — commit it whenever `pyproject.toml` changes (`make lock`).
- Runtime Python dependencies: `opentelemetry-sdk==1.26.0`, `opentelemetry-exporter-otlp-proto-http==1.26.0`. PyInstaller is declared in the `[build]` optional-dependency group and is a build-only tool.
- `container/requirements.txt` is a legacy compatibility reference; the Dockerfile no longer reads it.
- OTEL export is opt-in at runtime via `OTEL_ENABLED=true`; the Prometheus `/metrics` endpoint is always available.
- The final runtime image contains no Python interpreter, no pip, no npm, and no dnf — only the compiled `agent` binary, `/usr/bin/node`, and `/usr/local/lib/node_modules/@anthropic-ai/claude-code`.
- `examples/` contains eight ready-to-use deployment examples: `static-kubernetes`, `static-openshift`, `gateway-api`, `monitoring`, `on-demand-gitlab`, `on-demand-github`, `argocd`, `fluxcd`.
- `docker-compose.yml` starts the agent (static mode) + Prometheus + Grafana for local development.
- `docker-compose.nvidia.yml` is a Docker Compose override that adds NVIDIA GPU access (requires `nvidia-container-toolkit` on the host). Use with: `docker compose -f docker-compose.yml -f docker-compose.nvidia.yml up`.
- `prometheus/prometheus.yml` is the Prometheus scrape config used by Docker Compose.
- `grafana/dashboards/claude-mate-agent.json` is a pre-built Grafana dashboard with health, task, cost, and performance panels.
- `grafana/provisioning/` contains auto-provisioning config for the datasource and dashboard loader.

## Primary Document

- `requirement.md` is the source of truth for Claude Mate agent platform requirements.
- Preserve its enterprise scope: Kubernetes, OpenShift Enterprise Standard, monitoring, centralized logging, OpenShell protection, audit trail, remote log sync, and compliance.
- Preserve both operating modes when editing requirements: static always-on Kubernetes/OpenShift deployment and on-demand GitLab CI/CD pipeline execution.
- Preserve team mate role coverage for Security, Operations, SRE, and Architecture.

## Project Layout

- `Dockerfile` is a three-stage multi-stage build: `python-builder` (copies `uv` from `ghcr.io/astral-sh/uv`, installs deps via `uv sync --extra build`, compiles `app.py` + OTEL into a single binary with PyInstaller), `node-builder` (npm installs Claude Code CLI), `runtime` (ubi9-minimal — only the compiled binary, Node.js runtime, and claude module; no Python/pip/npm/dnf/uv).
- `container/app.py` exposes `/healthz`, `/readyz`, and `/metrics`; `--once` loads the persona for `TEAM_MATE_ROLE` (system prompt from `container/personas/<role>.md`, tool allow-list from `_PERSONA_TOOLS`), invokes `claude --print --output-format json --system-prompt ... --allowedTools ...` in `WORK_DIR`, parses cost from the JSON response, updates Prometheus metrics (with `role` label), and emits `task_cost_summary` on exit.
- `container/personas/` contains four Markdown system-prompt files: `architect.md`, `security.md`, `devops.md`, `sre.md`. These are copied to `/opt/claude-mate/personas/` in the runtime stage and loaded by the agent binary at runtime (not bundled in the binary). Override by mounting a ConfigMap over that path.
- `charts/claude-mate-agent` is the Helm chart for static deployment.
- `charts/claude-mate-agent/values-aks.yaml` enables Kubernetes Ingress for AKS; includes a commented Gateway API block for switching to Azure Application Gateway for Containers or nginx-gateway-fabric.
- `charts/claude-mate-agent/values-openshift.yaml` enables OpenShift Route rendering when the Route API is available.
- `charts/claude-mate-agent/templates/httproute.yaml` renders an `HTTPRoute` when `gateway.enabled: true` and the `gateway.networking.k8s.io/v1/HTTPRoute` API is present.
- `charts/claude-mate-agent/templates/gateway.yaml` optionally renders a `Gateway` when `gateway.createGateway: true` and the `gateway.networking.k8s.io/v1/Gateway` API is present.
- `.gitlab-ci.yml` validates Helm rendering, builds/pushes with Buildah, packages the chart, and has manual AKS/OpenShift deploy and on-demand jobs.
- `.github/workflows/ci.yml` validates Helm, builds docs, and builds/pushes to GHCR on every push.
- `.github/workflows/deploy.yml` deploys via `workflow_dispatch` to AKS or OpenShift.
- `.github/workflows/on-demand.yml` runs the agent with `--once` via `workflow_dispatch`; mirrors `run:on-demand-agent` in GitLab.
- `scripts/make.ps1` is the Windows PowerShell equivalent of the `Makefile`; supports all the same targets and auto-detects Podman/Docker.
- `examples/nvidia-gpu/` contains a Helm values overlay and README for GPU-enabled deployments using the NVIDIA Container Runtime.
- `examples/llm-gateway/` contains seven Helm values overlays for different LLM backends: Anthropic direct, Kong AI Gateway, LiteLLM, OpenRouter, Azure AI Foundry, Google Vertex AI / Gemini, and NVIDIA NIM (via LiteLLM). All use `claudeCode.baseUrl` to override `ANTHROPIC_BASE_URL`. The container image is provider-agnostic.
- `examples/sandbox/` contains a Helm values overlay and README for Claude sandboxes — one-shot, isolated Kubernetes Jobs with ephemeral workspace, hard time cap, egress allow-list, optional gVisor/Kata RuntimeClass, and `ttlSecondsAfterFinished` auto-cleanup. Submit via `helm template … | kubectl create -f -` because the Job uses `generateName`. CI/CD triggers: `.github/workflows/sandbox.yml` (GitHub Actions, workflow_dispatch) and `run:sandbox-agent` job in `.gitlab-ci.yml`. Chart templates: `templates/sandbox-job.yaml` + `templates/sandbox-networkpolicy.yaml`, rendered only when `sandbox.enabled: true`.
- `container/tests/` holds pytest unit tests for `app.py` (parse_output, persona/cmd construction, log helper). Pytest config + coverage threshold (50%) + Bandit config live in `[tool.pytest.ini_options]` / `[tool.coverage.*]` / `[tool.bandit]` of `container/pyproject.toml`. The `test` extra in `pyproject.toml` brings in pytest, pytest-cov, and bandit. Run locally: `make test`, `make sast`, `make scan`, `make secrets`, `make sbom`, or `make security` (all of them).
- `.github/workflows/security.yml` runs Trivy (fs + config + image), Bandit, Semgrep, Gitleaks, and Syft SBOM generation on every push and PR. All SAST/CVE findings upload as SARIF to GitHub Code Scanning. `.github/workflows/ci.yml` has a `test` job that runs pytest with coverage; `build-and-push` depends on both `validate-helm` and `test`. `.gitlab-ci.yml` has a new `test` stage (pytest, bandit, gitleaks, trivy fs+config) and a new `scan` stage (trivy image + syft SBOM) between `build` and `package`. `.trivyignore` and `.gitleaks.toml` hold allowlists with rationale comments.
- `scripts/dora-emit.sh` is the canonical DORA emitter — pushes `deploy` / `failure` / `restore` events to a Prometheus Pushgateway. CI deploy jobs call it when `PUSHGATEWAY_URL` is set (no-op otherwise). `prometheus/dora_rules.yml` holds recording rules (`dora:deployments_per_day:7d/30d`, `dora:lead_time_seconds:p50/p95:30d`, `dora:change_failure_rate:30d`, `dora:mttr_seconds:30d`, `quality_gate:pass_rate:7d`) and three alerting rules. `grafana/dashboards/dora-metrics.json` is the dashboard (four headline panels + trends + quality-gate row); auto-provisioned alongside the agent dashboard. `prometheus-pushgateway` service is wired into `docker-compose.yml`.
- DORA failure definition is codified in CI: rollout timeout *or* probe failure *or* a manual `dora-emit.sh failure` call within 24 h. Targets: deploy ≥1/day, lead-time P95 ≤1 day, change-failure rate ≤15%, MTTR ≤6 h. Documented in `docs/dora-metrics.md` and `requirement.md` §26.
- `VERSION` at the repo root is the single source of truth for SemVer 2.0.0 across every artefact (`container/pyproject.toml`, `charts/claude-mate-agent/Chart.yaml` `version`+`appVersion`, `values.yaml` `image.tag`). `make version-check` enforces drift and is wired into CI gates (GitHub `test` job, GitLab `version:check`). `scripts/bump-version.sh` updates them atomically — accepts `patch`/`minor`/`major` or a full SemVer string. `.github/workflows/release.yml` fires on `v[0-9]+.[0-9]+.[0-9]+*` tag pushes: re-verifies consistency, packages the Helm chart at the pinned version, pushes to `oci://ghcr.io/<owner>/charts`, and creates a GitHub Release (marked `prerelease` when tag contains `-`). `ci.yml` `docker/metadata-action` emits `<full>`, `<major>.<minor>`, `<major>`, `latest`, `<short-sha>` on stable tags; only `<full>` + `<short-sha>` on pre-release. GitLab `build:image` emits the same tag set. Bump workflow: `make release-tag NEW=patch|minor|major|<version>` → review → commit → `git tag -a vX.Y.Z` → push. Spec: `requirement.md` §27, docs: `docs/versioning.md`.

## Commands

Prefer `make <target>` on Linux/macOS. Use `.\scripts\make.ps1 <target>` on Windows. Both auto-detect Podman/Docker.

- Build image locally: `make build` or `docker build -t claude-mate-agent:dev .`
- Run locally: `make run` or `docker run --rm -p 8080:8080 claude-mate-agent:dev`
- Run on-demand mode locally: `make run-once` (requires `ANTHROPIC_API_KEY` and `CLAUDE_TASK` in env)
- Helm lint: `helm lint charts/claude-mate-agent`
- Render all routing variants: `make render`
- Render AKS manifests: `helm template claude-mate-agent charts/claude-mate-agent -f charts/claude-mate-agent/values-aks.yaml`
- Render OpenShift manifests with Route API: `helm template claude-mate-agent charts/claude-mate-agent -f charts/claude-mate-agent/values-openshift.yaml --api-versions route.openshift.io/v1/Route`
- Render Gateway API manifests: `helm template claude-mate-agent charts/claude-mate-agent --set gateway.enabled=true --api-versions gateway.networking.k8s.io/v1/HTTPRoute --api-versions gateway.networking.k8s.io/v1/Gateway`
- Package chart: `helm package charts/claude-mate-agent`

## Pipeline Notes

**GitLab CI:**
- Image publishing uses `$CI_REGISTRY_IMAGE/claude-mate-agent:$CI_COMMIT_SHORT_SHA`.
- `deploy:aks` requires `KUBE_CONFIG_AKS_B64` containing a base64-encoded kubeconfig.
- `deploy:openshift` requires `KUBE_CONFIG_OPENSHIFT_B64` containing a base64-encoded kubeconfig.
- `run:on-demand-agent` invokes the compiled `agent` binary with `--once`, which calls `claude --print $CLAUDE_TASK`.
- `ANTHROPIC_API_KEY` must be set as a masked, protected CI/CD variable for on-demand jobs.
- `CLAUDE_TASK` must be set as a CI/CD variable containing the task prompt for on-demand jobs.

**GitHub Actions:**
- Images are pushed to GHCR: `ghcr.io/<org>/<repo>/claude-mate-agent:<tag>`.
- `GITHUB_TOKEN` is used automatically for GHCR authentication — no configuration needed.
- `deploy.yml` requires `KUBE_CONFIG_AKS_B64` or `KUBE_CONFIG_OPENSHIFT_B64` as repository secrets.
- `on-demand.yml` requires `ANTHROPIC_API_KEY` as a repository or environment secret.
- On-demand GitHub Actions runs emit `ci_system: github_actions` in audit logs; GitLab runs emit `ci_system: gitlab_ci`. Both use the same `ci_*` field schema.

**Common:**
- The Claude Code CLI version is pinned via `CLAUDE_CODE_VERSION` build arg in the Dockerfile.
- `_ci_audit_context()` in `app.py` detects `GITHUB_ACTIONS=true` and reads the appropriate env vars for each platform.
- Cost tracking: `_parse_claude_output()` extracts `cost_usd` and `duration_ms` from the Claude CLI JSON response. Globals `TASK_COST_USD_TOTAL`, `TASK_EXECUTIONS`, `TASK_LAST_DURATION_SECONDS` accumulate values and are exposed on `/metrics`.

## Editing Guidance

- Keep changes compact and aligned with the requirements in `requirement.md`.
- Maintain Markdown heading numbering in `requirement.md` when inserting or moving sections.
- Prefer verifiable requirements over product guesses; keep unknowns in the Open Questions section.
- Keep the Helm chart compatible with both AKS and OpenShift; avoid hardcoding cloud-specific ingress classes or OpenShift hosts.
- Keep OpenShift compatibility: arbitrary UID support, no privileged container, no root-owned writable path requirement, and no fixed `runAsUser` in chart defaults.

## Verification

- For chart changes, run `helm lint charts/claude-mate-agent` and all three Helm render commands above (AKS, OpenShift, Gateway API).
- For container changes, build the image and check `/healthz`, `/readyz`, and `/metrics` if Docker or a compatible runtime is available.
- For documentation edits, review rendered Markdown structure and check that section numbering still flows correctly.
