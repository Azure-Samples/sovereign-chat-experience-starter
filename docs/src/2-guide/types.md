---
order: 8
---

# Type System

Sovereign Chat Experience Starter uses types from the `openai` npm package directly, ensuring compatibility with the OpenAI/Microsoft Foundry API contract.

## Overview

<LiteTree>
---
- src/types/
    api.types.ts              // Re-exports from openai SDK
    chat.types.ts             // UI-layer types and interfaces
</LiteTree>

## API Types (`api.types.ts`)

Re-exports from the `openai` package for use throughout the app:

```typescript
import type { Conversation, Message } from "@/types/api.types";
```

| Type                    | Source                           | Description                                       |
| ----------------------- | -------------------------------- | ------------------------------------------------- |
| `Conversation`          | `openai/resources/conversations` | Conversation object with id, metadata, timestamps |
| `Message`               | `openai/resources/conversations` | Message with role, content, status                |
| `ConversationItem`      | `openai/resources/conversations` | Union type for conversation items                 |
| `Response`              | `openai/resources/responses`     | Response object from `/api/responses`             |
| `ResponseOutputMessage` | `openai/resources/responses`     | Output message within a response                  |
| `ApiErrorResponse`      | Custom                           | `{ error: { message: string } }`                  |

## Chat Types (`chat.types.ts`)

UI-layer types that extend API types for the chat interface.

### Core Aliases

```typescript
type ChatMessage = Message;
type ChatConversation = Omit<Conversation, "metadata"> & {
  metadata: { title?: string; [key: string]: unknown };
};
```

### Send Message Types

```typescript
interface SendMessageOptions {
  message: string;
  conversationId?: string;
  title?: string;
}

interface SendMessageResult {
  message: Message;
  conversationId: string;
}
```

### Service Interfaces

```typescript
interface BaseChatApi {
  createConversation(title?: string): Promise<ChatConversation>;
  fetchConversations(): Promise<ChatConversation[]>;
  fetchConversation(id: string): Promise<ChatConversation | null>;
  fetchMessages(
    id: string,
    options?: { limit?: number; after?: string },
  ): Promise<{ messages: Message[]; hasMore: boolean; lastId?: string }>;
  deleteConversation(id: string): Promise<void>;
  renameConversation(id: string, newTitle: string): Promise<void>;
  abort(): void;
}

interface ChatApi extends BaseChatApi {
  sendMessage(options: SendMessageOptions): Promise<SendMessageResult>;
}

interface StreamingChatApi extends BaseChatApi {
  sendMessage(options: SendMessageOptions): Promise<SendMessageResult>;
  sendMessageStreaming(options: SendMessageOptions, callbacks: StreamCallbacks): Promise<void>;
}
```

### Stream Callbacks

```typescript
interface StreamCallbacks {
  onStart?: (data: { conversationId: string }) => void;
  onChunk?: (content: string) => void;
  onDone?: (response: string) => void;
  onError?: (error: { code: string; message: string }) => void;
}
```

### Hook Return Type

The hook return type is composed of separated interfaces for better organization:

```typescript
// Component-level interfaces (in src/types/chat.types.ts)

interface ChatState {
  activeConversation: ChatConversation | null;
  messages: ChatMessage[];
  isInitializing: boolean;
  isLoading: boolean;
}

interface ChatHandlers {
  handleSendMessage: (text: string) => Promise<void>;
  handleStop: () => void;
}

interface ChatHistoryState {
  conversations: ChatConversation[];
}

interface ChatHistoryHandlers {
  handleNewChat: () => void;
  handleSelectConversation: (id: string) => void;
  handleDeleteConversation: (id: string) => Promise<void>;
  handleRenameConversation: (id: string, newTitle: string) => Promise<void>;
}

// Combined interfaces (in src/hooks/internals/_types.ts)
interface ChatConversationState extends ChatState, ChatHistoryState {}
interface ChatConversationHandlers extends ChatHandlers, ChatHistoryHandlers {}
interface ChatConversationReturn {
  state: ChatConversationState;
  handlers: ChatConversationHandlers;
}
```

The combined types and hook-specific types (`ChatConversationOptions`, `ChatConversationReturn`, `ChatConversationHook`) live in `src/hooks/internals/_types.ts`. See [hooks.md](/2-guide/hooks.md) for hook usage and [chat-component.md](/2-guide/chat-component.md) for component prop mapping.
