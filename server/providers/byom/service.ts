// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
/**
 * BYOM Service - OpenAI-compatible HTTP client
 *
 * Supports two authentication modes:
 * - apikey: API key via header (auto-detects Azure vs standard OpenAI)
 * - mtls: Mutual TLS with client certificates
 *
 * Translates OpenAI SSE format to Foundry SSE format for the frontend.
 */

import * as fs from "node:fs";
import * as https from "node:https";
import { rootCertificates } from "node:tls";

// ============================================
// Configuration
// ============================================

type AuthMode = "apikey" | "mtls";
const validAuthModes: AuthMode[] = ["apikey", "mtls"];

function validateAuthMode(value: string | undefined): AuthMode {
  const normalized = (value || "apikey").trim().toLowerCase();
  return validAuthModes.includes(normalized as AuthMode) ? (normalized as AuthMode) : "apikey";
}

interface ByomConfig {
  endpoint: string;
  model: string;
  authMode: AuthMode;
  apiKey?: string;
  clientCertPath?: string;
  clientKeyPath?: string;
  caCertPath?: string;
  systemPrompt?: string;
}

function parseByomConfig(): ByomConfig {
  return {
    endpoint: process.env.BYOM_ENDPOINT || "",
    model: process.env.BYOM_MODEL || "gpt-4",
    authMode: validateAuthMode(process.env.BYOM_AUTH_MODE),
    apiKey: process.env.BYOM_API_KEY,
    clientCertPath: process.env.BYOM_CLIENT_CERT_PATH,
    clientKeyPath: process.env.BYOM_CLIENT_KEY_PATH,
    caCertPath: process.env.BYOM_CA_CERT_PATH,
    systemPrompt: process.env.BYOM_SYSTEM_PROMPT,
  };
}

// ============================================
// mTLS Agent (singleton)
// ============================================

let cachedAgent: https.Agent | null = null;

function getMtlsAgent(): https.Agent {
  if (cachedAgent) {return cachedAgent;}

  const cfg = parseByomConfig();
  const agentOptions: https.AgentOptions = {
    cert: cfg.clientCertPath ? fs.readFileSync(cfg.clientCertPath) : undefined,
    key: cfg.clientKeyPath ? fs.readFileSync(cfg.clientKeyPath) : undefined,
  };

  // Custom CA: append to default trust store (setting `ca` alone replaces it)
  if (cfg.caCertPath) {
    const customCA = fs.readFileSync(cfg.caCertPath, "utf-8");
    agentOptions.ca = [...rootCertificates, customCA];
  }

  cachedAgent = new https.Agent(agentOptions);
  console.log("🔐 BYOM mTLS agent initialized");
  return cachedAgent;
}

// ============================================
// Types
// ============================================

interface ChatMessage {
  role: "system" | "user" | "assistant";
  content: string;
}

interface ChatCompletionChoice {
  index: number;
  message: { role: string; content: string };
  finish_reason: string;
}

interface ChatCompletionResponse {
  id: string;
  choices: ChatCompletionChoice[];
  model: string;
  usage?: { prompt_tokens: number; completion_tokens: number; total_tokens: number };
}

interface ChatCompletionChunk {
  id: string;
  choices: Array<{ delta: { content?: string; role?: string }; index: number; finish_reason: string | null }>;
}

// ============================================
// HTTP Transport
// ============================================

function getAuthHeaders(cfg: ByomConfig): Record<string, string> {
  if (cfg.authMode !== "apikey" || !cfg.apiKey) {return {};}
  const isAzure = cfg.endpoint.includes(".openai.azure.com");
  return isAzure ? { "api-key": cfg.apiKey } : { Authorization: `Bearer ${cfg.apiKey}` };
}

/** Fetch with auth (apikey uses standard fetch, mtls uses Node https) */
async function byomFetch(url: string, init: RequestInit, stream = false): Promise<Response> {
  const cfg = parseByomConfig();
  if (cfg.authMode === "mtls") {
    return mtlsFetch(url, init, stream);
  }
  return fetch(url, { ...init, headers: { ...init.headers, ...getAuthHeaders(cfg) } });
}

