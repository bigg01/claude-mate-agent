# Deploy via the Kubernetes MCP server

Claude Mate Agent supports an *interactive* deployment path: instead of running
`kubectl apply` or `helm upgrade` yourself, you let an AI assistant drive the
[Kubernetes MCP server](https://github.com/manusa/kubernetes-mcp-server). The
assistant reads rendered manifests, calls the MCP server's
`resources_create_or_update` tool for each document, then verifies the rollout
through `pods_list_in_namespace` and `pods_log`.

This is a complement to — not a replacement for — the GitOps and CI-driven
paths in [ArgoCD](examples.md), [FluxCD](examples.md), and
[GitHub Actions](github-actions.md). Use MCP-driven deploy when a human is in
the loop and conversational guard-rails matter.

## When to use this

| Scenario | Why MCP fits |
|---|---|
| First install in a new namespace | The assistant explains each step and surfaces errors in plain English |
| Junior operator on-call | Hard guard-rails (no `resources_delete` unless asked) prevent accidents |
| Multi-cluster ad-hoc fix | Same prompt; switch kubeconfig contexts via `configuration_view` |
| Demo / training | Walks through every resource the chart produces |

| Scenario | Don't use this — use… |
|---|---|
| Unattended CI/CD | [GitHub Actions](github-actions.md) or [GitLab CI](gitlab-ci.md) |
| Continuous reconciliation | ArgoCD or FluxCD examples |
| Air-gapped clusters with no LLM egress | `helm upgrade --install` directly |

## Architecture

```
┌──────────────────┐    stdio / MCP     ┌─────────────────────────┐
│  Operator        │ ◀───────────────▶ │  Assistant (Claude Code,│
│  (Claude Code,   │                    │  Cursor, Cline, …)      │
│   CLI/IDE)       │                    └─────────────┬───────────┘
└──────────────────┘                                  │ MCP tool calls
                                                      ▼
                                       ┌─────────────────────────┐
                                       │  kubernetes-mcp-server  │
                                       │  (Node binary or image) │
                                       └─────────────┬───────────┘
                                                     │ kubeconfig
                                                     ▼
                                       ┌─────────────────────────┐
                                       │  Kubernetes API server  │
                                       └─────────────────────────┘
```

The MCP server exposes a stable tool surface — `resources_create_or_update`,
`resources_get`, `resources_list`, `resources_delete`, `resources_scale`,
`pods_*`, `nodes_*`, `events_list`, `configuration_view`. The assistant
chooses which tool to call from the prompt and rendered manifests.

## Prerequisites

- A reachable Kubernetes cluster and a working `~/.kube/config`. The MCP
  server inherits **all** permissions in this kubeconfig — use a
  namespace-scoped ServiceAccount token for deployments, not cluster-admin.
- `npx` (Node 18+) on `PATH`, or pull the server image:
  `ghcr.io/manusa/kubernetes-mcp-server:latest`.
- An MCP-aware client. The example registration in
  [`examples/mcp-deploy/.mcp.json`](https://github.com/.../tree/main/examples/mcp-deploy)
  works for Claude Code; other clients use the same JSON schema with a different filename.

## Walk-through

### 1 — Render the chart to one manifest

```bash
make render-bundle > claude-mate-bundle.yaml
```

`render-bundle` emits a leading `Namespace` document and then every chart
resource. Overrides:

```bash
# Custom namespace and image tag
make render-bundle NAMESPACE=claude-mate-staging TAG=abc1234 > bundle.yaml

# Apply an example overlay (LLM gateway, monitoring, OpenShift, …)
make render-bundle VALUES=examples/static-kubernetes/values.yaml > bundle.yaml
```

### 2 — Register the MCP server

Drop [`examples/mcp-deploy/.mcp.json`](https://github.com/.../tree/main/examples/mcp-deploy) in your project root
(Claude Code auto-loads it):

```json
{
  "mcpServers": {
    "kubernetes": {
      "command": "npx",
      "args": ["-y", "kubernetes-mcp-server@latest"],
      "env": { "KUBECONFIG": "${HOME}/.kube/config" }
    }
  }
}
```

For Cursor / Cline / Continue, copy the same `mcpServers` block into the
client's MCP config file (the location differs but the schema is identical).

### 3 — Ask the assistant to deploy

Start the assistant in the directory containing both `claude-mate-bundle.yaml`
and `.mcp.json`, then paste the contents of
[`examples/mcp-deploy/deploy-prompt.md`](https://github.com/.../tree/main/examples/mcp-deploy)
into the chat. The prompt enforces:

1. **Pre-flight** — `configuration_view` confirms the cluster; `namespaces_list`
   detects prior installs.
2. **Apply** — split the bundle on `---`, call `resources_create_or_update` per
   document, Namespace first, RBAC before Deployment.
3. **Verify** — poll `pods_list_in_namespace` until every pod is `Ready=True`;
   pull `pods_log` on the first `CrashLoopBackOff` or `ImagePullBackOff`.
4. **Smoke test** — `pods_exec` `curl -sf http://localhost:8080/readyz`.
5. **Report** — namespace, replica count, image tag, time to ready.

### 4 — Inspect afterwards

The MCP tools cover day-2 operations too. Example follow-up prompts:

- *"Show me the logs of the last failed pod in `claude-mate`."* →
  `pods_list_in_namespace` + `pods_log`
- *"Scale to 4 replicas."* → `resources_scale`
- *"What events fired in the last 10 minutes?"* → `events_list`
- *"Compare the live Deployment spec against `claude-mate-bundle.yaml`."* →
  `resources_get` + the assistant diffs the YAML

## Security posture

- The MCP server is a **process running on the operator's machine** (or the
  bastion you launch it from). It holds the kubeconfig — protect it like any
  credential.
- For shared use, run the server inside a sidecar / bastion container and
  expose it over MCP-over-HTTP rather than handing every operator a copy of
  the kubeconfig.
- The deployment prompt forbids `resources_delete` and `pods_delete` without
  explicit confirmation. Keep that guard-rail when you fork the prompt.
- Every assistant tool call is auditable in two places: the assistant
  transcript, and the structured log of `kubernetes-mcp-server`. Pair this
  with the agent's own [audit log](security.md) for a complete chain.
- Bind the kubeconfig to a `Role` (not `ClusterRole`) scoped to the target
  namespace. The chart's RBAC already follows the same principle — extend it
  for the operator account too.

## Comparison matrix

| Path | Drift handling | Audit | Best fit |
|---|---|---|---|
| **MCP (this page)** | None — one-shot apply | Assistant transcript + MCP log | Interactive, exploratory, training |
| ArgoCD | Continuous reconcile | Argo events + Git history | Long-running clusters, multi-team |
| FluxCD | Continuous reconcile | Flux events + Git history | GitOps purists, image automation |
| GitHub Actions | None — pipeline only | Workflow logs | Tagged releases, gated environments |
| `helm upgrade` (local) | None | Shell history | Quick local iteration |

## See also

- [`examples/mcp-deploy/`](https://github.com/.../tree/main/examples/mcp-deploy) — the
  `.mcp.json` and the full deployment prompt
- [`make render-bundle`](https://github.com/.../tree/main/Makefile) — the Make target this page references
- Upstream MCP server: <https://github.com/manusa/kubernetes-mcp-server>
- Model Context Protocol spec: <https://modelcontextprotocol.io>
