// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
/**
 * Completions Chat API
 *
 * Client-side adapter that talks DIRECTLY (browser → endpoint) to any
 * OpenAI-compatible `/v1/chat/completions` endpoint. No Express server needed.
 * Works with:
 *   - Foundry Local on Azure Local (vLLM / onnx-genai runtimes)
 *   - OpenAI / Azure OpenAI
 *   - Self-hosted vLLM, llama.cpp server, Ollama (OpenAI-compat mode), etc.
 *
 * Why this provider exists
 *   The Chat Completions API is stateless — no server-side conversations or
 *   threads. This adapter keeps a client-side `CompletionsHistoryStore` so the
 *   UI's conversation/history contract still works without any backend.
 *
 * Auth
 *   If `VITE_COMPLETIONS_API_KEY` is set, we send it as `Authorization: Bearer <key>`
 *   AND `api-key: <key>` (Azure-style). Either is harmless to the other server and
 *   avoids per-vendor branching.
 *
 *   ⚠️ Anything in `VITE_COMPLETIONS_API_KEY` ships in the browser bundle. For
 *   production, prefer fronting the endpoint with an auth-injecting reverse proxy.
 *
 * URL handling
 *   `VITE_API_URL` should be the FULL URL to the chat completions endpoint, OR
 *   end with `/v1` (we'll append `chat/completions`). Trailing slash is tolerated.
 */

import { env } from "@/config/runtime";
import type { Message } from "@/types/api.types";
import type {
  ChatConversation,
  SendMessageOptions,
  SendMessageResult,
  StreamCallbacks,
  StreamingChatApi,
} from "@/types/chat.types";
import { createConversation as createConversationObj, generateTitle } from "@/utils/conversation-helpers";
import { isAbortError } from "@/utils/errors";
import { generateId } from "@/utils/id";

import type {
  ChatCompletionMessage,
  ChatCompletionRequest,
  ChatCompletionResponse,
  ChatCompletionsErrorBody,
  ChatCompletionStreamChunk,
} from "./completionsChatApi.types";
import { CompletionsHistoryStore } from "./historyStore";

const toMessageContent = (text: string): Message["content"] => [{ type: "text", text }];

const extractText = (msg: Message): string => {
  for (const part of msg.content) {
    if (part.type === "input_text" || part.type === "output_text" || part.type === "text") {
      const t = (part as { text?: unknown }).text;
      if (typeof t === "string") {
        return t;
      }
    }
  }
  return "";
};

const toCompletionRole = (role: Message["role"]): ChatCompletionMessage["role"] => {
  if (role === "user" || role === "assistant" || role === "system") {
    return role;
  }
  // developer/tool/critic/etc. → user (safest default for unknown roles)
  return "user";
};

const buildEndpoint = (baseUrl: string): string => {
  const trimmed = baseUrl.replace(/\/$/, "");
  if (trimmed.endsWith("/chat/completions")) {
    return trimmed;
  }
  if (trimmed.endsWith("/v1")) {
    return `${trimmed}/chat/completions`;
  }
  return `${trimmed}/v1/chat/completions`;
};

class CompletionsChatApiService implements StreamingChatApi {
  private readonly endpoint = buildEndpoint(env("VITE_API_URL", "/v1"));
  private readonly model = env("VITE_COMPLETIONS_MODEL", "");
  private readonly apiKey = env("VITE_COMPLETIONS_API_KEY", "");
  private readonly systemPrompt = env("VITE_COMPLETIONS_SYSTEM_PROMPT", "");
  private readonly store = new CompletionsHistoryStore(
    env("VITE_COMPLETIONS_PERSIST_HISTORY", "false") === "true",
    env("VITE_COMPLETIONS_STORAGE_PREFIX", "sovereign-chat"),
  );
  private abortController: AbortController | null = null;

