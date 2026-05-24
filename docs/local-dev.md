# Local Development

## Quick start with Docker Compose

The repository ships a `docker-compose.yml` that starts the agent in static mode alongside Prometheus and Grafana. The base stack needs no Kubernetes or API keys to run the static health/metrics server — only on-demand mode (`--once`) needs credentials, and only if you point at a managed LLM.

```bash
# Build the agent image and start the full stack
docker compose up --build

# or with Podman Compose
podman-compose up --build
```

| Service | URL | Credentials |
|---|---|---|
| Claude Mate Agent | http://localhost:8080 | — |
| Prometheus | http://localhost:9090 | — |
| Grafana | http://localhost:3000 | admin / admin |

Grafana opens the **Claude Mate Agent** dashboard automatically.

## Compose overlays — pick what you need

Combine the base file with one or more overlays. Order matters: later files override earlier ones.

| Overlay | Adds | Use when |
|---|---|---|
| `docker-compose.local-llm.yml` | Ollama + LiteLLM, agent wired to local LLM | You want `--once` mode without any cloud API key |
| `docker-compose.opensearch.yml` | OpenSearch + Dashboards | You want to test audit-log shipping locally |
| `docker-compose.nvidia.yml` | NVIDIA GPU passthrough on the agent | You're on a GPU host |
| `docker-compose.artifactory.yml` | Routes builds through Artifactory mirrors | You're inside a corporate network |

## Run fully local — no Anthropic API key

The most useful local-test path. Boots agent + Ollama + LiteLLM in one shot; LiteLLM bridges the Anthropic ↔ OpenAI protocol gap so Claude Code talks to a local model.

```bash
# Boot the full local-LLM stack
docker compose -f docker-compose.yml -f docker-compose.local-llm.yml up --build

# Pull a model the first time (one-shot, runs inside the ollama container)
docker compose -f docker-compose.yml -f docker-compose.local-llm.yml \
  exec ollama ollama pull llama3.1:8b

# Verify the agent now points at a local backend
curl http://localhost:8080/healthz

# Run a one-shot task against the local model — no ANTHROPIC_API_KEY needed
CLAUDE_TASK="say hello in exactly three words" \
  docker compose -f docker-compose.yml -f docker-compose.local-llm.yml \
  run --rm agent --once
```

Edit `litellm/config.yaml` to map specific Claude Code model names (`claude-3-5-sonnet-20241022`, `claude-3-5-haiku-20241022`) to whichever Ollama model fits your hardware — defaults assume `llama3.1:8b` and `qwen2.5-coder:7b`. See [LLM Gateway → Local LLM runtimes](llm-gateway.md#local-llm-runtimes-ollama-vllm-lm-studio) for the broader picture and vLLM / LM Studio variants.

## Verify the agent

```bash
curl http://localhost:8080/healthz    # {"status":"ok"}
curl http://localhost:8080/readyz     # {"ready":true}
curl http://localhost:8080/metrics    # Prometheus text format
```

## Test on-demand mode locally

On-demand mode requires an Anthropic API key and a task prompt. The container exits after the task completes.

```bash
ANTHROPIC_API_KEY=sk-ant-... CLAUDE_TASK="list the files in /tmp" \
  docker-compose run --rm agent --once
```

The structured JSON log lines are printed to stdout. To extract the cost summary:

```bash
ANTHROPIC_API_KEY=sk-ant-... CLAUDE_TASK="say hello" \
  docker-compose run --rm agent --once 2>&1 | \
  grep '"message":"task_cost_summary"'
```

## Build the image standalone

The Makefile targets wrap the Docker Compose build:

```bash
make build          # builds claude-mate-agent:dev
make run            # build + start static server on port 8080
make run-once       # requires ANTHROPIC_API_KEY and CLAUDE_TASK in env
```

On Windows use `scripts/make.ps1`:

```powershell
.\scripts\make.ps1 build
.\scripts\make.ps1 run
```

## Helm chart local rendering

```bash
make lint           # helm lint
make render         # renders AKS, OpenShift, and Gateway API variants
```

## Resetting the stack

```bash
docker-compose down -v    # removes containers and named volumes (grafana-data)
```

## Customise Prometheus scrape interval

Edit `prometheus/prometheus.yml` and reload:

```bash
curl -X POST http://localhost:9090/-/reload
```

## NVIDIA GPU (optional)

To run the agent with GPU access locally, install the [NVIDIA Container Toolkit](https://github.com/NVIDIA/nvidia-container-toolkit) first:

```bash
# Debian / Ubuntu
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

Verify GPU access:

```bash
docker run --rm --runtime=nvidia --gpus all ubuntu nvidia-smi
```

Start the full stack with GPU support:

```bash
docker compose -f docker-compose.yml -f docker-compose.nvidia.yml up --build
```

## Override agent environment variables

Create a `docker-compose.override.yml`:

```yaml
services:
  agent:
    environment:
      OTEL_ENABLED: "true"
      OTEL_EXPORTER_OTLP_ENDPOINT: "http://your-collector:4318"
      TEAM_MATE_ROLE: security
```

Compose merges this automatically with the base `docker-compose.yml`.
