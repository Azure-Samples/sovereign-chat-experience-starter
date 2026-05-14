#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# Show current server settings for sovereign-chat-experience-starter

set -e

SERVER_URL="${SERVER_URL:-http://localhost:3001}"

echo "📊 Server Settings"
echo "=================="
echo ""

RESPONSE=$(curl -s "$SERVER_URL/api/settings")

if [ $? -eq 0 ]; then
    echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
else
    echo "❌ Failed to connect to server at $SERVER_URL"
    echo "   Make sure the server is running: npm run dev"
    exit 1
fi
