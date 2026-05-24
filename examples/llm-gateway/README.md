# LLM Gateway and Alternative Providers

Claude Code uses the Anthropic SDK, which honours `ANTHROPIC_BASE_URL` and `ANTHROPIC_API_KEY`. By overriding these, the same container can target any Anthropic-compatible endpoint — a gateway (Kong, LiteLLM) or a managed Claude deployment (Azure, Vertex AI, OpenRouter). For OpenAI-format-only providers (NVIDIA NIM, native Gemini), a translation proxy sits in front.

## Supported deployments

| File | Provider | Direct or proxied | Use case |
|---|---|---|---|
| `values-anthropic-direct.yaml` | Anthropic API | direct | Default; lowest latency |
| `values-kong.yaml` | Kong AI Gateway | proxied (Anthropic-compatible) | Enterprise gateway, central auth/rate-limit/audit |
| `values-litellm.yaml` | LiteLLM | proxied (any backend) | Mix Anthropic + Gemini + Azure + NIM behind one config |
| `values-openrouter.yaml` | OpenRouter | direct (Anthropic-compatible) | Pay-as-you-go, model fallbacks |
| `values-azure.yaml` | Azure AI Foundry | direct (Anthropic-compatible) | Microsoft enterprise compliance |
| `values-gemini.yaml` | Google Vertex AI / Gemini | direct or proxied | GCP customers; Vertex Claude or native Gemini |
| `values-nvidia.yaml` | NVIDIA NIM (free tier) | proxied (via LiteLLM) | Free open-source models for non-production |
| `values-ollama.yaml` | Ollama (local) | proxied (via LiteLLM) | Laptop / on-prem / air-gapped — CPU or GPU |
| `values-vllm.yaml` | vLLM (self-hosted) | proxied (via LiteLLM) | High-throughput GPU inference for prod open models |
| `values-lmstudio.yaml` | LM Studio (desktop) | proxied (via LiteLLM) | Laptop development with desktop GUI for model mgmt |

For all three local runtimes, see `docker-compose.local-llm.yml` in the repo root for a one-command laptop stack (agent + Ollama + LiteLLM).

## How routing works

```
Direct path (Anthropic-compatible providers):

  claude-mate-agent  ──ANTHROPIC_BASE_URL──▶  Provider
       (Anthropic SDK)                        (Anthropic, Kong, LiteLLM/Anthropic route,
                                               OpenRouter, Azure, Vertex AI Claude)

Translated path (OpenAI-only providers):

  claude-mate-agent  ──Anthropic API──▶  LiteLLM  ──OpenAI API──▶  NVIDIA NIM / Gemini native
```

## Deploy

```bash
# Pick the overlay for your backend
helm upgrade --install claude-mate-agent charts/claude-mate-agent \
  --namespace claude-mate --create-namespace \
  -f examples/llm-gateway/values-<provider>.yaml \
  --set image.repository=ghcr.io/your-org/claude-mate-agent \
  --set image.tag=latest
```

Each overlay assumes a pre-created secret holding the **provider's** API key under the key `ANTHROPIC_API_KEY`. For gateways this is the gateway's consumer key, not the upstream provider key.

## Switching providers without redeploying the image

The container image is provider-agnostic. To switch:

1. Update the Secret holding `ANTHROPIC_API_KEY` to the new provider's key.
2. Set `claudeCode.baseUrl` (and `claudeCode.apiVersion` if needed) via `helm upgrade --reuse-values --set ...`.
3. The next pod restart picks up the new endpoint.

## Cost tracking caveat

`/metrics` and OTEL counters report `task_cost_usd_total` parsed from the `cost_usd` field of the Claude CLI JSON response. Gateways that proxy to non-Anthropic backends may return `cost_usd: 0` or omit the field — the cost dashboard will under-report in those cases. Use the gateway's native cost telemetry (Kong: `ai-proxy` metrics; LiteLLM: built-in `/spend` API) as the authoritative source.
