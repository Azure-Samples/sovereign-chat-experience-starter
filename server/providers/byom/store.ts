// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
/**
 * BYOM Store - In-memory conversation and message storage
 *
 * Same pattern as mock store. BYOM endpoints don't have a Conversations API,
 * so we manage conversations server-side.
 */

import type { Conversation } from "openai/resources/conversations/conversations";

interface StoredConversation {
  id: string;
  sessionId: string;
  title: string;
  createdAt: number;
  metadata: Record<string, string>;
}

interface StoredMessage {
  id: string;
  conversationId: string;
  role: "user" | "assistant";
  text: string;
  createdAt: number;
}

/** Shape returned by toMessage — the subset of Message we actually populate */
export interface ByomMessage {
  id: string;
  type: "message";
  role: "user" | "assistant";
  status: "completed";
  content: Array<{ type: string; text: string }>;
  created_at: number;
  object: "message";
}

const conversations = new Map<string, StoredConversation>();
const messages = new Map<string, StoredMessage[]>();

let idCounter = 0;

export function generateId(prefix: string): string {
  return `${prefix}_${Date.now().toString(36)}${(idCounter++).toString(36)}`;
}

// ============================================
// Conversations
// ============================================

function toConversation(stored: StoredConversation): Conversation {
  return {
    id: stored.id,
    object: "conversation",
    created_at: stored.createdAt,
    metadata: { title: stored.title, ...stored.metadata },
  } as Conversation;
}

export function listConversations(sessionId: string): Conversation[] {
  return Array.from(conversations.values())
    .filter((c) => c.sessionId === sessionId)
    .sort((a, b) => b.createdAt - a.createdAt)
    .map(toConversation);
}

export function getConversation(conversationId: string): Conversation | null {
  const conv = conversations.get(conversationId);
  return conv ? toConversation(conv) : null;
}

export function createConversation(sessionId: string, title: string): Conversation {
  const conv: StoredConversation = {
    id: generateId("conv"),
    sessionId,
    title,
    createdAt: Math.floor(Date.now() / 1000),
    metadata: {},
  };
  conversations.set(conv.id, conv);
  messages.set(conv.id, []);
  return toConversation(conv);
}

export function updateConversation(
  conversationId: string,
  metadata: Record<string, string>,
): Conversation | null {
  const conv = conversations.get(conversationId);
  if (!conv) {return null;}
  if (metadata.title) {conv.title = metadata.title;}
  conv.metadata = { ...conv.metadata, ...metadata };
  return toConversation(conv);
}

export function deleteConversation(conversationId: string): void {
  conversations.delete(conversationId);
  messages.delete(conversationId);
}

// ============================================
// Messages
// ============================================

function toMessage(stored: StoredMessage): ByomMessage {
  return {
    id: stored.id,
    type: "message",
    role: stored.role,
    status: "completed",
    content: [{ type: stored.role === "assistant" ? "output_text" : "text", text: stored.text }],
    created_at: stored.createdAt,
    object: "message",
  };
}

export function getItems(conversationId: string): ByomMessage[] {
  return (messages.get(conversationId) || []).map(toMessage);
}

export function addMessage(conversationId: string, role: "user" | "assistant", text: string): ByomMessage {
  const msg: StoredMessage = {
    id: generateId("msg"),
    conversationId,
    role,
    text,
    createdAt: Math.floor(Date.now() / 1000),
  };
  const convMessages = messages.get(conversationId) || [];
  convMessages.push(msg);
  messages.set(conversationId, convMessages);
  return toMessage(msg);
}
