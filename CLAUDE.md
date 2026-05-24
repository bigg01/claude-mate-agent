# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

A `Makefile` wraps all common operations on Linux/macOS. Run `make help` to list targets.

```bash
make build                        # build IMAGE:TAG (default claude-mate-agent:dev)
make run                          # build + run static server on PORT (default 8080)
make run-once                     # run on-demand mode (ANTHROPIC_API_KEY + CLAUDE_TASK must be in env)
make check                        # syntax-check app.py via uv run (falls back to python3)
make lock                         # regenerate container/uv.lock — commit the result
make sync                         # sync local .venv to current uv.lock (IDE support)
make lint                         # helm lint
make render                       # render all three routing variants (AKS, OpenShift, Gateway API)
make package                      # helm package
make docs-build                   # build MkDocs site to site/ (uses squidfunk/mkdocs-material image)
make docs-serve                   # live preview docs at http://localhost:8000
make clean                        # remove local image and site/
docker-compose up --build         # start agent + Prometheus + Grafana for local dev
docker-compose down -v            # stop and remove volumes
# GPU (requires nvidia-container-toolkit on host):
docker compose -f docker-compose.yml -f docker-compose.nvidia.yml up --build
```

Override defaults: `make build IMAGE=myrepo/claude-mate-agent TAG=1.2.3`

The Makefile auto-detects `podman` or `docker`. Override with `CONTAINER_TOOL=docker make build`.

**Windows:** Use `scripts/make.ps1` instead:

```powershell
.\scripts\make.ps1 build
.\scripts\make.ps1 run
.\scripts\make.ps1 -Target run-once -ContainerTool podman
```

Run `make render` (all three variants) after any chart change — `lint` alone does not exercise capability-gated templates.

## Architecture

### Three-stage container build

The Dockerfile has three stages:

| Stage | Base | Purpose |
|---|---|---|
| `python-builder` | `ubi9/ubi` | PyInstaller compiles `app.py` + OTEL packages into `/build/dist/agent` — a single self-contained binary |
| `node-builder` | `ubi9/ubi` | npm installs `@anthropic-ai/claude-code` globally |
| `runtime` | `ubi9/ubi-minimal` | Copies only: compiled `agent` binary, `/usr/bin/node`, claude module directory |

The final image contains **no Python interpreter, no pip, no npm, no dnf**. `PYTHONUNBUFFERED` is no longer needed and is absent from the final `ENV`.

PyInstaller uses `--onefile`, so the binary self-extracts into `/tmp` on first run — the `/tmp` emptyDir volume mount in the Helm chart is required for this to work with `readOnlyRootFilesystem: true`.

The `--collect-all opentelemetry` flag ensures lazy-imported OTEL packages (inside `_setup_otel()`) are bundled even though PyInstaller's static analysis would not find them through the `try/except` import guards.

### Two-layer design

`container/app.py` is a thin Python process supervisor, not the AI agent itself. Its roles are:

1. **Static mode** (default): serves `/healthz`, `/readyz`, `/metrics` for Kubernetes probes and Prometheus scraping; logs `claude_code_version` at startup by shelling out to `claude --version`.
2. **On-demand mode** (`--once`): reads `CLAUDE_TASK` and `TEAM_MATE_ROLE` from env, builds a persona-aware `claude --print --output-format json` command (with `--system-prompt` and `--allowedTools`), runs it in `WORK_DIR`, parses cost from the JSON response, emits structured audit events, then exits.

### Personas

Four built-in personas live as Markdown system-prompt files in `container/personas/`:

| File | Role value | Tool restriction |
|---|---|---|
| `architect.md` | `architect` | All tools |
| `security.md` | `security` | Read + Bash only |
| `devops.md` | `devops` | All tools |
| `sre.md` | `sre` | Read + Bash + WebFetch |

`_build_claude_cmd()` in `app.py` assembles the Claude CLI command from the persona file and tool list. `PERSONAS_DIR` env var overrides the default `/opt/claude-mate/personas/` path. `WORK_DIR` sets the working directory for Claude Code so it operates on a mounted repository.

The Claude Code CLI (`@anthropic-ai/claude-code`, Node.js) is installed globally in the image and is the actual AI runtime. `app.py` never contains prompt logic.

### OpenShift arbitrary-UID constraint

The Dockerfile sets `HOME=/tmp`. Node.js calls `os.homedir()` to locate the Claude Code config directory; without a writable home the CLI fails under OpenShift's arbitrary UID assignment. This is not configurable at runtime — it must be set in the image.

### Three mutually exclusive routing mechanisms

The Helm chart supports Ingress, OpenShift Route, and Gateway API HTTPRoute. Enable exactly one per deployment. Route and HTTPRoute templates are guarded by `.Capabilities.APIVersions.Has` so the same chart renders correctly on both plain Kubernetes and OpenShift without extra flags — but you must pass `--api-versions` to `helm template` to test them locally (see commands above).

### OTEL is a lazy optional import

`_setup_otel()` in `app.py` is called at the start of both `serve()` and `run_once()`. It does nothing when `OTEL_ENABLED != "true"`. When enabled it initialises a `MeterProvider` with `OTLPMetricExporter` and creates two counters that mirror the Prometheus `/metrics` endpoint. All imports happen inside the function, so a missing package is caught and logged without crashing the process. In on-demand mode `_otel_meter_provider.force_flush()` is called in the `finally` block before exit.

