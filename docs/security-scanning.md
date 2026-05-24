# Security Scanning, SAST, and Code Coverage

Every commit on `main`, `develop`, and every pull request runs through five gates: unit tests with coverage, Python SAST, multi-language SAST, secret scanning, and CVE scanning of dependencies, IaC, and the final container image. A signed CycloneDX SBOM accompanies every published image.

## What runs on every push

| Gate | Tool | Scope | Blocks on |
|---|---|---|---|
| Unit tests + coverage | pytest + pytest-cov | `container/app.py` | < 50% coverage |
| Python SAST | Bandit | `container/app.py` | CRITICAL/HIGH findings |
| Multi-language SAST | Semgrep (`p/ci`, `p/security-audit`, `p/dockerfile`, `p/kubernetes`) | Whole repo | Configurable per ruleset |
| Secret scan | Gitleaks | Full git history | Any leak match |
| Dependency CVEs | Trivy `fs` (`vuln,secret`) | `pyproject.toml`, `uv.lock`, etc. | Fixed CRITICAL/HIGH |
| IaC misconfig | Trivy `config` | Dockerfile, Helm, K8s manifests | CRITICAL/HIGH |
| Image CVEs | Trivy `image` | Built container image | Fixed CRITICAL/HIGH |
| SBOM | Syft → CycloneDX | Built image | — (artifact only) |

Findings upload to GitHub Code Scanning (SARIF) and surface on the **Security** tab and inline in PRs. GitLab equivalents post to merge-request widgets.

## Coverage threshold

Set in `container/pyproject.toml`:

```toml
[tool.pytest.ini_options]
addopts = [
  "--cov=app",
  "--cov-fail-under=50",
]
```

The starting threshold is 50%. Raise it (never lower it) as tests are added — every PR that adds production code should add tests.

## Run gates locally

```bash
make test       # pytest + coverage (50% threshold)
make sast       # Bandit
make scan       # Trivy fs + IaC + image (image scan requires prior `make build`)
make secrets    # Gitleaks
make sbom       # Syft → sbom.cyclonedx.json
make security   # All of the above, sequentially
```

Tool prerequisites:

| Tool | Install |
|---|---|
| `uv` | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| `trivy` | https://aquasecurity.github.io/trivy/latest/getting-started/installation/ |
| `gitleaks` | `brew install gitleaks` or https://github.com/gitleaks/gitleaks/releases |
| `syft` | `curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh \| sh -s -- -b /usr/local/bin` |
| `semgrep` (optional) | `pip install semgrep` |

`make sync` installs the Python test toolchain (pytest, pytest-cov, bandit) into `container/.venv`.

## Pipeline gating

Both CI systems enforce the same dependency order:

```
validate-helm ─┐
               ├─▶ build-and-push ─▶ trivy-image ─▶ deploy
test ──────────┤
sast ──────────┤
secrets ───────┤
trivy-fs ──────┤
trivy-config ──┘
```

A merge-blocking failure on any gate stops the pipeline before push to any registry.

## Allowlists

CVE allowlist: `.trivyignore` — one CVE per line with a trailing `# rationale` comment.

```
CVE-2024-12345  # accepted — only exploitable via local file write, container is read-only root FS
```

Secret allowlist: `.gitleaks.toml` — paths and regex patterns for documented false positives (placeholder strings in docs/examples).

SAST suppressions: `# nosec B###` inline with a rationale comment. Blanket file/directory exclusions in `[tool.bandit]` are not permitted without a documented architectural reason.

## SBOM publication

Every successful image build attaches a CycloneDX SBOM (`sbom.cyclonedx.json`) as a CI artifact retained for 90 days. The SBOM lists:

- OS packages from the UBI9 base image (`registry.access.redhat.com/ubi9/ubi-minimal`)
- Python packages bundled by PyInstaller (from `uv.lock`)
- npm packages from the global `@anthropic-ai/claude-code` install
- Image layer digests and creation timestamps

Downstream consumers can verify supply-chain integrity by attesting the SBOM matches the deployed image digest.

## What is *not* automatically scanned

- The deployed cluster's runtime state — use Kubernetes Pod Security Admission and a runtime scanner (Falco, Tetragon) for that.
- Prompt injection — gate at the LLM gateway (Kong AI plugins, LiteLLM moderation).
- License obligations of dependencies — add a license scanner (`pip-licenses`, FOSSA, Snyk) if your compliance program requires it.

See `requirement.md` §25 for the full requirements catalogue.
