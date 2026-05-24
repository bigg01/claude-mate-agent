IMAGE     ?= claude-mate-agent
# TAG defaults to the canonical SemVer in VERSION. Override for branch / dev
# builds, e.g.  TAG=$(git rev-parse --short HEAD)  make build.
TAG       ?= $(shell cat VERSION 2>/dev/null | tr -d '[:space:]' || echo dev)
PORT      ?= 8080
DOCS_PORT ?= 8000
CHART     := charts/claude-mate-agent
RELEASE   := claude-mate-agent
VERSION   := $(shell cat VERSION 2>/dev/null | tr -d '[:space:]' || echo 0.0.0)

# ── Artifactory mirrors (all optional — leave unset to use upstream registries) ──
# DOCKER_REGISTRY   Artifactory Docker virtual/remote repo hostname+path
#                   e.g. artifactory.example.com/docker-remote
# PYPI_INDEX_URL    Artifactory PyPI virtual repo simple index
#                   e.g. https://artifactory.example.com/artifactory/api/pypi/pypi-virtual/simple
# NPM_REGISTRY      Artifactory npm virtual repo
#                   e.g. https://artifactory.example.com/artifactory/api/npm/npm-virtual/
DOCKER_REGISTRY  ?=
PYPI_INDEX_URL   ?=
NPM_REGISTRY     ?=

# Construct optional --build-arg flags; each expands to empty string when unset.
_MIRROR_ARGS =
ifneq ($(DOCKER_REGISTRY),)
  _MIRROR_ARGS += --build-arg UBI9_IMAGE=$(DOCKER_REGISTRY)/ubi9/ubi:latest
  _MIRROR_ARGS += --build-arg UBI9_MINIMAL_IMAGE=$(DOCKER_REGISTRY)/ubi9/ubi-minimal:latest
  _MIRROR_ARGS += --build-arg UV_IMAGE=$(DOCKER_REGISTRY)/astral-sh/uv:latest
endif
ifneq ($(PYPI_INDEX_URL),)
  _MIRROR_ARGS += --build-arg PYPI_INDEX_URL=$(PYPI_INDEX_URL)
endif
ifneq ($(NPM_REGISTRY),)
  _MIRROR_ARGS += --build-arg NPM_REGISTRY=$(NPM_REGISTRY)
endif

# Container tool: auto-detect podman, fall back to docker.
# Override: make build CONTAINER_TOOL=docker
ifndef CONTAINER_TOOL
  _PODMAN := $(shell command -v podman 2>/dev/null)
  ifneq ($(_PODMAN),)
    CONTAINER_TOOL := podman
  else
    CONTAINER_TOOL := docker
  endif
endif

# COMPOSE — both `docker compose` and `podman compose` accept the same syntax
# and the same docker-compose.*.yml files. Override with CONTAINER_TOOL=docker
# or CONTAINER_TOOL=podman to force a specific tool.
COMPOSE := $(CONTAINER_TOOL) compose

# MKDOCS_BUILD has no port mapping (build doesn't serve); MKDOCS_SERVE does.
MKDOCS_BUILD := $(CONTAINER_TOOL) run --rm -v $(PWD):/docs docker.io/squidfunk/mkdocs-material
MKDOCS_SERVE := $(CONTAINER_TOOL) run -p $(DOCS_PORT):8000 --rm -v $(PWD):/docs docker.io/squidfunk/mkdocs-material

# Pass CLAUDE_TASK and ANTHROPIC_API_KEY from your shell environment.
# Windows users: use scripts/make.ps1 instead of this file.

.PHONY: help build run run-once check test sast scan scan-fs scan-config \
        secrets sbom security lock sync lint render render-aks \
        render-openshift render-gateway render-bundle package docs-build \
        docs-serve docs-diagrams version version-check release-tag \
        compose-up compose-up-local-llm compose-up-opensearch compose-up-gpu \
        compose-down clean

