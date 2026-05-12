// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
// Text definitions - values can be strings or functions
const TEXT = {
  // General
  "general.pageNotFound": "Sorry, we can't find that page.",

  // Chat
  "chat.name": "Sovereign Chat Experience Starter",
  "chat.placeholder": "Message chat",
  "chat.ariaLabel": "Sovereign Chat Experience Starter",
  "chat.emptyState": "How can I help you today?",
  "chat.welcomeTitle": "Hi, how can I help you?",
  "chat.error": "Sorry, there was an error processing your request.",
  "chat.errorMessage": "An error occurred. Please try again.",
  "chat.loading": "Loading response",
  "chat.workingOnIt": "Working on it...",
  "chat.stoppedGenerating": "OK, I've stopped generating the response.",
  "chat.aiDisclaimer": "AI-generated content may be incorrect",
  "chat.charactersRemaining": (count: number) => `${count} characters remaining`,
  "chat.promptStartersLabel": "Suggested prompts",
  "chat.promptStartersShowMore": "See more",
  "chat.promptStartersShowLess": "See less",
  "chat.sendPrompt": (prompt: string) => `Send prompt: ${prompt}`,
} as const;

// Prompt starters configuration - easily extendable
export const PROMPT_STARTERS = [
  {
    id: "deployment",
    prompt: "Help me find deployment procedures",
    category: "Get help writing",
  },
  {
    id: "knowledge",
    prompt: "What's in the knowledge base?",
    category: "Ask",
  },
  {
    id: "summarize",
    prompt: "Summarize recent documents",
    category: "Get an overview",
  },
  {
    id: "troubleshoot",
    prompt: "Help me troubleshoot an issue",
    category: "Get help",
  },
  {
    id: "best-practices",
    prompt: "What are the best practices for this project?",
    category: "Learn",
  },
  {
    id: "code-review",
    prompt: "Review my code changes",
    category: "Get feedback",
  },
] as const satisfies readonly {
  id: string;
  prompt: string;
  category: string;
}[];

type TextKeys = keyof typeof TEXT;
type TextValue<K extends TextKeys> = (typeof TEXT)[K];

// Typesafe getText - handles both string and function values
export function getText<K extends TextKeys>(
  key: K,
  ...args: TextValue<K> extends (...args: infer P) => string ? P : []
): string {
  const value = TEXT[key];
  if (typeof value === "function") {
    return (value as (...args: unknown[]) => string)(...args);
  }
  return value as string;
}

export function getTextFn<K extends TextKeys>(key: K): TextValue<K> {
  return TEXT[key];
}
