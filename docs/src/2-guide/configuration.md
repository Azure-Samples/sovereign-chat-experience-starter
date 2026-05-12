---
order: 3
---

# Configuration

Sovereign Chat Experience Starter uses a type-safe configuration system with full autocomplete support.

## Overview

Configuration is managed through the `config` utility which provides:

- Type-safe access to all config values
- Autocomplete in IDEs
- Specialized helpers for common patterns
- Centralized configuration management

## Usage

```tsx
import { config } from "@/config/constants";

// Get any config value with autocomplete
const maxWidth = config.get("layout.maxWidth");
const maxLength = config.get("chat.maxLength");

// Check boolean values (only shows boolean keys in autocomplete)
if (config.isEnabled("chat.showPromptStarters")) {
  // render prompt starters
}

// Check non-empty strings/arrays (only shows string/array keys in autocomplete)
if (config.isNotEmpty("app.name")) {
  // use app name
}
```

## API Methods

### `config.get(key)`

Get any configuration value with full type safety.

```tsx
const maxLength = config.get("chat.maxLength");        // number
const appName = config.get("app.name");                // string
const showPrompts = config.get("chat.showPromptStarters"); // boolean
```

### `config.isEnabled(key)`

Check boolean configuration values. **Autocomplete shows only boolean keys.**

```tsx
// ✅ Only accepts boolean keys
config.isEnabled("chat.showPromptStarters")

// ❌ TypeScript error for non-boolean keys
config.isEnabled("chat.maxLength")
```

### `config.isNotEmpty(key)`

Check if string or array values are non-empty. **Autocomplete shows only string/array keys.**

```tsx
// ✅ For strings - checks trimmed length > 0
config.isNotEmpty("app.name")
config.isNotEmpty("layout.maxWidth")

// ✅ For arrays - checks length > 0
// (currently no array configs, but supported)

// ❌ TypeScript error for non-string/array keys
config.isNotEmpty("chat.maxLength")
```

## Available Configuration

### App Settings

| Key           | Type   | Default            | Description                       |
| ------------- | ------ | ------------------ | --------------------------------- |
| `app.name`    | string | `"Sovereign Chat Experience Starter"`   | Application display name          |
| `app.version` | string | `"1.0.0"`          | Application version number        |
| `app.title`   | string | `"Sovereign Chat Experience Starter"`   | Page title (shown in browser tab) |
| `app.favicon` | string | `"/favicon.ico"`   | Path to favicon file              |

### Storage Keys

| Key             | Type   | Default       | Description                                   |
| --------------- | ------ | ------------- | --------------------------------------------- |
| `storage.theme` | string | `"app-theme"` | localStorage key for storing theme preference |

### Query Parameters

| Key           | Type   | Default   | Description                                 |
| ------------- | ------ | --------- | ------------------------------------------- |
| `query.theme` | string | `"theme"` | URL query parameter name for theme override |

### Copilot Settings

| Key                     | Type   | Default    | Description                                                    |
| ----------------------- | ------ | ---------- | -------------------------------------------------------------- |
| `copilot.mode`          | string | `"canvas"` | Copilot display mode: "canvas" (larger) or "default" (compact) |
| `copilot.designVersion` | string | `"next"`   | Fluent UI Copilot design version: "next" or "current"          |

### Chat Settings

| Key                             | Type    | Default | Description                                                |
| ------------------------------- | ------- | ------- | ---------------------------------------------------------- |
| `chat.maxLength`                | number  | `4000`  | Maximum character length for chat input                    |
| `chat.showPromptStarters`       | boolean | `true`  | Show prompt starter suggestions on welcome screen          |
| `chat.promptStarterVisibleRows` | number  | `1`     | Number of visible rows for prompt starters before collapse |
| `chat.enableHistory`            | boolean | `true`  | Enable chat history sidebar                                |
| `chat.useRoutes`                | boolean | `false` | Use URL routes for conversations (`/chat/:id`)             |

### Icon Settings

| Key                    | Type    | Default                | Description                                  |
| ---------------------- | ------- | ---------------------- | -------------------------------------------- |
| `sidebar.showIcon`     | boolean | `false`                | Show icon in sidebar toggle button           |
| `sidebar.icon`         | string  | `""`                   | Path to sidebar icon (in `/public`)          |
| `chat.showMessageIcon` | boolean | `true`                 | Show icon in chat message headers            |
| `chat.messageIcon`     | string  | `"/copilot-icon.svg"`  | Path to chat message icon (in `/public`)     |
| `newChat.showIcon`     | boolean | `true`                 | Show icon in new chat button                 |
| `newChat.icon`         | string  | `"/new-chat-icon.svg"` | Path to new chat icon (in `/public`)         |

### Layout Settings

| Key                  | Type   | Default   | Description                                     |
| -------------------- | ------ | --------- | ----------------------------------------------- |
| `layout.maxWidth`    | string | `"950px"` | Maximum width for main content area (CSS value) |
| `layout.cardColumns` | number | `2`       | Number of columns for card grids                |

## Extending Configuration

To add new configuration options:

1. Add the key and type to `TypedConfigOptions` in `src/config/constants.types.ts`
2. Add a JSDoc comment for autocomplete support
3. Add the value to `CONFIG` in `src/config/constants.ts`

```ts
// constants.types.ts
export interface TypedConfigOptions {
  // ... existing config
  /** Description shown in autocomplete */
  "myFeature.enabled": boolean;
  "myFeature.name": string;
}

// constants.ts
const CONFIG: TypedConfigOptions = {
  // ... existing config
  "myFeature.enabled": true,
  "myFeature.name": "My Feature",
} as const;
```

The helper methods will automatically work with new config keys based on their types:
- Booleans show in `config.isEnabled()` autocomplete
- Strings/arrays show in `config.isNotEmpty()` autocomplete
- All keys show in `config.get()` autocomplete

## Environment Variables

### Frontend (.env)

```bash
# API endpoint (defaults to /api for proxy)
VITE_API_URL=http://localhost:3001
```

### Server (server/.env)

```bash
# Server
SERVER_PORT=3001
CORS_ORIGINS=http://localhost:5173

# Data Sources: "api" or "mock" (selects DataProvider implementation)
DATASOURCES=api

# Streaming: "enabled" or "disabled"
STREAMING=enabled

# Microsoft Foundry (required when DATASOURCES=api)
AI_PROJECT_ENDPOINT=https://your-project.services.ai.azure.com/api/projects/your-project
AI_AGENT_ID=your-agent-name:version

# Authentication: uses DefaultAzureCredential (Workload Identity in production, az login locally)
```

See [quickstart.md](../1-getting-started/quickstart.md) for full environment setup.
