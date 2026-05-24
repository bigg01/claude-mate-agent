# Deployment prompt — paste into Claude Code

You are deploying the Claude Mate Agent into a Kubernetes cluster.

Inputs you have:
- A rendered manifest at `claude-mate-bundle.yaml` containing every resource
  in the Helm chart (Namespace, ServiceAccount, RBAC, Deployment, Service,
  ConfigMap, PDB, NetworkPolicy, ServiceMonitor, …).
- The `kubernetes` MCP server, exposing `resources_create_or_update`,
  `resources_get`, `pods_list_in_namespace`, `pods_log`, and friends.

Do the deployment in this order — stop and surface any error rather than
moving on:

1. **Pre-flight**
   - `namespaces_list` — confirm the target namespace `claude-mate` does or
     does not exist. If it does, list existing Deployments to detect a prior
     install.
   - `configuration_view` — confirm you are pointed at the expected cluster.

2. **Apply manifests**
   - Split `claude-mate-bundle.yaml` on `---` document boundaries.
   - For each document, call `resources_create_or_update` with the YAML.
   - Skip empty documents. Apply Namespace *first*, RBAC *before* the
     Deployment, and the Deployment *last*.

3. **Verify rollout**
   - `pods_list_in_namespace` with namespace `claude-mate`.
   - Poll until every pod for the `claude-mate-agent` Deployment reports
     `Ready=True`. Wait up to 5 minutes.
   - If any pod is in `CrashLoopBackOff` or `ImagePullBackOff`, call
     `pods_log` on it and report the last 40 lines.

4. **Smoke test**
   - `resources_get` on the `Service/claude-mate-agent` — confirm it has
     endpoints.
   - `pods_exec` one ready pod with `curl -sf http://localhost:8080/readyz`
     and confirm HTTP 200.

5. **Report**
   - Summarise: namespace, replica count, image tag, time to ready, and any
     warnings observed during apply.

Constraints:
- Do **not** call `resources_delete` or `pods_delete` unless the user
  explicitly asks for a redeploy.
- Do **not** change any namespace outside `claude-mate`.
- If the user supplies a different `--namespace` or image tag, re-render
  the manifests by asking them to run `make render-bundle NAMESPACE=… TAG=…`
  rather than mutating the YAML in flight.