### Python dependencies

`container/pyproject.toml` is the single source of truth for Python dependencies. `uv` replaces `pip` everywhere — the Dockerfile, the Makefile, and local development all use `uv`.

- **Adding a dependency**: add it to `[project.dependencies]` in `pyproject.toml`, then run `make lock` to regenerate `container/uv.lock` and commit both files.
- **Build-only tools** (e.g. PyInstaller): add to `[project.optional-dependencies] build` — they are installed in the Docker builder stage but never land in the runtime image.
- **Local IDE setup**: run `make sync` to create `container/.venv` with all dependencies including the build extra.
- `container/requirements.txt` is a legacy compatibility file; the Dockerfile no longer reads it.

### NVIDIA Container Runtime

The `nvidia:` block in `values.yaml` is opt-in (`nvidia.enabled: false` by default). When enabled the deployment template adds:

- `runtimeClassName: nvidia` on the pod spec
- `nvidia.com/gpu: <gpuCount>` to both resource requests and limits
- `NVIDIA_VISIBLE_DEVICES=all` and `NVIDIA_DRIVER_CAPABILITIES` env vars
- NVIDIA `nodeSelector` and `tolerations` merged with any user-supplied scheduling constraints

Local override: `docker compose -f docker-compose.yml -f docker-compose.nvidia.yml up`. See `examples/nvidia-gpu/` for the Helm values overlay and setup instructions.

### DORA metrics and SDLC quality gates

The pipeline emits the four DORA metrics — Deployment Frequency, Lead Time, Change Failure Rate, MTTR — from every CI deploy job via `scripts/dora-emit.sh` → Prometheus Pushgateway. Recording rules in `prometheus/dora_rules.yml` precompute headline series; `grafana/dashboards/dora-metrics.json` renders them. The Pushgateway is wired into `docker-compose.yml` (port 9091). Lead time is `now - commit_ts` in seconds; rollout timeouts auto-emit `failure` events; manual failure/restore emission via `scripts/dora-emit.sh failure|restore` for incidents that span beyond a single CI run. SDLC quality-gate matrix and the pipeline DAG live in `requirement.md` §26 and `docs/quality-gates.md`.

### Security scanning, SAST, and coverage

Every CI run gates on five security tools: Trivy (image + fs + IaC config), Bandit (Python SAST), Semgrep (multi-language SAST), Gitleaks (secret scan), and pytest with coverage. The image build does not push until tests pass and the image scan finds zero fixed CRITICAL/HIGH CVEs. Coverage floor is 50% — set in `[tool.pytest.ini_options]` of `container/pyproject.toml` and enforced by `--cov-fail-under`. Test sources live in `container/tests/`. Local equivalents: `make test`, `make sast`, `make scan`, `make secrets`, `make sbom`, `make security`. CVE allowlist: `.trivyignore`; secret allowlist: `.gitleaks.toml`. SBOMs (CycloneDX via Syft) attach to every image build as a 90-day-retained artifact.

### Claude sandboxes

`sandbox.enabled: true` renders a one-shot Kubernetes Job (`templates/sandbox-job.yaml`) plus a strict NetworkPolicy (`templates/sandbox-networkpolicy.yaml`) — in addition to the regular Deployment, not instead of it. Each Job uses `generateName`, so submit with `kubectl create` (not `apply`); concurrent runs produce uniquely-named Jobs. Key isolation: `restartPolicy: Never`, `backoffLimit: 0`, `activeDeadlineSeconds` hard cap, `ttlSecondsAfterFinished` auto-cleanup, `automountServiceAccountToken: false`, ephemeral `/workspace` volume, ingress-blocked NetworkPolicy with operator-defined egress allow-list, optional `runtimeClassName: gvisor` or `kata`.

CI/CD: `.github/workflows/sandbox.yml` and the `run:sandbox-agent` GitLab job both `helm template` the chart against `examples/sandbox/values.yaml`, submit with `kubectl create`, stream logs, and surface the cost summary — the chart is the single source of truth.

### LLM provider routing

The container is provider-agnostic. `claudeCode.baseUrl` maps to `ANTHROPIC_BASE_URL` and `claudeCode.apiVersion` to `ANTHROPIC_API_VERSION` — set them to route through Kong AI Gateway, LiteLLM, OpenRouter, Azure AI Foundry, Vertex AI Claude, or (via a translation proxy) NVIDIA NIM and native Gemini. The same image binary works against any Anthropic-compatible endpoint; switching providers requires only a secret rotation and Helm value change, never an image rebuild. See `examples/llm-gateway/` for per-provider overlays.

For OpenAI-format-only providers (NVIDIA NIM, native Gemini), a LiteLLM (or Kong) proxy must sit in front to translate the Anthropic API into the provider's native format.

### Helm values layering

`values.yaml` is the base. `values-aks.yaml` and `values-openshift.yaml` are thin overlays — they only override what differs from the base. The `claudeCode.apiKeySecretName` value must be set at deploy time (it is intentionally empty in the chart defaults).
