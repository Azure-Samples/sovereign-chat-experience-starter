// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
/**
 * In-memory conversation/message store for the completions provider.
 *
 * The OpenAI Chat Completions API is stateless — every request must include the
 * full conversation context. Since the UI's `sendMessage` signature does NOT pass
 * prior messages, we keep our own per-conversation store and feed it back into
 * `messages: [...]` on every request.
 *
 * Two modes:
 *   - persist=false (default): in-memory only. Refreshing the page wipes history.
 *     Matches a stateless "single conversation" UX.
 *   - persist=true: mirror writes to localStorage so conversations survive
 *     reloads. Pair with `VITE_CHAT_ENABLE_HISTORY=true` for a multi-conversation UI.
 */

import type { ChatConversation, ChatMessage } from "@/types/chat.types";

const CONV_KEY = "conversations";
const MSG_KEY_PREFIX = "messages.";

interface StoredState {
  conversations: ChatConversation[];
}

export class CompletionsHistoryStore {
  private conversations: ChatConversation[] = [];
  private messages: Map<string, ChatMessage[]> = new Map();

  constructor(
    private readonly persist: boolean,
    private readonly storagePrefix: string,
  ) {
    if (this.persist) {
      this.loadFromStorage();
    }
  }

  // -------------------- conversations --------------------

  listConversations(): ChatConversation[] {
    return [...this.conversations].sort((a, b) => b.created_at - a.created_at);
  }

  getConversation(id: string): ChatConversation | undefined {
    return this.conversations.find((c) => c.id === id);
  }

  upsertConversation(conv: ChatConversation): void {
    const idx = this.conversations.findIndex((c) => c.id === conv.id);
    if (idx === -1) {
      this.conversations.push(conv);
    } else {
      this.conversations[idx] = conv;
    }
    this.flush();
  }

  renameConversation(id: string, newTitle: string): void {
    const conv = this.getConversation(id);
    if (!conv) {
      return;
    }
    conv.metadata = { ...conv.metadata, title: newTitle };
    this.flush();
  }

  deleteConversation(id: string): void {
    this.conversations = this.conversations.filter((c) => c.id !== id);
    this.messages.delete(id);
    if (this.persist) {
      try {
        localStorage.removeItem(this.key(MSG_KEY_PREFIX + id));
      } catch {
        // ignore quota/availability errors
      }
    }
    this.flush();
  }

  // -------------------- messages --------------------

  getMessages(conversationId: string): ChatMessage[] {
    return this.messages.get(conversationId) ?? [];
  }

  appendMessage(conversationId: string, msg: ChatMessage): void {
    const list = this.messages.get(conversationId) ?? [];
    list.push(msg);
    this.messages.set(conversationId, list);
    this.flush(conversationId);
  }

  // -------------------- persistence --------------------

  private key(suffix: string): string {
    return `${this.storagePrefix}.${suffix}`;
  }

  private loadFromStorage(): void {
    try {
      const raw = localStorage.getItem(this.key(CONV_KEY));
      if (!raw) {
        return;
      }
      const state: StoredState = JSON.parse(raw);
      this.conversations = Array.isArray(state.conversations) ? state.conversations : [];
      for (const conv of this.conversations) {
        const msgRaw = localStorage.getItem(this.key(MSG_KEY_PREFIX + conv.id));
        if (msgRaw) {
          const parsed = JSON.parse(msgRaw);
          this.messages.set(conv.id, Array.isArray(parsed) ? parsed : []);
        }
      }
    } catch (e) {
      console.warn("[CompletionsHistoryStore] failed to load from localStorage:", e);
      this.conversations = [];
      this.messages.clear();
    }
  }

  private flush(conversationId?: string): void {
    if (!this.persist) {
      return;
    }
    try {
      localStorage.setItem(this.key(CONV_KEY), JSON.stringify({ conversations: this.conversations }));
      if (conversationId) {
        localStorage.setItem(
          this.key(MSG_KEY_PREFIX + conversationId),
          JSON.stringify(this.messages.get(conversationId) ?? []),
        );
      }
    } catch (e) {
      console.warn("[CompletionsHistoryStore] failed to persist:", e);
    }
  }
}
