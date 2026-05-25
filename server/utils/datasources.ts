// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
/**
 * Server Configuration
 *
 * DATASOURCES: "mock" | "api" | "byom" (single source, toggleable at runtime)
 * STREAMING: "enabled" | "disabled" (toggleable at runtime)
 */

export type DataSource = "mock" | "api" | "byom";

const validDataSources: DataSource[] = ["mock", "api", "byom"];

/** Parse initial datasource from env */
const parseDataSource = (): DataSource => {
  const raw = (process.env.DATASOURCES || "api").trim().toLowerCase() as string;
  return validDataSources.includes(raw as DataSource) ? (raw as DataSource) : "api";
};

/** Parse initial streaming from env */
const parseStreaming = (): boolean => {
  const raw = (process.env.STREAMING || "enabled").trim().toLowerCase();
  return raw !== "disabled";
};

/** Runtime state */
let activeSource: DataSource = parseDataSource();
let streamingEnabled: boolean = parseStreaming();

// ANSI colors for terminal output
const colors = {
  reset: "\x1b[0m",
  bright: "\x1b[1m",
  yellow: "\x1b[33m",
  green: "\x1b[32m",
  cyan: "\x1b[36m",
  magenta: "\x1b[35m",
};

/** Log configuration change with colored banner */
const logChange = (type: "datasource" | "streaming", value: string): void => {
  const isMock = value === "mock";
  const isEnabled = value === "enabled";

  let color: string;
  let emoji: string;
  let label: string;

  if (type === "datasource") {
    if (isMock) {
      color = colors.yellow;
      emoji = "🧪";
      label = "MOCK MODE";
    } else if (value === "byom") {
      color = colors.cyan;
      emoji = "🔌";
      label = "BYOM MODE";
    } else {
      color = colors.green;
      emoji = "🚀";
      label = "API MODE ";
    }
  } else {
    color = isEnabled ? colors.cyan : colors.magenta;
    emoji = isEnabled ? "🌊" : "📦";
    label = isEnabled ? "STREAMING ON " : "STREAMING OFF";
  }

  console.log(`\n${colors.bright}${color}╔══════════════════════════════════════╗${colors.reset}`);
  console.log(`${colors.bright}${color}║  ${emoji} ${label}                    ║${colors.reset}`);
  console.log(`${colors.bright}${color}╚══════════════════════════════════════╝${colors.reset}\n`);
};

export const config = {
  // ============ Datasource ============

  /** Get current active datasource */
  getDatasource: (): DataSource => activeSource,

  /** Check if using mock */
  isMock: (): boolean => activeSource === "mock",

  /** Check if using API */
  isApi: (): boolean => activeSource === "api",

  /** Check if using BYOM */
  isByom: (): boolean => activeSource === "byom",

  /** Set datasource */
  setDatasource: (source: DataSource): void => {
    activeSource = source;
    logChange("datasource", source);
  },

  /** Toggle datasource: mock → api → byom → mock */
  toggleDatasource: (): DataSource => {
    const order: DataSource[] = ["mock", "api", "byom"];
    const currentIndex = order.indexOf(activeSource);
    activeSource = order[(currentIndex + 1) % order.length];
    logChange("datasource", activeSource);
    return activeSource;
  },

  // ============ Streaming ============

  /** Check if streaming is enabled */
  isStreamingEnabled: (): boolean => streamingEnabled,

  /** Set streaming enabled/disabled */
  setStreaming: (enabled: boolean): void => {
    streamingEnabled = enabled;
    logChange("streaming", enabled ? "enabled" : "disabled");
  },

  /** Toggle streaming */
  toggleStreaming: (): boolean => {
    streamingEnabled = !streamingEnabled;
    logChange("streaming", streamingEnabled ? "enabled" : "disabled");
    return streamingEnabled;
  },

  // ============ Status ============

  /** Get full config status */
  getStatus: () => ({
    datasource: activeSource,
    streaming: streamingEnabled,
  }),

  /** Log current configuration */
  log: (): void => {
    const dsMap: Record<DataSource, { emoji: string; label: string }> = {
      mock: { emoji: "🧪", label: "Mock" },
      api: { emoji: "🚀", label: "Azure AI" },
      byom: { emoji: "🔌", label: "BYOM" },
    };
    const ds = dsMap[activeSource];
    const stEmoji = streamingEnabled ? "🌊" : "📦";
    const stLabel = streamingEnabled ? "enabled" : "disabled";

    console.log(`${ds.emoji} Datasource: ${ds.label}`);
    console.log(`${stEmoji} Streaming: ${stLabel}`);
  },
};

// Legacy exports for backward compatibility
export const datasources = {
  hasMock: () => activeSource === "mock",
  hasApi: () => activeSource === "api",
  isMockOnly: () => activeSource === "mock",
  isApiOnly: () => activeSource === "api",
  enabled: () => [activeSource],
  getActive: () => activeSource,
  setActive: (source: DataSource) => {
    config.setDatasource(source);
    return true;
  },
  toggle: () => config.toggleDatasource(),
  log: () => config.log(),
};

/** Check if should use mock (for middleware) */
export const shouldUseMock = (): boolean => activeSource === "mock";

/** Check if should use BYOM (for middleware) */
export const shouldUseByom = (): boolean => activeSource === "byom";
