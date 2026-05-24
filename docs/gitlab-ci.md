# GitLab CI/CD

## Pipeline stages

```
validate → build → package → deploy → on-demand
```

| Job | Stage | Trigger | Description |
|---|---|---|---|
| `validate:helm` | validate | always | `helm lint` + render AKS and OpenShift manifests as artifacts |
| `build:image` | build | branch push | Buildah builds and pushes the image; passes `SOURCE_URL=$CI_PROJECT_URL` |
| `package:helm` | package | always | `helm package` — chart `.tgz` stored as artifact for 30 days |
| `deploy:aks` | deploy | manual | `helm upgrade --install` against the AKS cluster |
| `deploy:openshift` | deploy | manual | `helm upgrade --install` against the OpenShift cluster |
| `run:on-demand-agent` | on-demand | manual | Runs the built image with `--once` using `CLAUDE_TASK` and `ANTHROPIC_API_KEY` |

## Required CI/CD variables

| Variable | Type | Used by | Description |
|---|---|---|---|
| `CI_REGISTRY_USER` | auto | build | GitLab container registry credentials |
| `CI_REGISTRY_PASSWORD` | auto | build | GitLab container registry credentials |
| `KUBE_CONFIG_AKS_B64` | masked | deploy:aks | Base64-encoded kubeconfig for the AKS cluster |
| `KUBE_CONFIG_OPENSHIFT_B64` | masked | deploy:openshift | Base64-encoded kubeconfig for the OpenShift cluster |
| `ANTHROPIC_API_KEY` | masked + protected | run:on-demand-agent | Anthropic API key — must be masked |
| `CLAUDE_TASK` | variable | run:on-demand-agent | Task prompt for the on-demand execution |

!!! danger "ANTHROPIC_API_KEY must be masked"
    Set the variable as **masked** and **protected** in GitLab CI/CD settings.
    The agent will never log it, but the CI runner log could expose it if it appears in environment dumps.

## On-demand job

```yaml
run:on-demand-agent:
  timeout: 30m
  retry:
    max: 1
    when: [runner_system_failure, stuck_or_timeout_failure]
  variables:
    OPERATING_MODE: on-demand
    TEAM_MATE_ROLE: operations
    CLAUDE_TIMEOUT_SECONDS: "1800"
```

The job inherits `ANTHROPIC_API_KEY` and `CLAUDE_TASK` from CI/CD variables.
Every execution emits a structured audit log line containing the GitLab project path, pipeline ID, job ID, commit SHA, branch, runner ID, and triggering user.

## Image naming

```
$CI_REGISTRY_IMAGE/claude-mate-agent:$CI_COMMIT_SHORT_SHA
$CI_REGISTRY_IMAGE/claude-mate-agent:latest
```

Both tags are pushed on every branch build.

## Artifact retention

| Artifact | Expires |
|---|---|
| `aks-rendered.yaml`, `openshift-rendered.yaml` | 7 days |
| `claude-mate-agent-*.tgz` | 30 days |
