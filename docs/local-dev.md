# Local Development

## Quick start with Docker Compose

The repository ships a `docker-compose.yml` that starts the agent in static mode alongside Prometheus and Grafana. No Kubernetes or API keys are required.

```bash
# Build the agent image and start the full stack
docker-compose up --build

# or with Podman Compose
podman-compose up --build
```

| Service | URL | Credentials |
|---|---|---|
| Claude Mate Agent | http://localhost:8080 | — |
| Prometheus | http://localhost:9090 | — |
| Grafana | http://localhost:3000 | admin / admin |

Grafana opens the **Claude Mate Agent** dashboard automatically.

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
