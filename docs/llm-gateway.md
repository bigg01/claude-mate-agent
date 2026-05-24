# LLM Gateway and Alternative Providers

Claude Mate Agent is provider-agnostic: it ships with the Anthropic-compatible Claude Code CLI but can be pointed at any endpoint that speaks the same protocol. Set `claudeCode.baseUrl` and the same image runs against Anthropic directly, Kong AI Gateway, LiteLLM, OpenRouter, Azure AI Foundry, Google Vertex AI, or — via a translation proxy — NVIDIA NIM and native Gemini.

## How it works

The Anthropic SDK (used by Claude Code) honours two environment variables:

| Variable | Helm value | Purpose |
|---|---|---|
| `ANTHROPIC_BASE_URL` | `claudeCode.baseUrl` | API endpoint override |
| `ANTHROPIC_API_VERSION` | `claudeCode.apiVersion` | Required by Azure AI Foundry |
| `ANTHROPIC_API_KEY` | secret referenced by `claudeCode.apiKeySecretName` | Credential — provider-specific |

Setting `claudeCode.baseUrl` to anything non-empty routes every request through that endpoint. The container image is identical across providers; only Helm values and the bound Secret change.

## Provider matrix

| Provider | Endpoint type | Translation needed | Overlay |
|---|---|---|---|
| Anthropic (direct) | native | no | `values-anthropic-direct.yaml` |
| Kong AI Gateway | Anthropic-compatible proxy | no | `values-kong.yaml` |
| LiteLLM proxy | Anthropic-compatible proxy | no (proxy handles upstream) | `values-litellm.yaml` |
| OpenRouter | Anthropic-compatible | no | `values-openrouter.yaml` |
| Azure AI Foundry | Anthropic-compatible (Claude on Azure) | no | `values-azure.yaml` |
| Google Vertex AI (Claude) | Anthropic-compatible | no | `values-gemini.yaml` |
| Google Gemini (native) | OpenAI-format | yes — LiteLLM in front | `values-gemini.yaml` |
| NVIDIA NIM | OpenAI-format | yes — LiteLLM in front | `values-nvidia.yaml` |
| Ollama (local) | OpenAI-format | yes — LiteLLM in front | `values-ollama.yaml` |
| vLLM (self-hosted) | OpenAI-format | yes — LiteLLM in front | `values-vllm.yaml` |
| LM Studio (desktop) | OpenAI-format | yes — LiteLLM in front | `values-lmstudio.yaml` |

## Local LLM runtimes (Ollama, vLLM, LM Studio)

All three run open models locally — no calls leave the cluster (or the laptop). Useful for:

- **Air-gapped environments** — banks, defence, regulated workloads where no traffic may reach `api.anthropic.com`.
- **Cost-sensitive workloads** — high-volume DevOps tasks (lint, format, doc generation) where a 7-14B local model is "good enough".
- **Pre-prod evaluation** — testing prompts/personas against multiple open models before paying for a managed provider.
- **Laptop development** — `docker compose -f docker-compose.yml -f docker-compose.local-llm.yml up` boots agent + Ollama + LiteLLM in one shot.

| Runtime | Best for | Notes |
|---|---|---|
| **Ollama** | Laptop dev, on-prem CPU/GPU, air-gapped clusters | Simplest install, model catalogue at <https://ollama.com/library> |
| **vLLM** | Production GPU serving, batched inference, fine-tuned models | Highest throughput; needs CUDA-capable nodes |
| **LM Studio** | Desktop evaluation with GUI for model browse/download | Native macOS/Windows/Linux app; not cluster-native |

### Why all three need LiteLLM

Claude Code speaks the **Anthropic protocol**. Ollama, vLLM, and LM Studio all speak the **OpenAI protocol**. LiteLLM sits in front, accepts Anthropic-format requests on `/anthropic`, translates them to OpenAI-format, and forwards to the local backend. The agent's `claudeCode.baseUrl` points at LiteLLM's `/anthropic` route; the `claudeCode.apiKeySecretName` holds LiteLLM's master/virtual key (no real Anthropic credential needed).

