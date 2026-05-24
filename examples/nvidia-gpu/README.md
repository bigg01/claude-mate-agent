# NVIDIA GPU Example

Deploys the Claude Mate Agent with GPU access via the [NVIDIA Container Runtime](https://github.com/NVIDIA/nvidia-container-toolkit).

## Prerequisites

### Cluster

- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/getting-started.html) installed, **or** the NVIDIA device plugin + `nvidia-container-toolkit` configured on GPU nodes manually.
- GPU nodes labelled `nvidia.com/gpu.present=true` (done automatically by the GPU Operator).
- `RuntimeClass` named `nvidia` registered (done automatically by the GPU Operator).

### Local Docker / Podman

```bash
# Install nvidia-container-toolkit (Debian/Ubuntu)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor \
  -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

Verify:

```bash
docker run --rm --runtime=nvidia --gpus all ubuntu nvidia-smi
```

## Kubernetes deployment

```bash
helm upgrade --install claude-mate-agent charts/claude-mate-agent \
  --namespace claude-mate --create-namespace \
  -f examples/nvidia-gpu/values.yaml \
  --set image.repository=ghcr.io/your-org/claude-mate-agent \
  --set image.tag=latest \
  --set claudeCode.apiKeySecretName=claude-mate-api-key
```

## Local Docker Compose

```bash
docker compose -f docker-compose.yml -f docker-compose.nvidia.yml up
```

## Verify GPU access inside the container

```bash
# Kubernetes
kubectl exec -n claude-mate deploy/claude-mate-agent -- nvidia-smi

# Docker
docker run --rm \
  --runtime=nvidia \
  -e NVIDIA_VISIBLE_DEVICES=all \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility \
  claude-mate-agent:dev nvidia-smi
```

## Key values

| Value | Default | Description |
|---|---|---|
| `nvidia.enabled` | `false` | Enable GPU access |
| `nvidia.runtimeClassName` | `nvidia` | RuntimeClass registered by GPU Operator |
| `nvidia.gpuCount` | `1` | GPUs per pod (requests + limits) |
| `nvidia.driverCapabilities` | `compute,utility` | CUDA capabilities exposed in container |
| `nvidia.nodeSelector` | `nvidia.com/gpu.present: "true"` | Targets GPU nodes |
| `nvidia.tolerations` | `nvidia.com/gpu=true:NoSchedule` | Tolerates GPU taint |
