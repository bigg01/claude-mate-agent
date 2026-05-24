# Personas

Claude Mate Agent ships five built-in personas. Each persona activates when the agent starts in on-demand mode (`--once`) and applies a role-specific system prompt and Claude Code tool set to every task it executes.

## How personas work

When the agent starts, it reads `TEAM_MATE_ROLE` from the environment. It then:

1. Loads the system-prompt file from `$PERSONAS_DIR/<role>.md` (default: `/opt/claude-mate/personas/`)
2. Passes the prompt to the Claude CLI via `--system-prompt`
3. Applies a tool allow-list via `--allowedTools` if the persona has one
4. Runs the task in the working directory specified by `WORK_DIR` (defaults to `$CWD`)

The audit log records `role`, `persona_loaded`, and `tools_restricted` on every execution, giving a complete trail of which persona handled which task.

## Built-in personas

### Solution Architect

**Role:** `architect` | **Tools:** all tools including `WebSearch` and `Write`

Maintains architectural integrity at the **system / topology layer** — services, deployments, integration points, technology choices. Reads existing architecture documentation, maps component relationships, identifies cross-cutting risks, and authors Architecture Decision Records (ADRs).

**Typical tasks:**
- "Review the current deployment topology and identify the top three coupling risks across services"
- "Create an ADR for our decision to use Gateway API instead of Ingress"
- "Assess our integration points with the upstream identity provider for failure modes"

Pair with the **Software Architect** persona when you also need code-level review.

---

### Software Architect

**Role:** `software-architect` | **Tools:** all tools including `WebSearch` and `Write`

Maintains architectural integrity at the **source-code layer** — module / package boundaries, design patterns (hexagonal, clean, DDD), internal API contracts, dependency direction, refactoring plans. Where the Solution Architect thinks across services, the Software Architect thinks across packages, classes, and functions.

**Typical tasks:**
- "Map the module-level dependency graph and flag any cycles or violations of intended direction"
- "Audit whether this codebase follows hexagonal architecture; produce a refactoring plan ordered by leverage"
- "Review the public API of the `claudeCode` module for surface size and stability"
- "Identify the top three god classes and recommend a decomposition strategy"

The Software Architect explicitly **defers system-topology findings** to the Solution Architect — keeps each persona's outputs sharp and non-overlapping.

---

### Security

**Role:** `security` | **Tools:** `Read`, `Glob`, `Grep`, `LS`, `Bash` (no write access)

Performs security analysis without modifying any files. The security persona checks for OWASP Top 10 vulnerabilities, hardcoded secrets, outdated vulnerable dependencies, container misconfigurations, and CI/CD supply chain risks.

**Typical tasks:**
- "Scan for hardcoded API keys, tokens, and passwords across all files"
- "Review the Dockerfile and Helm chart for CIS Kubernetes benchmark compliance"
- "Check all dependencies for known CVEs and produce a risk-prioritised report"

---

### DevOps

**Role:** `devops` | **Tools:** all tools including `Write` and `Edit`

Reviews and improves build pipelines, container configurations, and Helm charts. Can make changes directly when asked. Identifies automation gaps and missing best practices in CI/CD.

**Typical tasks:**
- "Review the Dockerfile for layer caching improvements and security hardening"
- "Add a vulnerability scanning step to the GitHub Actions CI workflow"
- "Improve the Helm chart's default resource limits and probes"

---

### SRE

**Role:** `sre` | **Tools:** `Read`, `Write`, `Edit`, `Glob`, `Grep`, `LS`, `Bash`, `WebFetch`

Reviews the system for reliability, observability, and operational readiness. Creates runbooks and SLO recommendations. Focuses on failure modes, golden signals, and incident response.

**Typical tasks:**
- "Map all external dependencies and their failure modes"
- "Propose SLI expressions and SLO targets for the agent's HTTP endpoints"
- "Create a runbook in docs/runbooks/ for the pod-crash-loop incident scenario"

---

## Running a persona

### Docker / Podman

Mount your repository and set `WORK_DIR`:

```bash
docker run --rm \
  -v $(pwd):/workspace \
  -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
  -e CLAUDE_TASK="Review for OWASP Top 10 vulnerabilities. Produce a risk report." \
  -e TEAM_MATE_ROLE=security \
  -e WORK_DIR=/workspace \
  ghcr.io/your-org/claude-mate-agent:latest --once
```

### GitHub Actions

Trigger from the **Actions → On-Demand Agent** workflow. Select the persona from the **team_mate_role** dropdown and enable **mount_repo** to give the agent access to the repository contents.

The job summary shows the cost and execution result after the run completes.

### GitLab CI

Set `TEAM_MATE_ROLE` and `CLAUDE_TASK` as pipeline variables. Mount the repository via the runner's checkout path or an explicit Git clone step.

```yaml
architect:review:
  stage: review
  variables:
    TEAM_MATE_ROLE: architect
    CLAUDE_TASK: "Review the architecture and produce a structured findings report."
    WORK_DIR: $CI_PROJECT_DIR
  script:
    - docker run --rm
        -v "$CI_PROJECT_DIR:/workspace"
        -e ANTHROPIC_API_KEY
        -e CLAUDE_TASK
        -e TEAM_MATE_ROLE
        -e WORK_DIR=/workspace
        -e CI_PIPELINE_ID
        -e CI_JOB_ID
        "$CI_REGISTRY_IMAGE/claude-mate-agent:$CI_COMMIT_SHORT_SHA" --once
  when: manual
  allow_failure: false
```

## Prometheus metrics with role label

All metrics include a `role` label so you can compare cost and execution patterns across personas in Grafana:

```promql
# Cost per persona over the last 24 hours
sum by (role) (increase(claude_mate_agent_task_cost_usd_total[24h]))

# Task success rate per persona
sum by (role) (rate(claude_mate_agent_task_executions_total{result="ok"}[1h]))
/ sum by (role) (rate(claude_mate_agent_task_executions_total[1h]))
```

## Custom persona prompts

Override built-in prompts by mounting a Kubernetes ConfigMap over the personas directory:

```yaml
# configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-personas
  namespace: claude-mate
data:
  security.md: |
    You are a PCI-DSS compliance reviewer. Your scope is limited to cardholder data flows...
  data-privacy.md: |
    You are a GDPR Data Privacy Officer. Review this repository for personal data handling...
```

```yaml
# In Helm values (or values overlay)
persona:
  personasDir: /opt/claude-mate/personas

extraVolumes:
  - name: custom-personas
    configMap:
      name: custom-personas

extraVolumeMounts:
  - name: custom-personas
    mountPath: /opt/claude-mate/personas
    readOnly: true
```

The agent will use your custom prompt files instead of (or alongside) the built-in ones.
