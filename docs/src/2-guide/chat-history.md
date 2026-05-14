---
order: 2
---

# Chat History & Conversation Management

## Overview

Sovereign Chat Experience Starter includes built-in conversation management with a sidebar history interface, allowing users to:

- Create new conversations
- View conversation history
- Switch between conversations
- Delete conversations
- Share conversations via URLs (optional)

## Features

### Core Functionality

- **Persistent Conversations**: All conversations are saved and can be resumed later
- **Automatic Titles**: First message becomes the conversation title
- **Real-time Updates**: Sidebar updates as conversations are created/modified
- **Optimistic UI**: Instant feedback while server processes requests
- **Request Cancellation**: Abort in-flight requests when switching conversations
- **Atomic Persistence**: Both user and assistant messages saved together (no orphan messages)

### Optional Features

- **Route-based URLs**: Enable shareable conversation links (`/chat/:conversationId`)
- **Collapsible Sidebar**: Toggle history visibility
- **Disable History**: Can be turned off for single-conversation apps

## Architecture

Chat history is managed by the `useChatConversation` hook and rendered by ChatPage:

<LiteTree>
---
- ChatPage.tsx
    useChatConversation                // hook (business logic)
    ChatHistory.tsx                    // self-managing sidebar
    Chat.tsx                           // presentation
</LiteTree>

Messages use the [Atomic Pattern](/1-getting-started/architecture.md#atomic-pattern-responses-api) - both user and assistant messages are persisted together in a single API call. See [architecture.md](/1-getting-started/architecture.md) for the full system overview.

## Configuration

### Enable/Disable Features

Edit `src/config/constants.ts`:

```typescript
const CONFIG: TypedConfigOptions = {
  // ...
  "chat.enableHistory": true, // Show/hide chat history sidebar
  "chat.useRoutes": true, // Enable URL routing for conversations
  // ...
};
```

- **`chat.enableHistory`**: When `true`, shows sidebar with conversation list. When `false`, single conversation mode.
- **`chat.useRoutes`**: When `true`, conversations use shareable URLs. When `false`, state managed in memory only.

### Routes Configuration

When `"chat.useRoutes": true`:

```
/              → Home (new conversation)
/chat/:id      → Specific conversation
```

When `"chat.useRoutes": false`:

- All conversations stay on `/` route
- State managed in memory only
- URLs don't change when switching conversations

## API Requirements

Your backend must implement the [API contract](/1-getting-started/architecture.md#api-contract). See [services.md](/2-guide/services.md#implementing-a-custom-backend) for endpoint details and custom backend implementation examples.

## Backend Requirements

Chat history requires a backend server. The included Microsoft Foundry server (`server/`) provides a reference implementation.

**Required Environment Variables** (in `server/.env`):

```bash
AI_PROJECT_ENDPOINT=https://your-project.services.ai.azure.com/api/projects/your-project
AI_AGENT_ID=your-agent-name:version
DATASOURCES=api
```

See [Server Setup](/server/README.md) for full configuration, or the [Deployment Guide](/3-deployment/deploy.md) for Azure deployment recipes.

## Usage Examples

### Basic Usage (No Routes)

```typescript
// App.tsx
import { ChatPage } from "./routes/ChatPage";

function App() {
  return <ChatPage />;
}
```

### With React Router

```typescript
// App.tsx
import { BrowserRouter, Routes, Route } from "react-router-dom";
import { ChatPage } from "./routes/ChatPage";

function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<ChatPage />} />
        <Route path="/chat/:conversationId" element={<ChatPage />} />
      </Routes>
    </BrowserRouter>
  );
}
```

## Request Handling

### Refresh Mid-Request (Atomic Pattern)

With the atomic pattern, refresh handling is simple:

| Scenario           | What Happens                               | User Experience    |
| ------------------ | ------------------------------------------ | ------------------ |
| User sends message | Request in-flight, nothing persisted       | Shows loading      |
| User refreshes     | Request aborted, nothing saved             | Clean conversation |
| Page reloads       | Fetch items shows only completed exchanges | Normal state       |

**No orphan messages, no polling needed.**

### Optimistic Updates

New conversations appear immediately in sidebar:

1. User sends message
2. Temporary conversation created instantly (UI updates)
3. Server processes request atomically
4. Temp conversation replaced with real ID + title

### Efficient Fetching

- Single conversation endpoint (`GET /api/conversations/:id`) avoids fetching full list
- Messages fetched only when conversation is selected
- Sidebar shows title/metadata only (no full message history)

## UI Components

### ChatHistory (Sidebar)

Uses the FluentAI Navigation component from `@fluentui-copilot/react-nav`:

```tsx
import { Nav, NavCategory, NavCategoryItem, NavSubItem } from "@fluentui-copilot/react-nav";

<Nav>
  <NavCategory value="chats">
    <NavCategoryItem>Chats</NavCategoryItem>
    {conversations.map((conv) => (
      <ChatSubItem key={conv.id} conversation={conv} />
    ))}
  </NavCategory>
</Nav>;
```

**Features:**

- Collapsible categories
- Active item highlighting
- Hover actions (rename, delete)
- Auto-focus on new chat

### ChatSubItem Component

Individual conversation item in the sidebar:

```tsx
<ChatSubItem
  conversation={conv}
  isActive={conv.id === activeId}
  onSelect={() => selectConversation(conv.id)}
  onDelete={() => deleteConversation(conv.id)}
  onRename={(newTitle) => renameConversation(conv.id, newTitle)}
/>
```

**Features:**

- Single-line title with ellipsis
- Hover reveals action buttons
- Inline rename editing
- Delete confirmation

### App Icons

Configure the icons shown in sidebar header and new chat button:

```typescript
// src/config/constants.ts
const CONFIG: TypedConfigOptions = {
  // ...
  "sidebar.showIcon": true,
  "sidebar.icon": "/my-app-icon.svg",
  "newChat.showIcon": true,
  "newChat.icon": "/new-chat-icon.svg",
  // ...
};
```

See [Styling Guide](./styling.md) for theming options.

## Troubleshooting

### Conversations Not Persisting

- Check server `/api/responses` endpoint is implemented correctly
- Verify `conversationId` is returned in response
- Check browser console for API errors

### Sidebar Not Updating

- Ensure server returns updated conversation list
- Verify no React strict mode double-render issues

### Messages Showing in Wrong Order

- Server must return messages sorted by timestamp (newest first)
- Client reverses for display (oldest at top)
- Check message timestamps are correctly set

### Route URLs Not Working

- Verify `"chat.useRoutes": true` in `src/config/constants.ts`
- Ensure React Router is configured with `/chat/:conversationId` route in `src/routes.tsx`
- Navigation on conversation change is now handled internally by the hook (uses `useNavigate`)
