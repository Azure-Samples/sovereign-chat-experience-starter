// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
/**
 * Data Providers
 *
 * Clean abstraction for data sources (mock vs API).
 * Both MockProvider and ApiProvider implement the DataProvider interface.
 * Use getProvider() to get the active provider based on runtime config.
 *
 * ============================================
 * HOW TO REMOVE MOCK PROVIDER:
 * ============================================
 * 1. Delete /server/providers/mock folder
 * 2. In this file: remove MockProvider import, return ApiProvider directly
 * 3. Remove DATASOURCES from .env (defaults to api)
 * 4. Remove admin toggle endpoints if not needed
 * ============================================
 */

import { shouldUseByom, shouldUseMock } from "../utils/datasources";
import { ApiProvider } from "./api";
import { ChatCompletionsProvider } from "./byom";
import { MockProvider } from "./mock";
import type { DataProvider } from "./types";

export * from "./types";

// Singleton instances
let mockProvider: MockProvider | null = null;
let apiProvider: ApiProvider | null = null;
let chatCompletionsProvider: ChatCompletionsProvider | null = null;

/** Get the active data provider based on runtime config */
export const getProvider = (): DataProvider => {
  if (shouldUseMock()) {
    if (!mockProvider) {
      mockProvider = new MockProvider();
    }
    return mockProvider;
  }
  if (shouldUseByom()) {
    if (!chatCompletionsProvider) {
      chatCompletionsProvider = new ChatCompletionsProvider();
    }
    return chatCompletionsProvider;
  }
  if (!apiProvider) {
    apiProvider = new ApiProvider();
  }
  return apiProvider;
};
