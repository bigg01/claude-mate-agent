<#
.SYNOPSIS
  Windows equivalent of the project Makefile. Requires Docker Desktop or Podman Desktop.

.DESCRIPTION
  Runs Claude Mate Agent build, test, and deployment tasks on Windows.
  All Linux/macOS users should use the Makefile instead.

.PARAMETER Target
  The target to execute. Run without arguments or with 'help' to list all targets.

.PARAMETER Image
  Container image name. Default: claude-mate-agent

.PARAMETER Tag
  Container image tag. Default: dev

.PARAMETER Port
  Local port for the static server. Default: 8080

.PARAMETER DocsPort
  Local port for docs preview. Default: 8000

.PARAMETER ContainerTool
  Container tool to use: docker or podman. Auto-detected if not specified.

.EXAMPLE
  .\scripts\make.ps1 build
  .\scripts\make.ps1 build -Tag 1.0.0 -Image myrepo/claude-mate-agent
  .\scripts\make.ps1 run-once
  .\scripts\make.ps1 render
#>
param(
    [Parameter(Position = 0)]
    [string]$Target = "help",

    [string]$Image         = "claude-mate-agent",
    [string]$Tag           = "dev",
    [int]   $Port          = 8080,
    [int]   $DocsPort      = 8000,
    [string]$ContainerTool = "",

    # Artifactory mirrors (optional — leave empty to use upstream registries)
    # DockerRegistry  e.g. artifactory.example.com/docker-remote
    # PypiIndexUrl    e.g. https://artifactory.example.com/artifactory/api/pypi/pypi-virtual/simple
    # NpmRegistry     e.g. https://artifactory.example.com/artifactory/api/npm/npm-virtual/
    [string]$DockerRegistry = "",
    [string]$PypiIndexUrl   = "",
    [string]$NpmRegistry    = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Resolve container tool ──────────────────────────────────────────────────
if (-not $ContainerTool) {
    if (Get-Command podman -ErrorAction SilentlyContinue) {
        $ContainerTool = "podman"
    } elseif (Get-Command docker -ErrorAction SilentlyContinue) {
        $ContainerTool = "docker"
    } else {
        Write-Error "Neither podman nor docker found in PATH. Install Docker Desktop or Podman Desktop."
        exit 1
    }
}

$Chart   = "charts/claude-mate-agent"
$Release = "claude-mate-agent"
$Root    = Split-Path $PSScriptRoot -Parent

Push-Location $Root

# ── Helper functions ────────────────────────────────────────────────────────
function Run([string]$cmd) {
    Write-Host "> $cmd" -ForegroundColor Cyan
    Invoke-Expression $cmd
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

function Get-VcsRef {
    try { return (git rev-parse --short HEAD 2>$null).Trim() }
    catch { return "unknown" }
}

function Get-BuildDate {
    return (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ" -AsUTC)
}

function Get-SourceUrl {
    try { return (git remote get-url origin 2>$null).Trim() }
    catch { return "unknown" }
}

# ── Targets ─────────────────────────────────────────────────────────────────
switch ($Target) {

    "help" {
        Write-Host ""
        Write-Host "Container tool: $ContainerTool  (override: -ContainerTool docker|podman)" -ForegroundColor Green
        Write-Host ""
        Write-Host "Usage: .\scripts\make.ps1 <target> [options]" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Targets:" -ForegroundColor Yellow
        Write-Host "  build             Build the container image"
        Write-Host "  run               Build + run static server on PORT"
        Write-Host "  run-once          Run on-demand mode (requires ANTHROPIC_API_KEY + CLAUDE_TASK in env)"
        Write-Host "  check             Syntax-check container/app.py (via uv run if available)"
        Write-Host "  lock              Regenerate container/uv.lock from pyproject.toml"
        Write-Host "  sync              Sync local virtualenv to container/uv.lock"
        Write-Host "  lint              Helm lint the chart"
        Write-Host "  render            Render AKS, OpenShift, and Gateway API manifests"
        Write-Host "  render-aks        Render AKS manifests"
        Write-Host "  render-openshift  Render OpenShift manifests"
        Write-Host "  render-gateway    Render Gateway API manifests"
        Write-Host "  package           Package the Helm chart"
        Write-Host "  docs-build        Build MkDocs static site to site\"
        Write-Host "  docs-serve        Live-preview docs at http://localhost:$DocsPort"
        Write-Host "  clean             Remove local image and site\"
        Write-Host ""
        Write-Host "Options: -Image $Image  -Tag $Tag  -Port $Port  -DocsPort $DocsPort" -ForegroundColor Gray
        Write-Host "Mirrors: -DockerRegistry  -PypiIndexUrl  -NpmRegistry  (all optional)" -ForegroundColor Gray
    }

    "build" {
        $vcs  = Get-VcsRef
        $date = Get-BuildDate
        $src  = Get-SourceUrl

        $mirrorArgs = @()
        if ($DockerRegistry) {
            $mirrorArgs += "--build-arg UBI9_IMAGE=$DockerRegistry/ubi9/ubi:latest"
            $mirrorArgs += "--build-arg UBI9_MINIMAL_IMAGE=$DockerRegistry/ubi9/ubi-minimal:latest"
            $mirrorArgs += "--build-arg UV_IMAGE=$DockerRegistry/astral-sh/uv:latest"
        }
        if ($PypiIndexUrl) { $mirrorArgs += "--build-arg PYPI_INDEX_URL=$PypiIndexUrl" }
        if ($NpmRegistry)  { $mirrorArgs += "--build-arg NPM_REGISTRY=$NpmRegistry" }

        $mirrorStr = $mirrorArgs -join " ``n            "
        Run "$ContainerTool build ``
            --build-arg VERSION=$Tag ``
            --build-arg VCS_REF=$vcs ``
            --build-arg BUILD_DATE=$date ``
            --build-arg SOURCE_URL=$src ``
            $mirrorStr ``
            -t ${Image}:${Tag} ."
    }

    "run" {
        & $PSCommandPath build -Image $Image -Tag $Tag -ContainerTool $ContainerTool
        Run "$ContainerTool run --rm -p ${Port}:8080 -e OPERATING_MODE=static ${Image}:${Tag}"
    }

    "run-once" {
        if (-not $env:ANTHROPIC_API_KEY) {
            Write-Error "ERROR: ANTHROPIC_API_KEY environment variable is not set."
            exit 1
        }
        if (-not $env:CLAUDE_TASK) {
            Write-Error "ERROR: CLAUDE_TASK environment variable is not set."
            exit 1
        }
        Run "$ContainerTool run --rm ``
            -e ANTHROPIC_API_KEY=$env:ANTHROPIC_API_KEY ``
            -e CLAUDE_TASK=$env:CLAUDE_TASK ``
            -e OPERATING_MODE=on-demand ``
            ${Image}:${Tag} --once"
    }

    "check" {
        if (Get-Command uv -ErrorAction SilentlyContinue) {
            Push-Location "container"
            Run "uv run python -m py_compile app.py"
            Pop-Location
        } else {
            Run "python3 -m py_compile container/app.py"
        }
        Write-Host "app.py syntax OK" -ForegroundColor Green
    }

    "lock" {
        Push-Location "container"
        Run "uv lock"
        Pop-Location
        Write-Host "uv.lock updated — commit container/uv.lock" -ForegroundColor Green
    }

    "sync" {
        Push-Location "container"
        Run "uv sync --extra build"
        Pop-Location
        Write-Host "Virtual environment synced." -ForegroundColor Green
    }

    "lint" {
        Run "helm lint $Chart"
    }

    "render" {
        & $PSCommandPath render-aks       -Image $Image -Tag $Tag
        & $PSCommandPath render-openshift -Image $Image -Tag $Tag
        & $PSCommandPath render-gateway   -Image $Image -Tag $Tag
    }

    "render-aks" {
        Run "helm template $Release $Chart -f $Chart/values-aks.yaml --set image.repository=$Image --set image.tag=$Tag"
    }

    "render-openshift" {
        Run "helm template $Release $Chart -f $Chart/values-openshift.yaml --api-versions route.openshift.io/v1/Route --set image.repository=$Image --set image.tag=$Tag"
    }

    "render-gateway" {
        Run "helm template $Release $Chart --set gateway.enabled=true --api-versions gateway.networking.k8s.io/v1/HTTPRoute --api-versions gateway.networking.k8s.io/v1/Gateway --set image.repository=$Image --set image.tag=$Tag"
    }

    "package" {
        Run "helm package $Chart"
    }

    "docs-build" {
        $pwd = (Get-Location).Path -replace '\\', '/'
        Run "$ContainerTool run --rm -v `"${pwd}:/docs`" squidfunk/mkdocs-material build --strict"
    }

    "docs-serve" {
        $pwd = (Get-Location).Path -replace '\\', '/'
        Write-Host "Starting docs server at http://localhost:$DocsPort ..." -ForegroundColor Green
        Run "$ContainerTool run --rm -p ${DocsPort}:8000 -v `"${pwd}:/docs`" squidfunk/mkdocs-material serve --dev-addr 0.0.0.0:8000"
    }

    "clean" {
        & $ContainerTool rmi "${Image}:${Tag}" 2>$null
        if (Test-Path "site") { Remove-Item -Recurse -Force "site" }
        Write-Host "Clean complete." -ForegroundColor Green
    }

    default {
        Write-Error "Unknown target: $Target. Run '.\scripts\make.ps1 help' for available targets."
        exit 1
    }
}

Pop-Location