  constructor() {
    if (this.apiKey) {
      console.warn(
        "[completions] ⚠️ Static API key detected in browser bundle (VITE_COMPLETIONS_API_KEY). " +
          "This value is inlined at build time and visible in source maps and the network tab. " +
          "INSECURE for production — front the endpoint with an auth-injecting reverse proxy instead.",
      );
    }
    if (!this.model) {
      console.warn("[completions] VITE_COMPLETIONS_MODEL is not set — requests will fail.");
    }
  }

  private buildHeaders(): Record<string, string> {
    const headers: Record<string, string> = { "Content-Type": "application/json" };
    if (this.apiKey) {
      headers["Authorization"] = `Bearer ${this.apiKey}`;
      headers["api-key"] = this.apiKey;
    }
    return headers;
  }

  private buildMessagesPayload(conversationId: string): ChatCompletionMessage[] {
    const out: ChatCompletionMessage[] = [];
    if (this.systemPrompt) {
      out.push({ role: "system", content: this.systemPrompt });
    }
    for (const m of this.store.getMessages(conversationId)) {
      out.push({ role: toCompletionRole(m.role), content: extractText(m) });
    }
    return out;
  }

  private async parseError(res: Response): Promise<string> {
    try {
      const body = (await res.json()) as ChatCompletionsErrorBody;
      return body?.error?.message || `${res.status} ${res.statusText}`;
    } catch {
      return `${res.status} ${res.statusText}`;
    }
  }

  // ---------------------------------------------------------------------------
  // Conversations
  // ---------------------------------------------------------------------------

  fetchConversations = async (): Promise<ChatConversation[]> => {
    return this.store.listConversations();
  };

  fetchConversation = async (id: string): Promise<ChatConversation | null> => {
    return this.store.getConversation(id) ?? null;
  };

  createConversation = async (title?: string): Promise<ChatConversation> => {
    const conv = createConversationObj(generateId("conv"), title ?? "New Chat");
    this.store.upsertConversation(conv);
    return conv;
  };

  deleteConversation = async (id: string): Promise<void> => {
    this.store.deleteConversation(id);
  };

  renameConversation = async (id: string, newTitle: string): Promise<void> => {
    this.store.renameConversation(id, newTitle);
  };

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

  fetchMessages = async (conversationId: string): Promise<{ messages: Message[]; hasMore: boolean; lastId?: string }> => {
    const messages = this.store.getMessages(conversationId);
    return { messages, hasMore: false, lastId: messages.length ? messages[messages.length - 1].id : undefined };
  };

  // ---------------------------------------------------------------------------
  // Send message (non-streaming)
  // ---------------------------------------------------------------------------

  sendMessage = async ({ message, conversationId, title }: SendMessageOptions): Promise<SendMessageResult> => {
    if (this.abortController) {
      this.abortController.abort();
    }
    this.abortController = new AbortController();
    const signal = this.abortController.signal;

    try {
      const convId = conversationId || (await this.createConversation(title || generateTitle(message))).id;

      const userMsg: Message = {
        id: generateId("msg"),
        type: "message",
        role: "user",
        status: "completed",
        content: toMessageContent(message),
      };
      this.store.appendMessage(convId, userMsg);

      const body: ChatCompletionRequest = {
        model: this.model,
        messages: this.buildMessagesPayload(convId),
        stream: false,
      };

      const res = await fetch(this.endpoint, {
        method: "POST",
        headers: this.buildHeaders(),
        body: JSON.stringify(body),
        signal,
      });
      if (!res.ok) {
        throw new Error(await this.parseError(res));
      }

      const data: ChatCompletionResponse = await res.json();
      const text = data.choices?.[0]?.message?.content || "";

      const assistantMsg: Message = {
        id: generateId("msg"),
        type: "message",
        role: "assistant",
        status: "completed",
        content: toMessageContent(text),
      };
      this.store.appendMessage(convId, assistantMsg);

      return { message: assistantMsg, conversationId: convId };
    } finally {
      this.abortController = null;
    }
  };

