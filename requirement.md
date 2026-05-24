# Requirements: Claude Mate Agents Container Platform

## 1. Purpose

Define the enterprise requirements for running Claude Mate agents as containerized workloads on Kubernetes and Red Hat OpenShift, with standard operational monitoring, OpenShell-based protection, and remote audit trail synchronization.

## 2. Scope

This document applies to:

- Claude Mate agent containers running the Claude Code CLI.
- Kubernetes clusters used for production, staging, and development.
- Red Hat OpenShift enterprise environments.
- Static always-on Kubernetes and OpenShift deployments.
- On-demand GitLab CI/CD and GitHub Actions pipeline execution.
- Claude sandboxes — ephemeral, isolated one-shot Kubernetes Jobs.
- Persona-based team-mate roles for Architect, Security, DevOps, and SRE personas.
- LLM provider routing — direct Anthropic, Kong AI Gateway, LiteLLM, OpenRouter, Azure AI Foundry, Google Vertex AI, NVIDIA NIM.
- NVIDIA Container Runtime for GPU-accelerated workloads.
- Artifactory remote mirrors for Docker, PyPI, npm, and Helm.
- Monitoring, logging, security, and audit-trail integrations.
- Remote log synchronization targets used for compliance and investigation.
- Container CVE scanning, dependency scanning, IaC misconfig scanning, Python SAST, multi-language SAST, secret scanning, SBOM generation, and Python unit-test coverage.
- DORA metrics (Deployment Frequency, Lead Time, Change Failure Rate, MTTR) and the SDLC quality-gate matrix.

## 2.1 Capabilities at a Glance

The platform delivers five capability pillars; each is enumerated in detail in the numbered requirements that follow.

| Pillar | Capabilities | Requirement sections |
|---|---|---|
| **Execution** | Static long-running Deployment · on-demand CI Job · sandboxed Kubernetes Job with kernel-level isolation | §3, §6, §24 |
| **Connectivity** | Direct Anthropic API · LLM gateway (Kong, LiteLLM) · OpenRouter · Azure AI Foundry · Vertex AI · NVIDIA NIM (via translation proxy) | §23 |
| **Observability** | Prometheus `/metrics` · OTEL OTLP export · Grafana agent dashboard · Grafana DORA dashboard · structured audit logs · remote log sync | §7, §8, §11, §20, §26 |
| **Protection** | Defense-in-depth: minimal base image · read-only root FS · non-root + arbitrary UID · NetworkPolicy egress allow-list · sandbox kernel isolation · persona tool allow-list · CVE/SAST/secret scanning · SBOM · Renovate | §4, §9, §13, §17, §24, §25 |
| **Transparency** | DORA-metric pipeline · quality-gate pass rate · pipeline test-coverage trend · CVE-findings dashboard · per-deploy lead-time/status events | §25, §26 |

## 3. Platform Requirements

### 3.1 Kubernetes Support

The solution must run on a CNCF-conformant Kubernetes cluster.

Minimum requirements:

- Kubernetes version must be supported by the enterprise platform lifecycle policy.
- Workloads must be deployed using standard Kubernetes resources such as `Deployment`, `Service`, `ConfigMap`, `Secret`, `ServiceAccount`, `Role`, `RoleBinding`, `NetworkPolicy`, and `PersistentVolumeClaim` where needed.
- Traffic routing must support the Kubernetes Gateway API (`GatewayClass`, `Gateway`, `HTTPRoute`) as an alternative to `Ingress` where the Gateway API is available in the cluster.
- `HTTPRoute` resources must be rendered only when the `gateway.networking.k8s.io/v1` API is present in the cluster.
- The deployment must support attaching to an existing shared `Gateway` via `parentRefs`, or optionally provisioning a dedicated `Gateway` resource within the same namespace.
- `GatewayClass` selection must be configurable to support any CNCF-conformant gateway implementation such as Envoy Gateway, Cilium, NGINX Gateway Fabric, or Azure Application Gateway for Containers.
- Container images must run without privileged access unless formally approved by security.
- Pods must define CPU and memory requests and limits.
- Pods must support readiness, liveness, and startup probes.
- Deployments must support rolling updates and rollback.
- Workloads must support horizontal scaling through replica count or Horizontal Pod Autoscaler.
- Application configuration must be injected through environment variables, mounted configuration, or Kubernetes secrets.

### 3.2 OpenShift Support

The solution must run on Red Hat OpenShift Enterprise Standard environments.

Minimum requirements:

- Workloads must be compatible with OpenShift Security Context Constraints.
- Containers must support running as a non-root user with an arbitrary UID.
- Images must not require root-owned writable paths.
- Writable data must be placed under approved writable directories such as `/tmp` or mounted volumes.
- Routes, Services, and Ingress resources must be supported according to the OpenShift cluster standard.
- OpenShift Gateway API support via the OpenShift Service Mesh or Red Hat OpenShift Gateway API implementation must be supported where available.
- The deployment must support OpenShift-native image scanning, admission policies, and registry controls.
- The deployment must support OpenShift monitoring and logging integrations.

### 3.3 Claude Code Agent Runtime

The Claude Mate agent container runs the Anthropic Claude Code CLI (`claude`) as its primary agent runtime.

Minimum requirements:

- The container image must include the Claude Code CLI (`@anthropic-ai/claude-code`) installed from the official npm registry using an enterprise-approved Node.js runtime.
- The Node.js version must be supported by the enterprise platform lifecycle policy and compatible with the installed Claude Code version.
- The Claude Code CLI must be invocable as a non-interactive process using the `--print` flag for on-demand and pipeline execution.
- The Anthropic API key required by the Claude Code CLI must be injected at runtime through a Kubernetes or OpenShift Secret and must never be embedded in the container image or source code.
- The Claude Code CLI version must be pinned and controlled through the build process; floating `latest` installs are not permitted for production images.
- Claude Code CLI output must be captured and forwarded to the structured logging pipeline.
- Sensitive prompt content, API responses, and keys must not appear in logs or audit records.
- The agent process wrapper must emit structured audit events for Claude Code task start, completion, and failure, including task identity and exit code.
- The Claude Code CLI home directory must be placed under an approved writable path such as `/tmp` or a mounted volume to support arbitrary UID execution on OpenShift.

## 4. Container Requirements

The Claude Mate agent container must meet the following requirements:

- Use a multi-stage build to produce the smallest possible runtime image; build tooling must not be present in any final image layer.
- The final runtime image must be based on `registry.access.redhat.com/ubi9/ubi-minimal` or an equivalently minimal enterprise-approved base.
- The Python agent wrapper must be compiled into a self-contained standalone executable using PyInstaller or an equivalent tool; the final image must not contain a Python interpreter, pip, or pip-installed packages.
- The compiled executable must bundle all Python runtime dependencies, including optional OpenTelemetry packages.
- The Node.js runtime binary and the Claude Code CLI module must be copied from the build stage; npm and package manager tools must not be present in the final image.
- Build stages may use the full `ubi9/ubi` image; only the compiled artifacts are promoted to the runtime stage.
- The Claude Code CLI (`@anthropic-ai/claude-code`) must be installed at a pinned version during the build stage.
- Python dependency management must use `uv` as the package manager in the build stage; `pip` and `pip3` must not be used directly.
- Python runtime and build dependencies must be declared in `container/pyproject.toml` using the standard `[project.dependencies]` and `[project.optional-dependencies]` tables; `requirements.txt` must not be the authoritative dependency source.
- A `uv.lock` file must be committed to the repository to ensure fully reproducible dependency resolution across all builds; `uv lock` must be run and the lock file committed whenever `pyproject.toml` dependencies change.
- The `uv` binary must be sourced from the official `ghcr.io/astral-sh/uv` image using a `COPY --from` instruction; it must not be downloaded via shell script during the build.
- PyInstaller is a build-time-only dependency and must be declared in the `build` optional-dependency group in `pyproject.toml`; it must not appear in the runtime dependency list.
- Run as a non-root user.
- Support running as an arbitrary UID as required by OpenShift SCC.
- Use a read-only root filesystem where feasible; writable paths must use mounted volumes or `/tmp`.
- The Claude Code CLI home directory must be set to a writable path at runtime via `HOME=/tmp`, since OpenShift assigns an arbitrary UID with no guaranteed home directory.
- Avoid embedded credentials, tokens, or private keys; the Anthropic API key must be injected via Kubernetes or OpenShift Secret at runtime.
- Support configuration through externalized runtime settings.
- Emit structured logs to `stdout` and `stderr`.
- Expose a health endpoint for Kubernetes and OpenShift probes.
- Expose metrics in Prometheus-compatible format where applicable.
- Include image labels for version, build date, source repository, and maintainer.
- Be scanned for vulnerabilities before promotion to production.
- Be signed or verified using the enterprise container image trust process.

