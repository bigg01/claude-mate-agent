# ── Registry mirrors ──────────────────────────────────────────────────────────
# Override these build-args to route all external pulls through Artifactory.
# Example:
#   --build-arg UBI9_IMAGE=artifactory.example.com/docker-remote/ubi9/ubi:latest
#   --build-arg UV_IMAGE=artifactory.example.com/docker-remote/astral-sh/uv:latest
ARG UBI9_IMAGE="registry.access.redhat.com/ubi9/ubi:latest"
ARG UBI9_MINIMAL_IMAGE="registry.access.redhat.com/ubi9/ubi-minimal:latest"
ARG UV_IMAGE="ghcr.io/astral-sh/uv:latest"

# ── Stage 0: alias the uv image to a named stage ──────────────────────────────
# Buildkit forbids variable expansion in `COPY --from=` but allows it in `FROM`,
# so we materialise UV_IMAGE here and reference it by stage name below.
FROM ${UV_IMAGE} AS uv-source

# ── Stage 1: compile Python wrapper into a single static binary ───────────────
FROM ${UBI9_IMAGE} AS python-builder

ARG PYPI_INDEX_URL=""

# uv — fast Python package manager; replaces pip entirely in this stage.
COPY --from=uv-source /uv /usr/local/bin/uv

RUN dnf -y install python3.12 python3.12-devel binutils \
    && dnf -y clean all \
    && rm -rf /var/cache/dnf

WORKDIR /build

# Copy dependency manifest first so layer cache survives app.py-only edits.
COPY container/pyproject.toml ./

# UV_SYSTEM_PYTHON=1 installs into the system Python instead of a venv.
# UV_PYTHON pins to 3.12 explicitly — UBI9's default `python3` is still 3.9.
ENV UV_SYSTEM_PYTHON=1 \
    UV_PYTHON=python3.12

# --extra build adds pyinstaller; --no-install-project skips installing
# the project itself (app.py is a script, not a distributable package).
# When PYPI_INDEX_URL is set, uv resolves packages through the Artifactory PyPI mirror.
RUN if [ -n "$PYPI_INDEX_URL" ]; then \
        uv sync --extra build --no-install-project --default-index "$PYPI_INDEX_URL"; \
    else \
        uv sync --extra build --no-install-project; \
    fi

COPY container/app.py app.py

# --collect-all opentelemetry bundles lazy-imported OTEL namespace packages
# --runtime-tmpdir /tmp directs onefile extraction to the emptyDir /tmp mount
# uv run picks up pyinstaller from the .venv that uv sync just created
# (UV_SYSTEM_PYTHON has no effect on uv sync — only on uv pip install).
RUN uv run --extra build pyinstaller --onefile --name agent --clean --strip \
        --collect-all opentelemetry \
        --runtime-tmpdir /tmp \
        app.py


# ── Stage 2: install Claude Code CLI ─────────────────────────────────────────
FROM ${UBI9_IMAGE} AS node-builder

ARG CLAUDE_CODE_VERSION="2.1.150"
ARG NPM_REGISTRY=""

RUN dnf -y module enable nodejs:22 \
    && dnf -y install nodejs npm \
    && if [ -n "$NPM_REGISTRY" ]; then npm config set registry "$NPM_REGISTRY"; fi \
    && npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
    && npm cache clean --force \
    && dnf -y clean all \
    && rm -rf /var/cache/dnf /root/.npm


# ── Stage 3: minimal runtime image ───────────────────────────────────────────
FROM ${UBI9_MINIMAL_IMAGE}

ARG BUILD_DATE="unknown"
ARG VERSION="dev"
ARG VCS_REF="unknown"
ARG SOURCE_URL=""
ARG CLAUDE_CODE_VERSION="2.1.150"

LABEL org.opencontainers.image.title="Claude Mate Agent" \
      org.opencontainers.image.description="Claude Mate agent container with health, metrics, and on-demand pipeline mode" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.vendor="Claude Mate" \
      org.opencontainers.image.base.name="registry.access.redhat.com/ubi9/ubi-minimal:latest"

# Node.js runtime binary (claude CLI requires it; ubi-minimal provides glibc/libstdc++)
COPY --from=node-builder /usr/bin/node /usr/bin/node

# Claude Code CLI: module directory contains all npm dependencies
COPY --from=node-builder \
     /usr/local/lib/node_modules/@anthropic-ai/claude-code \
     /usr/local/lib/node_modules/@anthropic-ai/claude-code

# Copy the entry-point symlink/wrapper created by npm install -g as-is
COPY --from=node-builder /usr/local/bin/claude /usr/local/bin/claude

# Compiled agent binary (Python + OTEL bundled; no Python interpreter needed)
COPY --from=python-builder /build/dist/agent /opt/claude-mate/agent

# Persona system-prompt files — read at runtime by the agent binary
COPY container/personas/ /opt/claude-mate/personas/

RUN chgrp -R 0 /opt/claude-mate && chmod -R g=u /opt/claude-mate

ENV APP_NAME="claude-mate-agent" \
    APP_VERSION="${VERSION}" \
    PORT="8080" \
    HOME="/tmp" \
    npm_config_cache="/tmp/.npm"

EXPOSE 8080

USER 1001

ENTRYPOINT ["/opt/claude-mate/agent"]
