// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
/**
 * Types for the OpenAI-compatible Chat Completions API.
 *
 * Spec: https://platform.openai.com/docs/api-reference/chat
 *
 * Minimal request/response shapes needed to talk to:
 *   - OpenAI / Azure OpenAI
 *   - Foundry Local (vLLM / onnx-genai runtimes)
 *   - Any other OpenAI-compatible inference server
 */

export type ChatCompletionRole = "system" | "user" | "assistant";

export interface ChatCompletionMessage {
  role: ChatCompletionRole;
  content: string;
}

export interface ChatCompletionRequest {
  model: string;
  messages: ChatCompletionMessage[];
  stream?: boolean;
  temperature?: number;
  max_tokens?: number;
}

export interface ChatCompletionChoice {
  index: number;
  message?: ChatCompletionMessage;
  delta?: { role?: ChatCompletionRole; content?: string };
  finish_reason?: string | null;
}

export interface ChatCompletionResponse {
  id: string;
  object: "chat.completion";
  created: number;
  model: string;
  choices: ChatCompletionChoice[];
}

/** A single SSE chunk in streaming mode (`data: {...}`). */
export interface ChatCompletionStreamChunk {
  id: string;
  object: "chat.completion.chunk";
  created: number;
  model: string;
  choices: ChatCompletionChoice[];
}

export interface ChatCompletionsErrorBody {
  error?: {
    message?: string;
    type?: string;
    code?: string;
  };
}