help:
	@echo "Container tool: $(CONTAINER_TOOL)  (override: CONTAINER_TOOL=docker|podman)"
	@echo ""
	@echo "Targets:"
	@echo "  build             Build the container image (IMAGE:TAG)"
	@echo "  run               Run the agent in static server mode on PORT"
	@echo "  run-once          Run on-demand mode (requires CLAUDE_TASK and ANTHROPIC_API_KEY in env)"
	@echo "  check             Syntax-check container/app.py with uv run"
	@echo "  test              Run pytest with coverage (fails under 50%)"
	@echo "  sast              Run Bandit Python SAST against container/app.py"
	@echo "  scan              Trivy scan: image (run after build) + filesystem + IaC config"
	@echo "  scan-fs           Trivy filesystem scan (deps, source code)"
	@echo "  scan-config       Trivy IaC scan (Dockerfile, Helm chart, manifests)"
	@echo "  secrets           Gitleaks secret scan of the working tree"
	@echo "  sbom              Generate CycloneDX SBOM for the image (requires syft)"
	@echo "  security          Run all security gates: test + sast + scan + secrets"
	@echo "  lock              Regenerate container/uv.lock from pyproject.toml"
	@echo "  sync              Sync local virtualenv to container/uv.lock"
	@echo "  lint              Helm lint the chart"
	@echo "  render            Render AKS, OpenShift, and Gateway API manifests"
	@echo "  render-aks        Render manifests with values-aks.yaml"
	@echo "  render-openshift  Render manifests with values-openshift.yaml + Route API"
	@echo "  render-gateway    Render manifests with Gateway API capabilities"
	@echo "  render-bundle     Render full chart to one manifest (for MCP-driven apply)"
	@echo "                    Overrides: NAMESPACE, VALUES, TAG"
	@echo "  package           Package the Helm chart as a .tgz"
	@echo "  docs-build        Build MkDocs static site to site/"
	@echo "  docs-serve        Live-preview docs at http://localhost:DOCS_PORT"
	@echo ""
	@echo "Local compose (works with $(CONTAINER_TOOL) compose — docker or podman):"
	@echo "  compose-up              Base stack: agent + Prometheus + Grafana + Pushgateway"
	@echo "  compose-up-local-llm    + Ollama + LiteLLM (zero API key, fully local)"
	@echo "  compose-up-opensearch   + OpenSearch + Dashboards (audit-log sink test)"
	@echo "  compose-up-gpu          + NVIDIA GPU passthrough on the agent"
	@echo "  compose-down            Stop everything (removes orphans, keeps volumes)"
	@echo "  docs-diagrams     Re-export docs/assets/architecture.drawio to JPEG"
	@echo "  clean             Remove the local container image and docs site"
	@echo ""
	@echo "Overrides: IMAGE=$(IMAGE) TAG=$(TAG) PORT=$(PORT) DOCS_PORT=$(DOCS_PORT)"
	@echo "Mirrors:   DOCKER_REGISTRY=$(DOCKER_REGISTRY) PYPI_INDEX_URL=$(PYPI_INDEX_URL) NPM_REGISTRY=$(NPM_REGISTRY)"

build:
	$(CONTAINER_TOOL) build \
		--build-arg VERSION=$(TAG) \
		--build-arg VCS_REF=$$(git rev-parse --short HEAD 2>/dev/null || echo unknown) \
		--build-arg BUILD_DATE=$$(date -u +%Y-%m-%dT%H:%M:%SZ) \
		--build-arg SOURCE_URL=$$(git remote get-url origin 2>/dev/null || echo unknown) \
		$(_MIRROR_ARGS) \
		-t $(IMAGE):$(TAG) .

run: build
	$(CONTAINER_TOOL) run --rm \
		-p $(PORT):8080 \
		-e OPERATING_MODE=static \
		$(IMAGE):$(TAG)

run-once:
	@test -n "$$ANTHROPIC_API_KEY" || (echo "ERROR: ANTHROPIC_API_KEY is not set" && exit 1)
	@test -n "$$CLAUDE_TASK"       || (echo "ERROR: CLAUDE_TASK is not set" && exit 1)
	$(CONTAINER_TOOL) run --rm \
		-e ANTHROPIC_API_KEY="$$ANTHROPIC_API_KEY" \
		-e CLAUDE_TASK="$$CLAUDE_TASK" \
		-e OPERATING_MODE=on-demand \
		$(IMAGE):$(TAG) --once