/** HTTPS request with mTLS client certificates, returns Web API Response */
async function mtlsFetch(url: string, init: RequestInit, stream = false): Promise<Response> {
  const agent = getMtlsAgent();
  const parsed = new URL(url);

  return new Promise((resolve, reject) => {
    const reqOptions: https.RequestOptions = {
      hostname: parsed.hostname,
      port: parsed.port || 443,
      path: parsed.pathname + parsed.search,
      method: (init.method || "POST").toUpperCase(),
      agent,
      headers: {
        "Content-Type": "application/json",
        ...(init.headers as Record<string, string>),
      },
    };

    const req = https.request(reqOptions, (res) => {
      if (stream) {
        const readableStream = new ReadableStream({
          start(controller) {
            res.on("data", (chunk: Buffer) => controller.enqueue(chunk));
            res.on("end", () => controller.close());
            res.on("error", (err) => controller.error(err));
          },
        });
        resolve(new Response(readableStream, { status: res.statusCode || 200, headers: res.headers as HeadersInit }));
      } else {
        const chunks: Buffer[] = [];
        res.on("data", (chunk: Buffer) => chunks.push(chunk));
        res.on("end", () => {
          const body = Buffer.concat(chunks).toString("utf-8");
          resolve(new Response(body, { status: res.statusCode || 200, headers: res.headers as HeadersInit }));
        });
        res.on("error", reject);
      }
    });

    req.on("error", reject);
    if (init.signal) {
      init.signal.addEventListener("abort", () => req.destroy());
    }
    if (init.body) {req.write(init.body);}
    req.end();
  });
}

// ============================================
// Public API
// ============================================

/** Build chat messages array from conversation history + new user input */
export function buildChatMessages(
  existingItems: Array<{ role: string; content: Array<{ text?: string }> }>,
  newInput: string,
): ChatMessage[] {
  const cfg = parseByomConfig();
  const messages: ChatMessage[] = [];

  if (cfg.systemPrompt) {
    messages.push({ role: "system", content: cfg.systemPrompt });
  }

  for (const item of existingItems) {
    const text = item.content?.[0]?.text;
    if (text && (item.role === "user" || item.role === "assistant")) {
      messages.push({ role: item.role as "user" | "assistant", content: text });
    }
  }

  messages.push({ role: "user", content: newInput });
  return messages;
}

/** Non-streaming chat completion */
export async function createChatCompletion(
  messages: ChatMessage[],
  options: { signal?: AbortSignal } = {},
): Promise<ChatCompletionResponse> {
  const cfg = parseByomConfig();
  const body = JSON.stringify({ model: cfg.model, messages, stream: false });

  const response = await byomFetch(cfg.endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body,
    signal: options.signal,
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`BYOM request failed (${response.status}): ${errorText}`);
  }

  return response.json() as Promise<ChatCompletionResponse>;
}

/** Streaming chat completion — yields Foundry-format SSE events */
export async function* createStreamingCompletion(
  messages: ChatMessage[],
  responseId: string,
  conversationId: string,
  options: { signal?: AbortSignal } = {},
): AsyncGenerator<unknown> {
  const cfg = parseByomConfig();
  const body = JSON.stringify({ model: cfg.model, messages, stream: true });

  const response = await byomFetch(
    cfg.endpoint,
    { method: "POST", headers: { "Content-Type": "application/json" }, body, signal: options.signal },
    true,
  );

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`BYOM streaming request failed (${response.status}): ${errorText}`);
  }

  // Emit response.created
  yield {
    type: "response.created",
    response: { id: responseId, status: "in_progress", output: [] },
  };

  const reader = response.body!.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  const msgId = `msg_${Date.now()}`;

  // Emit output_item.added
  yield {
    type: "response.output_item.added",
    output_index: 0,
    item: { id: msgId, type: "message", role: "assistant", content: [] },
  };
  yield {
    type: "response.content_part.added",
    output_index: 0,
    content_index: 0,
    part: { type: "output_text", text: "" },
  };

  while (true) {
    const { done, value } = await reader.read();
    if (done) {break;}

    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split("\n");
    buffer = lines.pop() || "";

    for (const rawLine of lines) {
      const line = rawLine.replace(/\r$/, "");
      if (!line.startsWith("data:")) {continue;}
      const data = line.slice(line.startsWith("data: ") ? 6 : 5).trim();
      if (data === "[DONE]") {continue;}

      try {
        const chunk = JSON.parse(data) as ChatCompletionChunk;
        const content = chunk.choices?.[0]?.delta?.content;
        if (content) {
          yield {
            type: "response.output_text.delta",
            output_index: 0,
            content_index: 0,
            delta: content,
          };
        }
      } catch {
        // Skip malformed chunks
      }
    }
  }

  // Emit completion events
  yield {
    type: "response.output_text.done",
    output_index: 0,
    content_index: 0,
  };
  yield {
    type: "response.output_item.done",
    output_index: 0,
    item: { id: msgId, type: "message", role: "assistant", status: "completed" },
  };
  yield {
    type: "response.completed",
    response: { id: responseId, status: "completed", conversation_id: conversationId },
  };
}
