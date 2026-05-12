---
order: 4
---

# Localization

Sovereign Chat Experience Starter supports localization with all UI strings externalized.

> **Note:** Currently only **English** is implemented. The i18n framework is in place and ready for adding new languages, but no additional language files ship with the project yet.

## Overview

The localization system provides:
- Centralized string management
- Type-safe string access
- Template string support with parameters
- Infrastructure for adding new languages

## Usage

### Getting Text

```tsx
import { getText } from '@/localization/en';

// Simple string
const title = getText('chat.welcomeTitle');

// With parameters
const label = getText('chat.sendPrompt', 'Help me write');
// Result: "Send prompt: Help me write"
```

### In Components

```tsx
function MyComponent() {
  return (
    <h1>{getText('chat.welcomeTitle')}</h1>
    <p>{getText('chat.aiDisclaimer')}</p>
  );
}
```

## Available Strings

### Chat Strings

| Key | Default Value |
|-----|---------------|
| `chat.welcomeTitle` | `"Hi, how can I help you?"` |
| `chat.name` | `"Sovereign Chat Experience Starter"` |
| `chat.placeholder` | `"Message chat"` |
| `chat.ariaLabel` | `"Sovereign Chat Experience Starter"` |
| `chat.aiDisclaimer` | `"AI-generated content may be incorrect"` |
| `chat.promptStartersLabel` | `"Suggested prompts"` |
| `chat.promptStartersShowMore` | `"See more"` |
| `chat.promptStartersShowLess` | `"See less"` |
| `chat.sendPrompt` | `"Send prompt: {0}"` |

## Adding New Strings

1. Add the string to `src/localization/en.ts`:

```ts
export const en = {
  // ... existing strings
  myFeature: {
    title: 'My Feature Title',
    description: 'Description with {0} parameter',
  },
};
```

2. Use in components:

```tsx
getText('myFeature.title')
getText('myFeature.description', 'dynamic')
```

## Adding New Languages

> The steps below describe how you **would** add a new language. This infrastructure is not yet wired up — you'll need to implement a language registry and selection mechanism.

1. Create a new language file (e.g., `src/localization/es.ts`):

```ts
export const es = {
  chat: {
    welcomeTitle: '¡Hola, cómo puedo ayudarte?',
    name: 'Sovereign Chat Experience Starter',
    // ... all other strings
  },
};
```

2. Update `en.ts` to support language selection:

```ts
import { en } from './en';
import { es } from './es';

const languages = { en, es };
let currentLang = 'en';

export const setLanguage = (lang: keyof typeof languages) => {
  currentLang = lang;
};

export const getText = (key: string, ...args: string[]) => {
  const strings = languages[currentLang];
  // ... rest of implementation
};
```

## Template Strings

For dynamic content, use `{0}`, `{1}`, etc. as placeholders:

```ts
// In en.ts
sendPrompt: 'Send prompt: {0}',
greeting: 'Hello {0}, welcome to {1}!',

// Usage
getText('sendPrompt', 'Help me write')
// → "Send prompt: Help me write"

getText('greeting', 'John', 'Sovereign Chat Experience Starter')
// → "Hello John, welcome to Sovereign Chat Experience Starter!"
```

## Best Practices

1. **Always use `getText()`** - Never hardcode UI strings
2. **Descriptive keys** - Use dot notation: `feature.element.action`
3. **Keep strings short** - Long text should be in docs, not UI
4. **Test with long strings** - Some languages expand text by 30%+
