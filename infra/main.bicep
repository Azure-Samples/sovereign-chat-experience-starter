// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
// ============================================================
// sovereign-chat-experience-starter — Main Bicep Orchestrator
// ============================================================
// Creates Azure resources for K8s deployment.
// Arc connection and K8s resources are handled by hooks.
// No Container Apps extension required.
// ============================================================

targetScope = 'subscription'

// ─── Parameters ─────────────────────────────────────────────
@description('Prefix for all resource names (set via ARC_PREFIX env var)')
param prefix string = 'not-set'

@description('Azure region (set via AZURE_LOCATION env var)')
@metadata({
  azd: {
    type: 'location'
    usageName: [
      'OpenAI.GlobalStandard.gpt-4o-mini,1'
    ]
  }
})
param location string

@description('AKS node count (recommended: 2 for dev, 3+ for prod)')
param nodeCount int = 2

@description('AKS VM size (recommended: Standard_D2s_v3 for dev, D4s_v6 for prod)')
param vmSize string = 'Standard_D2s_v3'

@description('MS Foundry endpoint (optional — leave empty for mock mode). Also injected into the pod at deploy time.')
param aiProjectEndpoint string = ''

@description('AI mode: "byo" = bring your own, "create" = provision MS Foundry, "mock" = no AI')
@allowed(['byo', 'create', 'mock'])
param aiMode string = 'byo'

@description('Model to deploy (only used when aiMode=create)')
param aiModelName string = 'gpt-4o-mini'

@description('Model version (only used when aiMode=create)')
param aiModelVersion string = '2024-07-18'

@description('Model capacity in TPM thousands (only used when aiMode=create)')
param aiModelCapacity int = 1

@description('Kubernetes namespace')
param namespace string = '${prefix}-ns'

@description('Deploy scope — controls whether identity resources are created')
param deployScope string = 'all'

var needsBackend = deployScope == 'all' || deployScope == 'backend'
var createAI = aiMode == 'create' && needsBackend

// ─── Resource Group ─────────────────────────────────────────
resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: '${prefix}-rg'
  location: location
}

// ─── Modules ────────────────────────────────────────────────
module aks './modules/aks.bicep' = {
  name: 'aks'
  scope: rg
  params: {
    prefix: prefix
    location: location
    nodeCount: nodeCount
    vmSize: vmSize
  }
}

module acr './modules/acr.bicep' = {
  name: 'acr'
  scope: rg
  params: {
    prefix: prefix
    location: location
  }
}

// Identity — only when deploying backend
module identity './modules/identity.bicep' = if (needsBackend) {
  name: 'identity'
  scope: rg
  params: {
    prefix: prefix
    location: location
    namespace: namespace
    oidcIssuerUrl: aks.outputs.oidcIssuerUrl
  }
}

// MS Foundry resources — only when aiMode=create
module aiFoundry './modules/ai-foundry.bicep' = if (createAI) {
  name: 'aiFoundry'
  scope: rg
  params: {
    prefix: prefix
    location: location
    modelName: aiModelName
    modelVersion: aiModelVersion
    modelCapacity: aiModelCapacity
  }
}

// RBAC for AI resources is handled in the postprovision hook (az CLI)
// to avoid RoleAssignmentExists errors on re-deploy.

// ─── Cross-RG RBAC (BYO mode only) ──────────────────────────
// When aiMode=byo, cross-RG role assignments for MS Foundry are
// handled in the postprovision hook (via az CLI) to avoid azd down
// tracking the external AI resource group.
// When aiMode=create, RBAC is handled inline by ai-foundry.bicep.

// ─── Outputs (consumed by hooks) ────────────────────────────
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_AKS_CLUSTER_NAME string = aks.outputs.clusterName
output AZURE_ACR_NAME string = acr.outputs.acrName
output AZURE_ACR_SERVER string = acr.outputs.acrLoginServer
output AZURE_WI_IDENTITY_NAME string = needsBackend ? identity.outputs.identityName : ''
output AZURE_WI_CLIENT_ID string = needsBackend ? identity.outputs.identityClientId : ''
output AZURE_WI_PRINCIPAL_ID string = needsBackend ? identity.outputs.identityPrincipalId : ''
output AZURE_WI_SA_NAME string = '${prefix}-backend-sa'
output AZURE_NAMESPACE string = namespace
output AZURE_LOCATION string = location
output AZURE_PREFIX string = prefix
output AI_MODE string = aiMode
output AI_FOUNDRY_ENDPOINT string = createAI ? aiFoundry.outputs.aiEndpoint : ''
output AI_FOUNDRY_MODEL_DEPLOYMENT string = createAI ? aiFoundry.outputs.aiModelDeploymentName : ''
