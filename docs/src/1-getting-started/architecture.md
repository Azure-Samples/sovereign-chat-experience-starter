---
order: 2
---

# Architecture

## System Overview

```mermaid
flowchart LR
    A["React App<br/>(Frontend)"] -->|Responses API| B["Your Server<br/>(Backend)"]
    B -->|Workload Identity| C["Microsoft Foundry<br/>or OpenAI, etc."]

    style A fill:#0366d6,color:#fff
    style B fill:#0d6e3e,color:#fff
    style C fill:#6f42c1,color:#fff
```

The frontend connects to **any backend** implementing the OpenAI Conversations API contract. You can use the included reference server, bring your own backend (BYOB), or implement the API contract from scratch.

## Project Structure

<LiteTree>
---
- sovereign-chat-experience-starter/
    + src/                          // Frontend React app
        components/
        config/                    // App constants + runtime env override
        context/
        hooks/
        localization/
        services/
        styles/
        types/
        utils/
        routes.tsx
        main.tsx
    + server/                       // Reference server (optional)
    + infra/                        // Bicep + K8s manifests
        + modules/
        + modes/
            k8s/
            containerapp/
    + hooks/                        // azd lifecycle hooks
    + scripts/                      // Dev utilities
    vite.config.ts
    docker-entrypoint.sh           // Runtime config injection for Docker
    Dockerfile                     // Multi-stage: Node build + nginx serve
</LiteTree>

## Pluggable Provider Pattern

Both the client and server use pluggable providers, making every layer swappable:

### Client-Side Providers

The frontend has a `chatApi` service layer with pluggable implementations:

```mermaid
flowchart LR
    A["React Hooks"] --> B["chatApiFactory"]
    B --> C["ChatApiService<br/>(standard HTTP)"]
    B --> D["StreamingChatApiService<br/>(SSE streaming)"]

    style C fill:#0366d6,color:#fff
    style D fill:#0366d6,color:#fff
```

The factory auto-detects the server mode via `GET /api/settings` and lazy-loads the matching implementation. See [services.md](/2-guide/services.md) for API details.

### Server-Side Providers

The reference server uses a `DataProvider` interface to abstract data sources:

```mermaid
flowchart LR
    A["Express Routes"] --> B["getProvider()"]
    B --> C["ApiProvider<br/>(Microsoft Foundry)"]
    B --> D["MockProvider<br/>(in-memory)"]

    style C fill:#0d6e3e,color:#fff
    style D fill:#b08800,color:#fff
```

Routes call `getProvider()` based on the `DATASOURCES` env var. See [services.md](/2-guide/services.md#server-side-dataprovider) for implementation details.

## Atomic Pattern (Responses API)

Message handling follows the **Atomic Pattern** - a single API call creates the conversation (if needed), processes the message, and persists both user and assistant messages together:

```mermaid
flowchart LR
    A["POST /api/responses"] --> B["Create conversation<br/>(if needed)"]
    B --> C["Process message<br/>with AI agent"]
    C --> D["Persist BOTH<br/>atomically"]
    D --> E["Response"]

    style A fill:#0366d6,color:#fff
    style E fill:#0d6e3e,color:#fff
```

**Benefits:** Single API call, no orphan messages, refresh-safe (nothing saved mid-request), no polling or status tracking.

## API Contract

Your server must implement these endpoints:

| Method | Endpoint                       | Description                              |
| ------ | ------------------------------ | ---------------------------------------- |
| POST   | `/api/responses`               | **Send message + get response (ATOMIC)** |
| GET    | `/api/conversations`           | List all conversations                   |
| GET    | `/api/conversations/:id`       | Get conversation details                 |
| PATCH  | `/api/conversations/:id`       | Update conversation (title)              |
| DELETE | `/api/conversations/:id`       | Delete conversation                      |
| GET    | `/api/conversations/:id/items` | List messages (paginated)                |

All types come from the `openai` npm package — see [types.md](/2-guide/types.md) for type definitions and [services.md](/2-guide/services.md) for request/response examples and custom backend implementation.

## Component Architecture

```mermaid
flowchart LR
    A["AppProviders"] --> B["ThemeProvider"]
    A --> C["CopilotProvider"]
    C --> D["AppRoutes"]
    D --> E["ChatPage"]
    E --> F["ChatHistory"]
    E --> G["Chat"]

    style A fill:#6f42c1,color:#fff
    style E fill:#0366d6,color:#fff
```

Services are instantiated via factory, consumed by [hooks](/2-guide/hooks.md), and passed as props to [components](/2-guide/chat-component.md). Configuration happens at the page/hook level — the Chat component is pure presentation.

See [configuration.md](/2-guide/configuration.md) for all frontend and server environment variables.