## 5. Deployment Requirements

The deployment must include:

- Namespace or project isolation per environment.
- Dedicated service account with least-privilege permissions.
- RBAC rules limited to required actions only.
- Network policies restricting ingress and egress traffic.
- Traffic exposure must support three routing mechanisms: Kubernetes `Ingress`, OpenShift `Route`, and Kubernetes Gateway API `HTTPRoute`; exactly one must be enabled per deployment.
- TLS for all external and internal service communication where supported.
- Secrets managed by the enterprise secret management process.
- Configurable replica count.
- Pod anti-affinity or topology spread constraints for high availability.
- Resource quotas and limit ranges aligned with platform standards.
- Support for GitOps or CI/CD-based deployment.

## 6. Operating Mode Requirements

The solution must support two operating modes.

### 6.1 Option 1: Static Kubernetes or OpenShift Deployment

Static mode is used when Claude Mate agents run continuously inside Kubernetes or OpenShift.

Minimum requirements:

- Agents must be deployed as long-running workloads using Kubernetes or OpenShift-native resources.
- Agents must support fixed replica counts and autoscaling where appropriate.
- Agents must restart automatically after pod, node, or container failure.
- Configuration must be managed through Kubernetes or OpenShift configuration and secret resources.
- Monitoring, logging, audit trail, and OpenShell protection must be active for the full lifetime of the workload.
- Static deployments must support production-grade high availability, maintenance windows, rollback, and change tracking.
- Static deployments must be suitable for shared platform services used by multiple teams.

### 6.2 Option 2: On-Demand CI/CD Pipeline Execution

On-demand mode is used when Claude Mate agents run only for a specific pipeline, job, task, or approved workflow. Both GitLab CI/CD and GitHub Actions are supported CI platforms.

Minimum requirements:

- Agents must be executable from GitLab CI/CD pipelines and GitHub Actions workflows using approved runners.
- Pipeline execution must support Kubernetes or OpenShift runner backends where available.
- Each on-demand execution must have a unique job, pipeline, commit, branch, project, and user identity in logs and audit records.
- Secrets used by pipeline jobs must come from CI/CD variables, external secret management, or approved workload identity mechanisms; GitLab CI/CD variables must be masked and protected.
- The Claude Code task or prompt to execute must be supplied through the `CLAUDE_TASK` environment variable or an approved equivalent mechanism; it must not be embedded in the image.
- The Anthropic API key must be supplied through a masked and protected CI/CD variable (`ANTHROPIC_API_KEY`) or an equivalent approved mechanism and must never appear in logs or pipeline output.
- On-demand containers must be short-lived and cleaned up automatically after completion or failure.
- Pipeline jobs must enforce resource limits, timeouts, retry rules, and failure handling.
- Pipeline-generated logs, audit events, and security events must be synchronized to the remote log destination.
- OpenShell access to on-demand jobs must be disabled by default and only enabled through approved break-glass workflows.
- Pipeline definitions must be version-controlled and reviewed before production use.
- GitHub Actions `workflow_dispatch` workflows that execute agent tasks must be gated by an environment with required reviewers where possible.
- The agent container must detect the CI platform at runtime and emit a structured audit context that identifies the CI system (`ci_system`), project, run or pipeline ID, job, commit, branch, runner, and triggering user using a common field schema regardless of platform.

### 6.3 GitHub Actions Support

The solution must include GitHub Actions CI/CD workflow definitions for building, deploying, and running on-demand agent tasks.

Minimum requirements:

- A CI workflow must validate Helm chart rendering, build the MkDocs documentation site, and build and push the container image to the GitHub Container Registry (GHCR) on every push and pull request.
- Container images built by GitHub Actions must be tagged with the commit SHA, branch name, and `latest` (on the default branch).
- A deployment workflow triggered by `workflow_dispatch` must deploy the Helm chart to a target Kubernetes or OpenShift cluster using a base64-encoded kubeconfig secret.
- An on-demand workflow triggered by `workflow_dispatch` must accept a task prompt, team mate role, image tag, and timeout as inputs and run the agent container with `--once`.
- GitHub Actions workflows must use GitHub-managed OIDC or repository secrets for all credentials; secrets must never be printed or logged.
- Build layer caching must be enabled to reduce image build times using the GitHub Actions cache backend.

## 7. Monitoring Requirements

The platform must provide monitoring for the Claude Mate agent workloads.

Required monitoring capabilities:

- Pod health, restart count, and availability.
- CPU, memory, disk, and network utilization.
- Request rate, error rate, and latency where the agent exposes service endpoints.
- Queue depth, job count, task execution status, or equivalent agent activity metrics where applicable.
- Container image version and deployment revision visibility.
- Alerting for failed pods, crash loops, high resource usage, unavailable replicas, probe failures, and abnormal error rates.
- Integration with Prometheus, OpenShift Monitoring, Grafana, Alertmanager, or enterprise-approved monitoring tools.
- Dashboards for operations, security, and service ownership teams.

### 7.1 Prometheus Metrics

The agent container must expose a Prometheus-compatible metrics endpoint.

Required capabilities:

- The `/metrics` endpoint must be available on the agent HTTP port and must return metrics in Prometheus text format version 0.0.4.
- The endpoint must expose at minimum: process availability (`claude_mate_agent_up`), process start timestamp (`claude_mate_agent_start_timestamp_seconds`), uptime (`claude_mate_agent_uptime_seconds`), HTTP request count (`claude_mate_agent_http_requests_total`), and on-demand task execution count with result label (`claude_mate_agent_task_executions_total`).
- A Prometheus Operator `ServiceMonitor` resource must be configurable via the Helm chart to enable automatic scrape target registration.
- The scrape interval and timeout must be configurable.

### 7.2 OpenTelemetry Metrics Export

The agent container must optionally export metrics to an OpenTelemetry-compatible collector via OTLP.

Required capabilities:

- OTLP metrics export must be configurable at runtime through environment variables and must be disabled by default.
- When enabled, the agent must export the same metrics exposed on the Prometheus endpoint to the configured OTLP HTTP endpoint using the `opentelemetry-exporter-otlp-proto-http` protocol.
- The OTLP endpoint must be configurable via `OTEL_EXPORTER_OTLP_ENDPOINT`.
- The export interval must be configurable via `OTEL_EXPORT_INTERVAL_MILLIS`.
- OTEL resource attributes must include the service name, Kubernetes namespace, and pod name.
- On-demand pipeline executions must force-flush pending OTEL metrics before process exit to prevent data loss.
- OTEL initialization failure must be logged but must not prevent the agent from starting or executing its task.
- The OpenTelemetry SDK version must be pinned in the container image build manifest.