# Syntax check via uv so it uses the project's Python version.
# Falls back to plain python3 if uv is not installed.
check:
	@if command -v uv >/dev/null 2>&1; then \
	  cd container && uv run python -m py_compile app.py; \
	else \
	  python3 -m py_compile container/app.py; \
	fi
	@echo "app.py syntax OK"

# ── Quality and security gates ────────────────────────────────────────────────

# Run pytest with coverage. Requires the `test` extra (uv sync --extra test).
test:
	@if command -v uv >/dev/null 2>&1; then \
	  cd container && uv run --extra test pytest; \
	else \
	  cd container && python3 -m pytest; \
	fi

# Bandit Python SAST. Reads config from container/pyproject.toml.
sast:
	@if command -v uv >/dev/null 2>&1; then \
	  cd container && uv run --extra test bandit -r app.py -c pyproject.toml; \
	else \
	  cd container && bandit -r app.py -c pyproject.toml; \
	fi

# Trivy scans — fail on CRITICAL/HIGH unhandled by .trivyignore.
# Install Trivy: https://aquasecurity.github.io/trivy/latest/getting-started/installation/
scan: scan-fs scan-config
	@command -v trivy >/dev/null 2>&1 || { echo "ERROR: trivy not installed"; exit 1; }
	trivy image --severity CRITICAL,HIGH --exit-code 1 \
	  --ignore-unfixed --ignorefile .trivyignore \
	  $(IMAGE):$(TAG)

scan-fs:
	@command -v trivy >/dev/null 2>&1 || { echo "ERROR: trivy not installed"; exit 1; }
	trivy fs --severity CRITICAL,HIGH --exit-code 1 \
	  --ignore-unfixed --ignorefile .trivyignore \
	  --scanners vuln,secret \
	  --skip-dirs container/.venv,container/__pycache__,container/tests/__pycache__,site \
	  .

scan-config:
	@command -v trivy >/dev/null 2>&1 || { echo "ERROR: trivy not installed"; exit 1; }
	trivy config --severity CRITICAL,HIGH --exit-code 1 \
	  --skip-dirs container/.venv,site \
	  .

# Gitleaks secret scan. Install: https://github.com/gitleaks/gitleaks
secrets:
	@command -v gitleaks >/dev/null 2>&1 || { echo "ERROR: gitleaks not installed"; exit 1; }
	gitleaks detect --config .gitleaks.toml --verbose --redact

# Generate a CycloneDX SBOM for the built image. Install: https://github.com/anchore/syft
sbom:
	@command -v syft >/dev/null 2>&1 || { echo "ERROR: syft not installed"; exit 1; }
	syft $(IMAGE):$(TAG) -o cyclonedx-json=sbom.cyclonedx.json
	@echo "Wrote sbom.cyclonedx.json"

# Run every gate sequentially. Useful before opening a PR.
security: test sast scan secrets

# Regenerate container/uv.lock — commit the result.
lock:
	cd container && uv lock
	@echo "uv.lock updated — commit container/uv.lock"

# Sync local virtualenv with both extras so IDEs see build + test deps.
sync:
	cd container && uv sync --extra build --extra test

lint:
	helm lint $(CHART)

render: render-aks render-openshift render-gateway

render-aks:
	helm template $(RELEASE) $(CHART) \
		-f $(CHART)/values-aks.yaml \
		--set image.repository=$(IMAGE) \
		--set image.tag=$(TAG)

render-openshift:
	helm template $(RELEASE) $(CHART) \
		-f $(CHART)/values-openshift.yaml \
		--api-versions route.openshift.io/v1/Route \
		--set image.repository=$(IMAGE) \
		--set image.tag=$(TAG)

render-gateway:
	helm template $(RELEASE) $(CHART) \
		--set gateway.enabled=true \
		--api-versions gateway.networking.k8s.io/v1/HTTPRoute \
		--api-versions gateway.networking.k8s.io/v1/Gateway \
		--set image.repository=$(IMAGE) \
		--set image.tag=$(TAG)

