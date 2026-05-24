# Example: On-demand GitLab CI job

Two job variants for running an on-demand Claude Code task from a GitLab pipeline.

## Setup

1. Set `ANTHROPIC_API_KEY` as a **masked + protected** CI/CD variable in your GitLab project.
2. Set `CLAUDE_TASK` as a CI/CD variable (or pass it via pipeline trigger).
3. Copy the desired job from [`snippet.yml`](snippet.yml) into your `.gitlab-ci.yml`.

## Manual trigger

Navigate to **CI/CD → Pipelines → Run pipeline** and set `CLAUDE_TASK` as a variable before triggering.

## API trigger

```bash
curl --request POST \
  --form token="$CI_JOB_TOKEN" \
  --form ref=main \
  --form "variables[CLAUDE_TASK]=summarise this week's merged MRs" \
  "https://gitlab.example.com/api/v4/projects/$PROJECT_ID/trigger/pipeline"
```

## Audit trail

Every execution emits structured JSON log lines containing:
- `ci_system: gitlab_ci`
- `ci_project`, `ci_run`, `ci_job`, `ci_commit`, `ci_branch`, `ci_runner`, `ci_user`
- `result: ok | error | timeout`
