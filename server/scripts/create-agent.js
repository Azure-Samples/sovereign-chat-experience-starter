#!/usr/bin/env node
// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
// ═══════════════════════════════════════════════════════════════
// create-agent.js — Create an MS Foundry agent via SDK
// ═══════════════════════════════════════════════════════════════
// Usage:  node scripts/create-agent.js
// Env:    AI_PROJECT_ENDPOINT  (required)
//         AI_MODEL_DEPLOYMENT  (default: gpt-4o-mini)
//         AGENT_NAME           (default: foundry-chat-agent)
//         AGENT_INSTRUCTIONS   (optional override)
// Output: prints AGENT_ID=<name>:<version> on success
// ═══════════════════════════════════════════════════════════════

import { AIProjectClient } from "@azure/ai-projects";
import { DefaultAzureCredential } from "@azure/identity";

const endpoint = process.env.AI_PROJECT_ENDPOINT;
const model = process.env.AI_MODEL_DEPLOYMENT || process.env.AI_MODEL_NAME || "gpt-4o-mini";
const agentName = process.env.AGENT_NAME || "foundry-chat-agent";
const instructions = process.env.AGENT_INSTRUCTIONS || "You are a helpful AI assistant for the Sovereign Chat Experience Starter application.";

if (!endpoint) {
  console.error("❌ AI_PROJECT_ENDPOINT is required");
  process.exit(1);
}

console.log(`  Creating agent '${agentName}' with model '${model}'...`);
console.log(`  Endpoint: ${endpoint}`);

try {
  const client = new AIProjectClient(endpoint, new DefaultAzureCredential());

  const agent = await client.agents.create(agentName, {
    name: agentName,
    instructions: instructions,
    kind: "prompt",
    model: model,
  });

  console.log(`  ✅ Agent created: ${agent.name} (id: ${agent.id})`);
  console.log(`  AGENT_ID=${agent.name}:1`);
} catch (err) {
  if (err.statusCode === 404) {
    console.error(`  ❌ Model '${model}' not found. Check the deployment name.`);
  } else if (err.statusCode === 403 || err.statusCode === 401) {
    console.error(`  ❌ Auth failed. RBAC may still be propagating (wait 1-2 min and retry).`);
    console.error(`     ${err.message}`);
  } else {
    console.error(`  ❌ Failed to create agent: ${err.message}`);
  }
  process.exit(1);
}
