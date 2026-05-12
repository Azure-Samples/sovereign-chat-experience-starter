// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
import type { TypedConfigOptions } from "./constants.types";
import { env } from "./runtime";

// Maps config keys to VITE_* env var names for runtime override.
// Any key listed here can be overridden via Helm/Docker env vars.
const ENV_OVERRIDES: Partial<Record<keyof TypedConfigOptions, { envKey: string; parse?: (v: string) => unknown }>> = {
  "app.name": { envKey: "VITE_APP_NAME" },
  "app.title": { envKey: "VITE_APP_TITLE" },
  "app.favicon": { envKey: "VITE_APP_FAVICON" },
  "chat.maxLength": { envKey: "VITE_CHAT_MAX_LENGTH", parse: Number },
  "chat.showPromptStarters": { envKey: "VITE_CHAT_SHOW_PROMPT_STARTERS", parse: (v) => v === "true" },
  "chat.enableHistory": { envKey: "VITE_CHAT_ENABLE_HISTORY", parse: (v) => v === "true" },
  "chat.useRoutes": { envKey: "VITE_CHAT_USE_ROUTES", parse: (v) => v === "true" },
  "chat.showMessageIcon": { envKey: "VITE_CHAT_SHOW_MESSAGE_ICON", parse: (v) => v === "true" },
  "chat.messageIcon": { envKey: "VITE_CHAT_MESSAGE_ICON" },
  "sidebar.showIcon": { envKey: "VITE_SIDEBAR_SHOW_ICON", parse: (v) => v === "true" },
  "sidebar.icon": { envKey: "VITE_SIDEBAR_ICON" },
  "newChat.showIcon": { envKey: "VITE_NEW_CHAT_SHOW_ICON", parse: (v) => v === "true" },
  "newChat.icon": { envKey: "VITE_NEW_CHAT_ICON" },
  "layout.maxWidth": { envKey: "VITE_LAYOUT_MAX_WIDTH" },
  "layout.cardColumns": { envKey: "VITE_LAYOUT_CARD_COLUMNS", parse: Number },
  "copilot.mode": { envKey: "VITE_COPILOT_MODE" },
};

// All config values in a flat structure for typesafe access
const DEFAULTS: TypedConfigOptions = {
  // Storage keys
  "storage.theme": "app-theme",

  // Query params
  "query.theme": "theme",

  // App info
  "app.name": "Sovereign Chat Experience Starter",
  "app.version": "1.0.0",
  "app.title": "Sovereign Chat Experience Starter",
  "app.favicon": "",

  // Copilot settings
  "copilot.mode": "canvas",
  "copilot.designVersion": "next",

  // Chat input settings
  "chat.maxLength": 4000,
  "chat.showPromptStarters": true,
  "chat.promptStarterVisibleRows": 1,

  // Chat history settings
  "chat.enableHistory": true,
  "chat.useRoutes": true, // If true, conversations use /chat/:id routes

  // Sidebar icon settings
  "sidebar.showIcon": false,
  "sidebar.icon": "", // Path to icon in /public

  // Chat message icon settings
  "chat.showMessageIcon": false,
  "chat.messageIcon": "", // Path to icon in /public

  // New chat button icon settings
  "newChat.showIcon": true,
  "newChat.icon": "/new-chat-icon.svg", // Path to icon in /public

  // Layout settings
  "layout.maxWidth": "950px",
  "layout.cardColumns": 2,
} as const;

// Apply runtime overrides from env vars
const CONFIG = { ...DEFAULTS } as TypedConfigOptions;
for (const [key, override] of Object.entries(ENV_OVERRIDES)) {
  const value = env(override.envKey);
  if (value) {
    try {
      (CONFIG as unknown as Record<string, unknown>)[key] = override.parse ? override.parse(value) : value;
    } catch (error) {
      console.warn(`[Config] Failed to parse ${override.envKey}="${value}": ${error}. Using default value.`);
    }
  }
}

// Extract all keys where the value is boolean
type BooleanConfigKeys = {
  [K in keyof TypedConfigOptions]: TypedConfigOptions[K] extends boolean ? K : never;
}[keyof TypedConfigOptions];

// Extract all keys where the value could be string or array (empty-checkable types)
type EmptyCheckableKeys = {
  [K in keyof TypedConfigOptions]: TypedConfigOptions[K] extends string | unknown[] ? K : never;
}[keyof TypedConfigOptions];

export const config = {
  get<K extends keyof typeof CONFIG>(key: K): (typeof CONFIG)[K] {
    return CONFIG[key];
  },

  isEnabled(key: BooleanConfigKeys): boolean {
    return CONFIG[key] as boolean;
  },

  isNotEmpty(key: EmptyCheckableKeys): boolean {
    const value = CONFIG[key] as string | unknown[];
    if (typeof value === "string") {
      return value.trim().length > 0;
    }
    if (Array.isArray(value)) {
      return value.length > 0;
    }
    return false;
  },

  // Direct access for destructuring
  values: CONFIG,
};
