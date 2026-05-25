// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
/**
 * BYOM Provider - Bring Your Own Model implementation of DataProvider
 *
 * Connects to any OpenAI-compatible chat/completions endpoint.
 * Supports apikey and mTLS authentication modes.
 *
 * Wraps byomStore (in-memory) + byomService (HTTP client) with the DataProvider interface.
 * Easily removable: delete this folder and update providers/index.ts
 */

import type {
  Conversation,
  CreateConversationParams,
  CreateResponseParams,
  CreateResponseResult,
  DataProvider,
  DeleteConversationResult,
  ListConversationItemsParams,
  ListConversationItemsResult,
  Message,
} from "../types";
import * as byomService from "./service";
import * as byomStore from "./store";

export class ChatCompletionsProvider implements DataProvider {
  async listConversations(sessionId: string): Promise<Conversation[]> {
    return byomStore.listConversations(sessionId);
  }

  async getConversation(conversationId: string): Promise<Conversation | null> {
    return byomStore.getConversation(conversationId);
  }

  async createConversation(params: CreateConversationParams): Promise<Conversation> {
    return byomStore.createConversation(params.sessionId, params.title || "New Conversation");
  }

  async updateConversation(conversationId: string, metadata: Record<string, string>): Promise<Conversation | null> {
    return byomStore.updateConversation(conversationId, metadata);
  }

  async deleteConversation(conversationId: string, _sessionId: string): Promise<DeleteConversationResult> {
    byomStore.deleteConversation(conversationId);
    return { id: conversationId, deleted: true, object: "conversation.deleted" };
  }

  async listConversationItems(params: ListConversationItemsParams): Promise<ListConversationItemsResult> {
    const { conversationId, limit = 20, after, order = "desc" } = params;

    let items = byomStore.getItems(conversationId);

    if (order === "desc") {
      items = [...items].reverse();
    }

    if (after) {
      const idx = items.findIndex((i) => i.id === after);
      if (idx !== -1) {
        items = items.slice(idx + 1);
      }
    }

    const limitNum = Math.min(Math.max(limit, 1), 100);
    const hasMore = items.length > limitNum;
    items = items.slice(0, limitNum);

    return {
      data: items as Message[],
      first_id: items[0]?.id || "",
      last_id: items[items.length - 1]?.id || "",
      has_more: hasMore,
      object: "list",
    };
  }

  async createResponse(params: CreateResponseParams): Promise<CreateResponseResult> {
    const { input, conversationId: providedId, sessionId, title, stream, signal } = params;

    let conv = providedId ? byomStore.getConversation(providedId) : null;
    const isNew = !conv;

    if (!conv) {
      conv = byomStore.createConversation(sessionId, title || input.substring(0, 50));
      console.log(`[BYOM] Created new conversation: ${conv.id}`);
    }

    // Build messages from conversation history + new user message
    const existingItems = byomStore.getItems(conv.id);
    const messages = byomService.buildChatMessages(
      existingItems.map((m) => ({
        role: m.role,
        content: m.content,
      })),
      input,
    );

    console.log(`[BYOM] Sending to: ${conv.id}, stream: ${stream}, messages: ${messages.length}`);

    if (stream) {
      const responseId = byomStore.generateId("resp");
      let fullStreamedText = "";

      const streamEvents = byomService.createStreamingCompletion(messages, responseId, conv.id, { signal });

      // Wrap to capture streamed text for persistence
      const capturedStream = (async function* (source: AsyncGenerator<unknown>) {
        for await (const event of source) {
          const e = event as Record<string, unknown>;
          if (e.type === "response.output_text.delta" && typeof e.delta === "string") {
            fullStreamedText += e.delta;
          }
          yield event;
        }
      })(streamEvents);

      const convId = conv.id;
      return {
        conversationId: convId,
        isNew,
        stream: capturedStream,
        onStreamComplete: () => {
          // Atomic persistence: only persist user+assistant pair if the stream produced output.
          // If the upstream failed before any delta, or client aborted before any delta,
          // no orphan user-only message is left behind.
          if (fullStreamedText) {
            byomStore.addMessage(convId, "user", input);
            byomStore.addMessage(convId, "assistant", fullStreamedText);
          }
        },
      };
    }

    // Non-streaming — atomic: only persist messages after upstream call succeeds.
    // If createChatCompletion throws, no orphan user message is persisted.
    const completion = await byomService.createChatCompletion(messages, { signal });
    const assistantText = completion.choices?.[0]?.message?.content || "";
    byomStore.addMessage(conv.id, "user", input);
    const assistantMsg = byomStore.addMessage(conv.id, "assistant", assistantText);

    console.log(`[BYOM] Response generated for: ${conv.id}`);

    return {
      conversationId: conv.id,
      isNew,
      response: {
        id: completion.id || byomStore.generateId("resp"),
        status: "completed",
        output: [assistantMsg],
      },
    };
  }
}
