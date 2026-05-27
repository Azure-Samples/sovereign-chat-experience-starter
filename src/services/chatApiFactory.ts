// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
/**
 * Chat Module Factory
 *
 * Selects the chat backend at boot:
 *
 *   server       (default) → browser → our Express server (/api) → Foundry Responses API
 *                            Honors the server's /settings.streaming toggle (streaming
 *                            vs standard REST), as today.
 *
 *   completions  → browser → /v1/chat/completions  (no Express server in the loop)
 *                  Talks directly to any OpenAI-compatible Chat Completions endpoint
 *                  (Foundry Local, OpenAI, Azure OpenAI, vLLM, Ollama, llama.cpp, ...).
 *                  Conversation history is kept client-side. See completions/.
 *
 * Mode is selected via VITE_API_MODE. Each provider is dynamic-imported so only the
 * active mode's code is bundled.
 */

import { env } from "@/config/runtime";
import type { ChatConversationHook } from "@/hooks/internals/_types";
import type { BaseChatApi } from "@/types/chat.types";

/** Server settings response (server mode only) */
export interface ServerSettings {
  streaming: boolean;
}

/** Chat module containing API and hook for the current mode */
export interface ChatModule {
  api: BaseChatApi;
  useChatConversation: ChatConversationHook;
  settings: ServerSettings;
}

export type ApiMode = "server" | "completions";

// Cache settings to avoid refetching
let cachedSettings: ServerSettings | null = null;

/**
 * Fetch server settings (cached). Server mode only — in completions mode we
 * never call /api/settings (the Express server isn't required).
 */
export const fetchServerSettings = async (): Promise<ServerSettings> => {
  if (cachedSettings) {
    return cachedSettings;
  }

  try {
    const baseUrl = env("VITE_API_URL", "/api");
    const response = await fetch(`${baseUrl}/settings`);
    if (response.ok) {
      cachedSettings = await response.json();
      return cachedSettings!;
    }
  } catch (error) {
    console.warn("[ChatFactory] Failed to fetch server settings, using defaults:", error);
  }

  // Default settings if server unavailable
  return { streaming: false };
};

const loadServerMode = async (): Promise<ChatModule> => {
  const settings = await fetchServerSettings();

  if (settings.streaming) {
    const [{ streamingChatApi }, { useStreamingChatConversation }] = await Promise.all([
      import("./streamingChatApi"),
      import("@/hooks/internals/_useStreamingChatConversation"),
    ]);
    return { api: streamingChatApi, useChatConversation: useStreamingChatConversation, settings };
  }

  const [{ chatApi }, { useStandardChatConversation }] = await Promise.all([
    import("./chatApi"),
    import("@/hooks/internals/_useStandardChatConversation"),
  ]);
  return { api: chatApi, useChatConversation: useStandardChatConversation, settings };
};

const loadCompletionsMode = async (): Promise<ChatModule> => {
  const [{ completionsChatApi }, { useStreamingChatConversation }] = await Promise.all([
    import("./completions/completionsChatApi"),
    import("@/hooks/internals/_useStreamingChatConversation"),
  ]);
  return {
    api: completionsChatApi,
    useChatConversation: useStreamingChatConversation,
    settings: { streaming: true },
  };
};

const MODE_LOADERS: Record<ApiMode, () => Promise<ChatModule>> = {
  server: loadServerMode,
  completions: loadCompletionsMode,
};

/**
 * Load the appropriate API and hook based on VITE_API_MODE.
 * Enables code splitting - only the active mode's code is bundled.
 */
export const loadChatModule = async (): Promise<ChatModule> => {
  const mode = (env("VITE_API_MODE", "server") || "server") as ApiMode;
  const loader = MODE_LOADERS[mode];
  if (!loader) {
    console.warn(`[ChatFactory] Unknown VITE_API_MODE="${mode}", falling back to "server".`);
    return loadServerMode();
  }
  return loader();
};