## 8. Logging Requirements

The solution must provide centralized logging.

Required logging capabilities:

- Application logs must be written to `stdout` and `stderr` in structured JSON format when possible.
- Logs must include timestamp, severity, component, request or task identifier, namespace, pod name, container name, and correlation ID where applicable.
- Sensitive data such as credentials, tokens, secrets, prompts containing protected data, and private keys must not be logged.
- Logs must be collected by the enterprise logging stack.
- Logs must support search, filtering, retention, and export.
- Log retention must comply with enterprise and regulatory requirements.

## 9. OpenShell Protection Requirements

Claude Mate agent workloads must be protected by OpenShell or the enterprise-approved OpenShell protection layer.

Required protection capabilities:

- Shell access to running containers must be disabled by default or restricted to approved break-glass workflows.
- Interactive access must require strong authentication and authorization.
- Access must be limited by role, namespace, workload, and environment.
- All shell sessions must be logged and auditable.
- Commands executed through OpenShell must be captured in the audit trail.
- OpenShell access must enforce session timeout and inactivity timeout.
- Privilege escalation must be blocked unless explicitly approved.
- Access requests must be traceable to an individual user identity.
- OpenShell policies must be managed as code where possible.
- OpenShell activity must be forwarded to the centralized security monitoring system.

### 9.1 OpenShell Technical Implementation

The Helm chart must support enterprise OpenShell protection through Kubernetes-native controls and annotations.

Minimum requirements:

- The Helm chart must include an `openshell` configuration block in `values.yaml` that controls protection mode and pod annotations.
- When `openshell.enabled: true`, the Helm chart must add the configured annotations to every pod so that the enterprise OpenShell admission webhook or agent can identify and protect the workload.
- Pod annotations must be configurable to match the annotation schema of the enterprise OpenShell product (e.g., `openshell.io/protection`, `openshell.io/audit`).
- Pods must run with `readOnlyRootFilesystem: true`, no privilege escalation, and all Linux capabilities dropped to deny container breakout that would circumvent OpenShell controls.
- The `kubectl exec` surface must be restricted through Kubernetes RBAC; the chart ServiceAccount must not be bound to roles that permit exec on its own pods.
- OpenShell session events must be captured by the enterprise protection layer and forwarded to the centralized audit trail and security monitoring system.

## 10. Audit Trail Requirements

The solution must maintain a complete audit trail for security, compliance, and incident response.

Audit events must include:

- Deployment creation, update, rollback, and deletion.
- GitLab pipeline, job, runner, commit, branch, project, and triggering user details for on-demand executions.
- Configuration and secret reference changes.
- Authentication and authorization decisions.
- OpenShell access requests, approvals, denials, session starts, session ends, and executed commands.
- Administrative actions performed against the workload.
- Agent start, stop, restart, and abnormal termination events.
- Security policy violations.
- Image pull, image verification, and image scan results where available.

Each audit event must include:

- Timestamp in UTC.
- User or service account identity.
- Source IP or originating system where available.
- Namespace or OpenShift project.
- Workload, pod, and container identity.
- Action performed.
- Result or status.
- Correlation ID or request ID where available.

## 11. Remote Log Sync Requirements

Audit trails and security logs must be synchronized to a remote logging destination.

Minimum requirements:

- Logs must be forwarded to an enterprise-approved remote log platform such as SIEM, object storage, centralized syslog, Elasticsearch/OpenSearch, Splunk, or another approved destination.
- Remote log sync must support TLS encryption in transit.
- Remote log sync must authenticate using approved credentials, certificates, or workload identity.
- Local buffering must be supported during temporary remote destination outages.
- Buffered logs must be retried until successfully delivered or until retention limits are reached.
- Log delivery failures must generate alerts.
- Remote logs must be protected from tampering and unauthorized deletion.
- Audit logs must have retention configured according to compliance requirements.
- Time synchronization must be enforced across cluster nodes and log receivers.
- Log synchronization must preserve original event timestamps and source metadata.

## 12. Team Mate Role Support Requirements

The solution must support different team mate roles and responsibilities across the enterprise.

### 12.1 Security Team Mate Support

Security users must be able to:

- Review workload security posture, image scan status, and policy compliance.
- Review OpenShell access requests, approvals, denials, and command history.
- Search audit trails by user, namespace, workload, pipeline, and time range.
- Receive alerts for policy violations, suspicious shell activity, failed log sync, and unapproved privilege escalation.
- Validate that secrets are not exposed in logs, pipeline output, manifests, or container images.

### 12.2 Operations Team Mate Support

Operations users must be able to:

- Deploy, update, rollback, and scale static Kubernetes or OpenShift workloads through approved workflows.
- View workload health, pod status, restart count, events, and deployment revision.
- Access operational dashboards and alerts.
- Trigger approved maintenance, restart, and recovery actions.
- Confirm that remote logging and monitoring integrations are healthy.

### 12.3 SRE Team Mate Support

SRE users must be able to:

- Define and review service-level indicators, service-level objectives, and alert thresholds.
- Analyze error rates, latency, saturation, resource usage, and reliability trends.
- Review pipeline execution reliability for on-demand agents.
- Perform incident investigation using correlated metrics, logs, traces, audit events, and deployment history.
- Tune autoscaling, resource limits, probes, timeouts, and retry policies.

### 12.4 Architect Team Mate Support

Architect users must be able to:

- Review architecture, deployment topology, integration points, and environment boundaries.
- Validate that Kubernetes, OpenShift, GitLab, OpenShell, monitoring, and logging integrations align with enterprise standards.
- Define approved operating patterns for static and on-demand agent usage.
- Review capacity, scalability, resilience, and disaster recovery design.
- Maintain reference architecture and implementation guidance for adopting teams.

## 13. Security Requirements

The solution must follow enterprise container and cluster security standards.

Required controls:

- Least-privilege RBAC.
- Non-root containers.
- Restricted Linux capabilities.
- Seccomp, AppArmor, or SELinux profiles where supported.
- OpenShift SCC compliance.
- NetworkPolicy enforcement.
- TLS for service communication.
- Encrypted secrets at rest.
- Regular image vulnerability scanning.
- Admission control for untrusted images and unsafe workload configuration.
- No hardcoded secrets in images, manifests, or source code.
- Dependency and base image patching according to vulnerability severity SLAs.

## 14. Availability and Resilience Requirements

The platform must support reliable operation.

Minimum requirements:

- Multiple replicas for production workloads where the agent supports active-active operation.
- Pod disruption budgets for critical workloads.
- Rolling updates with no avoidable downtime.
- Automatic restart of failed containers.
- Graceful shutdown handling.
- Configurable timeout and retry behavior for external dependencies.
- Backup and restore procedures for persistent state, if any.
- Disaster recovery requirements aligned with business RTO and RPO targets.

## 15. Compliance Requirements

The deployment must support enterprise compliance needs.

Minimum requirements:

- Audit evidence must be retained for the required compliance period.
- Access to logs and audit data must be restricted by role.
- Production access must be reviewed periodically.
- Changes must be traceable to approved change records or CI/CD runs.
- On-demand GitLab pipeline executions must be traceable to project, pipeline, job, commit, branch, runner, and triggering user.
- Security exceptions must be documented, approved, and time-bound.
- Compliance reports must be available for workload configuration, access, deployments, and audit log delivery.

## 16. Acceptance Criteria

The implementation is acceptable when:

