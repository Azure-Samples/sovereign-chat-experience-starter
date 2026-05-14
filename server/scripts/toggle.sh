#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# Toggle server settings for sovereign-chat-experience-starter

set -e

SERVER_URL="${SERVER_URL:-http://localhost:3001}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get current settings
get_settings() {
    curl -s "$SERVER_URL/api/settings" 2>/dev/null
}

# Parse JSON value (handles both strings and booleans)
get_value() {
    echo "$1" | grep -o "\"$2\":[^,}]*" | sed 's/"'$2'"://; s/"//g'
}

# Show current state
show_current() {
    echo -e "${BLUE}📊 Current Settings${NC}"
    echo "===================="
    
    SETTINGS=$(get_settings)
    if [ -z "$SETTINGS" ]; then
        echo "❌ Cannot connect to server at $SERVER_URL"
        echo "   Make sure server is running: npm run dev"
        exit 1
    fi
    
    STREAMING=$(get_value "$SETTINGS" "streaming")
    DATASOURCE=$(get_value "$SETTINGS" "datasource")
    
    echo -e "Streaming:  ${YELLOW}$STREAMING${NC}"
    echo -e "Provider:   ${YELLOW}$DATASOURCE${NC}"
    echo ""
}

# Toggle streaming
toggle_streaming() {
    local BEFORE=$(get_value "$(get_settings)" "streaming")
    
    echo -e "${BLUE}🔄 Toggling streaming...${NC}"
    RESPONSE=$(curl -s -X POST "$SERVER_URL/api/admin/streaming/toggle")
    
    local AFTER=$(get_value "$RESPONSE" "streaming")
    
    echo -e "   ${YELLOW}$BEFORE${NC} → ${GREEN}$AFTER${NC}"
    echo ""
}

# Toggle provider
toggle_provider() {
    local BEFORE=$(get_value "$(get_settings)" "datasource")
    
    echo -e "${BLUE}🔄 Toggling provider...${NC}"
    RESPONSE=$(curl -s -X POST "$SERVER_URL/api/admin/datasource/toggle")
    
    local AFTER=$(get_value "$RESPONSE" "datasource")
    
    echo -e "   ${YELLOW}$BEFORE${NC} → ${GREEN}$AFTER${NC}"
    echo ""
}

# Main menu
main() {
    echo ""
    echo "🔧 Sovereign Chat Experience Starter - Server Toggle"
    echo "=================================="
    echo ""
    
    show_current
    
    if [ -n "$1" ]; then
        # Non-interactive mode
        case "$1" in
            streaming|s)
                toggle_streaming
                ;;
            provider|p)
                toggle_provider
                ;;
            *)
                echo "Usage: $0 [streaming|provider]"
                exit 1
                ;;
        esac
    else
        # Interactive mode
        echo "What do you want to toggle?"
        echo "  1) Streaming"
        echo "  2) Provider (mock/api)"
        echo "  3) Both"
        echo "  q) Quit"
        echo ""
        read -p "Select [1-3/q]: " choice
        
        case "$choice" in
            1)
                toggle_streaming
                ;;
            2)
                toggle_provider
                ;;
            3)
                toggle_streaming
                toggle_provider
                ;;
            q|Q)
                echo "Cancelled"
                exit 0
                ;;
            *)
                echo "Invalid choice"
                exit 1
                ;;
        esac
    fi
    
    echo -e "${GREEN}✅ Done!${NC}"
}

main "$@"
