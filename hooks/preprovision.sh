#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  preprovision.sh — Interactive Setup Wizard & Validation                ║
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
# ║                                                                         ║
# ║  Dependencies:                                                          ║
# ║    • infra/validate.sh  — require_cli, validate_or_exit                 ║
# ║    • infra/prompts.sh   — section, prompt_select, prompt_val, etc.      ║
# ║    • infra/naming.sh    — resource-name helpers (loaded at summary)     ║
# ║                                                                         ║
# ║  Modes:                                                                 ║
# ║    Interactive (default) — shows all config steps, arrow-key menus      ║
# ║    CI  (-y / --yes)      — uses saved values + defaults, no prompts     ║
# ║                                                                         ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

set -e

# ═══════════════════════════════════════════════════════════════════════════
# Dependencies & CLI Flags
# ═══════════════════════════════════════════════════════════════════════════

AUTO_YES="${AUTO_YES:-false}"
for arg in "$@"; do
    [[ "$arg" == "-y" || "$arg" == "--yes" ]] && AUTO_YES=true
done
# Auto-detect CI / non-interactive: if stdin is not a terminal, skip prompts
if [ ! -t 0 ]; then
    AUTO_YES=true
fi
export AUTO_YES

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "$SCRIPT_DIR/../infra" && pwd)"

source "$INFRA_DIR/validate.sh"
require_cli "az"
require_cli "azd"
validate_or_exit

source "$INFRA_DIR/prompts.sh"
source "$INFRA_DIR/defaults.sh"

# ═══════════════════════════════════════════════════════════════════════════
# Wizard Step ⓪  — Azure Subscription
# ═══════════════════════════════════════════════════════════════════════════

