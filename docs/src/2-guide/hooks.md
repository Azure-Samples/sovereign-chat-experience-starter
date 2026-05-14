---
order: 7
---

# Custom Hooks

Sovereign Chat Experience Starter provides custom hooks for chat state management, UI behavior, and theming.

## Overview

<LiteTree>
---
- src/hooks/
    useChatEffects.ts                     // useAutoScroll, useAutoFocus
    useTheme.ts                           // Theme management
    + internals/
        _types.ts                         // Hook types
        _reducer.ts                       // Chat state reducer
        _send-message-helpers.ts          // Send message helpers
        _useBaseChatConversation.ts       // Shared conversation state
        _useStandardChatConversation.ts   // Standard hook
        _useStreamingChatConversation.ts  // Streaming hook
</LiteTree>

## useChatConversation

The main hook for chat functionality. Returns all state and handlers needed by the Chat component. Loaded dynamically via the [chat API factory](/2-guide/services.md#chat-api-factory) based on server settings.

```typescript
import { useChatConversation } from '@/hooks/internals/_useStandardChatConversation';
// or
import { useChatConversation } from '@/hooks/internals/_useStreamingChatConversation';

const { state, handlers } = useChatConversation({
  api: chatApi,
  initialConversationId: conversationId,
});

<Chat
  activeConversation={state.activeConversation}
  messages={state.messages}
  isInitializing={state.isInitializing}
  isLoading={state.isLoading}
  handleSendMessage={handlers.handleSendMessage}
  handleStop={handlers.handleStop}
/>
```

### Options (`ChatConversationOptions<TApi>`)

| Option                  | Type                          | Description                   |
| ----------------------- | ----------------------------- | ----------------------------- |
| `api`                   | `ChatApi \| StreamingChatApi` | API service instance          |
| `initialConversationId` | `string \| undefined`         | Conversation to load on mount |

Navigation on conversation change is handled internally by the hook (uses `useNavigate`).

### Return Type (`ChatConversationReturn`)

Returns `{ state: ChatConversationState; handlers: ChatConversationHandlers }` - see [Chat component props](/components/Chat.md#props) for the full list.

### Internal Architecture

The hook is never imported directly — it is **loaded dynamically** by the [chat API factory](/2-guide/services.md#chat-api-factory). At startup, the factory calls `/api/settings` to check whether streaming is enabled, then returns the matching hook and API service:

```
chatApiFactory()
  → GET /api/settings → { streaming: true }
  → returns { hook: useStreamingChatConversation, api: StreamingChatApiService }
```

Internally, all conversation hooks share a **composition pattern**:

1. **`_useBaseChatConversation`** — shared state via `useReducer` (messages, conversations, loading flags, pagination)
2. **`_useStandardChatConversation`** — extends base with a synchronous `sendMessageHandler` (POST + poll)
3. **`_useStreamingChatConversation`** — extends base with an SSE-based `sendMessageHandler` (EventSource)

Each mode-specific hook calls `useBaseChatConversation(options, sendMessageHandler)`, injecting only the send logic while reusing all shared state management.

See [architecture.md](/1-getting-started/architecture.md#pluggable-provider-pattern) for how this fits into the overall provider pattern.

## useAutoScroll

Automatically scrolls a container to the bottom when content changes.

```typescript
import { useAutoScroll } from "@/hooks/useChatEffects";

const scrollRef = useRef<HTMLDivElement>(null);
useAutoScroll(scrollRef, messages);
```

| Parameter | Type                     | Description                             |
| --------- | ------------------------ | --------------------------------------- |
| `ref`     | `RefObject<HTMLElement>` | Container element ref                   |
| `trigger` | `any`                    | Value that triggers scroll when changed |

Used by the Chat component to keep the message list scrolled to the latest message.

## useAutoFocus

Focuses an element on mount or when a trigger value changes.

```typescript
import { useAutoFocus } from "@/hooks/useChatEffects";

useAutoFocus(shouldFocus, "textarea");
```

| Parameter  | Type     | Description                            |
| ---------- | -------- | -------------------------------------- |
| `trigger`  | `any`    | Value that triggers focus when changed |
| `selector` | `string` | CSS selector for the element to focus  |

Used by the Chat component to focus the input area after sending a message or switching conversations.

## useTheme

Manages theme state with system preference detection and persistence.

```typescript
import { useTheme } from "@/hooks/useTheme";

const { mode, isDark, theme, setMode } = useTheme();
```

### Return Type (`ThemeState`)

| Property  | Type                            | Description                  |
| --------- | ------------------------------- | ---------------------------- |
| `mode`    | `"light" \| "dark" \| "system"` | Current theme mode           |
| `isDark`  | `boolean`                       | Whether dark theme is active |
| `theme`   | `Theme`                         | Fluent UI theme object       |
| `setMode` | `(mode: ThemeMode) => void`     | Change theme mode            |

### Priority Order

1. URL query param: `?theme=dark`
2. localStorage: `app-theme` key
3. System preference: `prefers-color-scheme`

See [configuration.md](/2-guide/configuration.md) for `storage.theme` and `query.theme` config keys.
