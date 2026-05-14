---
order: 1
---

# Deployment Guide

Complete guide for deploying sovereign-chat-experience-starter to Azure using `azd`.

## Recipe-Based Deploy (Recommended)

The fastest way to deploy — a recipe sets all defaults for you:

```bash
azd env set RECIPE all    # full stack + MS Foundry (gpt-4o-mini, D2s_v6, 2 nodes)
azd up                    # prompts for subscription + location, recipe handles the rest
```

Available recipes:

| Recipe | What you get                                                   |
| ------ | -------------------------------------------------------------- |
| `all`  | Full stack + MS Foundry (gpt-4o-mini, D2s_v6, 2 nodes)         |
| `dev`  | Full stack + mock AI (B2s cheapest VM, admin enabled, CORS=\*) |

> **Note:** `ARC_PREFIX` is auto-derived from the azd environment name. `azd env new my-chat` creates `my-chat-rg`, `my-chat-cluster`, etc.

## Interactive Wizard

Run `azd up` without setting `RECIPE` to walk through the interactive wizard with arrow-key navigation:

```bash
azd up    # wizard prompts for region, VM size, AI mode, deploy scope, etc.
```

## Common Scenarios

### Dev/Test (Recipe: dev)

Full stack + mock AI on the cheapest VM (B2s, admin routes enabled, CORS=*):

```bash
azd env set RECIPE dev
azd up
```

### BYO MS Foundry

Use the wizard and select `byo` when prompted for AI mode:

```bash
azd up    # select "byo" in AI mode step, enter your MS Foundry details
```

### Frontend Only (BYOB)

Deploy the chat UI with your own backend:

```bash
azd env set DEPLOY_SCOPE "frontend"
azd env set VITE_API_URL "https://your-backend.com/api"
azd up
```

### CI/Automation

Use a recipe with the `-y` flag to skip all prompts:

```bash
azd env new my-chat
azd env set RECIPE all
azd up -- -y
```

### Resume Existing Deployment

On a new machine (or fresh clone), resume with just the prefix and subscription:

```bash
git clone <repo-url> && cd sovereign-chat-experience-starter
azd env new <existing-prefix>                     # must match original env name
azd env set AZURE_SUBSCRIPTION_ID <sub-id>
azd up
```

`infra/defaults.sh` auto-detects from Azure (AKS, ACR, identity, AI hub) and reads deployment config from RG tags. No need to re-set any other env vars.

> **How it works:** `apply_defaults()` uses the prefix to find the resource group (`<prefix>-rg`), queries AKS for VM size/nodes/location, reads ACR and identity, reads config from RG tags (including agent-id), and derives AI_MODE from hub existence. Local `azd env set` values always take priority over tags.

### Connect Existing Cluster to MS Foundry

Already running with mock mode? Switch to MS Foundry without re-provisioning:

```bash
azd env set AI_PROJECT_ENDPOINT "https://<name>.cognitiveservices.azure.com/api/projects/<project>"
azd env set AI_AGENT_ID "<agent-name>:<version>"
azd env set AI_RESOURCE_GROUP "<rg-containing-ai-foundry>"

# Connect (assigns RBAC + sets DATASOURCES=api + redeploys)
./hooks/connect-foundry.sh -y
```

This is a standalone operation — no Bicep, no cluster re-provisioning. It assigns RBAC roles on the MS Foundry resource group and redeploys the backend with API settings.

To switch back to mock:

```bash
azd env set DATASOURCES "mock"
./hooks/deploy.sh -y
```

## Common Operations

**Redeploy after code changes:**

```bash
azd up                  # full wizard — modify settings + provision + deploy
./hooks/deploy.sh       # fast redeploy — current settings, no provision
./hooks/deploy.sh -y    # instant redeploy, skip confirmation
```

**Tear down:**

```bash
azd down --force --purge
```

**Dry-run test (validate all deployment scenarios without Azure):**

```bash
bash scripts/test-deploy-matrix.sh           # 35 tests: config, manifests, transitions
bash scripts/test-deploy-matrix.sh --verbose  # show cleanup prompts that would fire
```

### Managing Environments

`azd` supports multiple environments — use separate environments for each deployment mode or cluster:

```bash
azd env new k8s                 # create environments
azd env new containerapp

azd env select k8s              # switch between them
azd env list                    # list all
azd env get-values              # view current config
```

### Viewing Kubernetes Resources in Azure Portal

The Azure Portal requires a bearer token to display cluster resources:

```bash
./scripts/portal-token.sh       # generates bearer token, copies to clipboard
```

Then in Portal: AKS cluster → Kubernetes resources → Sign in → Token → paste. The token is valid for 48 hours.

## Environment Reference

Complete reference for all `azd` environment variables. Most are set automatically by the interactive wizard — manual `azd env set` is optional.