wizard_subscription() {
    [ -n "$(get_val "AZURE_SUBSCRIPTION_ID")" ] && return

    section "⓪ Azure Subscription" "Select which Azure subscription to deploy into."

    # Fetch all enabled subscriptions and track which is the az default
    local SUB_IDS=() SUB_NAMES=() SUB_DISPLAY=() SUB_DEFAULT_IDX=0
    echo -ne "  ${DIM}Loading subscriptions...${NC}\r"
    while IFS=$'\t' read -r id name isDef; do
        [ -z "$id" ] && continue
        SUB_IDS+=("$id"); SUB_NAMES+=("$name")
        [ "$isDef" = "true" ] && SUB_DEFAULT_IDX=${#SUB_IDS[@]}
    done < <(az account list --query "[?state=='Enabled'].[id, name, isDefault]" -o tsv 2>/dev/null)
    echo -ne "                                    \r"

    if [ "${#SUB_IDS[@]}" -eq 0 ]; then
        echo -e "  ${RED}No subscriptions found. Run 'az login' first.${NC}"; exit 1
    elif [ "${#SUB_IDS[@]}" -eq 1 ]; then
        save_val "AZURE_SUBSCRIPTION_ID" "${SUB_IDS[0]}"
        echo -e "  Using subscription: ${CYAN}${SUB_NAMES[0]}${NC}"; echo ""
    else
        # Build display labels with truncated IDs and a tag for the az default
        SUB_DISPLAY=()
        for i in "${!SUB_IDS[@]}"; do
            SHORT_ID="${SUB_IDS[$i]:0:8}..."
            TAG=""; [ "$((i+1))" -eq "$SUB_DEFAULT_IDX" ] && TAG=" ${DIM}← az default${NC}"
            SUB_DISPLAY+=("${SUB_NAMES[$i]} ${DIM}(${SHORT_ID})${NC}${TAG}")
        done
        local DEF_SUB=""
        [ "$SUB_DEFAULT_IDX" -gt 0 ] && DEF_SUB="${SUB_IDS[$((SUB_DEFAULT_IDX-1))]}"
        prompt_select "AZURE_SUBSCRIPTION_ID" "Select subscription" SUB_IDS SUB_DISPLAY "" "$DEF_SUB"
    fi

    # Activate the selected subscription for subsequent az commands
    local SEL; SEL=$(get_val "AZURE_SUBSCRIPTION_ID")
    [ -n "$SEL" ] && az account set --subscription "$SEL" 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════════════════
# Wizard Step ①  — Infrastructure (AKS cluster, prefix, VM size)
# ═══════════════════════════════════════════════════════════════════════════

wizard_infrastructure() {
    section "① Infrastructure" "Azure resources that will be created for your deployment."

    # If already provisioned — show locked values, no selectors
    if [ "$(get_val "PROVISION_DONE")" = "true" ]; then
        local P; P=$(get_val "ARC_PREFIX")
        local L; L=$(get_val "AZURE_LOCATION")
        local N; N=$(get_val "NODE_COUNT")
        local V; V=$(get_val "VM_SIZE")
        echo -e "  ${DIM}🔒 Infrastructure is locked after first provision.${NC}"
        echo -e "  ${DIM}   To change, run 'azd down' first, then 'azd up'.${NC}"
        echo ""
        echo -e "  Prefix:     ${CYAN}${P}${NC}"
        echo -e "  Region:     ${CYAN}${L}${NC}"
        echo -e "  Nodes:      ${CYAN}${N}${NC}"
        echo -e "  VM Size:    ${CYAN}${V}${NC}"
        echo ""
        set_default "DEPLOY_MODE" "k8s"
        return
    fi

    # Prefix is always derived from azd env name — never prompted
    local ENV_NAME; ENV_NAME=$(get_val "AZURE_ENV_NAME")
    save_val "ARC_PREFIX" "$ENV_NAME"
    echo -e "  ${DIM}Prefix:${NC} ${CYAN}${ENV_NAME}${NC} ${DIM}(from azd env name)${NC}"

    # ── Auto-detect existing infrastructure from Azure ──────────────
    local PREFIX; PREFIX=$(get_val "ARC_PREFIX")
    local RG_NAME="${PREFIX}-rg"
    if [ -n "$PREFIX" ] && [ "$(get_val "PROVISION_DONE")" != "true" ]; then
        # Check if RG already exists — if so, detect existing config
        if az group show --name "$RG_NAME" --output none 2>/dev/null; then
            echo -e "  ${GREEN}✓ Found existing resource group: ${RG_NAME}${NC}"
            echo -ne "  ${DIM}Detecting existing infrastructure...${NC}\r"

            # Detect AKS cluster
            local AKS_TSV
            AKS_TSV=$(az aks show --name "${PREFIX}-cluster" --resource-group "$RG_NAME" \
                --query "[agentPoolProfiles[0].vmSize, agentPoolProfiles[0].count, location]" \
                -o tsv 2>/dev/null || echo "")
            if [ -n "$AKS_TSV" ]; then
                local DET_VM DET_NODES DET_LOC
                IFS=$'\t' read -r DET_VM DET_NODES DET_LOC <<< "$AKS_TSV"
                [ -n "$DET_VM" ] && save_val "VM_SIZE" "$DET_VM"
                [ -n "$DET_NODES" ] && save_val "NODE_COUNT" "$DET_NODES"
                [ -n "$DET_LOC" ] && save_val "AZURE_LOCATION" "$DET_LOC"
                echo -e "  ${GREEN}✓ AKS cluster:${NC} ${DET_NODES} x ${DET_VM} in ${DET_LOC}"
            fi

            # Detect AI hub
            local AI_HUB_NAME="${PREFIX}-ai-hub"
            local AI_INFO
            AI_INFO=$(az cognitiveservices account show --name "$AI_HUB_NAME" --resource-group "$RG_NAME" \
                --query "{endpoint:properties.endpoint}" -o json 2>/dev/null || echo "")
            if [ -n "$AI_INFO" ] && [ "$AI_INFO" != "" ]; then
                save_val "AI_MODE" "create"
                save_val "PREV_AI_MODE" "create"
                echo -e "  ${GREEN}✓ MS Foundry hub:${NC} ${AI_HUB_NAME}"

                # Detect model deployment
                local DEPLOY_TSV
                DEPLOY_TSV=$(az cognitiveservices account deployment list \
                    --name "$AI_HUB_NAME" --resource-group "$RG_NAME" \
                    --query "[0].[properties.model.name, properties.model.version, sku.capacity]" \
                    -o tsv 2>/dev/null || echo "")
                if [ -n "$DEPLOY_TSV" ]; then
                    local DET_MODEL DET_VER DET_CAP
                    IFS=$'\t' read -r DET_MODEL DET_VER DET_CAP <<< "$DEPLOY_TSV"
                    [ -n "$DET_MODEL" ] && [ "$DET_MODEL" != "None" ] && save_val "AI_MODEL_NAME" "$DET_MODEL"
                    [ -n "$DET_VER" ] && [ "$DET_VER" != "None" ] && save_val "AI_MODEL_VERSION" "$DET_VER"
                    [ -n "$DET_CAP" ] && [ "$DET_CAP" != "None" ] && save_val "AI_MODEL_CAPACITY" "$DET_CAP"
                    echo -e "  ${GREEN}✓ Model deployment:${NC} ${DET_MODEL} v${DET_VER} (${DET_CAP}K TPM)"
                fi

                # Detect project endpoint
                local PROJECT_NAME="${PREFIX}-ai-project"
                local PROJ_INFO
                PROJ_INFO=$(az cognitiveservices account show \
                    --name "${AI_HUB_NAME}/${PROJECT_NAME}" --resource-group "$RG_NAME" \
                    -o json 2>/dev/null || echo "")
                if [ -n "$PROJ_INFO" ] && [ "$PROJ_INFO" != "" ]; then
                    save_val "AI_PROJECT_ENDPOINT" "https://${AI_HUB_NAME}.cognitiveservices.azure.com/api/projects/${PROJECT_NAME}"
                    echo -e "  ${GREEN}✓ AI project:${NC} ${PROJECT_NAME}"
                fi
            fi

            # Detect workload identity
            local WI_NAME="${PREFIX}-backend-id"
            local WI_TSV
            WI_TSV=$(az identity show --name "$WI_NAME" --resource-group "$RG_NAME" \
                --query "[clientId, principalId]" -o tsv 2>/dev/null || echo "")
            if [ -n "$WI_TSV" ]; then
                local DET_CID DET_PID
                IFS=$'\t' read -r DET_CID DET_PID <<< "$WI_TSV"
                [ -n "$DET_CID" ] && save_val "AZURE_WI_CLIENT_ID" "$DET_CID"
                [ -n "$DET_PID" ] && save_val "AZURE_WI_PRINCIPAL_ID" "$DET_PID"
                echo -e "  ${GREEN}✓ Workload Identity:${NC} ${WI_NAME}"
            fi

            save_val "PROVISION_DONE" "true"
            echo ""
        fi
    fi

    set_default "DEPLOY_MODE" "k8s"

    prompt_val "NODE_COUNT" "AKS node count" "2" "" \
        "Number of nodes in the AKS cluster (2 for dev, 3+ for prod)"

    # ── VM size selector — popular first, with expand + custom ────
    local POP_VM_V=("Standard_B2s" "Standard_D2s_v3" "Standard_D4s_v6" "Standard_D2s_v5" "Standard_D4s_v5" "Standard_B4ms")
    local POP_VM_D=(
        "Standard_B2s ${DIM}— 2 vCPU, 4 GB (burstable, cheapest)${NC}"
        "Standard_D2s_v3 ${DIM}— 2 vCPU, 8 GB${NC} ${GREEN}(Recommended)${NC}"
        "Standard_D4s_v6 ${DIM}— 4 vCPU, 16 GB (prod)${NC}"
        "Standard_D2s_v5 ${DIM}— 2 vCPU, 8 GB (prev gen)${NC}"
        "Standard_D4s_v5 ${DIM}— 4 vCPU, 16 GB (prev gen)${NC}"
        "Standard_B4ms ${DIM}— 4 vCPU, 16 GB (burstable)${NC}"
    )
    POP_VM_V+=("__more__" "__custom__")
    POP_VM_D+=("${BOLD}More sizes...${NC} ${DIM}— additional VM options${NC}" "${BOLD}Custom...${NC} ${DIM}— type a VM size manually${NC}")

    echo -e "  ${DIM}VM size for AKS nodes.${NC}"
    while true; do
        prompt_select "VM_SIZE" "AKS VM size" POP_VM_V POP_VM_D \
            "" "Standard_D2s_v3"
        local VM_PICKED; VM_PICKED=$(get_val "VM_SIZE")

        if [ "$VM_PICKED" = "__back__" ]; then
            save_val "VM_SIZE" ""; continue
        elif [ "$VM_PICKED" = "__more__" ]; then
            save_val "VM_SIZE" ""
            local EXT_V=("Standard_B2ms" "Standard_B2s" "Standard_B4ms"
                "Standard_D2s_v3" "Standard_D2ds_v5" "Standard_D2s_v5" "Standard_D2s_v6"
                "Standard_D2as_v5" "Standard_D4s_v3" "Standard_D4s_v5" "Standard_D4s_v6"
                "Standard_D4as_v5" "Standard_D8s_v3" "Standard_D8s_v5"
                "Standard_E2s_v5" "Standard_E4s_v5" "Standard_E8s_v5"
                "Standard_F2s_v2" "Standard_F4s_v2" "Standard_F8s_v2")
            local EXT_D=(
                "Standard_B2ms ${DIM}— 2 vCPU, 8 GB (burstable)${NC}"
                "Standard_B2s ${DIM}— 2 vCPU, 4 GB (burstable, cheapest)${NC}"
                "Standard_B4ms ${DIM}— 4 vCPU, 16 GB (burstable)${NC}"
                "Standard_D2s_v3 ${DIM}— 2 vCPU, 8 GB${NC} ${GREEN}(Recommended)${NC}"
                "Standard_D2ds_v5 ${DIM}— 2 vCPU, 8 GB (local SSD)${NC}"
                "Standard_D2s_v5 ${DIM}— 2 vCPU, 8 GB${NC}"
                "Standard_D2s_v6 ${DIM}— 2 vCPU, 8 GB (newest)${NC}"
                "Standard_D2as_v5 ${DIM}— 2 vCPU, 8 GB (AMD)${NC}"
                "Standard_D4s_v3 ${DIM}— 4 vCPU, 16 GB${NC}"
                "Standard_D4s_v5 ${DIM}— 4 vCPU, 16 GB${NC}"
                "Standard_D4s_v6 ${DIM}— 4 vCPU, 16 GB (newest)${NC}"
                "Standard_D4as_v5 ${DIM}— 4 vCPU, 16 GB (AMD)${NC}"
                "Standard_D8s_v3 ${DIM}— 8 vCPU, 32 GB${NC}"
                "Standard_D8s_v5 ${DIM}— 8 vCPU, 32 GB${NC}"
                "Standard_E2s_v5 ${DIM}— 2 vCPU, 16 GB (memory opt)${NC}"
                "Standard_E4s_v5 ${DIM}— 4 vCPU, 32 GB (memory opt)${NC}"
                "Standard_E8s_v5 ${DIM}— 8 vCPU, 64 GB (memory opt)${NC}"
                "Standard_F2s_v2 ${DIM}— 2 vCPU, 4 GB (compute opt)${NC}"
                "Standard_F4s_v2 ${DIM}— 4 vCPU, 8 GB (compute opt)${NC}"
                "Standard_F8s_v2 ${DIM}— 8 vCPU, 16 GB (compute opt)${NC}")
            prompt_select "VM_SIZE" "AKS VM size" EXT_V EXT_D "" "Standard_D2s_v3"
            [ "$(get_val "VM_SIZE")" = "__back__" ] && { save_val "VM_SIZE" ""; continue; }
            break
        elif [ "$VM_PICKED" = "__custom__" ]; then
            save_val "VM_SIZE" ""
            prompt_val "VM_SIZE" "VM size name" "Standard_D2s_v3" --required \
                "Enter the exact Azure VM size (e.g. Standard_D2s_v3, Standard_E4s_v5)"
            break
        else
            break
        fi
    done
}

# ═══════════════════════════════════════════════════════════════════════════
# Wizard Step ②  — Deploy Scope (full-stack, backend-only, frontend-only)
# ═══════════════════════════════════════════════════════════════════════════

wizard_scope() {
    section "② Deploy" "What and how to deploy."

    local PREV_SCOPE; PREV_SCOPE=$(get_val "PREV_DEPLOY_SCOPE")

    prompt_choice "DEPLOY_SCOPE" "What to deploy" \
        "all|Full stack — frontend + backend + ingress" \
        "backend|Backend only — API server and AI integration" \
        "frontend|Frontend only — connect to an existing backend"

    local NEW_SCOPE; NEW_SCOPE=$(get_val "DEPLOY_SCOPE")

    if [ "$(get_val "DEPLOY_SCOPE")" = "frontend" ]; then
        prompt_val "VITE_API_URL" "Backend API URL" "" --required \
            "The URL of your existing backend API (e.g. https://my-api.example.com/api)"
    else
        save_val "VITE_API_URL" ""
    fi

    # Detect scope narrowing — offer to clean up orphaned resources
    # Only prompt if the deployment actually exists in K8s
    if [ "$AUTO_YES" != "true" ] && [ -n "$PREV_SCOPE" ] && [ "$PREV_SCOPE" != "$NEW_SCOPE" ]; then
        local NS; NS=$(get_val "ARC_NAMESPACE")
        local PREFIX; PREFIX=$(get_val "ARC_PREFIX")
        local FE_EXISTS=false BE_EXISTS=false
        if command -v kubectl &>/dev/null && [ -n "$NS" ]; then
            kubectl get deployment "${PREFIX}-frontend" -n "$NS" --no-headers 2>/dev/null | grep -q . && FE_EXISTS=true
            kubectl get deployment "${PREFIX}-server" -n "$NS" --no-headers 2>/dev/null | grep -q . && BE_EXISTS=true
        fi

        if [ "$NEW_SCOPE" = "backend" ] && [ "$FE_EXISTS" = "true" ]; then
            prompt_choice "CLEANUP_FRONTEND" "Frontend is currently deployed. Remove it?" \
                "yes|Remove frontend pods and service (saves cluster resources)" \
                "no|Keep it running"
        elif [ "$NEW_SCOPE" = "frontend" ] && [ "$BE_EXISTS" = "true" ]; then
            prompt_choice "CLEANUP_BACKEND" "Backend is currently deployed. Remove it?" \
                "yes|Remove backend pods and service" \
                "no|Keep it running"
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# Wizard Step ③  — AI Configuration (create / BYO / mock)
# ═══════════════════════════════════════════════════════════════════════════

wizard_ai() {
    [ "$(get_val "DEPLOY_SCOPE")" = "frontend" ] && return

    section "③ AI Configuration" "How to connect to Microsoft Foundry for the chat backend."

    local PREV_AI; PREV_AI=$(get_val "PREV_AI_MODE")

    prompt_choice "AI_MODE" "AI backend" \
        "create|Create new — provision MS Foundry hub, project, and model" \
        "byo|Bring your own — use an existing MS Foundry project and agent" \
        "mock|Mock mode — no AI, use dummy responses for testing"

    local MODE; MODE=$(get_val "AI_MODE")

    # Detect AI mode downgrade — offer to clean up provisioned resources
    if [ "$AUTO_YES" != "true" ] && [ "$PREV_AI" = "create" ] && [ "$MODE" != "create" ]; then
        echo ""
        echo -e "  ${YELLOW}⚠ You previously provisioned MS Foundry resources (hub, project, model).${NC}"
        echo -e "  ${DIM}These may still incur charges from the model deployment TPM allocation.${NC}"
        echo ""
        prompt_choice "CLEANUP_AI" "What to do with existing AI resources?" \
            "keep|Keep them — I might switch back later" \
            "delete|Delete AI hub, project, and model deployment"
    fi

    if [ "$MODE" = "mock" ]; then
        save_val "DATASOURCES" "mock"
        return
    fi

    case "$MODE" in
        create) wizard_ai_create ;;
        byo)    wizard_ai_byo ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════
# Wizard Step ③a — AI Create (provision new MS Foundry hub + model)
# ═══════════════════════════════════════════════════════════════════════════

wizard_ai_create() {
    echo -e "  ${DIM}We'll create an MS Foundry hub + project and deploy a model.${NC}"
    echo -e "  ${DIM}An agent will be created automatically after provisioning.${NC}"
    echo ""

    local LOCATION; LOCATION=$(get_val "AZURE_LOCATION")

    # ── Fetch available models in background while user picks ───
    local ALL_MODELS_FILE; ALL_MODELS_FILE=$(mktemp)
    if [ -n "$LOCATION" ]; then
        # Fetch models: use JMESPath to filter, awk to deduplicate
        ( az cognitiveservices model list --location "$LOCATION" \
            --query "[?model.format=='OpenAI'].{name:model.name, ver:model.version}" \
            -o tsv 2>/dev/null | \
            awk -F'\t' '
                /tts|transcribe|audio|embedding|dall-e|whisper|davinci|babbage|curie|ada|realtime|diarize|image|instruct|turbo-16k|codex|sora|oss|document|model-router|35-turbo/ {next}
                !seen[$1]++ {print $1 "|" $2 "|OpenAI"}
            ' | sort > "$ALL_MODELS_FILE" 2>/dev/null ) &
        local MODELS_PID=$!
    fi

    # ── Model selector — popular first, with expand + custom ──────
    local POP_M_V=("gpt-4o-mini" "gpt-4o" "gpt-4.1-mini" "gpt-4.1" "gpt-4.1-nano")
    local POP_M_D=(
        "gpt-4o-mini ${DIM}— fast & cheap${NC} ${GREEN}(Recommended)${NC}"
        "gpt-4o ${DIM}— powerful all-rounder${NC}"
        "gpt-4.1-mini ${DIM}— latest mini model${NC}"
        "gpt-4.1 ${DIM}— latest flagship${NC}"
        "gpt-4.1-nano ${DIM}— smallest & fastest${NC}"
    )
    POP_M_V+=("__more__" "__custom__")
    POP_M_D+=("${BOLD}More models...${NC} ${DIM}— all models (DeepSeek, Phi, Llama, etc.)${NC}" "${BOLD}Custom...${NC} ${DIM}— type a model name manually${NC}")

    echo -e "  ${DIM}Which model to deploy in your MS Foundry project.${NC}"
    while true; do
        prompt_select "AI_MODEL_NAME" "Model to deploy" POP_M_V POP_M_D \
            "" "gpt-4o-mini"
        local PICKED; PICKED=$(get_val "AI_MODEL_NAME")

        if [ "$PICKED" = "__back__" ]; then
            save_val "AI_MODEL_NAME" ""; continue
        elif [ "$PICKED" = "__more__" ]; then
            save_val "AI_MODEL_NAME" ""
            if [ -n "${MODELS_PID:-}" ] && kill -0 "$MODELS_PID" 2>/dev/null; then
                echo -ne "  ${DIM}Loading models...${NC}\r"
                wait "$MODELS_PID" 2>/dev/null || true
                echo -ne "                        \r"
            fi
            local ALL_M_V=() ALL_M_D=()
            while IFS='|' read -r name ver provider; do
                [ -n "$name" ] || continue
                ALL_M_V+=("$name")
                local tag=""; [ -n "$provider" ] && [ "$provider" != "OpenAI" ] && tag=" ${DIM}[${provider}]${NC}"
                if [ "$name" = "gpt-4o-mini" ]; then
                    ALL_M_D+=("${name} ${DIM}— v${ver}${NC}${tag} ${GREEN}(Recommended)${NC}")
                else
                    ALL_M_D+=("${name} ${DIM}— v${ver}${NC}${tag}")
                fi
            done < "$ALL_MODELS_FILE"
            if [ "${#ALL_M_V[@]}" -gt 0 ]; then
                prompt_select "AI_MODEL_NAME" "Model to deploy" ALL_M_V ALL_M_D "" "gpt-4o-mini"
                [ "$(get_val "AI_MODEL_NAME")" = "__back__" ] && { save_val "AI_MODEL_NAME" ""; continue; }
            else
                prompt_val "AI_MODEL_NAME" "Model name" "gpt-4o-mini" "" \
                    "Could not fetch models. Enter a model name."
            fi
            break
        elif [ "$PICKED" = "__custom__" ]; then
            save_val "AI_MODEL_NAME" ""
            prompt_val "AI_MODEL_NAME" "Model name" "gpt-4o-mini" --required \
                "Enter the exact model name (e.g. gpt-4o-mini, DeepSeek-R1, Phi-4)"
            break
        else
            break
        fi
    done

    # ── Auto-set version from fetched data ────────────────────────
    if [ -f "$ALL_MODELS_FILE" ]; then
        local SELECTED; SELECTED=$(get_val "AI_MODEL_NAME")
        local VER; VER=$(grep "^${SELECTED}|" "$ALL_MODELS_FILE" 2>/dev/null | head -1 | cut -d'|' -f2)
        [ -n "$VER" ] && save_val "AI_MODEL_VERSION" "$VER"
    fi
    if [ -n "${MODELS_PID:-}" ]; then
        kill "$MODELS_PID" 2>/dev/null || true; wait "$MODELS_PID" 2>/dev/null || true
    fi
    rm -f "$ALL_MODELS_FILE"

    # ── Version — show if auto-detected, prompt if not ──────────
    local CUR_VER; CUR_VER=$(get_val "AI_MODEL_VERSION")
    if [ -n "$CUR_VER" ]; then
        echo -e "  ${DIM}Model version:${NC} ${CYAN}${CUR_VER}${NC}"
    else
        prompt_val "AI_MODEL_VERSION" "Model version" "2024-07-18" --required \
            "Model version — check Microsoft Foundry for available versions"
    fi

    # ── Capacity (TPM) ────────────────────────────────────────────
    local CAP_V=("1" "5" "10" "30")
    local CAP_D=(
        " 1K TPM ${DIM}— minimal dev/test (cheapest)${NC}"
        " 5K TPM ${DIM}— light usage${NC}"
        "10K TPM ${DIM}— moderate usage${NC}"
        "30K TPM ${DIM}— production workload${NC}"
    )
    prompt_select "AI_MODEL_CAPACITY" "Model capacity" CAP_V CAP_D \
        "Tokens-per-minute limit (in thousands). Start low, scale up later." "1"

    # ── Validate quota before proceeding ──────────────────────────
    local Q_LOCATION; Q_LOCATION=$(get_val "AZURE_LOCATION")
    local Q_MODEL; Q_MODEL=$(get_val "AI_MODEL_NAME")
    local Q_CAPACITY; Q_CAPACITY=$(get_val "AI_MODEL_CAPACITY")
    if [ -n "$Q_LOCATION" ] && [ -n "$Q_MODEL" ] && [ -n "$Q_CAPACITY" ]; then
        check_model_quota "$Q_LOCATION" "$Q_MODEL" "GlobalStandard" "$Q_CAPACITY" "AI_MODEL_CAPACITY" || true
    fi

    save_val "DATASOURCES" "api"
}

# ═══════════════════════════════════════════════════════════════════════════
# Wizard Step ③b — AI Bring-Your-Own (existing MS Foundry project + agent)
# ═══════════════════════════════════════════════════════════════════════════

wizard_ai_byo() {
    echo -e "  ${DIM}Connect to an existing MS Foundry project. We'll assign RBAC roles${NC}"
    echo -e "  ${DIM}so the workload identity can call the AI API (even cross-RG).${NC}"
    echo ""

    prompt_val "AI_PROJECT_ENDPOINT" "MS Foundry project endpoint" "" --required \
        "Find this in Azure Portal → MS Foundry → Project → Settings → Endpoint"
    prompt_val "AI_AGENT_ID" "Agent ID (name:version)" "" --required \
        "The agent name and version, e.g. 'my-agent:1' — find in MS Foundry → Agents"

    # Auto-detect AI_RESOURCE_GROUP from the endpoint's account name
    if [ -z "$(get_val "AI_RESOURCE_GROUP")" ]; then
        local ENDPOINT; ENDPOINT=$(get_val "AI_PROJECT_ENDPOINT")
        local ACCT; ACCT=$(echo "$ENDPOINT" | sed -n 's|https://\([^.]*\)\..*|\1|p')
        if [ -n "$ACCT" ]; then
            echo -ne "  ${DIM}Auto-detecting resource group for ${ACCT}...${NC}"
            local RG; RG=$(az cognitiveservices account list \
                --query "[?name=='$ACCT'].resourceGroup" -o tsv 2>/dev/null || echo "")
            if [ -n "$RG" ]; then
                echo -e " ${GREEN}found: ${RG}${NC}"
                save_val "AI_RESOURCE_GROUP" "$RG"
            else
                echo -e " ${YELLOW}not found in current subscription${NC}"
                prompt_val "AI_RESOURCE_GROUP" "AI resource group" "" --required \
                    "The resource group containing the MS Foundry account (needed for RBAC)"
            fi
        else
            prompt_val "AI_RESOURCE_GROUP" "AI resource group" "" --required \
                "The resource group containing the MS Foundry account (needed for RBAC)"
        fi
    fi
    save_val "DATASOURCES" "api"
}

# ═══════════════════════════════════════════════════════════════════════════
# Wizard Step ④  — Backend Settings (streaming, CORS, admin routes)
# ═══════════════════════════════════════════════════════════════════════════

wizard_backend() {
    local SCOPE; SCOPE=$(get_val "DEPLOY_SCOPE")
    [ "$SCOPE" = "frontend" ] && return

    section "④ Backend Settings" "Runtime configuration for the backend server."

    prompt_choice "STREAMING" "Response streaming" \
        "enabled|Stream AI responses in real-time (better UX)" \
        "disabled|Wait for full response before displaying"

    # CORS help text varies depending on whether a frontend will be deployed
    local SCOPE; SCOPE=$(get_val "DEPLOY_SCOPE")
    local CORS_AUTO_DESC="Auto-detect from ingress IP"
    [ "$SCOPE" = "all" ] && CORS_AUTO_DESC="Auto-detect from frontend ingress URL"
    [ "$SCOPE" = "backend" ] && CORS_AUTO_DESC="Allow any origin (set manually later)"

    prompt_choice "CORS_ORIGINS" "CORS (Cross-Origin Resource Sharing)" \
        "auto|${CORS_AUTO_DESC}" \
        "*|Allow all origins (open, good for dev)" \
        "custom|Specify a custom origin URL"

    local CORS_VAL; CORS_VAL=$(get_val "CORS_ORIGINS")
    if [ "$CORS_VAL" = "custom" ]; then
        save_val "CORS_ORIGINS" ""
        prompt_val "CORS_ORIGINS" "Allowed origin URL" "" --required \
            "The frontend URL allowed to call the backend (e.g. https://myapp.example.com)"
    fi

    prompt_choice "ENABLE_ADMIN_ROUTES" "Admin API routes" \
        "false|Disabled — production safe" \
        "true|Enabled — allows runtime config toggle via /api/admin"
}

# ═══════════════════════════════════════════════════════════════════════════
# Validation — ensure all required config values are set
# ═══════════════════════════════════════════════════════════════════════════

validate_config() {
    ERRORS=""
    MISSING=false

    # Helper: record an error if a required value is empty
    _require() {
        [ -z "$(get_val "$1")" ] && { ERRORS="${ERRORS}\n  ❌ $1 — $2"; MISSING=true; } || true
    }

    _require "ARC_PREFIX"  "Resource prefix"
    _require "NODE_COUNT"  "AKS node count"
    _require "VM_SIZE"     "AKS VM size"
    _require "DEPLOY_MODE" "Deploy mode"

    local DM; DM=$(get_val "DEPLOY_MODE")
    if [ -n "$DM" ] && [ "$DM" != "k8s" ] && [ "$DM" != "containerapp" ]; then
        ERRORS="${ERRORS}\n  ❌ DEPLOY_MODE must be 'k8s' or 'containerapp'"; MISSING=true
    fi

    local DS; DS=$(get_val "DEPLOY_SCOPE")
    if [ "$DS" = "frontend" ] && [ -z "$(get_val "VITE_API_URL")" ]; then
        ERRORS="${ERRORS}\n  ❌ VITE_API_URL required when DEPLOY_SCOPE=frontend"; MISSING=true
    fi

    if [ "$MISSING" = "true" ]; then
        echo ""; echo -e "$ERRORS"; echo ""
        echo "  Fix the above and re-run, or set values with: azd env set <KEY> <VALUE>"
        exit 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# Summary — export values, display config, and ask for confirmation
# ═══════════════════════════════════════════════════════════════════════════

show_summary_and_confirm() {
    export ARC_PREFIX=$(get_val "ARC_PREFIX")
    export DEPLOY_MODE=$(get_val "DEPLOY_MODE")
    export DEPLOY_SCOPE=$(get_val "DEPLOY_SCOPE")
    export VITE_API_URL=$(get_val "VITE_API_URL")
    export NODE_COUNT=$(get_val "NODE_COUNT")
    export VM_SIZE=$(get_val "VM_SIZE")
    export DATASOURCES=$(get_val "DATASOURCES")
    export STREAMING=$(get_val "STREAMING")
    export ENABLE_ADMIN_ROUTES=$(get_val "ENABLE_ADMIN_ROUTES")
    export CORS_ORIGINS=$(get_val "CORS_ORIGINS")
    export AI_MODE=$(get_val "AI_MODE")
    export AI_MODEL_NAME=$(get_val "AI_MODEL_NAME")
    export AI_MODEL_VERSION=$(get_val "AI_MODEL_VERSION")
    export AI_MODEL_CAPACITY=$(get_val "AI_MODEL_CAPACITY")
    export AI_PROJECT_ENDPOINT=$(get_val "AI_PROJECT_ENDPOINT")
    export AI_AGENT_ID=$(get_val "AI_AGENT_ID")

    # Show loading while preparing summary (az calls can be slow)
    echo ""
    echo -ne "  ${DIM}Preparing summary...${NC}"

    source "$INFRA_DIR/naming.sh" 2>/dev/null || true

    # Clear the loading message and print summary
    echo -ne "\r                          \r"
    print_config_summary full "Provision"

    if [ "$AUTO_YES" != "true" ]; then
        # Flush any leftover input from arrow-key selectors before prompting
        read -rsn 100 -t 0.1 2>/dev/null || true
        echo ""
        read -p "  Continue with deployment? [Y/n]: " CONFIRM
        if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
            echo ""; echo "  ━━━ Cancelled ━━━"
            echo "  Adjust with 'azd env set <KEY> <VALUE>' and re-run 'azd up'."; echo ""
            exit 1
        fi

        echo ""
        read -p "  Auto-deploy after provision (skip deploy confirmation)? [Y/n]: " AUTO_DEPLOY
        if [[ ! "$AUTO_DEPLOY" =~ ^[Nn]$ ]]; then
            # Use temp file flag — .env gets overwritten by azd during provision
            touch "/tmp/.azd-auto-deploy-${AZURE_ENV_NAME:-default}"
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# Recipes — predefined configurations for quick deploy
# ═══════════════════════════════════════════════════════════════════════════

apply_recipe() {
    local RECIPE; RECIPE=$(get_val "RECIPE")
    [ -z "$RECIPE" ] && return 1

    echo -ne "  ${DIM}Applying recipe '${RECIPE}'...${NC}"

    case "$RECIPE" in
        all)
            # Full-stack with MS Foundry (recommended defaults)
            save_cached "DEPLOY_SCOPE" "all"
            save_cached "AI_MODE" "create"
            save_cached "DATASOURCES" "api"
            save_cached "AI_MODEL_NAME" "gpt-4o-mini"
            save_cached "AI_MODEL_VERSION" "2024-07-18"
            save_cached "AI_MODEL_CAPACITY" "1"
            save_cached "STREAMING" "enabled"
            save_cached "CORS_ORIGINS" "auto"
            save_cached "ENABLE_ADMIN_ROUTES" "false"
            save_cached "VM_SIZE" "Standard_D2s_v3"
            save_cached "NODE_COUNT" "2"
            ;;
        dev)
            # Development: mock AI, cheapest VM, admin routes on
            save_cached "DEPLOY_SCOPE" "all"
            save_cached "AI_MODE" "mock"
            save_cached "DATASOURCES" "mock"
            save_cached "STREAMING" "enabled"
            save_cached "CORS_ORIGINS" "*"
            save_cached "ENABLE_ADMIN_ROUTES" "true"
            save_cached "VM_SIZE" "Standard_B2s"
            save_cached "NODE_COUNT" "2"
            ;;
        *)
            echo ""
            echo -e "  ${RED}Unknown recipe: ${RECIPE}${NC}"
            echo -e "  ${DIM}Available: all, dev${NC}"
            return 1
            ;;
    esac

    # Prefix is always the env name
    local ENV_NAME; ENV_NAME=$(get_val "AZURE_ENV_NAME")
    [ -n "$ENV_NAME" ] && save_cached "ARC_PREFIX" "$ENV_NAME"

    # Batch-write all cached values to azd env in one shot
    flush_env

    echo -e "\r  ${GREEN}✅ Recipe '${RECIPE}' applied${NC}              "
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# Main Flow
# ═══════════════════════════════════════════════════════════════════════════

# Always detect existing infrastructure + runtime state FIRST
# This sets PROVISION_DONE, DEPLOY_SCOPE, AI_MODE etc. from live Azure/K8s
apply_defaults

# ── Path A: Recipe on FIRST RUN only ────────────────────────────────
# If already provisioned/deployed, skip recipe — go to Deploy/Modify
if [ "$(get_val "WIZARD_DONE")" != "true" ] && apply_recipe 2>/dev/null; then
    save_val "WIZARD_DONE" "true"
    validate_config
    show_summary_and_confirm
    exit 0
fi

# ── Path B: CI mode — apply defaults silently ───────────────────────────
if [ "$AUTO_YES" = "true" ]; then
    validate_config
    show_summary_and_confirm
    exit 0
fi

# ── Path C: Provisioned + deployed — redeploy or modify? ────────────────
if [ "$(get_val "PROVISION_DONE")" = "true" ] && [ "$(get_val "DEPLOY_DONE")" = "true" ]; then
    echo ""
    echo -e "  ${BOLD}${MAGENTA}🚀 sovereign-chat-experience-starter${NC}"
    echo ""

    # Show current config one-liner
    _P=$(get_val "ARC_PREFIX")
    _S=$(get_val "DEPLOY_SCOPE")
    _A=$(get_val "AI_MODE")
    echo -e "  ${DIM}Current: ${_P} | scope=${_S} | ai=${_A}${NC}"
    echo ""
    echo -e "    ${BOLD}1)${NC} ${GREEN}Deploy${NC} ${DIM}— redeploy with current settings${NC}"
    echo -e "    ${BOLD}2)${NC} ${CYAN}Modify${NC} ${DIM}— change scope, AI mode, backend settings${NC}"
    echo ""
    echo -ne "  Choice ${DIM}[1]${NC}: ${CYAN}"
    read -r REDEPLOY_CHOICE; echo -ne "${NC}"

    case "${REDEPLOY_CHOICE:-1}" in
        1)
            validate_config
            show_summary_and_confirm
            exit 0
            ;;
        2|modify)
            wizard_infrastructure
            wizard_scope
            wizard_ai
            wizard_backend
            save_val "WIZARD_DONE" "true"
            validate_config
            show_summary_and_confirm
            exit 0
            ;;
        *)
            validate_config
            show_summary_and_confirm
            exit 0
            ;;
    esac