- Claude Mate agent containers deploy successfully on Kubernetes.
- Claude Mate agent containers deploy successfully on OpenShift Enterprise Standard.
- Static always-on mode is supported on Kubernetes or OpenShift.
- On-demand mode is supported through GitLab CI/CD pipelines and GitHub Actions workflows.
- Containers run as non-root and comply with OpenShift SCC requirements.
- Health checks and metrics are available.
- Monitoring dashboards and alerts are configured.
- Logs are collected centrally.
- OpenShell protection is enabled and shell access is restricted.
- OpenShell sessions and commands are captured in the audit trail.
- Audit events are synchronized to the remote log destination.
- CI/CD pipeline audit context (GitLab or GitHub Actions) is included for on-demand executions.
- Container image builds succeed with both Docker and Podman.
- Security, Operations, SRE, and Architecture team mates have role-appropriate visibility and controls.
- Remote log sync failure generates an alert.
- Security scans and admission controls pass according to enterprise policy.

## 17. Local Development and Cross-Platform Build Requirements

The solution must provide tooling for local development, testing, and image building that works on Linux, macOS, and Windows.

Minimum requirements:

- A `Makefile` must be provided with targets for building the container image, running the agent locally, linting and rendering the Helm chart, building documentation, and cleaning build artifacts.
- The `Makefile` must auto-detect whether `podman` or `docker` is available and use the detected tool without requiring manual configuration; the active tool must be overridable via the `CONTAINER_TOOL` variable.
- Both Podman and Docker must be supported as container build and run backends; Buildah is supported for CI image builds.
- A Windows PowerShell script (`scripts/make.ps1`) must provide equivalent functionality to the `Makefile` for Windows developers; it must support the same targets and auto-detect Podman or Docker.
- The `make run-once` and PowerShell equivalent must validate that `ANTHROPIC_API_KEY` and `CLAUDE_TASK` are set before running the container to prevent silent failures.
- Helm chart rendering targets must exercise all three routing variants (AKS Ingress, OpenShift Route, and Gateway API HTTPRoute) to verify that capability-gated templates render correctly.
- The `make docs-build` and `make docs-serve` targets must build and serve the MkDocs documentation using the `squidfunk/mkdocs-material` container image without requiring a local Python installation.
- Local build defaults must be suitable for development use; production image builds must be performed through CI/CD pipelines with pinned versions and build-time metadata.

## 18. Solution Architecture Documentation Requirements

The solution must include and maintain up-to-date architecture documentation.

Minimum requirements:

- A solution architecture diagram must be maintained in `docs/assets/architecture.drawio` using the draw.io XML format, editable with draw.io Desktop or app.diagrams.net.
- The diagram must show all major system components: developer and operator interactions, GitLab CI/CD and GitHub Actions pipeline stages, container registry, Kubernetes or OpenShift cluster topology, pod internals (agent binary and claude CLI), secrets injection, routing resources, HPA, PDB, NetworkPolicy, RBAC, and all observability integrations.
- The diagram must reflect both operating modes: static long-running deployment and on-demand CI/CD pipeline execution.
- A MkDocs Material documentation site must be maintained under the `docs/` directory and must be buildable using the `squidfunk/mkdocs-material` container image without local Python installation.
- Documentation must cover: solution architecture, getting started, component architecture, container build, Helm chart values and routing options, GitLab CI/CD pipeline, GitHub Actions workflows, monitoring and metrics reference, security and compliance controls, and component usage examples.
- The `docs:build` GitLab CI job must build the documentation site with `--strict` mode and store the output as a pipeline artifact.
- The `make docs-build` and `make docs-serve` targets must be available for local documentation development.
- Architecture diagrams and documentation must be updated as part of any change that alters system components, integration points, deployment topology, or security controls.

## 19. Persona and Team Mate Role Requirements

The Claude Mate Agent must support multiple built-in personas that define the agent's role, system prompt, tool permissions, and task focus for each on-demand execution.

### 19.1 Built-in Personas

The solution must ship four built-in persona definitions:

| Persona | Role value | Purpose |
|---|---|---|
| **Architect** | `architect` | Architecture review, ADR creation, design pattern assessment, technical debt identification |
| **Security** | `security` | OWASP Top 10 assessment, secrets scanning, dependency CVE analysis, container and CI/CD security review |
| **DevOps** | `devops` | CI/CD pipeline review, Dockerfile and Helm chart improvement, automation gap identification |
| **SRE** | `sre` | Reliability review, SLO/SLI definition, runbook creation, observability gap identification |

An unrestricted `operations` role must also be supported for ad-hoc tasks that do not require a specific persona.

### 19.2 Persona Technical Requirements

Minimum requirements:

- Each persona must be defined as a Markdown file (`<role>.md`) stored at a configurable path inside the container (default: `/opt/claude-mate/personas/`).
- The persona Markdown file must contain a structured system prompt that defines the agent's mission, responsibilities, working method, constraints, and output format.
- The persona system prompt must be passed to the Claude Code CLI via the `--system-prompt` flag when building the CLI invocation for an on-demand task.
- Each persona must specify an allowed-tool set that is passed to the Claude Code CLI via `--allowedTools`. The security persona must be restricted to read-only tools (`Read`, `Glob`, `Grep`, `LS`, `Bash`) and must not include write or edit tools.
- Persona files must be loaded from the filesystem at runtime, not compiled into the binary, so that operators can override or extend them by mounting a Kubernetes ConfigMap over the personas directory.
- The `PERSONAS_DIR` environment variable must control the directory from which persona files are loaded; the Helm chart must expose this as a configurable value.
- When a persona file cannot be found for the configured role, the agent must fall back to running without a custom system prompt rather than failing.
- The `WORK_DIR` environment variable must set the working directory for the Claude Code CLI process, enabling the agent to operate on a mounted repository checkout. The Helm chart must expose this as a configurable value under `claudeCode.workDir`.
- Every on-demand execution must log `role`, `persona_loaded`, and `tools_restricted` as structured fields in the `agent_started` audit event.
- All Prometheus and OTEL metrics must include a `role` label so cost and task execution can be analysed per persona in Grafana.

### 19.3 Persona Deployment Requirements

Minimum requirements:

- Each persona must have a Helm values overlay in `examples/personas/` that configures `teamMateRole`, `operatingMode`, a default task prompt, and `claudeCode.workDir`.
- The GitHub Actions `on-demand.yml` workflow must expose `team_mate_role` as a `workflow_dispatch` input with all five role choices (`operations`, `architect`, `security`, `devops`, `sre`).
- The workflow must support an optional `mount_repo` input that mounts the checked-out repository into the container at `/workspace` and sets `WORK_DIR=/workspace`.
- The GitLab CI snippet for on-demand jobs must document how to set `TEAM_MATE_ROLE` and `WORK_DIR` for persona-based pipeline execution.
- Custom persona prompts must be overridable at deploy time by mounting a Kubernetes ConfigMap over the personas directory without rebuilding the container image.

## 20. Claude API Cost Tracking Requirements  

The solution must track, expose, and report Claude API usage costs for every on-demand task execution and pipeline run.

Minimum requirements:

