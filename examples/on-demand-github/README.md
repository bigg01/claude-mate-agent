# Example: On-demand GitHub Actions workflow

Runs a Claude Code task via GitHub Actions `workflow_dispatch` with full audit trail.

## Setup

1. Add `ANTHROPIC_API_KEY` to your repository secrets (**Settings → Secrets and variables → Actions**).
2. The `workflow.yml` is already deployed at [`.github/workflows/on-demand.yml`](../../.github/workflows/on-demand.yml).
   This example file is a standalone copy for reference.

## Run a task

1. Go to **Actions → On-Demand Agent → Run workflow**
2. Fill in the **task** prompt field
3. Select the **team_mate_role** for the audit trail
4. Click **Run workflow**

## Audit trail

Every run emits structured JSON including:
- `ci_system: github_actions`
- `ci_project` (repository), `ci_run` (run ID), `ci_job`, `ci_commit`, `ci_branch`
- `ci_user` (actor), `ci_workflow`, `ci_runner`
- `result: ok | error | timeout`

## Restrict access with a GitHub environment

Create a `on-demand` environment in **Settings → Environments** with:
- Required reviewers for approval before execution
- `ANTHROPIC_API_KEY` scoped to that environment only
