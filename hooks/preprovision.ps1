# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  preprovision.ps1 — Interactive Setup Wizard & Validation (PowerShell) ║
# ╠═══════════════════════════════════════════════════════════════════════════╣
# ║                                                                         ║
# ║  Flow:                                                                  ║
# ║    1. Parse flags (-y / --yes for CI mode)                              ║
# ║    2. Validate CLI dependencies (az, azd)                               ║
# ║    3. If a RECIPE env var is set → apply recipe, validate, confirm      ║
# ║    4. If AUTO_YES → apply defaults silently (CI path)                   ║
# ║    5. If already provisioned → offer redeploy or modify                 ║
# ║    6. Otherwise → first-run: recipe picker or full wizard               ║
# ║       Wizard steps: subscription → infrastructure → scope →             ║
# ║                     AI config → backend settings                        ║
# ║    7. Validate config, show summary, confirm                            ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

$ErrorActionPreference = "Stop"

# ═══════════════════════════════════════════════════════════════════════════
# Dependencies & CLI Flags
# ═══════════════════════════════════════════════════════════════════════════

$AUTO_YES = if ($env:AUTO_YES -eq "true") { $true } else { $false }
foreach ($a in $args) {
    if ($a -eq "-y" -or $a -eq "--yes") { $AUTO_YES = $true }
}
$env:AUTO_YES = if ($AUTO_YES) { "true" } else { "false" }

$SCRIPT_DIR = $PSScriptRoot
$INFRA_DIR  = (Resolve-Path (Join-Path $SCRIPT_DIR "..\infra")).Path

. "$INFRA_DIR\validate.ps1"
Require-Cli "az"
Require-Cli "azd"
Invoke-ValidateOrExit

. "$INFRA_DIR\prompts.ps1"
. "$INFRA_DIR\defaults.ps1"

$ESC = [char]27
$CYAN = "${ESC}[0;36m"; $GREEN = "${ESC}[0;32m"; $YELLOW = "${ESC}[1;33m"; $RED = "${ESC}[0;31m"
$DIM  = "${ESC}[2m"; $BOLD = "${ESC}[1m"; $MAGENTA = "${ESC}[0;35m"; $NC = "${ESC}[0m"

# ═══════════════════════════════════════════════════════════════════════════
# Wizard Step 0 — Azure Subscription
# ═══════════════════════════════════════════════════════════════════════════

function Wizard-Subscription {
    if (Get-Val "AZURE_SUBSCRIPTION_ID") { return }

    Show-Section "`u{24EA} Azure Subscription" "Select which Azure subscription to deploy into."

    Write-Host -NoNewline "  ${DIM}Loading subscriptions...${NC}`r"
    $subLines = az account list --query "[?state=='Enabled'].[id, name, isDefault]" -o tsv 2>$null
    Write-Host -NoNewline "                                    `r"

    $SUB_IDS = @(); $SUB_NAMES = @(); $SUB_DEFAULT_IDX = 0
    foreach ($line in $subLines) {
        if (-not $line) { continue }
        $parts = $line -split "`t"
        if ($parts.Count -lt 3) { continue }
        $SUB_IDS += $parts[0]
        $SUB_NAMES += $parts[1]
        if ($parts[2] -eq "true") { $SUB_DEFAULT_IDX = $SUB_IDS.Count }
    }

    if ($SUB_IDS.Count -eq 0) {
        Write-Host "  ${RED}No subscriptions found. Run 'az login' first.${NC}"; exit 1
    } elseif ($SUB_IDS.Count -eq 1) {
        Save-Val "AZURE_SUBSCRIPTION_ID" $SUB_IDS[0]
        Write-Host "  Using subscription: ${CYAN}$($SUB_NAMES[0])${NC}"; Write-Host ""
    } else {
        $SUB_DISPLAY = @()
        for ($i = 0; $i -lt $SUB_IDS.Count; $i++) {
            $SHORT_ID = $SUB_IDS[$i].Substring(0, [Math]::Min(8, $SUB_IDS[$i].Length)) + "..."
            $TAG = ""; if (($i + 1) -eq $SUB_DEFAULT_IDX) { $TAG = " ${DIM}`u{2190} az default${NC}" }
            $SUB_DISPLAY += "$($SUB_NAMES[$i]) ${DIM}(${SHORT_ID})${NC}${TAG}"
        }
        $DEF_SUB = ""
        if ($SUB_DEFAULT_IDX -gt 0) { $DEF_SUB = $SUB_IDS[$SUB_DEFAULT_IDX - 1] }
        Prompt-Select "AZURE_SUBSCRIPTION_ID" "Select subscription" $SUB_IDS $SUB_DISPLAY "" $DEF_SUB
    }

    $SEL = Get-Val "AZURE_SUBSCRIPTION_ID"
    if ($SEL) { az account set --subscription "$SEL" 2>$null }
}

# ═══════════════════════════════════════════════════════════════════════════
# Wizard Step 1 — Infrastructure (AKS cluster, prefix, VM size)
# ═══════════════════════════════════════════════════════════════════════════