  // ---------------------------------------------------------------------------
  // Send message (streaming)
  // ---------------------------------------------------------------------------

  sendMessageStreaming = async (
    { message, conversationId, title }: SendMessageOptions,
    callbacks: StreamCallbacks,
  ): Promise<void> => {
    if (this.abortController) {
      this.abortController.abort();
    }
    this.abortController = new AbortController();
    const signal = this.abortController.signal;

    try {
      const convId = conversationId || (await this.createConversation(title || generateTitle(message))).id;

      const userMsg: Message = {
        id: generateId("msg"),
        type: "message",
        role: "user",
        status: "completed",
        content: toMessageContent(message),
      };
      this.store.appendMessage(convId, userMsg);

      // Tell the UI which conversation this stream belongs to so it can wire up
      // routes/sidebar before chunks arrive.
      callbacks.onStart?.({ conversationId: convId });

      const body: ChatCompletionRequest = {
        model: this.model,
        messages: this.buildMessagesPayload(convId),
        stream: true,
      };

      const res = await fetch(this.endpoint, {
        method: "POST",
        headers: this.buildHeaders(),
        body: JSON.stringify(body),
        signal,
      });
      if (!res.ok) {
        throw new Error(await this.parseError(res));
      }

      const fullText = await this.parseSSE(res, callbacks);

      const assistantMsg: Message = {
        id: generateId("msg"),
        type: "message",
        role: "assistant",
        status: "completed",
        content: toMessageContent(fullText),
      };
      this.store.appendMessage(convId, assistantMsg);
    } catch (error) {
      if (isAbortError(error)) {
        return;
      }
      callbacks.onError?.({ code: "stream_error", message: (error as Error).message });
    } finally {
      this.abortController = null;
    }
  };

  // ---------------------------------------------------------------------------
  // SSE parser — OpenAI Chat Completions streaming format
  // ---------------------------------------------------------------------------
  // Each event is a single line: `data: {"choices":[{"delta":{"content":"..."}}]}`
  // terminated by `data: [DONE]`.
  private async parseSSE(response: Response, callbacks: StreamCallbacks): Promise<string> {
    const reader = response.body?.getReader();
    if (!reader) {
      throw new Error("No response body");
    }

    const decoder = new TextDecoder();
    let buffer = "";
    let fullResponse = "";
    let completed = false;

    const finish = () => {
      if (completed) {
        return;
      }
      completed = true;
      callbacks.onDone?.(fullResponse);
    };

    try {
      while (true) {
        let chunk: ReadableStreamReadResult<Uint8Array>;
        try {
          chunk = await reader.read();
        } catch (error) {
          if (isAbortError(error)) {
            // Stream aborted mid-flight — surface partial via onDone so the UI
            // can finalize the in-progress message bubble.
            completed = true;
            callbacks.onDone?.(fullResponse);
            return fullResponse;
          }
          throw error;
        }
        if (chunk.done) {
          break;
        }

        buffer += decoder.decode(chunk.value, { stream: true });
        const lines = buffer.split("\n");
        buffer = lines.pop() || "";

        for (const line of lines) {
          const trimmed = line.trim();
          if (!trimmed.startsWith("data:")) {
            continue;
          }
          const data = trimmed.slice(5).trim();
          if (data === "[DONE]") {
            finish();
            return fullResponse;
          }
          try {
            const event: ChatCompletionStreamChunk = JSON.parse(data);
            const delta = event.choices?.[0]?.delta?.content;
            if (delta) {
              fullResponse += delta;
              callbacks.onChunk?.(delta);
            }
          } catch {
            // Non-JSON / keepalive line — ignore
          }
        }
      }
      finish();
      return fullResponse;
    } finally {
      reader.releaseLock();
    }
  }

  abort = (): void => {
    this.abortController?.abort();
    this.abortController = null;
  };
}

export const completionsChatApi = new CompletionsChatApiService();
