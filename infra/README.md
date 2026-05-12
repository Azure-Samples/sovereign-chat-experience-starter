# sovereign-chat-experience-starter — Infrastructure

Deploy sovereign-chat-experience-starter to Azure Arc-connected AKS clusters using `azd` (Azure Developer CLI).

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Azure Developer CLI (azd)](https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/install-azd)
- bash (Linux, macOS, or WSL/Git Bash on Windows)

## Quick Start

```bash
azd init

azd env set ARC_PREFIX "your-prefix"
azd env set NODE_COUNT "2"
azd env set VM_SIZE "Standard_D4s_v6"
azd env set DEPLOY_MODE "containerapp"    # or "k8s"

azd up
```

### Minimal K8s + MS Foundry

```bash
azd init

azd env set ARC_PREFIX "your-prefix"
azd env set NODE_COUNT "2"
azd env set VM_SIZE "Standard_D2s_v3"
azd env set DEPLOY_MODE "k8s"
azd env set DATASOURCES "api"
azd env set AI_PROJECT_ENDPOINT "https://<name>.cognitiveservices.azure.com/api/projects/<project>"
azd env set AI_AGENT_ID "<agent-name>:<version>"

azd up
```

## Two Deployment Modes

| | `k8s` | `containerapp` |
|---|---|---|
| Ingress | AKS App Routing (nginx) | Envoy (Container Apps extension) |
| TLS | Self-signed (custom domain for real cert) | Free `*.k4apps.io` + auto TLS |
| API URL | Auto-detected from ingress IP | Auto-detected from backend FQDN |
| Regions | Any AKS region | 11 regions only |
| Min VM | D2s_v6 | D4s_v6 |
| Pods | ~32 | ~62 |
| Offline | Yes | No |
| Extra config | — | `CUSTOM_LOCATION_OID` required |

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `ARC_PREFIX` | ✅ | Resource name prefix — all names derived from this |
| `NODE_COUNT` | ✅ | AKS node count (e.g. `2`) |
| `VM_SIZE` | ✅ | AKS VM size (e.g. `Standard_D2s_v3`) |
| `DEPLOY_MODE` | ✅ | `k8s` or `containerapp` |
| `DEPLOY_SCOPE` | optional | `all` (default), `frontend`, or `backend` |
| `AZURE_LOCATION` | auto | Set during `azd init` (region dropdown) |
| `VITE_API_URL` | frontend scope | Custom backend URL — required for `DEPLOY_SCOPE=frontend` |
| `CUSTOM_LOCATION_OID` | containerapp only | Custom Locations RP Object ID ([how to get](https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/custom-locations#enable-custom-locations-on-cluster)) |
| `BACKEND_CPU` | optional | Backend CPU limit (default: `250m`) |
| `BACKEND_CPU_REQUEST` | optional | Backend CPU request for scheduling (default: `50m`) |
| `FRONTEND_CPU` | optional | Frontend CPU limit (default: `100m`) |
| `FRONTEND_CPU_REQUEST` | optional | Frontend CPU request for scheduling (default: `10m`) |
| `BACKEND_MEMORY` | optional | Backend memory limit (default: `512Mi`) |
| `BACKEND_MEMORY_REQUEST` | optional | Backend memory request (default: `256Mi`) |
| `FRONTEND_MEMORY` | optional | Frontend memory limit (default: `128Mi`) |
| `FRONTEND_MEMORY_REQUEST` | optional | Frontend memory request (default: `64Mi`) |
| `DATASOURCES` | optional | `mock` (default) or `api` (Microsoft Foundry) |
| `AI_PROJECT_ENDPOINT` | when `api` | Microsoft Foundry endpoint |
| `AI_AGENT_ID` | when `api` | MS Foundry agent ID |
| `STREAMING` | optional | `enabled` (default) or `disabled` |
| `ENABLE_ADMIN_ROUTES` | optional | `false` (default) or `true` |
| `CORS_ORIGINS` | optional | Allowed origins (auto-detected from frontend URL) |

## File Structure

```
azure.yaml                    # azd project definition
infra/
├── main.bicep                # Bicep orchestrator (AKS + ACR + Identity)
├── main.parameters.json      # Maps azd env → Bicep params
├── naming.sh                 # Shared resource naming (clamps to Azure limits)
├── modules/
│   ├── aks.bicep             # AKS + OIDC + Workload Identity + App Routing
│   ├── acr.bicep             # Container Registry
│   └── identity.bicep        # Managed Identity + Federated Credential + RBAC
└── modes/
    ├── k8s/                  # Raw K8s manifests + deploy script
    │   ├── postprovision.sh  # Arc connect + SA + ACR attach
    │   ├── deploy.sh         # Build images + kubectl apply
    │   ├── namespace.yaml
    │   ├── backend.yaml
    │   ├── frontend.yaml
    │   └── ingress.yaml
    └── containerapp/         # Container Apps on Arc
        ├── postprovision.sh  # Arc + extension + custom location + connected env
        └── deploy.sh         # Build images + az containerapp create
hooks/
├── preprovision.sh           # Config validation (runs before Bicep)
├── postprovision.sh          # RBAC + delegates to modes/<mode>/postprovision.sh
├── deploy.sh                 # Delegates to modes/<mode>/deploy.sh
└── connect-foundry.sh        # Connect existing cluster to MS Foundry (no re-provision)
```

## How It Works

```
azd up
  ├─ preprovision.sh         → validates config, checks region for containerapp
  ├─ Bicep provision         → creates AKS + ACR + Managed Identity (shared)
  ├─ postprovision.sh        → delegates to mode:
  │   ├─ k8s:          Arc connect + ACR attach + K8s SA
  │   └─ containerapp: Arc + extension + custom location + connected env + SA
  └─ deploy.sh (postup)      → delegates to mode:
      ├─ k8s:          build images → deploy backend → get IP → build frontend → deploy frontend
      └─ containerapp: build images → create backend app → get FQDN → build frontend → create frontend app
```

## Identity

- **Workload Identity** — per-pod, no secrets
- Managed Identity + Federated Credential created by Bicep
- K8s Service Account annotated in postprovision
- `DefaultAzureCredential` in the server picks it up automatically
- RBAC scoped to MS Foundry resource only

## Commands

```bash
azd up                  # provision + deploy (full)
azd provision           # infra only
./hooks/deploy.sh       # redeploy only (build + apply)
./hooks/deploy.sh -y    # redeploy, skip confirmation prompt
./hooks/connect-foundry.sh  # connect existing cluster to MS Foundry
azd down --force        # tear down everything

# Skip all confirmation prompts (CI/automation)
AUTO_YES=true azd up

# Frontend only (BYOB)
azd env set DEPLOY_SCOPE "frontend"
azd env set VITE_API_URL "https://your-backend.com/api"
azd up
```
