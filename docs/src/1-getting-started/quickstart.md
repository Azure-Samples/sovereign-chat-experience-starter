---
order: 1
---

# Quickstart

## Prerequisites

- Node.js 20+
- npm

> **Tip:** Skip all local setup by using the included Dev Container. Open in GitHub Codespaces or VS Code Dev Containers and everything is pre-configured.

## Installation

```bash
# Clone the repository
git clone https://your-repo-url
cd sovereign-chat-experience-starter

# Install dependencies
npm install
```

## Quick Start

### Option 1: With Mock Server (Fastest)

Run the frontend and server with mock responses — no Azure credentials needed:

```bash
# Install server dependencies
cd server && npm install && cd ..

# Set up server config (defaults to mock mode)
cp server/.env.example server/.env

# Terminal 1: Start frontend
npm run dev

# Terminal 2: Start server
cd server && npm run dev
```

The app runs at http://localhost:5173 with the server returning mock AI responses on port 3001.

### Option 2: With Microsoft Foundry

To use the included Microsoft Foundry server:

```bash
# Configure the server
cp server/.env.example server/.env
# Edit server/.env:
#   DATASOURCES=api
#   AI_PROJECT_ENDPOINT=https://...
#   AI_AGENT_ID=<agent>:<version>

# Terminal 1: Start frontend
npm run dev

# Terminal 2: Start server
cd server && npm run start
```

### Option 3: Your Own Backend

Point to your own server that implements the [API contract](./architecture.md#api-contract):

```sh
# .env
VITE_API_URL=https://your-server.com
```

## Configuration

### Mock Mode

Mock responses are provided by the **server** (not the frontend). The frontend requires a running backend — there is no client-side mock.

To run the server in mock mode, set `DATASOURCES` in `server/.env`:

```sh
# server/.env
DATASOURCES=mock       # Mock only (for UI development)
DATASOURCES=api        # API only (default - requires Microsoft Foundry)
```

Toggle at runtime:

```bash
curl -X POST http://localhost:3001/api/admin/datasource/toggle
```

### Streaming Mode

Toggle streaming at runtime:

```bash
curl -X POST http://localhost:3001/api/admin/streaming/toggle
```

### Theme

Set via:

1. Query parameter: `?theme=dark`
2. localStorage: `app-theme` key
3. System preference (fallback)

### Chat Configuration

Centralized in `src/config/constants.ts`:

```typescript
import { config } from "@/config/constants";

const title = config.get("app.title");
const maxWidth = config.get("layout.maxWidth");
```

See [configuration.md](../2-guide/configuration.md) for all options.

### Localization

UI strings in `src/localization/en.ts`.

## Reference Server

A reference Express server with Microsoft Foundry integration is included in `server/`.

See [server/README.md](../../../server/README.md) for setup and configuration.

This is optional — implement your own server following the [API contract](./architecture.md#api-contract).

## Quick Reference

| I want to...         | Do this                                                  |
| -------------------- | -------------------------------------------------------- |
| Run frontend only    | `npm run dev`                                            |
| Run with server      | `npm run dev` + `cd server && npm run dev`               |
| Use mock data        | `DATASOURCES=mock` in `server/.env`                      |
| Use MS Foundry       | `DATASOURCES=api` + set `AI_PROJECT_ENDPOINT`            |
| Deploy full stack    | `azd env set RECIPE all && azd up`                       |
| Deploy frontend only | `azd env set DEPLOY_SCOPE "frontend"` + `azd up`         |
| Change theme         | `?theme=dark` in URL                                     |
| Toggle streaming     | `curl -X POST localhost:3001/api/admin/streaming/toggle` |
| Bring my own backend | Set `VITE_API_URL` in `.env`                             |

## Learning Path

| #   | Doc                                                       | What you'll learn                       |
| --- | --------------------------------------------------------- | --------------------------------------- |
| 1   | [Quickstart](./quickstart.md)                             | Install, run, dev workflow              |
| 2   | [Architecture](./architecture.md)                         | System design, API contract, providers  |
| 3   | [Services](../2-guide/services.md)                        | Client chatApi + server DataProvider    |
| 4   | [Hooks](../2-guide/hooks.md)                              | React hooks API reference               |
| 5   | [Chat Component](../2-guide/chat-component.md)            | Main chat UI props and usage            |
| 6   | [Chat History](../2-guide/chat-history.md)                | Sidebar, conversation management        |
| 7   | [Configuration](../2-guide/configuration.md)              | All config options (frontend + server)  |
| 8   | [Types](../2-guide/types.md)                              | TypeScript type reference               |
| 9   | [Styling](../2-guide/styling.md)                          | Theme system, CSS customization         |
| 10  | [Localization](../2-guide/localization.md)                | i18n setup, adding languages            |
| 11  | [Deployment](../3-deployment/deploy.md)                   | Azure deploy, recipes, env reference    |
| 12  | [Custom Providers](../3-deployment/custom-providers.md)   | BYOB, custom API providers              |

**Shortcut paths:**

- **"I just want to run it"** → #1
- **"I want to understand the code"** → #2, #3, #4
- **"I want to deploy to Azure"** → #1, #11
- **"I want to bring my own backend"** → #2 (API contract), #12
- **"I want to customize the UI"** → #5, #9, #10

## Technology Stack

<details>
<summary>Core dependencies and tools (click to expand)</summary>

### Core Framework

| Technology | Version | Purpose |
|------------|---------|---------|
| React | 18.x | UI library |
| TypeScript | 5.8 | Type-safe JavaScript |
| Vite | 7.x | Build tool and dev server |

### UI Components

| Package | Description |
|---------|-------------|
| `@fluentui/react-components` | Fluent UI v9 component library |
| `@fluentui/react-icons` | Fluent UI icon set |
| `@fluentui-copilot/react-copilot` | CopilotProvider, CopilotChat |
| `@fluentui-copilot/react-copilot-chat` | CopilotMessage, UserMessage |
| `@fluentui-copilot/react-chat-input` | ChatInput with send/stop |
| `@fluentui-copilot/react-copilot-nav` | Nav, NavCategory, NavSubItem |
| `@fluentui-copilot/react-morse-code` | MorseCodeLoader |
| `@fluentui-copilot/react-prompt-starter` | PromptStarterV2, PromptStarterList |

### Markdown Rendering

| Package | Purpose |
|---------|---------|
| `react-markdown` | Core markdown renderer |
| `react-syntax-highlighter` | Code syntax highlighting (Prism) |
| `remark-gfm` | GitHub Flavored Markdown |
| `remark-math` + `rehype-katex` | Math rendering (LaTeX) |

### Development Tools

| Tool | Purpose |
|------|---------|
| ESLint 9 | Linting with TypeScript support |
| react-router-dom 7.x | Client-side routing |
| Griffel | CSS-in-JS (Fluent UI's makeStyles) |
| `openai` ^6.18.0 | Type definitions (dev dependency) |

### Path Aliases

```typescript
// tsconfig.json — single alias resolves all subpaths
"@/*" → "src/*"
```

### Build Outputs

| Command | Output |
|---------|--------|
| `npm run build` | Standard build in `/dist` |
| `npm run build:static` | Static build with relative paths |

</details>