fi

# ── Path D: Provisioned but not deployed — recipe or configure ──────────
if [ "$(get_val "PROVISION_DONE")" = "true" ]; then
    echo ""
    echo -e "  ${BOLD}${MAGENTA}🚀 sovereign-chat-experience-starter — Configure Deployment${NC}"
    echo -e "  ${DIM}Infrastructure is ready. Choose how to deploy.${NC}"
    echo ""
    echo -e "    ${BOLD}1)${NC} ${GREEN}all${NC} ${DIM}— Full stack + MS Foundry (gpt-4o-mini)${NC}"
    echo -e "    ${BOLD}2)${NC} ${CYAN}dev${NC} ${DIM}— Full stack + mock AI, admin enabled${NC}"
    echo -e "    ${BOLD}3)${NC} ${YELLOW}custom${NC} ${DIM}— Configure each setting manually${NC}"
    echo ""
    echo -ne "  Choice ${DIM}[1]${NC}: ${CYAN}"
    read -r DEPLOY_RECIPE; echo -ne "${NC}"

    case "${DEPLOY_RECIPE:-1}" in
        1)
            save_val "RECIPE" "all"
            apply_recipe
            ;;
        2)
            save_val "RECIPE" "dev"
            apply_recipe
            ;;
        3|custom)
            wizard_infrastructure
            wizard_scope
            wizard_ai
            wizard_backend
            ;;
        *)
            save_val "RECIPE" "all"
            apply_recipe
            ;;
    esac

    save_val "WIZARD_DONE" "true"
    validate_config
    show_summary_and_confirm
    exit 0