function Wizard-Infrastructure {
    Show-Section "`u{2460} Infrastructure" "Azure resources that will be created for your deployment."

    # If already provisioned — show locked values, no selectors
    if ((Get-Val "PROVISION_DONE") -eq "true") {
        $P = Get-Val "ARC_PREFIX"; $L = Get-Val "AZURE_LOCATION"
        $N = Get-Val "NODE_COUNT"; $V = Get-Val "VM_SIZE"
        Write-Host "  ${DIM}`u{1F512} Infrastructure is locked after first provision.${NC}"
        Write-Host "  ${DIM}   To change, run 'azd down' first, then 'azd up'.${NC}"
        Write-Host ""
        Write-Host "  Prefix:     ${CYAN}${P}${NC}"
        Write-Host "  Region:     ${CYAN}${L}${NC}"
        Write-Host "  Nodes:      ${CYAN}${N}${NC}"
        Write-Host "  VM Size:    ${CYAN}${V}${NC}"
        Write-Host ""
        Save-Val "DEPLOY_MODE" "k8s"
        return
    }

    # Prefix is always derived from azd env name — never prompted
    $ENV_NAME = Get-Val "AZURE_ENV_NAME"
    Save-Val "ARC_PREFIX" "$ENV_NAME"
    Write-Host "  ${DIM}Prefix:${NC} ${CYAN}${ENV_NAME}${NC} ${DIM}(from azd env name)${NC}"

    # ── Auto-detect existing infrastructure from Azure ──────────────
    $PREFIX = Get-Val "ARC_PREFIX"
    $RG_NAME = "${PREFIX}-rg"
    if ($PREFIX -and (Get-Val "PROVISION_DONE") -ne "true") {
        $rgExists = $false
        try { az group show --name "$RG_NAME" --output none 2>$null; $rgExists = ($LASTEXITCODE -eq 0) } catch {}
        if ($rgExists) {
            Write-Host "  ${GREEN}`u{2713} Found existing resource group: ${RG_NAME}${NC}"
            Write-Host -NoNewline "  ${DIM}Detecting existing infrastructure...${NC}`r"

            # Detect AKS cluster
            $AKS_TSV = az aks show --name "${PREFIX}-cluster" --resource-group "$RG_NAME" `
                --query "[agentPoolProfiles[0].vmSize, agentPoolProfiles[0].count, location]" `
                -o tsv 2>$null
            if ($AKS_TSV -and $LASTEXITCODE -eq 0) {
                $parts = $AKS_TSV -split "`t"
                if ($parts.Count -ge 3) {
                    if ($parts[0]) { Save-Val "VM_SIZE" $parts[0] }
                    if ($parts[1]) { Save-Val "NODE_COUNT" $parts[1] }
                    if ($parts[2]) { Save-Val "AZURE_LOCATION" $parts[2] }
                    Write-Host "  ${GREEN}`u{2713} AKS cluster:${NC} $($parts[1]) x $($parts[0]) in $($parts[2])"
                }
            }

            # Detect AI hub
            $AI_HUB_NAME = "${PREFIX}-ai-hub"
            $aiInfo = $null
            try { $aiInfo = az cognitiveservices account show --name "$AI_HUB_NAME" --resource-group "$RG_NAME" `
                --query "{endpoint:properties.endpoint}" -o json 2>$null } catch {}
            if ($aiInfo -and $LASTEXITCODE -eq 0) {
                Save-Val "AI_MODE" "create"
                Save-Val "PREV_AI_MODE" "create"
                Write-Host "  ${GREEN}`u{2713} MS Foundry hub:${NC} ${AI_HUB_NAME}"

                # Detect model deployment
                $DEPLOY_TSV = az cognitiveservices account deployment list `
                    --name "$AI_HUB_NAME" --resource-group "$RG_NAME" `
                    --query "[0].[properties.model.name, properties.model.version, sku.capacity]" `
                    -o tsv 2>$null
                if ($DEPLOY_TSV -and $LASTEXITCODE -eq 0) {
                    $dp = $DEPLOY_TSV -split "`t"
                    if ($dp.Count -ge 3) {
                        if ($dp[0] -and $dp[0] -ne "None") { Save-Val "AI_MODEL_NAME" $dp[0] }
                        if ($dp[1] -and $dp[1] -ne "None") { Save-Val "AI_MODEL_VERSION" $dp[1] }
                        if ($dp[2] -and $dp[2] -ne "None") { Save-Val "AI_MODEL_CAPACITY" $dp[2] }
                        Write-Host "  ${GREEN}`u{2713} Model deployment:${NC} $($dp[0]) v$($dp[1]) ($($dp[2])K TPM)"
                    }
                }

                # Detect project endpoint
                $PROJECT_NAME = "${PREFIX}-ai-project"
                $projInfo = $null
                try { $projInfo = az cognitiveservices account show `
                    --name "${AI_HUB_NAME}/${PROJECT_NAME}" --resource-group "$RG_NAME" `
                    -o json 2>$null } catch {}
                if ($projInfo -and $LASTEXITCODE -eq 0) {
                    Save-Val "AI_PROJECT_ENDPOINT" "https://${AI_HUB_NAME}.cognitiveservices.azure.com/api/projects/${PROJECT_NAME}"
                    Write-Host "  ${GREEN}`u{2713} AI project:${NC} ${PROJECT_NAME}"
                }
            }

            # Detect workload identity
            $WI_NAME = "${PREFIX}-backend-id"
            $WI_TSV = az identity show --name "$WI_NAME" --resource-group "$RG_NAME" `
                --query "[clientId, principalId]" -o tsv 2>$null
            if ($WI_TSV -and $LASTEXITCODE -eq 0) {
                $wp = $WI_TSV -split "`t"
                if ($wp.Count -ge 2) {
                    if ($wp[0]) { Save-Val "AZURE_WI_CLIENT_ID" $wp[0] }
                    if ($wp[1]) { Save-Val "AZURE_WI_PRINCIPAL_ID" $wp[1] }
                    Write-Host "  ${GREEN}`u{2713} Workload Identity:${NC} ${WI_NAME}"
                }
            }

            Save-Val "PROVISION_DONE" "true"
            Write-Host ""
        }
    }

    Save-Val "DEPLOY_MODE" "k8s"

    Prompt-Val "NODE_COUNT" "AKS node count" "2" "" "Number of nodes in the AKS cluster (2 for dev, 3+ for prod)"

    # ── VM size selector — popular first, with expand + custom ────
    $POP_VM_V = @("Standard_B2s", "Standard_D2s_v3", "Standard_D4s_v6", "Standard_D2s_v5", "Standard_D4s_v5", "Standard_B4ms")
    $POP_VM_D = @(
        "Standard_B2s ${DIM}`u{2014} 2 vCPU, 4 GB (burstable, cheapest)${NC}"
        "Standard_D2s_v3 ${DIM}`u{2014} 2 vCPU, 8 GB${NC} ${GREEN}(Recommended)${NC}"
        "Standard_D4s_v6 ${DIM}`u{2014} 4 vCPU, 16 GB (prod)${NC}"
        "Standard_D2s_v5 ${DIM}`u{2014} 2 vCPU, 8 GB (prev gen)${NC}"
        "Standard_D4s_v5 ${DIM}`u{2014} 4 vCPU, 16 GB (prev gen)${NC}"
        "Standard_B4ms ${DIM}`u{2014} 4 vCPU, 16 GB (burstable)${NC}"
    )
    $POP_VM_V += "__more__"; $POP_VM_V += "__custom__"
    $POP_VM_D += "${BOLD}More sizes...${NC} ${DIM}`u{2014} additional VM options${NC}"
    $POP_VM_D += "${BOLD}Custom...${NC} ${DIM}`u{2014} type a VM size manually${NC}"

    Write-Host "  ${DIM}VM size for AKS nodes.${NC}"
    while ($true) {
        Prompt-Select "VM_SIZE" "AKS VM size" $POP_VM_V $POP_VM_D "" "Standard_D2s_v3"
        $VM_PICKED = Get-Val "VM_SIZE"

        if ($VM_PICKED -eq "__back__") {
            Save-Val "VM_SIZE" ""; continue
        } elseif ($VM_PICKED -eq "__more__") {
            Save-Val "VM_SIZE" ""
            $EXT_V = @("Standard_B2ms","Standard_B2s","Standard_B4ms",
                "Standard_D2s_v3","Standard_D2ds_v5","Standard_D2s_v5","Standard_D2s_v6",
                "Standard_D2as_v5","Standard_D4s_v3","Standard_D4s_v5","Standard_D4s_v6",
                "Standard_D4as_v5","Standard_D8s_v3","Standard_D8s_v5",
                "Standard_E2s_v5","Standard_E4s_v5","Standard_E8s_v5",
                "Standard_F2s_v2","Standard_F4s_v2","Standard_F8s_v2")
            $EXT_D = @(
                "Standard_B2ms ${DIM}`u{2014} 2 vCPU, 8 GB (burstable)${NC}"
                "Standard_B2s ${DIM}`u{2014} 2 vCPU, 4 GB (burstable, cheapest)${NC}"
                "Standard_B4ms ${DIM}`u{2014} 4 vCPU, 16 GB (burstable)${NC}"
                "Standard_D2s_v3 ${DIM}`u{2014} 2 vCPU, 8 GB${NC} ${GREEN}(Recommended)${NC}"
                "Standard_D2ds_v5 ${DIM}`u{2014} 2 vCPU, 8 GB (local SSD)${NC}"
                "Standard_D2s_v5 ${DIM}`u{2014} 2 vCPU, 8 GB${NC}"
                "Standard_D2s_v6 ${DIM}`u{2014} 2 vCPU, 8 GB (newest)${NC}"
                "Standard_D2as_v5 ${DIM}`u{2014} 2 vCPU, 8 GB (AMD)${NC}"
                "Standard_D4s_v3 ${DIM}`u{2014} 4 vCPU, 16 GB${NC}"
                "Standard_D4s_v5 ${DIM}`u{2014} 4 vCPU, 16 GB${NC}"
                "Standard_D4s_v6 ${DIM}`u{2014} 4 vCPU, 16 GB (newest)${NC}"
                "Standard_D4as_v5 ${DIM}`u{2014} 4 vCPU, 16 GB (AMD)${NC}"
                "Standard_D8s_v3 ${DIM}`u{2014} 8 vCPU, 32 GB${NC}"
                "Standard_D8s_v5 ${DIM}`u{2014} 8 vCPU, 32 GB${NC}"
                "Standard_E2s_v5 ${DIM}`u{2014} 2 vCPU, 16 GB (memory opt)${NC}"
                "Standard_E4s_v5 ${DIM}`u{2014} 4 vCPU, 32 GB (memory opt)${NC}"
                "Standard_E8s_v5 ${DIM}`u{2014} 8 vCPU, 64 GB (memory opt)${NC}"
                "Standard_F2s_v2 ${DIM}`u{2014} 2 vCPU, 4 GB (compute opt)${NC}"
                "Standard_F4s_v2 ${DIM}`u{2014} 4 vCPU, 8 GB (compute opt)${NC}"
                "Standard_F8s_v2 ${DIM}`u{2014} 8 vCPU, 16 GB (compute opt)${NC}"
            )
            Prompt-Select "VM_SIZE" "AKS VM size" $EXT_V $EXT_D "" "Standard_D2s_v3"
            if ((Get-Val "VM_SIZE") -eq "__back__") { Save-Val "VM_SIZE" ""; continue }
            break
        } elseif ($VM_PICKED -eq "__custom__") {
            Save-Val "VM_SIZE" ""
            Prompt-Val "VM_SIZE" "VM size name" "Standard_D2s_v3" "--required" `
                "Enter the exact Azure VM size (e.g. Standard_D2s_v3, Standard_E4s_v5)"
            break
        } else {
            break
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Wizard Step 2 — Deploy Scope (full-stack, backend-only, frontend-only)
# ═══════════════════════════════════════════════════════════════════════════

function Wizard-Scope {
    Show-Section "`u{2461} Deploy" "What and how to deploy."

    $PREV_SCOPE = Get-Val "PREV_DEPLOY_SCOPE"

    Prompt-Choice "DEPLOY_SCOPE" "What to deploy" `
        "all|Full stack `u{2014} frontend + backend + ingress" `
        "backend|Backend only `u{2014} API server and AI integration" `
        "frontend|Frontend only `u{2014} connect to an existing backend"

    $NEW_SCOPE = Get-Val "DEPLOY_SCOPE"

    if ((Get-Val "DEPLOY_SCOPE") -eq "frontend") {
        Prompt-Val "VITE_API_URL" "Backend API URL" "" "--required" `
            "The URL of your existing backend API (e.g. https://my-api.example.com/api)"
    } else {
        Save-Val "VITE_API_URL" ""
    }

    # Detect scope narrowing — offer to clean up orphaned resources
    if (-not $AUTO_YES -and $PREV_SCOPE -and $PREV_SCOPE -ne $NEW_SCOPE) {
        $NS = Get-Val "ARC_NAMESPACE"
        $PREFIX = Get-Val "ARC_PREFIX"
        $FE_EXISTS = $false; $BE_EXISTS = $false
        if ((Get-Command kubectl -ErrorAction SilentlyContinue) -and $NS) {
            try { kubectl get deployment "${PREFIX}-frontend" -n "$NS" --no-headers 2>$null | Out-Null; $FE_EXISTS = ($LASTEXITCODE -eq 0) } catch {}
            try { kubectl get deployment "${PREFIX}-server" -n "$NS" --no-headers 2>$null | Out-Null; $BE_EXISTS = ($LASTEXITCODE -eq 0) } catch {}
        }

        if ($NEW_SCOPE -eq "backend" -and $FE_EXISTS) {
            Prompt-Choice "CLEANUP_FRONTEND" "Frontend is currently deployed. Remove it?" `
                "yes|Remove frontend pods and service (saves cluster resources)" `
                "no|Keep it running"
        } elseif ($NEW_SCOPE -eq "frontend" -and $BE_EXISTS) {
            Prompt-Choice "CLEANUP_BACKEND" "Backend is currently deployed. Remove it?" `
                "yes|Remove backend pods and service" `
                "no|Keep it running"
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Wizard Step 3 — AI Configuration (create / BYO / mock)
# ═══════════════════════════════════════════════════════════════════════════

function Wizard-AI {
    if ((Get-Val "DEPLOY_SCOPE") -eq "frontend") { return }

    Show-Section "`u{2462} AI Configuration" "How to connect to Microsoft Foundry for the chat backend."

    $PREV_AI = Get-Val "PREV_AI_MODE"

    Prompt-Choice "AI_MODE" "AI backend" `
        "create|Create new `u{2014} provision MS Foundry hub, project, and model" `
        "byo|Bring your own `u{2014} use an existing MS Foundry project and agent" `
        "mock|Mock mode `u{2014} no AI, use dummy responses for testing"

    $MODE = Get-Val "AI_MODE"

    # Detect AI mode downgrade — offer to clean up provisioned resources
    if (-not $AUTO_YES -and $PREV_AI -eq "create" -and $MODE -ne "create") {
        Write-Host ""
        Write-Host "  ${YELLOW}`u{26A0} You previously provisioned MS Foundry resources (hub, project, model).${NC}"
        Write-Host "  ${DIM}These may still incur charges from the model deployment TPM allocation.${NC}"
        Write-Host ""
        Prompt-Choice "CLEANUP_AI" "What to do with existing AI resources?" `
            "keep|Keep them `u{2014} I might switch back later" `
            "delete|Delete AI hub, project, and model deployment"
    }

    if ($MODE -eq "mock") {
        Save-Val "DATASOURCES" "mock"
        return
    }

    switch ($MODE) {
        "create" { Wizard-AICreate }
        "byo"    { Wizard-AIByo }
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Wizard Step 3a — AI Create (provision new MS Foundry hub + model)
# ═══════════════════════════════════════════════════════════════════════════

function Wizard-AICreate {
    Write-Host "  ${DIM}We'll create an MS Foundry hub + project and deploy a model.${NC}"
    Write-Host "  ${DIM}An agent will be created automatically after provisioning.${NC}"
    Write-Host ""

    $LOCATION = Get-Val "AZURE_LOCATION"

    # ── Fetch available models in background while user picks ───
    $ALL_MODELS_FILE = Join-Path $env:TEMP "azd-models-$(Get-Random).txt"
    $modelJob = $null
    if ($LOCATION) {
        $modelJob = Start-Job -ScriptBlock {
            param($loc, $outFile)
            try {
                $raw = & az cognitiveservices model list --location $loc `
                    --query "[?model.format=='OpenAI'].{name:model.name, ver:model.version}" `
                    -o tsv 2>$null
                $seen = @{}
                $skip = 'tts|transcribe|audio|embedding|dall-e|whisper|davinci|babbage|curie|ada|realtime|diarize|image|instruct|turbo-16k|codex|sora|oss|document|model-router|35-turbo'
                $results = @()
                foreach ($line in $raw) {
                    if (-not $line) { continue }
                    $parts = $line -split "`t"
                    if ($parts.Count -lt 2) { continue }
                    $name = $parts[0]; $ver = $parts[1]
                    if ($name -match $skip) { continue }
                    if ($seen.ContainsKey($name)) { continue }
                    $seen[$name] = $true
                    $results += "${name}|${ver}|OpenAI"
                }
                $results | Sort-Object | Set-Content $outFile
            } catch {}
        } -ArgumentList $LOCATION, $ALL_MODELS_FILE
    }

    # ── Model selector — popular first, with expand + custom ──────
    $POP_M_V = @("gpt-4o-mini", "gpt-4o", "gpt-4.1-mini", "gpt-4.1", "gpt-4.1-nano")
    $POP_M_D = @(
        "gpt-4o-mini ${DIM}`u{2014} fast & cheap${NC} ${GREEN}(Recommended)${NC}"
        "gpt-4o ${DIM}`u{2014} powerful all-rounder${NC}"
        "gpt-4.1-mini ${DIM}`u{2014} latest mini model${NC}"
        "gpt-4.1 ${DIM}`u{2014} latest flagship${NC}"
        "gpt-4.1-nano ${DIM}`u{2014} smallest & fastest${NC}"
    )
    $POP_M_V += "__more__"; $POP_M_V += "__custom__"
    $POP_M_D += "${BOLD}More models...${NC} ${DIM}`u{2014} all models (DeepSeek, Phi, Llama, etc.)${NC}"
    $POP_M_D += "${BOLD}Custom...${NC} ${DIM}`u{2014} type a model name manually${NC}"

    Write-Host "  ${DIM}Which model to deploy in your MS Foundry project.${NC}"
    while ($true) {
        Prompt-Select "AI_MODEL_NAME" "Model to deploy" $POP_M_V $POP_M_D "" "gpt-4o-mini"
        $PICKED = Get-Val "AI_MODEL_NAME"

        if ($PICKED -eq "__back__") {
            Save-Val "AI_MODEL_NAME" ""; continue
        } elseif ($PICKED -eq "__more__") {
            Save-Val "AI_MODEL_NAME" ""
            if ($modelJob -and $modelJob.State -eq "Running") {
                Write-Host -NoNewline "  ${DIM}Loading models...${NC}`r"
                Wait-Job $modelJob -Timeout 30 | Out-Null
                Write-Host -NoNewline "                        `r"
            }
            $ALL_M_V = @(); $ALL_M_D = @()
            if (Test-Path $ALL_MODELS_FILE) {
                foreach ($mline in (Get-Content $ALL_MODELS_FILE)) {
                    $mp = $mline -split '\|'
                    if ($mp.Count -lt 2 -or -not $mp[0]) { continue }
                    $ALL_M_V += $mp[0]
                    $tag = ""; if ($mp.Count -ge 3 -and $mp[2] -ne "OpenAI") { $tag = " ${DIM}[$($mp[2])]${NC}" }
                    if ($mp[0] -eq "gpt-4o-mini") {
                        $ALL_M_D += "$($mp[0]) ${DIM}`u{2014} v$($mp[1])${NC}${tag} ${GREEN}(Recommended)${NC}"
                    } else {
                        $ALL_M_D += "$($mp[0]) ${DIM}`u{2014} v$($mp[1])${NC}${tag}"
                    }
                }
            }
            if ($ALL_M_V.Count -gt 0) {
                Prompt-Select "AI_MODEL_NAME" "Model to deploy" $ALL_M_V $ALL_M_D "" "gpt-4o-mini"
                if ((Get-Val "AI_MODEL_NAME") -eq "__back__") { Save-Val "AI_MODEL_NAME" ""; continue }
            } else {
                Prompt-Val "AI_MODEL_NAME" "Model name" "gpt-4o-mini" "" `
                    "Could not fetch models. Enter a model name."
            }
            break
        } elseif ($PICKED -eq "__custom__") {
            Save-Val "AI_MODEL_NAME" ""
            Prompt-Val "AI_MODEL_NAME" "Model name" "gpt-4o-mini" "--required" `
                "Enter the exact model name (e.g. gpt-4o-mini, DeepSeek-R1, Phi-4)"
            break
        } else {
            break
        }
    }

    # ── Auto-set version from fetched data ────────────────────────
    if (Test-Path $ALL_MODELS_FILE) {
        $SELECTED = Get-Val "AI_MODEL_NAME"
        $verLine = Get-Content $ALL_MODELS_FILE | Where-Object { $_ -match "^${SELECTED}\|" } | Select-Object -First 1
        if ($verLine) {
            $VER = ($verLine -split '\|')[1]
            if ($VER) { Save-Val "AI_MODEL_VERSION" $VER }
        }
    }
    if ($modelJob) {
        Stop-Job $modelJob -ErrorAction SilentlyContinue
        Remove-Job $modelJob -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $ALL_MODELS_FILE -Force -ErrorAction SilentlyContinue

    # ── Version — show if auto-detected, prompt if not ──────────
    $CUR_VER = Get-Val "AI_MODEL_VERSION"
    if ($CUR_VER) {
        Write-Host "  ${DIM}Model version:${NC} ${CYAN}${CUR_VER}${NC}"
    } else {
        Prompt-Val "AI_MODEL_VERSION" "Model version" "2024-07-18" "--required" `
            "Model version `u{2014} check Microsoft Foundry for available versions"
    }

    # ── Capacity (TPM) ────────────────────────────────────────────
    $CAP_V = @("1", "5", "10", "30")
    $CAP_D = @(
        " 1K TPM ${DIM}`u{2014} minimal dev/test (cheapest)${NC}"
        " 5K TPM ${DIM}`u{2014} light usage${NC}"
        "10K TPM ${DIM}`u{2014} moderate usage${NC}"
        "30K TPM ${DIM}`u{2014} production workload${NC}"
    )
    Prompt-Select "AI_MODEL_CAPACITY" "Model capacity" $CAP_V $CAP_D `
        "Tokens-per-minute limit (in thousands). Start low, scale up later." "1"

    # ── Validate quota before proceeding ──────────────────────────
    $Q_LOC = Get-Val "AZURE_LOCATION"
    $Q_MODEL = Get-Val "AI_MODEL_NAME"
    $Q_CAP = Get-Val "AI_MODEL_CAPACITY"
    if ($Q_LOC -and $Q_MODEL -and $Q_CAP) {
        Check-ModelQuota $Q_LOC $Q_MODEL "GlobalStandard" $Q_CAP "AI_MODEL_CAPACITY"
    }

    Save-Val "DATASOURCES" "api"
}

# ═══════════════════════════════════════════════════════════════════════════
# Wizard Step 3b — AI Bring-Your-Own (existing MS Foundry project + agent)
# ═══════════════════════════════════════════════════════════════════════════

function Wizard-AIByo {
    Write-Host "  ${DIM}Connect to an existing MS Foundry project. We'll assign RBAC roles${NC}"
    Write-Host "  ${DIM}so the workload identity can call the AI API (even cross-RG).${NC}"
    Write-Host ""

    Prompt-Val "AI_PROJECT_ENDPOINT" "MS Foundry project endpoint" "" "--required" `
        "Find this in Azure Portal `u{2192} MS Foundry `u{2192} Project `u{2192} Settings `u{2192} Endpoint"
    Prompt-Val "AI_AGENT_ID" "Agent ID (name:version)" "" "--required" `
        "The agent name and version, e.g. 'my-agent:1' `u{2014} find in MS Foundry `u{2192} Agents"

    # Auto-detect AI_RESOURCE_GROUP from the endpoint's account name
    if (-not (Get-Val "AI_RESOURCE_GROUP")) {
        $ENDPOINT = Get-Val "AI_PROJECT_ENDPOINT"
        if ($ENDPOINT -match 'https://([^.]+)\.') {
            $ACCT = $Matches[1]
            Write-Host -NoNewline "  ${DIM}Auto-detecting resource group for ${ACCT}...${NC}"
            $RG = az cognitiveservices account list `
                --query "[?name=='$ACCT'].resourceGroup" -o tsv 2>$null
            if ($RG) {
                Write-Host " ${GREEN}found: ${RG}${NC}"
                Save-Val "AI_RESOURCE_GROUP" "$RG"
            } else {
                Write-Host " ${YELLOW}not found in current subscription${NC}"
                Prompt-Val "AI_RESOURCE_GROUP" "AI resource group" "" "--required" `
                    "The resource group containing the MS Foundry account (needed for RBAC)"
            }
        } else {
            Prompt-Val "AI_RESOURCE_GROUP" "AI resource group" "" "--required" `
                "The resource group containing the MS Foundry account (needed for RBAC)"
        }
    }
    Save-Val "DATASOURCES" "api"
}

# ═══════════════════════════════════════════════════════════════════════════
# Wizard Step 4 — Backend Settings (streaming, CORS, admin routes)
# ═══════════════════════════════════════════════════════════════════════════

function Wizard-Backend {
    $SCOPE = Get-Val "DEPLOY_SCOPE"
    if ($SCOPE -eq "frontend") { return }

    Show-Section "`u{2463} Backend Settings" "Runtime configuration for the backend server."

    Prompt-Choice "STREAMING" "Response streaming" `
        "enabled|Stream AI responses in real-time (better UX)" `
        "disabled|Wait for full response before displaying"

    $SCOPE = Get-Val "DEPLOY_SCOPE"
    $CORS_AUTO_DESC = "Auto-detect from ingress IP"
    if ($SCOPE -eq "all") { $CORS_AUTO_DESC = "Auto-detect from frontend ingress URL" }
    if ($SCOPE -eq "backend") { $CORS_AUTO_DESC = "Allow any origin (set manually later)" }

    Prompt-Choice "CORS_ORIGINS" "CORS (Cross-Origin Resource Sharing)" `
        "auto|${CORS_AUTO_DESC}" `
        "*|Allow all origins (open, good for dev)" `
        "custom|Specify a custom origin URL"

    $CORS_VAL = Get-Val "CORS_ORIGINS"
    if ($CORS_VAL -eq "custom") {
        Save-Val "CORS_ORIGINS" ""
        Prompt-Val "CORS_ORIGINS" "Allowed origin URL" "" "--required" `
            "The frontend URL allowed to call the backend (e.g. https://myapp.example.com)"
    }

    Prompt-Choice "ENABLE_ADMIN_ROUTES" "Admin API routes" `
        "false|Disabled `u{2014} production safe" `
        "true|Enabled `u{2014} allows runtime config toggle via /api/admin"
}

# ═══════════════════════════════════════════════════════════════════════════
# Validation — ensure all required config values are set
# ═══════════════════════════════════════════════════════════════════════════

function Validate-Config {
    $ERRORS = ""; $MISSING = $false

    function _require { param([string]$Key, [string]$Desc)
        if (-not (Get-Val $Key)) {
            $script:ERRORS += "`n  `u{274C} $Key `u{2014} $Desc"; $script:MISSING = $true
        }
    }

    _require "ARC_PREFIX"  "Resource prefix"
    _require "NODE_COUNT"  "AKS node count"
    _require "VM_SIZE"     "AKS VM size"
    _require "DEPLOY_MODE" "Deploy mode"

    $DM = Get-Val "DEPLOY_MODE"
    if ($DM -and $DM -ne "k8s" -and $DM -ne "containerapp") {
        $ERRORS += "`n  `u{274C} DEPLOY_MODE must be 'k8s' or 'containerapp'"; $MISSING = $true
    }

    $DS = Get-Val "DEPLOY_SCOPE"
    if ($DS -eq "frontend" -and -not (Get-Val "VITE_API_URL")) {
        $ERRORS += "`n  `u{274C} VITE_API_URL required when DEPLOY_SCOPE=frontend"; $MISSING = $true
    }

    if ($MISSING) {
        Write-Host ""; Write-Host $ERRORS; Write-Host ""
        Write-Host "  Fix the above and re-run, or set values with: azd env set <KEY> <VALUE>"
        exit 1
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Summary — export values, display config, and ask for confirmation
# ═══════════════════════════════════════════════════════════════════════════

function Show-SummaryAndConfirm {
    $env:ARC_PREFIX          = Get-Val "ARC_PREFIX"
    $env:AZURE_LOCATION      = Get-Val "AZURE_LOCATION"
    $env:DEPLOY_MODE         = Get-Val "DEPLOY_MODE"
    $env:DEPLOY_SCOPE        = Get-Val "DEPLOY_SCOPE"
    $env:VITE_API_URL        = Get-Val "VITE_API_URL"
    $env:NODE_COUNT          = Get-Val "NODE_COUNT"
    $env:VM_SIZE             = Get-Val "VM_SIZE"
    $env:DATASOURCES         = Get-Val "DATASOURCES"
    $env:STREAMING           = Get-Val "STREAMING"
    $env:ENABLE_ADMIN_ROUTES = Get-Val "ENABLE_ADMIN_ROUTES"
    $env:CORS_ORIGINS        = Get-Val "CORS_ORIGINS"
    $env:AI_MODE             = Get-Val "AI_MODE"
    $env:AI_MODEL_NAME       = Get-Val "AI_MODEL_NAME"
    $env:AI_MODEL_VERSION    = Get-Val "AI_MODEL_VERSION"
    $env:AI_MODEL_CAPACITY   = Get-Val "AI_MODEL_CAPACITY"
    $env:AI_PROJECT_ENDPOINT = Get-Val "AI_PROJECT_ENDPOINT"
    $env:AI_AGENT_ID         = Get-Val "AI_AGENT_ID"

    Write-Host ""
    Write-Host -NoNewline "  ${DIM}Preparing summary...${NC}"

    . "$INFRA_DIR\naming.ps1" 2>$null

    Write-Host -NoNewline "`r                          `r"
    Print-ConfigSummary "full" "Provision"

    if (-not $AUTO_YES) {
        Write-Host ""
        $CONFIRM = Read-Host "  Continue with deployment? [Y/n]"
        if ($CONFIRM -match "^[Nn]$") {
            Write-Host ""; Write-Host "  `u{2501}`u{2501}`u{2501} Cancelled `u{2501}`u{2501}`u{2501}"
            Write-Host "  Adjust with 'azd env set <KEY> <VALUE>' and re-run 'azd up'."; Write-Host ""
            exit 1
        }

        Write-Host ""
        $AUTO_DEPLOY = Read-Host "  Auto-deploy after provision (skip deploy confirmation)? [Y/n]"
        if ($AUTO_DEPLOY -notmatch "^[Nn]$") {
            $flagName = if ($env:AZURE_ENV_NAME) { $env:AZURE_ENV_NAME } else { "default" }
            $flagPath = Join-Path $env:TEMP ".azd-auto-deploy-$flagName"
            New-Item -ItemType File -Path $flagPath -Force | Out-Null
        }
    }

    # Persist all bicep parameters via azd env set as safety net
    foreach ($k in @("ARC_PREFIX", "AZURE_LOCATION", "NODE_COUNT", "VM_SIZE",
        "AI_PROJECT_ENDPOINT", "AI_MODE", "AI_MODEL_NAME", "AI_MODEL_VERSION",
        "AI_MODEL_CAPACITY", "DEPLOY_SCOPE", "ARC_NAMESPACE")) {
        $v = Get-Val $k
        if ($v) { try { azd env set $k $v 2>$null } catch {} }
    }
}

# ═══════════════════════════════════════════════════════════════════════════
# Recipes — predefined configurations for quick deploy
# ═══════════════════════════════════════════════════════════════════════════

function Apply-Recipe {
    $RECIPE = Get-Val "RECIPE"
    if (-not $RECIPE) { return $false }

    Write-Host -NoNewline "  ${DIM}Applying recipe '${RECIPE}'...${NC}"

    switch ($RECIPE) {
        "all" {
            Save-Val "DEPLOY_SCOPE" "all"
            Save-Val "AI_MODE" "create"
            Save-Val "DATASOURCES" "api"
            Save-Val "AI_MODEL_NAME" "gpt-4o-mini"
            Save-Val "AI_MODEL_VERSION" "2024-07-18"
            Save-Val "AI_MODEL_CAPACITY" "1"
            Save-Val "STREAMING" "enabled"
            Save-Val "CORS_ORIGINS" "auto"
            Save-Val "ENABLE_ADMIN_ROUTES" "false"
            Save-Val "VM_SIZE" "Standard_D2s_v3"
            Save-Val "NODE_COUNT" "2"
        }
        "dev" {
            Save-Val "DEPLOY_SCOPE" "all"
            Save-Val "AI_MODE" "mock"
            Save-Val "DATASOURCES" "mock"
            Save-Val "STREAMING" "enabled"
            Save-Val "CORS_ORIGINS" "*"
            Save-Val "ENABLE_ADMIN_ROUTES" "true"
            Save-Val "VM_SIZE" "Standard_B2s"
            Save-Val "NODE_COUNT" "2"
        }
        default {
            Write-Host ""
            Write-Host "  ${RED}Unknown recipe: ${RECIPE}${NC}"
            Write-Host "  ${DIM}Available: all, dev${NC}"
            return $false
        }
    }

    # Prefix is always the env name
    $ENV_NAME = Get-Val "AZURE_ENV_NAME"
    if ($ENV_NAME) { Save-Val "ARC_PREFIX" "$ENV_NAME" }

    Save-Val "DEPLOY_MODE" "k8s"

    Write-Host "`r  ${GREEN}`u{2705} Recipe '${RECIPE}' applied${NC}              "
    return $true
}

# ═══════════════════════════════════════════════════════════════════════════
# Main Flow
# ═══════════════════════════════════════════════════════════════════════════

# Always detect existing infrastructure + runtime state FIRST
Apply-Defaults

# ── Path A: Recipe on FIRST RUN only ────────────────────────────────
if ((Get-Val "WIZARD_DONE") -ne "true") {
    $recipeResult = Apply-Recipe
    if ($recipeResult) {
        Save-Val "WIZARD_DONE" "true"
        Validate-Config
        Show-SummaryAndConfirm
        exit 0
    }
}

# ── Path B: CI mode — apply defaults silently ───────────────────────────
if ($AUTO_YES) {
    Validate-Config
    Show-SummaryAndConfirm
    exit 0
}

# ── Path C: Provisioned + deployed — redeploy or modify? ────────────────
if ((Get-Val "PROVISION_DONE") -eq "true" -and (Get-Val "DEPLOY_DONE") -eq "true") {
    Write-Host ""
    Write-Host "  ${BOLD}${MAGENTA}`u{1F680} sovereign-chat-experience-starter${NC}"
    Write-Host ""

    $_P = Get-Val "ARC_PREFIX"
    $_S = Get-Val "DEPLOY_SCOPE"
    $_A = Get-Val "AI_MODE"
    Write-Host "  ${DIM}Current: ${_P} | scope=${_S} | ai=${_A}${NC}"
    Write-Host ""
    Write-Host "    ${BOLD}1)${NC} ${GREEN}Deploy${NC} ${DIM}`u{2014} redeploy with current settings${NC}"
    Write-Host "    ${BOLD}2)${NC} ${CYAN}Modify${NC} ${DIM}`u{2014} change scope, AI mode, backend settings${NC}"
    Write-Host ""
    Write-Host -NoNewline "  Choice ${DIM}[1]${NC}: ${CYAN}"
    $REDEPLOY_CHOICE = Read-Host
    Write-Host -NoNewline "${NC}"

    switch ($(if ($REDEPLOY_CHOICE) { $REDEPLOY_CHOICE } else { "1" })) {
        { $_ -eq "1" } {
            Validate-Config
            Show-SummaryAndConfirm
            exit 0
        }
        { $_ -eq "2" -or $_ -eq "modify" } {
            Wizard-Infrastructure
            Wizard-Scope
            Wizard-AI
            Wizard-Backend
            Save-Val "WIZARD_DONE" "true"
            Validate-Config
            Show-SummaryAndConfirm
            exit 0
        }
        default {
            Validate-Config
            Show-SummaryAndConfirm
            exit 0
        }
    }
}

# ── Path D: Provisioned but not deployed — recipe or configure ──────────
if ((Get-Val "PROVISION_DONE") -eq "true") {
    Write-Host ""
    Write-Host "  ${BOLD}${MAGENTA}`u{1F680} sovereign-chat-experience-starter `u{2014} Configure Deployment${NC}"
    Write-Host "  ${DIM}Infrastructure is ready. Choose how to deploy.${NC}"
    Write-Host ""
    Write-Host "    ${BOLD}1)${NC} ${GREEN}all${NC} ${DIM}`u{2014} Full stack + MS Foundry (gpt-4o-mini)${NC}"
    Write-Host "    ${BOLD}2)${NC} ${CYAN}dev${NC} ${DIM}`u{2014} Full stack + mock AI, admin enabled${NC}"
    Write-Host "    ${BOLD}3)${NC} ${YELLOW}custom${NC} ${DIM}`u{2014} Configure each setting manually${NC}"
    Write-Host ""
    Write-Host -NoNewline "  Choice ${DIM}[1]${NC}: ${CYAN}"
    $DEPLOY_RECIPE = Read-Host
    Write-Host -NoNewline "${NC}"

    switch ($(if ($DEPLOY_RECIPE) { $DEPLOY_RECIPE } else { "1" })) {
        "1" { Save-Val "RECIPE" "all"; Apply-Recipe | Out-Null }
        "2" { Save-Val "RECIPE" "dev"; Apply-Recipe | Out-Null }
        { $_ -eq "3" -or $_ -eq "custom" } {
            Wizard-Infrastructure
            Wizard-Scope
            Wizard-AI
            Wizard-Backend
        }
        default { Save-Val "RECIPE" "all"; Apply-Recipe | Out-Null }
    }

    Save-Val "WIZARD_DONE" "true"
    Validate-Config
    Show-SummaryAndConfirm
    exit 0
}

# ── Path E: First run — recipe picker or full wizard ───────────────────
Write-Host ""
Write-Host "  ${BOLD}${MAGENTA}`u{1F680} sovereign-chat-experience-starter `u{2014} Setup${NC}"
Write-Host ""
Write-Host "  ${DIM}Choose a deployment recipe or configure manually.${NC}"
Write-Host ""
Write-Host "    ${BOLD}1)${NC} ${GREEN}all${NC} ${DIM}`u{2014} Full stack + MS Foundry (gpt-4o-mini) `u{2014} recommended${NC}"
Write-Host "    ${BOLD}2)${NC} ${CYAN}dev${NC} ${DIM}`u{2014} Full stack + mock AI, cheapest VM, admin enabled${NC}"
Write-Host "    ${BOLD}3)${NC} ${YELLOW}custom${NC} ${DIM}`u{2014} Walk through the full setup wizard${NC}"
Write-Host ""
Write-Host -NoNewline "  Choice ${DIM}[1]${NC}: ${CYAN}"
$RECIPE_CHOICE = Read-Host
Write-Host -NoNewline "${NC}"

switch ($(if ($RECIPE_CHOICE) { $RECIPE_CHOICE } else { "1" })) {
    "1" { Save-Val "RECIPE" "all"; Apply-Recipe | Out-Null }
    "2" { Save-Val "RECIPE" "dev"; Apply-Recipe | Out-Null }
    { $_ -eq "3" -or $_ -eq "custom" } {
        Wizard-Subscription
        Wizard-Infrastructure
        Wizard-Scope
        Wizard-AI
        Wizard-Backend
    }
    default {
        Write-Host "  ${YELLOW}Invalid choice. Using 'all' recipe.${NC}"
        Save-Val "RECIPE" "all"; Apply-Recipe | Out-Null
    }
}

Save-Val "WIZARD_DONE" "true"
Validate-Config
Show-SummaryAndConfirm