```
claude-mate-agent  ──Anthropic API──▶  LiteLLM  ──OpenAI API──▶  Ollama / vLLM / LM Studio
   (Anthropic SDK)                  (translator)              (local model server)
```

### Laptop quickstart (one command)

```bash
docker compose -f docker-compose.yml -f docker-compose.local-llm.yml up --build

# Pull a model the first time:
docker compose -f docker-compose.yml -f docker-compose.local-llm.yml \
  exec ollama ollama pull llama3.1:8b
```

The agent at `http://localhost:8080` is now backed by `llama3.1:8b` running in Ollama, with LiteLLM transparently bridging the protocols. Edit `litellm/config.yaml` to map specific Claude Code model names (`claude-3-5-sonnet-20241022`, `claude-3-5-haiku-20241022`) to whichever local model you want.

### Cluster deployment

```bash
# Pick the overlay
helm upgrade --install claude-mate-agent charts/claude-mate-agent \
  --namespace claude-mate --create-namespace \
  -f examples/llm-gateway/values-ollama.yaml   # or -vllm.yaml / -lmstudio.yaml
```

Each overlay assumes LiteLLM is already deployed in the `litellm` namespace with a Service named `litellm-ollama` / `litellm-vllm` / `litellm-lmstudio`. The overlay's `claudeCode.baseUrl` points at that Service's `/anthropic` route; the `model_list` snippet in the overlay's comments shows how to wire LiteLLM to the matching backend Service.

## Routing diagrams

**Direct path** (provider speaks the Anthropic protocol):

```
claude-mate-agent  ──ANTHROPIC_BASE_URL──▶  Provider
   (Anthropic SDK)
```

**Translated path** (provider speaks OpenAI / something else):

```
claude-mate-agent  ──Anthropic API──▶  LiteLLM / Kong  ──Provider API──▶  Gemini / NIM / Bedrock
```

## Deploying a specific backend

```bash
helm upgrade --install claude-mate-agent charts/claude-mate-agent \
  --namespace claude-mate --create-namespace \
  -f examples/llm-gateway/values-openrouter.yaml \
  --set image.repository=ghcr.io/your-org/claude-mate-agent \
  --set image.tag=latest
```

Switch provider later with no image rebuild:

```bash
# Rotate the secret to the new provider's key
kubectl create secret generic claude-mate-api-key \
  --from-literal=ANTHROPIC_API_KEY=<new-key> \
  --dry-run=client -o yaml | kubectl apply -f -

# Repoint to the new endpoint
helm upgrade claude-mate-agent charts/claude-mate-agent \
  --reuse-values \
  --set claudeCode.baseUrl=https://litellm.litellm.svc.cluster.local:4000/anthropic
```

## Cost telemetry across providers

`task_cost_usd_total` and the Grafana **API Cost** row are parsed from the Claude CLI's `cost_usd` JSON field. Behaviour varies:

| Provider | `cost_usd` populated? | Authoritative source |
|---|---|---|
| Anthropic direct | yes | `/metrics` |
| OpenRouter | yes (own pricing) | `/metrics` |
| Azure AI Foundry | yes | `/metrics` (verify against Azure Cost Management) |
| Kong AI Gateway | depends on plugin config | Kong's `ai-proxy` metrics |
| LiteLLM | usually 0 in client response | LiteLLM `/spend` API |
| NVIDIA NIM (via LiteLLM) | 0 (free tier) | LiteLLM `/spend` (will be 0) |

For gateways that under-report client-side, scrape the gateway's own telemetry into Prometheus alongside the agent metrics.

## Security

- Store every provider credential in a Kubernetes Secret — never in `values.yaml` or container images.
- For public-internet endpoints (OpenRouter, Azure, Vertex AI), keep `networkPolicy.enabled: true` and restrict egress to HTTPS only.
- For in-cluster gateways (Kong, LiteLLM), tighten `networkPolicy.egress` to the gateway's namespace and port.
- Credential rotation: replace the Secret data and trigger a pod restart (`kubectl rollout restart deployment/claude-mate-agent`).

See [`examples/llm-gateway/README.md`](https://github.com/your-org/claude-mate-agent/tree/main/examples/llm-gateway) for per-provider configuration details.
