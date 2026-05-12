---
order: 5
---

# Styling

Sovereign Chat Experience Starter uses Griffel (CSS-in-JS) for styling with a typed style system.

## Overview

The styling system provides:
- Type-safe style access with autocomplete
- Token-based design system from Fluent UI
- Centralized style management
- Component overrides for Fluent AI components

## Style System

### Using Styles

```tsx
import { useGlobalStyles } from '@/styles/globalStyles';

function MyComponent() {
  const layoutStyles = useGlobalStyles('layout');
  const textStyles = useGlobalStyles('text');
  
  return (
    <div className={layoutStyles.root}>
      <p className={textStyles.disclaimer}>Hello</p>
    </div>
  );
}
```

### Available Style Groups

| Group | Description | Classes |
|-------|-------------|---------|
| `layout` | Page layout | `root`, `mainContent`, `centeredContent`, `pageWrapper`, `contentArea` |
| `chat` | Chat container | `container`, `welcomeContainer`, `welcomeTitle`, `sidebarToggle` |
| `input` | Input area | `container`, `welcome`, `chatInput` |
| `prompt` | Prompt starters | `list`, `item` |
| `text` | Text styles | `userMessage`, `preserveWhitespace` |
| `progress` | Loading states | `morseCode`, `bar` |

## Fluent UI Tokens

Use Fluent UI tokens for consistent styling:

```tsx
import { tokens } from '@fluentui/react-components';

const useStyles = makeStyles({
  myClass: {
    padding: tokens.spacingVerticalM,
    color: tokens.colorNeutralForeground1,
    fontSize: tokens.fontSizeBase300,
  },
});
```

### Common Tokens

| Category | Examples |
|----------|----------|
| Spacing | `spacingVerticalS`, `spacingHorizontalM`, `spacingVerticalXXL` |
| Colors | `colorNeutralForeground1`, `colorNeutralBackground1` |
| Typography | `fontSizeBase200`, `fontWeightSemibold` |
| Borders | `borderRadiusMedium`, `strokeWidthThin` |

## Component Overrides

Fluent AI Copilot components use BEM-style class names (e.g. `.fai-ChatInput__editor`). Since these are third-party components, you cannot pass Griffel styles directly — instead, override them via global CSS selectors in `globalStyles.ts`.

**When to use overrides:** Only when you need to change the layout or behavior of Fluent AI internal elements that don't expose style props.

```tsx
// In globalStyles.ts — these are applied globally via Griffel's :global() selector
".fai-ChatInput__inputWrapper": {
  position: "relative",
  display: "flex",
  flexDirection: "column",
},
".fai-ChatInput__editor": {
  flex: "1",
  overflowY: "auto",
  minHeight: "20px",
},
```

### Override Classes

| Component | Class | Purpose |
|-----------|-------|---------|
| ChatInput | `.fai-ChatInput__inputWrapper` | Input container |
| ChatInput | `.fai-ChatInput__editor` | Text editor area |
| ChatInput | `.fai-ChatInput__actions` | Send/stop buttons |
| ChatInput | `.fai-ChatInput__status` | Character count |
| PromptStarter | `.fui-PromptStarterV2__reasonMarker` | Category label |

> **Tip:** Inspect Fluent AI components in browser DevTools to discover class names. They follow the pattern `.fai-{ComponentName}__{element}` for Fluent AI and `.fui-{ComponentName}__{element}` for Fluent UI.

## Scrollbar Styling

Custom scrollbar styles are applied globally:

```css
/* Thin, elegant scrollbars */
::-webkit-scrollbar {
  width: 6px;
  height: 6px;
}
::-webkit-scrollbar-thumb {
  background: rgba(128, 128, 128, 0.3);
  border-radius: 3px;
}
```

## Responsive Design

Prompt starters use CSS Grid with auto-fit:

```tsx
gridTemplateColumns: "repeat(auto-fit, minmax(250px, 1fr))",
```

This automatically adjusts from 1 to 3 columns based on container width.

## Adding New Styles

1. Add to appropriate group in `src/styles/globalStyles.ts`
2. The `useGlobalStyles` hook will automatically include the new classes

```tsx
const styleGroups = {
  // Add new group
  myFeature: makeStyles({
    container: { /* styles */ },
    item: { /* styles */ },
  }),
};
```