- The agent must invoke the Claude Code CLI with `--output-format json` to obtain structured output that includes `cost_usd` and `duration_ms` fields in the response.
- The agent must maintain cumulative cost and task execution counters and expose them as Prometheus metrics: `claude_mate_agent_task_cost_usd_total` (counter), `claude_mate_agent_task_last_duration_seconds` (gauge), and `claude_mate_agent_task_executions_total{result}` (counter by result).
- Cost metrics must be present in the Prometheus `/metrics` output in both static and on-demand modes; values are `0` until a task executes.
- When OTEL is enabled, the `claude_mate_agent_task_cost_usd_total` counter must be exported via OTLP alongside the other agent metrics.
- Every on-demand task execution must emit a `task_cost_summary` structured log event containing `cost_usd` and `task_executions` at the end of the run, regardless of success or failure.
- CI/CD pipeline definitions must include a cost reporting step that extracts the `task_cost_summary` log line and surfaces the cost in the pipeline job summary (GitHub Actions step summary or GitLab CI dotenv report artifact).
- Cost metrics must be visible in the Grafana dashboard alongside task execution and health metrics.
- The Grafana dashboard must include: total cost (stat), average cost per task (stat), cost per hour (time series), task success rate (gauge), and task executions by result (time series).
- A pre-built Grafana dashboard JSON must be maintained at `grafana/dashboards/claude-mate-agent.json` and auto-provisioned by the Docker Compose local development stack.

## 21. GitOps Deployment Requirements

The solution must support GitOps-based deployment using ArgoCD and FluxCD.

Minimum requirements:

- An ArgoCD `Application` manifest must be provided in `examples/argocd/` that deploys the Helm chart from the git repository with automated sync, pruning, and self-healing enabled.
- The ArgoCD `Application` must include an `ignoreDifferences` rule for `/spec/replicas` to allow the Horizontal Pod Autoscaler to manage replica counts without triggering drift detection.
- A FluxCD `HelmRepository` and `HelmRelease` manifest must be provided in `examples/fluxcd/` that deploys the Helm chart with upgrade remediation and rollback on failure.
- The FluxCD `HelmRelease` must support a `valuesFrom` reference to an existing Kubernetes Secret for sensitive Helm values.
- Both GitOps examples must document the prerequisite Secret creation for the Anthropic API key and reference the matching Helm values overlay for the target platform.
- GitOps deployments must be compatible with the existing Helm chart without modifications; all GitOps-specific configuration must reside in the example manifests only.

## 22. NVIDIA Container Runtime Requirements

### 22.1 GPU Access

