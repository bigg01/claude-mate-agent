# Security & Compliance

## Container security

| Control | Implementation |
|---|---|
| Non-root user | `USER 1001` in Dockerfile; `runAsNonRoot: true` in pod security context |
| Arbitrary UID (OpenShift) | No fixed `runAsUser` in chart defaults; `chgrp 0 / chmod g=u` pattern |
| Read-only root filesystem | `readOnlyRootFilesystem: true`; only `/tmp` is writable (emptyDir) |
| No privilege escalation | `allowPrivilegeEscalation: false` |
| Dropped capabilities | `capabilities.drop: [ALL]` |
| Seccomp | `seccompProfile.type: RuntimeDefault` |
| No embedded secrets | `ANTHROPIC_API_KEY` injected at runtime from a Kubernetes/OpenShift Secret only |

## RBAC

The chart creates a `Role` and `RoleBinding` scoped to the deployment namespace:

```yaml
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
```

No cluster-scoped permissions are required. The service account cannot modify workloads, secrets, or other resources.

## Network policy

```yaml
networkPolicy:
  enabled: true
  ingressNamespaceSelector: {}   # restrict to monitoring/ingress namespaces in production
  egress: []                     # restrict to Anthropic API + OTEL collector in production
```

Restrict egress in production to the minimum required endpoints:

```yaml
networkPolicy:
  egress:
    - ports:
        - port: 443          # Anthropic API
    - ports:
        - port: 4318         # OTEL collector
    - ports:
        - port: 53           # DNS
          protocol: UDP
```

## OpenShift SCC

The chart is compatible with the `restricted-v2` SCC on OpenShift 4.11+:

- Runs as non-root with arbitrary UID
- No privileged containers
- No root-owned writable paths (all writes go to `/tmp` emptyDir)
- No host path volumes

## OpenShell protection

The `openshell` block adds pod annotations that trigger the enterprise OpenShell admission webhook:

```yaml
openshell:
  enabled: true
  protectionMode: restricted
  annotations:
    openshell.io/protection: restricted
    openshell.io/audit: enabled
```

When active:

- Interactive shell access to the container requires break-glass approval
- All shell sessions are logged to the centralised audit trail
- Commands are captured in the audit record with user identity, timestamp, and session ID
- Session and inactivity timeouts are enforced by the OpenShell policy

## Audit trail

Every significant event is emitted as a structured JSON log line. Key audit events:

| Event | Mode | Fields |
|---|---|---|
| `agent_started` | both | `operating_mode`, `port` / GitLab context |
| `on_demand_agent_execution` | on-demand | `result`, `exit_code`, full GitLab context |
| `on_demand_agent_execution_failed` | on-demand | `error`, `result=error\|timeout` |
| `agent_stopped` | both | `operating_mode` |
| `shutdown_signal_received` | static | `signal` |
| `otel_initialized` | both | `endpoint` |

GitLab context fields included in every on-demand event: `gitlab_project`, `gitlab_pipeline`, `gitlab_job`, `gitlab_commit`, `gitlab_branch`, `gitlab_runner`, `gitlab_user`, `teammate_role`.

All audit logs are written to `stdout` (INFO) or `stderr` (ERROR/CRITICAL) and collected by the enterprise logging stack for forwarding to the remote SIEM.

## Secrets management

- The `ANTHROPIC_API_KEY` is never stored in the image, chart values files, or pipeline logs.
- In Kubernetes/OpenShift: reference a pre-created Secret via `claudeCode.apiKeySecretName`.
- In GitLab CI: set `ANTHROPIC_API_KEY` as a **masked** and **protected** CI/CD variable.
- The agent never logs the API key or any prompt content that could contain protected data.
