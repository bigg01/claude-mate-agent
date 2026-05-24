# DORA Metrics

The four DORA metrics — Deployment Frequency, Lead Time for Changes, Change Failure Rate, and Mean Time to Restore — are emitted from every CI/CD deploy job to a Prometheus Pushgateway and rendered on a Grafana dashboard auto-provisioned alongside the agent dashboard.

## Architecture

```
GitHub Actions ─┐
                ├─▶ scripts/dora-emit.sh ─▶ Pushgateway ─▶ Prometheus ─▶ Grafana
GitLab CI ──────┘                                                    │
                                                                     ▼
                                                              Alertmanager
```

| Component | Role |
|---|---|
| `scripts/dora-emit.sh` | Pushes `deploy`, `failure`, `restore` events as Prometheus exposition format |
| Pushgateway | Holds short-lived CI metrics so Prometheus can scrape them on schedule |
| `prometheus/dora_rules.yml` | Recording + alerting rules computed every 30 s |
| `grafana/dashboards/dora-metrics.json` | Auto-provisioned dashboard with four headline panels + trends |

## The four metrics

### 1. Deployment Frequency

How often you ship successful production deploys.

- Source: `dora_deployments_total{status="ok"}`
- Recording rule: `dora:deployments_per_day:7d`, `:30d`
- Target: ≥ 1/day per environment (stretch: ≥ 5/day)

### 2. Lead Time for Changes

Wall-clock seconds from commit timestamp to successful deploy.

- Source: `dora_lead_time_seconds` (per-deploy gauge)
- Recording rule: `dora:lead_time_seconds:p50:30d`, `:p95:30d`
- Target: P95 ≤ 1 day (stretch: ≤ 1 hour)

Lead time is calculated in the deploy job by:

```bash
COMMIT_TS=$(git log -1 --format=%ct "$SHA")
NOW=$(date -u +%s)
LEAD=$((NOW - COMMIT_TS))
```

For tag-based or manually-triggered deploys, this is an over-estimate; the recording rules normalise via quantiles over 30-day windows.

### 3. Change Failure Rate

Fraction of deploys that fail (rollout timeout, non-200 probe) or require an unplanned remediation.

- Source: `dora_change_failures_total / dora_deployments_total`
- Recording rule: `dora:change_failure_rate:30d`
- Target: ≤ 15% (stretch: ≤ 5%)

A change is counted as failed when:

1. The Helm `rollout status` times out (default 5 min), **or**
2. The post-deploy synthetic probe (`/healthz`, `/readyz`) returns non-200, **or**
3. A rollback or hotfix is deployed within 24 h targeting the same release

CI auto-counts (1) and (2); (3) is emitted manually via:

```bash
./scripts/dora-emit.sh failure --env prod --service claude-mate-agent --commit <sha>
```

### 4. Mean Time to Restore

Wall-clock seconds between incident open and service restoration.

- Source: `dora_restore_seconds` (per-incident gauge)
- Recording rule: `dora:mttr_seconds:30d`
- Target: ≤ 6 h (stretch: ≤ 1 h)

Emit on incident closure:

```bash
./scripts/dora-emit.sh restore --env prod --service claude-mate-agent --restore-seconds 1234
```

## Dashboard

The Grafana dashboard at `grafana/dashboards/dora-metrics.json` is auto-loaded by the local Docker Compose stack:

```bash
docker compose up
# Grafana → http://localhost:3000 → Dashboards → DORA Metrics
```

Panels:

- **Row 1 — Headline DORA Four** — Deployment Frequency, Lead Time P50, Change Failure Rate, MTTR
- **Row 2 — Trends** — Deployments per day (bar), Lead time P50 vs P95 (line)
- **Row 3 — Quality Gates** — Pass rate gauge, CVE findings by severity, test-coverage trend
- **Annotations** — Every successful deploy adds a green marker showing `env`/`commit`

Template variables let viewers filter by `env`. Default time window: 30 days.

## Alerting

Rules in `dora_rules.yml`:

| Alert | Condition | For | Severity |
|---|---|---|---|
| `DORAChangeFailureRateHigh` | `dora:change_failure_rate:30d > 0.15` | 1 h | warning |
| `DORALeadTimeRegression` | P95 lead time > 1 day | 2 h | info |
| `DORADeploymentFrequencyLow` | < 0.5 deploys/day | 24 h | info |

Routing is handled by your Alertmanager configuration — this repository does not ship a routing layer.

## Local testing

Push synthetic DORA events to the running stack:

```bash
PUSHGATEWAY_URL=http://localhost:9091 ./scripts/dora-emit.sh deploy \
  --env dev --status ok --lead-time-seconds 1800 --commit "$(git rev-parse HEAD)"

PUSHGATEWAY_URL=http://localhost:9091 ./scripts/dora-emit.sh failure \
  --env dev --service claude-mate-agent --commit "$(git rev-parse HEAD)"

PUSHGATEWAY_URL=http://localhost:9091 ./scripts/dora-emit.sh restore \
  --env dev --service claude-mate-agent --restore-seconds 540
```

Within ~15 s the dashboard updates with the new data point.

## CI configuration

Both GitHub Actions and GitLab CI deploy jobs auto-emit events when `PUSHGATEWAY_URL` is set:

| System | Where to set | Example value |
|---|---|---|
| GitHub Actions | Repository variable | `vars.PUSHGATEWAY_URL=https://pushgateway.example.com` |
| GitLab CI | CI/CD variable | `PUSHGATEWAY_URL=https://pushgateway.example.com` |

When the variable is unset, the emit steps no-op silently — CI does not require a Pushgateway to run.

## Transparency

The DORA dashboard is intended to be visible to every engineer on the team, not just SREs. The default Grafana instance enables anonymous viewer access on `http://localhost:3000`; production instances should expose the dashboard through SSO-gated read-only access.

A clear, agreed-upon definition of "failure" — see §3 above — is the most common reason DORA dashboards become unreliable. The definition is documented here and codified by the emit logic; changes require a PR with team sign-off.
