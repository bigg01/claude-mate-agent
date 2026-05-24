# Example: Persona-based agent deployments

The Claude Mate Agent ships five built-in personas. Each persona loads a system-prompt file from `/opt/claude-mate/personas/<role>.md` at startup and optionally restricts the Claude Code tool set to match the role's responsibilities.

## Personas at a glance

| Role | `TEAM_MATE_ROLE` | Tool scope | Primary output |
|---|---|---|---|
| **Solution Architect** | `architect` | All tools incl. WebSearch | System-level ADRs, topology reviews, component-boundary recommendations |
| **Software Architect** | `software-architect` | All tools incl. WebSearch | Code-level ADRs, module/package refactoring plans, internal API contract reviews |
| **Security** | `security` | Read + Bash only (no writes) | Security findings reports, CVE analysis |
| **DevOps** | `devops` | All tools incl. file writes | Pipeline improvements, Dockerfile fixes, Helm reviews |
| **SRE** | `sre` | Read + Bash + WebFetch | Runbooks, SLO recommendations, reliability findings |
| **Operations** | `operations` | All tools (no restriction) | Ad-hoc tasks |

**Architect vs. Software Architect** — the Solution Architect thinks at the system/topology layer (services, deployments, ADRs for technology choices). The Software Architect thinks at the source-code layer (module boundaries, design patterns, dependency direction, refactoring plans). Pair them when you need both perspectives on the same codebase.

## Running a persona locally

```bash
# Security review of the repository
ANTHROPIC_API_KEY=sk-ant-... \
CLAUDE_TASK="Review this repository for OWASP Top 10 vulnerabilities and hardcoded secrets. Produce a risk report." \
TEAM_MATE_ROLE=security \
WORK_DIR=/path/to/your/repo \
  docker run --rm \
    -v /path/to/your/repo:/workspace \
    -e ANTHROPIC_API_KEY \
    -e CLAUDE_TASK \
    -e TEAM_MATE_ROLE \
    -e WORK_DIR=/workspace \
    claude-mate-agent:dev --once

# Architecture review
TEAM_MATE_ROLE=architect \
CLAUDE_TASK="Review the current architecture. Identify the top three coupling risks and create a concise ADR for each." \
  docker-compose run --rm \
    -e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY \
    -e CLAUDE_TASK \
    -e TEAM_MATE_ROLE \
    -v $(pwd):/workspace \
    -e WORK_DIR=/workspace \
    agent --once
```

## GitHub Actions integration

Trigger a persona-based review from the Actions UI:

1. Go to **Actions → On-Demand Agent → Run workflow**
2. Set **task** to the review prompt
3. Set **team_mate_role** to `architect`, `security`, `devops`, or `sre`
4. Enable **mount_repo** to give the agent access to the checked-out repository
5. Click **Run workflow**

The job summary will include cost and execution status.

## Helm values overlays

Use the values files in this directory to deploy a persona as a static Kubernetes workload or an on-demand job:

```bash
# Deploy security reviewer (on-demand mode)
helm upgrade --install claude-mate-security charts/claude-mate-agent \
  --namespace claude-mate --create-namespace \
  -f examples/personas/values-security.yaml \
  --set image.repository=ghcr.io/your-org/claude-mate-agent \
  --set image.tag=latest \
  --set claudeCode.apiKeySecretName=claude-mate-api-key
```

## Custom persona prompts

Override the built-in persona prompts by mounting a ConfigMap into the personas directory:

```yaml
# Custom persona ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: custom-personas
data:
  security.md: |
    You are a PCI-DSS compliance reviewer. Your focus is...
  custom-role.md: |
    You are a data privacy officer...
```

```yaml
# In Helm values
persona:
  personasDir: /opt/claude-mate/personas

# Mount the ConfigMap over the built-in personas
extraVolumes:
  - name: custom-personas
    configMap:
      name: custom-personas

extraVolumeMounts:
  - name: custom-personas
    mountPath: /opt/claude-mate/personas
```