# Render the full chart (including Namespace) to a single multi-doc YAML that an
# MCP-aware assistant can ingest and apply via resources_create_or_update.
# Overrides:
#   NAMESPACE  target namespace (default: claude-mate)
#   VALUES    optional values overlay path (e.g. examples/static-kubernetes/values.yaml)
#   TAG       image tag override (default: $(TAG))
# See: examples/mcp-deploy/ and docs/mcp-deploy.md
NAMESPACE ?= claude-mate
VALUES    ?=
render-bundle:
	@printf -- "---\napiVersion: v1\nkind: Namespace\nmetadata:\n  name: %s\n" "$(NAMESPACE)"
	@helm template $(RELEASE) $(CHART) \
		--namespace $(NAMESPACE) \
		$(if $(VALUES),-f $(VALUES),) \
		--set image.repository=$(IMAGE) \
		--set image.tag=$(TAG)

package:
	helm package $(CHART)

docs-build:
	$(MKDOCS_BUILD) build --strict

docs-serve:
	$(MKDOCS_SERVE) serve --dev-addr 0.0.0.0:8000 &
	@echo "Docs available at http://localhost:$(DOCS_PORT)"

# Re-export docs/assets/architecture.drawio → architecture.jpg.
# Requires the drawio CLI (https://github.com/jgraph/drawio-desktop).
# Install: snap install drawio  OR  flatpak install flathub com.jgraph.drawio.desktop
docs-diagrams:
	@command -v drawio >/dev/null 2>&1 || { \
	  echo "ERROR: drawio CLI not found on PATH"; \
	  echo "Install: snap install drawio  (or download from https://github.com/jgraph/drawio-desktop)"; \
	  exit 1; }
	drawio --no-sandbox -x -f jpg -q 95 -b 20 --width 1920 \
	  -o docs/assets/architecture.jpg docs/assets/architecture.drawio
	@echo "Exported docs/assets/architecture.jpg"

# ── Local compose stacks (works with both docker compose and podman compose) ──
# CONTAINER_TOOL is auto-detected; override with CONTAINER_TOOL=docker if needed.
# Equivalent to running the underlying `$(COMPOSE) ...` command shown beside each target.

compose-up:
	$(COMPOSE) up --build

compose-up-local-llm:
	$(COMPOSE) -f docker-compose.yml -f docker-compose.local-llm.yml up --build

compose-up-opensearch:
	$(COMPOSE) -f docker-compose.yml -f docker-compose.opensearch.yml up --build

compose-up-gpu:
	$(COMPOSE) -f docker-compose.yml -f docker-compose.nvidia.yml up --build

compose-down:
	$(COMPOSE) down --remove-orphans

clean:
	$(CONTAINER_TOOL) rmi $(IMAGE):$(TAG) 2>/dev/null || true
	rm -rf site/

# ── Versioning (SemVer 2.0.0) ─────────────────────────────────────────────────

# Print the current canonical version.
version:
	@echo $(VERSION)

# Verify every artefact agrees with VERSION. Used by CI before tagging.
version-check:
	@FILE=$$(cat VERSION | tr -d '[:space:]'); \
	PY=$$(awk -F\" '/^version =/ {print $$2}' container/pyproject.toml); \
	CHART=$$(awk '/^version:/ {print $$2}' $(CHART)/Chart.yaml); \
	APP=$$(awk '/^appVersion:/ {gsub(/"/,""); print $$2}' $(CHART)/Chart.yaml); \
	TAG=$$(awk -F\" '/^  tag:/ {print $$2; exit}' $(CHART)/values.yaml); \
	ok=1; \
	for v in "$$PY" "$$CHART" "$$APP" "$$TAG"; do \
	  [ "$$v" = "$$FILE" ] || { echo "ERROR: '$$v' != VERSION '$$FILE'"; ok=0; }; \
	done; \
	[ $$ok = 1 ] && echo "All artefacts at version $$FILE" || exit 1

# Bump the version across every artefact. Usage:
#   make release-tag NEW=patch          # 1.2.3 → 1.2.4
#   make release-tag NEW=minor          # 1.2.3 → 1.3.0
#   make release-tag NEW=major          # 1.2.3 → 2.0.0
#   make release-tag NEW=1.4.0-rc.1     # exact SemVer string
release-tag:
	@test -n "$(NEW)" || { echo "ERROR: NEW=patch|minor|major|<version> required"; exit 2; }
	./scripts/bump-version.sh $(NEW)