The platform must support optional GPU access for AI/ML workloads via the [NVIDIA Container Runtime](https://github.com/NVIDIA/nvidia-container-toolkit).

Requirements:

- GPU support must be opt-in via a Helm value (`nvidia.enabled`). Deployments without GPU requirements must not be affected.
- When enabled, the pod spec must declare `runtimeClassName: nvidia` to use the NVIDIA RuntimeClass registered by the GPU Operator.
- The container must receive `nvidia.com/gpu` resource requests and limits matching the configured `gpuCount`.
- The `NVIDIA_VISIBLE_DEVICES=all` and `NVIDIA_DRIVER_CAPABILITIES` environment variables must be injected automatically when GPU is enabled.

### 22.2 Cluster Prerequisites

- The [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/getting-started.html) must be installed on the cluster, **or** the NVIDIA device plugin and `nvidia-container-toolkit` must be configured manually on GPU nodes.
- GPU nodes must be labelled `nvidia.com/gpu.present=true` (automatic with GPU Operator).
- A `RuntimeClass` named `nvidia` must be registered in the cluster (automatic with GPU Operator).

### 22.3 Node Scheduling

- When GPU is enabled, pods must be scheduled exclusively on GPU nodes via a `nodeSelector` (`nvidia.com/gpu.present=true` by default).
- Toleration for the `nvidia.com/gpu=true:NoSchedule` taint must be applied automatically when GPU is enabled.
- Both the `nodeSelector` and `tolerations` must merge with any user-supplied values so standard scheduling constraints are preserved.

### 22.4 Driver Capabilities

- Supported NVIDIA driver capability sets: `compute,utility` (default), `video`, `graphics`, or any valid combination accepted by the NVIDIA Container Runtime.
- The capability string must be configurable via `nvidia.driverCapabilities` in Helm values.

### 22.5 Local Development

- A `docker-compose.nvidia.yml` override file must enable GPU access when running locally with Docker Compose.
- The override must set the `nvidia` Docker runtime and reserve all available GPU devices.
- Prerequisites for local GPU access: `nvidia-container-toolkit` installed and configured on the host, Docker daemon restarted after toolkit configuration.

## 23. LLM Provider and Gateway Requirements

### 23.1 Provider Independence

The platform must run the Claude Code CLI against any Anthropic-compatible API endpoint. The image and Helm chart must not hard-code `api.anthropic.com`.

Requirements:

- The `ANTHROPIC_BASE_URL` environment variable must be exposed as a configurable Helm value (`claudeCode.baseUrl`). When unset, the container falls back to the Anthropic public endpoint.
- The `ANTHROPIC_API_VERSION` environment variable must be exposed as a configurable Helm value (`claudeCode.apiVersion`) for providers (notably Azure AI Foundry) that require an explicit API version header.
- `ANTHROPIC_API_KEY` must hold whatever credential the configured endpoint expects — direct Anthropic key, gateway consumer key, OpenRouter key, Azure Cognitive Services key, or LiteLLM virtual key.
- Switching providers must not require rebuilding the container image; only secret rotation and a Helm value change are permitted.

### 23.2 Supported Provider Categories

The platform must support, at minimum, the following provider configurations:

1. **Direct Anthropic API** — `api.anthropic.com`, no gateway, lowest latency.
2. **LLM Gateway (Anthropic-compatible)** — Kong AI Gateway, LiteLLM proxy, or equivalent that exposes an Anthropic-format endpoint and proxies to one or more backends.
3. **OpenRouter** — multi-provider router with native Anthropic-format API.
4. **Microsoft Azure AI Foundry** — Claude models hosted in Azure with enterprise compliance and private networking.
5. **Google Gemini / Vertex AI** — either Vertex AI's Anthropic-compatible Claude endpoint, or native Gemini via LiteLLM translation.
6. **NVIDIA NIM free-tier** — OpenAI-format provider accessed via a LiteLLM (or Kong) translation layer for Anthropic compatibility.

### 23.3 Gateway Architecture

For Anthropic-incompatible upstreams, a translation gateway must sit between the agent and the provider:

```
claude-mate-agent  ──Anthropic API──▶  LiteLLM / Kong  ──Provider API──▶  NVIDIA NIM / Gemini native
```

Requirements:

- The gateway must be reachable from the agent's pod via a `NetworkPolicy`-permitted egress route.
- The agent must not require knowledge of the upstream provider — routing, model selection, and credential management belong to the gateway.
- Gateway choice (Kong vs. LiteLLM vs. alternative) must be operator-selected; the chart must remain gateway-agnostic.

### 23.4 Per-Provider Configuration Examples

The repository must ship one Helm values overlay per supported provider under `examples/llm-gateway/`. Each overlay must:

- Document the secret prerequisite and which key value to store.
- Set `claudeCode.baseUrl` (and `apiVersion` where required) to the provider's endpoint.
- Include any provider-specific `env` entries (e.g. OpenRouter `Referer`, Azure deployment name).
- Where relevant, declare a tightened `networkPolicy.egress` to the gateway namespace.

### 23.5 Cost and Audit Telemetry

- The `cost_usd` field returned by the Claude CLI JSON response must be parsed and exported on `/metrics` regardless of provider. Providers that do not return `cost_usd` are expected to under-report; the gateway's native telemetry (Kong `ai-proxy` metrics, LiteLLM `/spend` API, Azure cost management) must be used as the authoritative cost source in those deployments.
- Audit log lines must record the configured `baseUrl` (sanitised — no credentials) so operators can trace which provider/gateway handled each run.

### 23.6 Security

- API keys for any provider must be mounted from a Kubernetes Secret — never embedded in values, ConfigMaps, or images.
- Gateway endpoints over public networks must use TLS; egress NetworkPolicies must restrict the agent to the configured gateway only.
- Provider credentials must be rotatable without container restart where the provider supports key rotation (typically a pod re-roll suffices).

## 24. Claude Sandbox Requirements

### 24.1 Definition and Purpose

A *Claude sandbox* is a one-shot, ephemeral, isolated execution of the Claude Code agent against a single task. It complements the always-on Deployment with a stronger isolation profile, intended for:

- Untrusted or contractor-submitted prompts
- CI/CD-triggered automated tasks
- Per-request tenant isolation in multi-tenant clusters
- High-risk operations (codebase modification, command execution) that must not share state

### 24.2 Kubernetes Lifecycle

The platform must support sandboxes as Kubernetes Jobs with the following properties:

- `restartPolicy: Never` and `backoffLimit: 0` — sandboxes are one-shot and must not retry on failure.
- `activeDeadlineSeconds` — a hard wall-clock cap enforced by the API server (default 1800).
- `ttlSecondsAfterFinished` — automatic deletion of the Job and its Pod after completion (default 3600).
- `automountServiceAccountToken: false` — sandbox Pods must not have access to the cluster API.
- `generateName` — each submission produces a uniquely-named Job to support concurrent runs.

### 24.3 Filesystem Isolation

- `readOnlyRootFilesystem: true` on the container security context.
- Writable `/tmp` provided by an `emptyDir` volume (existing behaviour for PyInstaller extraction).
- A dedicated ephemeral workspace volume mounted at `WORK_DIR` (default `/workspace`), backed by either `emptyDir` (default) or a generic-ephemeral PVC for larger workloads.
- No persistent volume claims; no shared volumes with other Pods.

### 24.4 Network Isolation

- A dedicated NetworkPolicy must be applied to sandbox Pods with `claude-mate.io/sandbox: "true"` selector.
- `ingress: []` — sandbox Pods must not accept inbound traffic.
- Egress must be restricted to an operator-configured allow-list, minimally including DNS and the configured LLM endpoint.
- Default egress allow-list must exclude RFC 1918 private ranges to prevent lateral movement.

### 24.5 Optional Kernel-Level Isolation

The chart must accept an optional `sandbox.runtimeClassName` value to engage a sandboxed RuntimeClass:

- **gVisor** (`runsc`) — user-space kernel; recommended baseline for untrusted prompts.
- **Kata Containers** — per-Pod lightweight VM; recommended for regulated or multi-tenant workloads.
- When the value is empty, the cluster default runtime is used; the chart must not require a sandboxed RuntimeClass.

### 24.6 Resource Caps

- CPU and memory `requests` and `limits` must be set explicitly on every sandbox container. Defaults must be tighter than the long-lived Deployment (default: 250m / 256Mi request, 1000m / 1Gi limit).
- Workspace volume size must be capped via `sizeLimit` (for `emptyDir`) or PVC `resources.requests.storage`.

### 24.7 CI/CD Integration

The repository must ship sandbox triggers for both supported CI systems:

- **GitHub Actions**: a `workflow_dispatch` workflow that accepts task prompt, persona, optional RuntimeClass, and max duration; renders the sandbox manifests via `helm template`; submits with `kubectl create`; streams logs; collects the cost summary; uploads logs as an artifact.
- **GitLab CI**: a manual `run:sandbox-agent` job in the `on-demand` stage with the same flow, parameterised by CI variables.

Both must use the chart as the single source of truth — CI must not maintain a separate Job manifest.

### 24.8 Audit and Telemetry

- Sandbox Pods must carry the label `claude-mate.io/sandbox=true` and an OTEL resource attribute `claude.sandbox=true` for filtering.
- The same structured audit log lines (`task_started`, `task_completed`, `task_cost_summary`) must be emitted as in on-demand mode, with sandbox identifiers in the pod name field.
- Cost reporting via `/metrics` and OTEL must function unchanged — sandbox runs are accounted as normal `task_executions_total{result}` increments.

### 24.9 Concurrent Isolation

- Multiple sandbox Jobs in the same namespace must be able to run concurrently without sharing state.
- Each sandbox must produce its own workspace volume, log stream, and audit trail.
- The chart must not require manual name overrides for concurrent submission (`generateName` is mandatory).

### 24.10 Constraints

- Sandboxes are not a substitute for prompt review; kernel isolation does not prevent the model from generating policy-violating output. A content/policy gate at the LLM gateway is required for production sandbox use.
- Sandboxes must not be used to bypass the static Deployment's persistent telemetry — the always-on agent remains the source of long-running operational metrics.

## 25. Security Scanning, SAST, and Code Coverage Requirements

### 25.1 Container CVE Scanning

Every build pipeline must scan the container image for known CVEs **before** publishing to any registry.

Requirements:

- A vulnerability scanner (Trivy, Grype, or equivalent) must scan the final runtime image.
- The pipeline must fail on `CRITICAL` and `HIGH` severity findings that have a fix available (`--ignore-unfixed`).
- Acknowledged false positives or accepted-risk findings must be tracked in a versioned allowlist (`.trivyignore`) with a rationale per entry.
- Scan results must be uploaded as SARIF to GitHub Code Scanning / equivalent to surface findings on PRs.

### 25.2 Filesystem and Dependency Scanning

In addition to the image scan, the filesystem and source tree must be scanned for vulnerable dependencies before the build runs.

- `pyproject.toml`, `uv.lock`, `package.json`, and any other manifest must be scanned for known-vulnerable versions.
- Secret-detection scanners must run against the working tree (`scanners: vuln,secret` in Trivy fs, plus a dedicated tool such as gitleaks).
- Secret findings must fail the pipeline.

### 25.3 IaC Configuration Scanning

Dockerfile, Helm charts, Kubernetes manifests, and CI configurations must be statically analysed for misconfigurations.

- Trivy `config` (or equivalent) must scan the repository.
- Findings must be triaged at `CRITICAL`/`HIGH` severity.
- Helm chart issues (privileged containers, missing resource limits, hostPath mounts, etc.) must block merge.

### 25.4 Python Static Application Security Testing (SAST)

Python source code must be analysed with at least one SAST tool.

- **Bandit** must run against `container/app.py` and any future Python source files.
- Findings must be uploaded as SARIF to GitHub Code Scanning.
- A documented suppression mechanism (`# nosec B###` inline comment with rationale) must be used for accepted findings; blanket exclusions are not permitted.
- **Semgrep** (or equivalent multi-language scanner) must run with rulesets covering Python, Dockerfile, and Kubernetes configurations.

### 25.5 Software Bill of Materials (SBOM)

Each published image must have a CycloneDX (or SPDX) SBOM generated by the build pipeline.

- The SBOM must be generated with Syft or equivalent immediately after image build.
- The SBOM must be retained as a build artifact for at least 90 days.
- The SBOM must list both OS packages (UBI9 dnf) and language packages (Python from `uv.lock`, npm modules from the Claude Code install).

### 25.6 Code Coverage

Python code must have unit-test coverage measured by every CI run.

- `pytest` with `pytest-cov` must produce both terminal and XML coverage reports.
- The coverage threshold is enforced via `--cov-fail-under` in `pyproject.toml`.
- Starting threshold: **50%** (baseline for the existing `app.py` surface). The threshold must increase as new tests are added; it must not decrease without an architectural justification recorded in this document.
- Coverage XML (Cobertura format) must be uploaded as a CI artifact and rendered in PR comments / MR widgets.

### 25.7 Pipeline Gating

The dependency graph between jobs must enforce that:

1. Unit tests and SAST run **before** the container build.
2. The container image scan runs **before** any registry push.
3. SBOM generation runs **after** image build but **before** publication.
4. Helm chart packaging runs in parallel with image scanning but the deploy stage requires both to pass.

Manual override of any security gate must require explicit human approval recorded in the pipeline history.

### 25.8 Local Developer Workflow

The Makefile and PowerShell wrapper must expose security gates as named targets so developers can run them locally before opening a PR:

- `make test` — pytest with coverage
- `make sast` — Bandit
- `make scan` — Trivy filesystem + IaC + image
- `make secrets` — Gitleaks
- `make sbom` — Syft
- `make security` — meta-target running every gate sequentially

Tool installation is the developer's responsibility; the Makefile must emit a clear error when a tool is missing rather than silently skipping.

## 26. SDLC Quality Gates and DORA Metrics Requirements

### 26.1 SDLC Quality-Gate Matrix

Every change must pass an explicit set of quality gates aligned to its SDLC phase. The pipeline must enforce these gates in order; a failure at an earlier stage must block all subsequent stages.

| SDLC phase | Gate | Tool | Failure threshold | Owner |
|---|---|---|---|---|
| Plan | Requirement traceability | Manual review | Missing acceptance criteria | Architect |
| Code | Style + lint | Pre-commit / IDE | Lint errors | Author |
| Code | Python SAST | Bandit | CRITICAL/HIGH unhandled | Author |
| Code | Multi-language SAST | Semgrep | CRITICAL/HIGH unhandled | Author |
| Code | Secret scan | Gitleaks | Any leak | Author |
| Build | Unit tests | pytest | Any failure | Author |
| Build | Code coverage | pytest-cov | < `--cov-fail-under` (50% baseline) | Author |
| Build | Dependency CVE scan | Trivy fs | Fixed CRITICAL/HIGH | Author |
| Build | IaC misconfig scan | Trivy config | CRITICAL/HIGH | Author |
| Package | Image CVE scan | Trivy image | Fixed CRITICAL/HIGH | Author |
| Package | SBOM generation | Syft (CycloneDX) | Missing / corrupt | Pipeline |
| Package | Helm chart lint + render | helm lint, helm template | Any rendering error | Author |
| Deploy | Smoke tests | helm rollout status | Rollout timeout (5m) | SRE |
| Deploy | Synthetic probe | `/healthz`, `/readyz` | Non-200 after rollout | SRE |
| Run | Metrics scrape healthy | Prometheus `up` | up==0 for > 5 min | SRE |
| Run | SLO burn-rate | Recording rules | > 2× burn for 1h | SRE |
| Observe | DORA telemetry emitted | Pushgateway | Missing event per deploy | Pipeline |

Each gate must be runnable locally via `make <target>` and must emit machine-readable output (SARIF, JUnit XML, Cobertura) for CI aggregation.

### 26.2 DORA Metrics — Definitions

The platform must publish the four DORA metrics for every controlled environment:

1. **Deployment Frequency** — count of successful production deployments per unit time. Source: `dora_deployments_total{status="ok"}`.
2. **Lead Time for Changes** — wall-clock seconds between commit timestamp and successful production deployment. Source: `dora_lead_time_seconds` (per-deploy gauge).
3. **Change Failure Rate** — fraction of deployments that fail or require an unplanned remediation. Source: `dora_change_failures_total / dora_deployments_total` over a 30-day window.
4. **Mean Time to Restore (MTTR)** — average wall-clock seconds between an incident being declared and the service being restored. Source: `dora_restore_seconds` (per-incident gauge).

Targets (initial; tightened as the platform matures):

| Metric | Target | Stretch |
|---|---|---|
| Deployment Frequency | ≥ 1/day per env | ≥ 5/day |
| Lead Time (P95) | ≤ 1 day | ≤ 1 hour |
| Change Failure Rate (30d) | ≤ 15% | ≤ 5% |
| MTTR (30d) | ≤ 6 h | ≤ 1 h |

### 26.3 DORA Emission Pipeline

- The CI/CD system must emit DORA events via `scripts/dora-emit.sh` to a Prometheus Pushgateway after every deploy stage.
- Three event types are required: `deploy` (with `--status`, `--lead-time-seconds`), `failure` (on rollout failure or rollback), and `restore` (on incident closure).
- Events must carry labels: `env`, `status`, `ci_system` (`github_actions` / `gitlab_ci`), `commit` (Git SHA).
- The Pushgateway must persist state to disk so DORA history survives restarts (`--persistence.file`).
- Prometheus must scrape the Pushgateway every 15 s with `honor_labels: true`.

### 26.4 Recording Rules

Prometheus must precompute the headline metrics so dashboards and alerts query stable series rather than ad-hoc functions:

- `dora:deployments_per_day:7d`, `dora:deployments_per_day:30d`
- `dora:lead_time_seconds:p50:30d`, `dora:lead_time_seconds:p95:30d`
- `dora:change_failure_rate:30d`
- `dora:mttr_seconds:30d`
- `quality_gate:pass_rate:7d`

Rules live in `prometheus/dora_rules.yml` and are mounted into the Prometheus container.

### 26.5 Grafana DORA Dashboard

The repository must ship a Grafana dashboard (`grafana/dashboards/dora-metrics.json`) auto-provisioned alongside the agent dashboard. Required panels:

- Four headline stat panels (Deploy Frequency, Lead Time P50, Change Failure Rate, MTTR).
- Trend time-series for deploys/day and lead-time P50/P95.
- Quality-gate pass-rate gauge.
- CVE findings by severity (sourced from `pipeline_cve_findings`).
- Test coverage trend (`pipeline_test_coverage_percent`).
- Deploy event annotations on every time-series panel.

The dashboard must use template variables for environment selection and default to a 30-day window.

### 26.6 Alerting

Prometheus alerting rules in `dora_rules.yml` must fire on:

- `DORAChangeFailureRateHigh` — `dora:change_failure_rate:30d > 0.15` for 1 h.
- `DORALeadTimeRegression` — P95 lead time > 1 day for 2 h.
- `DORADeploymentFrequencyLow` — < 0.5 deploys/day for 24 h.

Alerts must route to the team's existing notification channel (PagerDuty, Slack, etc.); the routing layer is environment-specific and outside the chart.

### 26.7 Transparency and Audit

- The DORA dashboard must be world-readable by every engineer on the team (anonymous viewer access in non-production Grafana, SSO-gated read in production).
- Each emitted DORA event must be retrievable for at least 30 days for incident-review purposes.
- The Change Failure Rate definition must be documented in `docs/dora-metrics.md` so the team agrees on what counts as a "failure" (rollout failure, post-deploy rollback, hotfix within N hours).

## 27. Semantic Versioning Requirements

### 27.1 Versioning Scheme

All releasable artefacts must follow [Semantic Versioning 2.0.0](https://semver.org/) — `MAJOR.MINOR.PATCH[-prerelease][+build]`. The version components have the following meanings for this project:

- **MAJOR** — incremented for any backwards-incompatible change to one of: container CLI flags / env-var contract, Helm values schema, `/healthz` `/readyz` `/metrics` response shapes, audit-log JSON keys, persona role names, or DORA-event field names.
- **MINOR** — incremented for any backwards-compatible addition (new Helm value with a safe default, new optional env var, new metric, new persona, new example overlay).
- **PATCH** — incremented for bug fixes, security patches, and dependency-only updates that do not change behaviour.
- **Pre-release identifiers** — `-alpha.N`, `-beta.N`, `-rc.N` must be used for staged rollouts. Pre-release tags must never carry the `latest` Docker tag or the `major` / `major.minor` rolling tags.
- **Build metadata** — `+sha.<short>` may be appended for traceability; it must not affect precedence comparisons.

### 27.2 Single Source of Truth

The repository must hold one canonical version string in a top-level `VERSION` file. Every artefact-bearing file must be derived from or verified against it:

| File | Field | How it must match `VERSION` |
|---|---|---|
| `VERSION` | (entire contents) | Canonical |
| `container/pyproject.toml` | `[project] version` | Identical string |
| `charts/claude-mate-agent/Chart.yaml` | `version`, `appVersion` | Both identical |
| `charts/claude-mate-agent/values.yaml` | `image.tag` | Identical (quoted) |

Drift between any of the above must fail CI. The `make version-check` target enforces this in pipelines and locally.

### 27.3 Bump Workflow

A single script (`scripts/bump-version.sh`) must update every dependent file atomically. It must accept either:

- `patch` / `minor` / `major` — increment the named component, reset lower components to 0.
- A full SemVer string — set the version to that exact value; reject inputs that do not match the SemVer grammar.

`make release-tag NEW=...` must wrap the script for ergonomics. The script must not create commits or tags itself — release control belongs to the operator and the release workflow.

### 27.4 Git Tags

- Release tags must be of the form `v<MAJOR>.<MINOR>.<PATCH>[-prerelease]` (no `+build` suffix in the tag name).
- Tags must be created only on commits where every artefact file already agrees with the target version (`make version-check` passes).
- Tag pushes must trigger the release workflow (`.github/workflows/release.yml`), which:
  1. Re-verifies that `VERSION`, `pyproject.toml`, and `Chart.yaml` all agree with the pushed tag.
  2. Packages the Helm chart at the pinned version.
  3. Pushes the chart to the OCI Helm registry.
  4. Generates release notes from `git log` between the previous SemVer tag and the new one.
  5. Creates a GitHub Release marked `prerelease: true` if the tag contains a pre-release identifier.

### 27.5 Container Image Tagging

Every successful build must emit, at minimum:

| Tag | When |
|---|---|
| `<MAJOR>.<MINOR>.<PATCH>` | Always on a SemVer tag push |
| `<MAJOR>.<MINOR>` | On stable tags only (no pre-release identifier) |
| `<MAJOR>` | On stable tags only |
| `latest` | On stable tags only |
| `<branch>` | On every branch push |
| `<short-sha>` | On every push |

Pre-release tags (containing `-`) must only emit the full SemVer tag plus the commit SHA — never the rolling `major`, `major.minor`, or `latest` tags. This rule applies to both GHCR (GitHub Actions) and the GitLab Container Registry / Artifactory (GitLab CI).

### 27.6 Helm Chart Version Coupling

The chart `version` and `appVersion` must remain identical until and unless the chart contracts diverge from the application contract — at which point they may move independently but both must still follow SemVer 2.0.0.

### 27.7 Documentation and SBOM

- The MkDocs site must display the current version on every page (header or footer).
- Every CycloneDX SBOM produced by the build pipeline must include the artefact version under `metadata.component.version`.
- The CHANGELOG (when introduced) must use [Keep a Changelog](https://keepachangelog.com/) format, with versions matching the `VERSION` file exactly.

### 27.8 Deprecation Policy

- Any change that requires a MAJOR bump must be preceded by at least one MINOR release where the affected field, flag, or behaviour is marked deprecated in the documentation and emits a warning log when used.
- Deprecation entries must reference the target removal version (e.g. *"Removed in v2.0.0"*).
- The removal commit must update the requirement document to reflect the new contract.

## 28. Guardrail Requirements

### 28.1 Scope

The platform must support optional, runtime-toggleable guardrails that wrap every Claude Code task execution. Guardrails complement — they do not replace — the persona tool allow-list, the LLM gateway, the sandbox kernel isolation, and the static-analysis pipeline. They exist to give operators an in-pod control point for content-level concerns that gateways may not catch (e.g. local-only deployments without a gateway) and to make experimentation cheap during the "find out what works" phase.

### 28.2 Independence and Cost

Five guardrail families must be implemented as independent on/off switches:

1. **Cost** — pre-flight refuse on rolling-hour cap; post-task warn on per-task overage.
2. **Input scrubbing** — redact or block sensitive patterns in `CLAUDE_TASK` before invoking the CLI.
3. **Output scrubbing** — redact or block sensitive patterns in the Claude CLI stdout before audit logging and JSON parsing.
4. **Workspace allowlist** — materialise `.claudeignore` in `WORK_DIR` from a configured pattern list.
5. **Intent denylist** — per-persona regex denylist against the task prompt; block or warn.

Each family must be a no-op when its `enabled` flag is false. The chart must emit no `GUARDRAILS_*` env vars when `guardrails.enabled` is false at the top level, so disabled deployments incur zero startup cost.

### 28.3 Pattern Library

Input and output scrubbing must share a built-in pattern library covering at minimum:

- API keys: Anthropic (`sk-ant-…`), OpenAI / OpenRouter (`sk-…`, `sk-or-v1-…`), AWS (`AKIA…`), Google (`AIza…`), GitHub (`ghp_…`), GitLab (`glpat-…`), Slack (`xox[abprs]-…`).
- PEM-formatted private-key blocks.
- US SSN and Visa / Mastercard / Amex credit-card numbers.
- RFC 1918 private-range IPv4 addresses.

Operators must be able to supply additional regex patterns via `extraPatterns`. Invalid user-supplied regex must be silently dropped at runtime (the engine must not crash).

### 28.4 Modes

Input, output, and intent guardrails must support at least two modes:

- `redact` (input/output only) — replace matched substrings with `[REDACTED]`; the task continues.
- `block` — refuse the task entirely (input/intent) or mark the result as `error` (output); emit a `guardrail_blocked` audit event.
- `warn` (intent only) — log a `guardrail_warning` audit event but allow the task.

The cost guardrail's hourly cap must always be enforced as a hard block; the per-task cap must always be a soft warning (since cost is only known after the task completes).

### 28.5 Audit Events

Every guardrail action must emit a structured JSON audit line with at minimum these fields: `timestamp`, `severity`, `message` (`guardrail_*`), `type` (`cost` / `input` / `output` / `intent` / `workspace`), `role`, pod identifiers, and CI context fields. Matched pattern IDs must be included; redacted content must never appear in logs.

### 28.6 Helm Chart Integration

The chart must expose a single `guardrails:` block in `values.yaml` containing one sub-block per family. A reusable helper template (`claude-mate-agent.guardrailsEnv`) must render the env entries for both the long-running Deployment and the sandbox Job, ensuring consistent guardrail behaviour across operating modes.

### 28.7 Test Coverage

Each guardrail family must have unit tests covering:

- Disabled (default) — no-op behaviour.
- Enabled with no relevant patterns — no-op behaviour.
- Enabled with a matching pattern — correct redact / block outcome.
- Mode switching (redact ↔ block / block ↔ warn).
- Invalid input handling (malformed regex, unwritable workspace, non-numeric cost env).

Coverage of the guardrails module must not drop below the project-wide `--cov-fail-under` threshold.

### 28.8 Boundaries

Guardrails are **not** a replacement for:

- LLM gateway controls (Kong, LiteLLM) — those remain the recommended primary defence for multi-agent or multi-tenant deployments.
- Persona tool allow-lists — guardrails are content-aware; persona tooling is action-aware.
- Static-analysis / supply-chain scanning — guardrails operate at runtime on prompts and responses, not on source code or images.

## 29. Open Questions

- Which remote log platform is the enterprise standard target?
- What is the required audit log retention period?
- What OpenShell implementation or product profile must be used?
- What compliance frameworks apply to this deployment?
- What are the required production RTO and RPO targets?
- Which GitLab runner types are approved for on-demand execution?
- What permissions should each team mate role have in each environment?
