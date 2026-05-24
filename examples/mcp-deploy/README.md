# Deploy via the Kubernetes MCP server

This example shows how to deploy Claude Mate Agent by letting an AI assistant
(Claude Code, Cursor, Continue, Cline, or any MCP-aware client) drive the
[`kubernetes-mcp-server`](https://github.com/manusa/kubernetes-mcp-server)
instead of running `kubectl`/`helm` from a developer laptop or CI runner.

## What's in this folder

| File | Purpose |
|---|---|
| `.mcp.json` | MCP server registration — drop into your project root for Claude Code to auto-load |
| `deploy-prompt.md` | The deployment runbook to paste into the assistant |

## Prerequisites

- A reachable Kubernetes cluster and a working `~/.kube/config` (the MCP server
  reads `KUBECONFIG`).
- `npx` (Node 18+) on `PATH`, or pull the server image directly:
  `ghcr.io/manusa/kubernetes-mcp-server:latest`.
- An MCP-aware client. For Claude Code, `.mcp.json` in the workspace root is
  enough — the CLI auto-discovers it.

## One-shot deployment

```bash
# 1. Render the chart to a single manifest the MCP client will ingest.
make render-bundle > claude-mate-bundle.yaml

# 2. Start Claude Code in this directory (.mcp.json is auto-loaded).
claude

# 3. In the Claude Code session, paste the contents of deploy-prompt.md.
```

The assistant will:
1. Inspect the current cluster via `mcp__kubernetes__configuration_view`.
2. Apply every document in `claude-mate-bundle.yaml` via
   `mcp__kubernetes__resources_create_or_update`.
3. Poll pods via `pods_list_in_namespace` until rollout is complete.
4. Run a `pods_exec` smoke test against `/readyz`.

## Why this and not plain `kubectl apply`?

| Scenario | MCP wins because… |
|---|---|
| Junior operator on call | LLM explains each step, surfaces errors in plain English, won't silently `apply` a manifest that mutates RBAC outside the target namespace |
| Multi-cluster rollout | Same prompt, switch contexts via `mcp__kubernetes__configuration_view` |
| Ad-hoc fix from a chat UI | No kubectl install needed on the operator's machine — the MCP server holds the cluster credentials |
| Audit trail | The assistant transcript + the MCP server's structured log become the audit record |

`kubectl apply -f claude-mate-bundle.yaml` still works and is still the
right tool for unattended pipelines (GitLab/GitHub Actions). The MCP path
is for *interactive* deployments where a human wants conversational
guard-rails and explanations.

## Security notes

- The MCP server inherits the **full** permissions in your kubeconfig. Use
  a namespace-scoped ServiceAccount kubeconfig (`kubectl config use-context
  claude-mate-deployer`) for deployments — not a cluster-admin token.
- The deployment prompt explicitly forbids `resources_delete` /
  `pods_delete` without confirmation. Keep that guard-rail in any custom
  variant you write.
- For production, run `kubernetes-mcp-server` inside a sidecar (or your
  own bastion) instead of letting it launch from the operator's laptop —
  that way the kubeconfig never leaves the controlled environment.

See [docs/mcp-deploy.md](../../docs/mcp-deploy.md) for the full write-up,
including a worked example transcript and a comparison against
ArgoCD/FluxCD.
