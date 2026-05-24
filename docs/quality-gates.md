# SDLC Quality Gates

Every change passes through an explicit sequence of automated gates from code to runtime. A failure at any stage blocks the change from progressing — there is no manual override path that bypasses the gates without a recorded approval.

## Gate matrix

```
Plan ─▶ Code ─▶ Build ─▶ Package ─▶ Deploy ─▶ Run ─▶ Observe
                                                          │
                                                          ▼
                                                    DORA telemetry
```

| Phase | Gate | Tool | Local target | Pipeline job | Blocks on |
|---|---|---|---|---|---|
| Code | Python SAST | Bandit | `make sast` | `bandit` (security.yml) / `sast:bandit` | CRITICAL/HIGH |
| Code | Multi-lang SAST | Semgrep | — | `semgrep` (security.yml) | Configurable per ruleset |
| Code | Secret scan | Gitleaks | `make secrets` | `gitleaks` / `secrets:gitleaks` | Any leak |
| Build | Unit tests | pytest | `make test` | `test` / `test:python` | Any failure |
| Build | Coverage | pytest-cov | `make test` | `test` / `test:python` | < 50% |
| Build | Dep CVEs | Trivy fs | `make scan-fs` | `trivy-filesystem` / `scan:trivy-fs` | Fixed CRITICAL/HIGH |
| Build | IaC misconfig | Trivy config | `make scan-config` | `trivy-config` / `scan:trivy-config` | CRITICAL/HIGH |
| Package | Image CVEs | Trivy image | `make scan` | `trivy-image` / `scan:trivy-image` | Fixed CRITICAL/HIGH |
| Package | SBOM | Syft | `make sbom` | `trivy-image` / `sbom:syft` | Missing artifact |
| Package | Helm lint | helm lint | `make lint` | `validate-helm` / `validate:helm` | Any error |
| Package | Helm render | helm template | `make render` | `validate-helm` / `validate:helm` | Any render error |
| Deploy | Smoke test | helm rollout status | — | `deploy` jobs | 5 min timeout |
| Deploy | Probe | `/healthz`, `/readyz` | — | `deploy` jobs | Non-200 |
| Run | Metrics scrape | Prometheus `up` | — | Continuous | up==0 for > 5 min |
| Observe | DORA emission | Pushgateway POST | — | Every deploy job | Missing event |

## Pipeline DAG

```
validate-helm ─┐                                  ┌─▶ deploy ─▶ DORA emit
               ├─▶ build-and-push ─▶ trivy-image ─┤
test ──────────┤                                  └─▶ sbom (syft)
bandit ────────┤
semgrep ───────┤
gitleaks ──────┤
trivy-fs ──────┤
trivy-config ──┘
```

Each `─▶` is an explicit `needs:` (GitLab) or `needs:` (GitHub Actions) edge.

## Running the gates locally

```bash
# Individual gates
make test           # pytest + 50% coverage floor
make sast           # Bandit
make scan           # Trivy: fs + config + image
make secrets        # Gitleaks
make sbom           # Syft → sbom.cyclonedx.json

# All at once (recommended before opening a PR)
make security
```

Each target emits machine-readable artifacts (SARIF, JUnit XML, Cobertura, CycloneDX) so CI aggregation reads the same data your local run does.

## Allowlists and rationale

- **CVE allowlist** — `.trivyignore` (one CVE per line + `# why`)
- **Secret false positives** — `.gitleaks.toml`
- **Bandit suppressions** — inline `# nosec B<id>` with rationale; blanket exclusions require sign-off
- **Code coverage exemptions** — recorded in `[tool.coverage.report] exclude_also`

Every entry must include a one-line rationale; orphan suppressions are removed at quarterly cadence.

## How gate outcomes feed DORA

The pipeline emits the following Pushgateway metrics on every run:

| Metric | When | Used for |
|---|---|---|
| `pipeline_quality_gate_runs_total` | Each build-and-push completion | DORA pass-rate denominator |
| `pipeline_quality_gate_pass_total` | Each successful build-and-push | DORA pass-rate numerator |
| `pipeline_test_coverage_percent` | Each test run | Coverage trend |
| `dora_deployments_total{status}` | Each deploy job | Deployment Frequency / Change Failure Rate |
| `dora_lead_time_seconds` | Each successful deploy | Lead Time |
| `dora_change_failures_total` | On rollout failure | Change Failure Rate |
| `dora_restore_seconds` | On incident closure | MTTR |

See [DORA Metrics](dora-metrics.md) for the dashboard, targets, and alerting rules.