fi

# ── Path D: First run — recipe picker or full wizard ───────────────────
echo ""
echo -e "  ${BOLD}${MAGENTA}🚀 sovereign-chat-experience-starter — Setup${NC}"
echo ""
echo -e "  ${DIM}Choose a deployment recipe or configure manually.${NC}"
echo ""
echo -e "    ${BOLD}1)${NC} ${GREEN}all${NC} ${DIM}— Full stack + MS Foundry (gpt-4o-mini) — recommended${NC}"
echo -e "    ${BOLD}2)${NC} ${CYAN}dev${NC} ${DIM}— Full stack + mock AI, cheapest VM, admin enabled${NC}"
echo -e "    ${BOLD}3)${NC} ${YELLOW}custom${NC} ${DIM}— Walk through the full setup wizard${NC}"
echo ""
echo -ne "  Choice ${DIM}[1]${NC}: ${CYAN}"
read -r RECIPE_CHOICE; echo -ne "${NC}"

case "${RECIPE_CHOICE:-1}" in
    1)
        save_val "RECIPE" "all"
        apply_recipe
        ;;
    2)
        save_val "RECIPE" "dev"
        apply_recipe
        ;;
    3|custom)
        # Full wizard
        wizard_subscription
        wizard_infrastructure
        wizard_scope
        wizard_ai
        wizard_backend
        ;;
    *)
        echo -e "  ${YELLOW}Invalid choice. Using 'all' recipe.${NC}"
        save_val "RECIPE" "all"
        apply_recipe
        ;;
esac

save_val "WIZARD_DONE" "true"
validate_config
show_summary_and_confirm
