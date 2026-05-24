# Container Build

## Multi-stage Dockerfile

The image is built in three stages. Only compiled artifacts reach the final layer.

```
┌─────────────────────┐    ┌─────────────────────┐
│   python-builder    │    │    node-builder      │
│   ubi9/ubi          │    │    ubi9/ubi           │
│                     │    │                     │
│  python3 + pip      │    │  nodejs:20 + npm    │
│  pyinstaller        │    │  @anthropic-ai/     │
│  opentelemetry-*    │    │  claude-code@pinned │
│                     │    │                     │
│  → dist/agent       │    │  → /usr/bin/node    │
│    (single binary)  │    │  → /usr/local/bin/  │
│                     │    │    claude           │
│                     │    │  → node_modules/    │
│                     │    │    @anthropic-ai/   │
│                     │    │    claude-code/     │
└────────┬────────────┘    └──────────┬──────────┘
         │  COPY --from                │  COPY --from
         ▼                            ▼
┌────────────────────────────────────────────────┐
│                   runtime                      │
│               ubi9/ubi-minimal                 │
│                                                │
│  /opt/claude-mate/agent   (compiled binary)    │
│  /usr/bin/node            (Node.js runtime)    │
│  /usr/local/bin/claude    (CLI entry point)    │
│  /usr/local/lib/node_modules/@anthropic-ai/    │
│    claude-code/           (with dependencies)  │
│                                                │
│  NO: python3, pip, npm, dnf, gcc, make         │
└────────────────────────────────────────────────┘
```

## Build arguments

| ARG | Default | Description |
|---|---|---|
| `VERSION` | `dev` | Image version, written to OCI label and `APP_VERSION` env |
| `VCS_REF` | `unknown` | Git commit SHA |
| `BUILD_DATE` | `unknown` | ISO 8601 build timestamp |
| `SOURCE_URL` | `""` | Source repository URL (OCI label) |
| `CLAUDE_CODE_VERSION` | `1.0.3` | Pinned `@anthropic-ai/claude-code` version |

The `Makefile` populates `VCS_REF` and `BUILD_DATE` automatically from `git` and `date`.

## PyInstaller compilation

`app.py` is compiled with:

```
pyinstaller --onefile --name agent --clean --strip \
    --collect-all opentelemetry \
    --runtime-tmpdir /tmp \
    app.py
```

| Flag | Why |
|---|---|
| `--onefile` | Produces a single self-contained executable |
| `--strip` | Strips debug symbols — reduces binary size |
| `--collect-all opentelemetry` | Bundles all OTEL namespace packages; without this, the lazy imports inside `_setup_otel()` are invisible to PyInstaller's static analyser |
| `--runtime-tmpdir /tmp` | Extraction target when the binary runs — aligns with the `/tmp` emptyDir mount in the Helm chart |

!!! note "Read-only filesystem and PyInstaller"
    `--onefile` binaries self-extract at startup. With `readOnlyRootFilesystem: true`, this only works because the Helm chart mounts `/tmp` as an emptyDir volume. Do not remove that volume mount.

## Claude Code entry point

`npm install -g` creates a wrapper script or symlink at `/usr/local/bin/claude`. The final stage copies it with `COPY --from=node-builder /usr/local/bin/claude /usr/local/bin/claude`, preserving whatever npm created (symlink or script).

The full `@anthropic-ai/claude-code` module directory — including its own `node_modules/` subdirectory — is copied so no additional npm install is needed at runtime.

## OpenShift arbitrary UID

`HOME=/tmp` is set in the image `ENV`. Node.js calls `os.homedir()` to locate `~/.claude`. Without a writable home directory the CLI fails under the arbitrary UIDs assigned by OpenShift SCC. Setting `HOME=/tmp` redirects that to the writable emptyDir mount.

## Updating dependencies

- **Claude Code version**: change `CLAUDE_CODE_VERSION` build arg in the Dockerfile or pass `--build-arg CLAUDE_CODE_VERSION=x.y.z`.
- **OTEL/Python packages**: edit `container/requirements.txt` and rebuild.
- **PyInstaller version**: add `pyinstaller==x.y.z` to `container/requirements.txt` or pin it in the `pip3 install` line in the builder stage.
