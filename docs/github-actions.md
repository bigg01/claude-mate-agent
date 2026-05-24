# GitHub Actions CI/CD

Three workflows ship with the repository under `.github/workflows/`. They mirror the GitLab CI pipeline and share the same container image published to GHCR.

## Workflows

### `ci.yml` — Continuous Integration

Triggered on every push and pull request.

**Jobs:**

| Job | What it does |
|---|---|
| `validate-helm` | `helm lint` + renders all three routing variants (AKS, OpenShift, Gateway API) |
| `build-docs` | Builds MkDocs site with `--strict`; fails on warnings |
| `build-and-push` | Builds multi-stage image, tags with commit SHA + branch + `latest`, pushes to GHCR |

Image tags produced:

```
ghcr.io/<org>/<repo>/claude-mate-agent:sha-<short-sha>
ghcr.io/<org>/<repo>/claude-mate-agent:<branch-name>
ghcr.io/<org>/<repo>/claude-mate-agent:latest   # on default branch only
```

Layer caching uses `type=gha` (GitHub Actions cache) to speed up repeated builds.

### `deploy.yml` — Deploy to Cluster

Triggered manually via `workflow_dispatch`.

**Inputs:**

| Input | Description | Default |
|---|---|---|
| `environment` | Target cluster type (`aks` or `openshift`) | — |
| `image_tag` | Image tag to deploy | `latest` |
| `namespace` | Kubernetes namespace | `claude-mate` |

The job runs `helm upgrade --install --atomic --timeout 5m` followed by `kubectl rollout status` to confirm the rollout completes.

**Required secrets:**

| Secret | Used for |
|---|---|
| `KUBE_CONFIG_AKS_B64` | Base64-encoded kubeconfig for AKS deploy |
| `KUBE_CONFIG_OPENSHIFT_B64` | Base64-encoded kubeconfig for OpenShift deploy |

### `on-demand.yml` — On-Demand Agent Task

Triggered manually via `workflow_dispatch`. Runs the agent container with `--once` and a user-supplied task prompt.

**Inputs:**

| Input | Description | Default |
|---|---|---|
| `task` | Claude Code task prompt | — |
| `image_tag` | Agent image tag | `latest` |
| `team_mate_role` | Role for audit trail (`operations`, `security`, `sre`, `architect`) | `operations` |
| `timeout_seconds` | Task timeout | `1800` |

**Required secrets:**

| Secret | Used for |
|---|---|
| `ANTHROPIC_API_KEY` | Anthropic API key injected into the container at runtime |

**Run a task:**

1. Go to **Actions → On-Demand Claude Code Task → Run workflow**
2. Fill in the **task** prompt
3. Select **team_mate_role**
4. Click **Run workflow**

Every run produces a structured JSON audit log with `ci_system: github_actions` and full GitHub context fields (`ci_project`, `ci_run`, `ci_job`, `ci_commit`, `ci_branch`, `ci_user`, `ci_workflow`, `ci_runner`).

## Required Secrets

Configure these in **Settings → Secrets and variables → Actions**:

| Secret | Required by |
|---|---|
| `ANTHROPIC_API_KEY` | `on-demand.yml` |
| `KUBE_CONFIG_AKS_B64` | `deploy.yml` (AKS) |
| `KUBE_CONFIG_OPENSHIFT_B64` | `deploy.yml` (OpenShift) |

`GITHUB_TOKEN` is provided automatically by GitHub Actions for GHCR authentication — no configuration needed.

## Restricting On-Demand Access

Create an `on-demand` environment in **Settings → Environments** and:

- Add required reviewers (approval gate before each run)
- Scope `ANTHROPIC_API_KEY` to that environment only

The `on-demand.yml` workflow references `environment: on-demand`, so it will pause for approval before the container runs.

## GHCR Image Registry

Images are pushed to `ghcr.io/<github-org>/<repo>/claude-mate-agent`. To pull images privately, packages must be linked to the repository and visibility set appropriately under **Settings → Packages**.

For downstream Helm deployments using a GHCR image, add an image pull secret:

```bash
kubectl create secret docker-registry ghcr-pull-secret \
  --docker-server=ghcr.io \
  --docker-username=<github-actor> \
  --docker-password=<personal-access-token> \
  --namespace claude-mate
```

Then set `imagePullSecrets[0].name=ghcr-pull-secret` in your Helm values.