### Infrastructure

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `RECIPE` | - | - | `all` (full stack + MS Foundry), `dev` (mock + cheapest VM), or empty for wizard |
| `ARC_PREFIX` | auto | - | Auto-derived from azd env name — do NOT set manually |
| `NODE_COUNT` | ✅ | - | AKS node count |
| `VM_SIZE` | ✅ | - | AKS VM size (e.g. `Standard_D2s_v3`) |
| `DEPLOY_MODE` | ✅ | - | `k8s` or `containerapp` |
| `DEPLOY_SCOPE` | - | `all` | `all`, `frontend`, or `backend` |
| `AZURE_LOCATION` | auto | - | Set during `azd init` |
| `CUSTOM_LOCATION_OID` | containerapp | - | Custom Locations RP Object ID |
| `AI_RESOURCE_GROUP` | - | - | RG containing MS Foundry — enables cross-RG RBAC |
| `AZURE_WI_CLIENT_ID` | auto | - | Managed Identity client ID — set by Bicep |

### AI Configuration

| Variable | Default | Used in mode | Description |
|----------|---------|-------------|-------------|
| `AI_MODE` | `byo` | all | `create` (auto-provision), `byo` (existing project), or `mock` |
| `AI_MODEL_NAME` | `gpt-4o-mini` | create | Model to deploy |
| `AI_MODEL_VERSION` | `2024-07-18` | create | Model version |
| `AI_MODEL_CAPACITY` | `1` | create | Capacity in K TPM |
| `AI_PROJECT_ENDPOINT` | - | create, byo | MS Foundry project endpoint |
| `AI_AGENT_ID` | - | create, byo | Agent ID (`name:version`) |
| `DATASOURCES` | `mock` | all | `mock` or `api` |

### App Settings (Pod Runtime)

| Variable | Default | Description |
|----------|---------|-------------|
| `VITE_API_URL` | `/api` | Backend API URL. Defaults to `/api` (proxied in dev, relative in production). Required for `DEPLOY_SCOPE=frontend` when backend is on a different host |
| `STREAMING` | `enabled` | `enabled` or `disabled` — SSE streaming for responses |
| `CORS_ORIGINS` | `auto` | `auto` detects from frontend ingress URL, `*` allows all, or a specific URL |
| `ENABLE_ADMIN_ROUTES` | `false` | Enable `/api/admin/*` endpoints for runtime toggles |

### Resource Sizing

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKEND_REPLICAS` | `1` | Backend replica count |
| `FRONTEND_REPLICAS` | `1` | Frontend replica count |
| `BACKEND_CPU` | `250m` | Backend CPU limit |
| `BACKEND_CPU_REQUEST` | `50m` | Backend CPU request |
| `BACKEND_MEMORY` | `512Mi` | Backend memory limit |
| `BACKEND_MEMORY_REQUEST` | `256Mi` | Backend memory request |
| `FRONTEND_CPU` | `100m` | Frontend CPU limit |
| `FRONTEND_CPU_REQUEST` | `10m` | Frontend CPU request |
| `FRONTEND_MEMORY` | `128Mi` | Frontend memory limit |
| `FRONTEND_MEMORY_REQUEST` | `64Mi` | Frontend memory request |
| `IMAGE_TAG` | `latest` | Container image tag |

### Wizard State

These track deployment state for the wizard's change-detection logic. On resume, `PROVISION_DONE` is auto-set by `infra/defaults.sh` when it detects existing Azure resources. Config state is persisted as RG tags for cross-machine resume — local `azd env set` values always take priority.

| Variable | Description |
|----------|-------------|
| `WIZARD_DONE` | `true` after wizard completes |
| `PROVISION_DONE` | `true` after first provision — locks infra settings. Run `azd down` to unlock |
| `PREV_DEPLOY_SCOPE` | Previous deploy scope — detects scope narrowing and offers cleanup |
| `PREV_AI_MODE` | Previous AI mode — detects mode changes and offers resource cleanup |
| `CLEANUP_AI` | `keep` or `delete` — MS Foundry resource cleanup |
| `CLEANUP_FRONTEND` | `yes` or `no` — remove frontend pods when narrowing scope |
| `CLEANUP_BACKEND` | `yes` or `no` — remove backend pods when narrowing scope |
| `AUTO_YES` | One-shot flag — wizard creates temp file, deploy.sh reads and deletes it |

## Troubleshooting

### WI Watcher Not Running (Container Apps)

If your Container Apps backend returns 500 errors with `DefaultAzureCredential` failures, the WI watcher may not be running. This typically happens when Azure Policy (Gatekeeper) blocks the watcher's container image.

**Symptoms:**

- Backend returns `{"error":{"code":"server_error","message":"Failed to generate response"}}`
- Container logs show `CredentialUnavailableError` from `DefaultAzureCredential`
- Watcher pod shows `FailedCreate` or `ImagePullBackOff`

**Diagnose:**

```bash
kubectl get pods -n <namespace> | grep watcher
kubectl describe deployment <prefix>-wi-watcher -n <namespace> | tail -20
```

**Fix:**

```bash
./hooks/deploy.sh       # redeploy handles everything automatically
```

**Quick manual WI patch** (if watcher is down and you need it working now):

```bash
DEPLOY=$(kubectl get deployment -n <namespace> -o name | grep <prefix>-server | head -1)

kubectl patch $DEPLOY -n <namespace> --type='json' -p='[
  {"op":"add","path":"/spec/template/metadata/labels/azure.workload.identity~1use","value":"true"},
  {"op":"replace","path":"/spec/template/spec/serviceAccountName","value":"<prefix>-backend-sa"}
]'
```
