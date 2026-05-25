// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
/**
 * Admin Routes
 *
 * Server-side configuration endpoints (for development/testing)
 *
 * Security:
 * - In development mode (NODE_ENV !== "production"): Always enabled
 * - In production mode: Requires ENABLE_ADMIN_ROUTES=true in environment
 *
 * Endpoints:
 *   GET  /admin/config              - Get current config
 *   POST /admin/datasource          - Set datasource { source: "mock" | "api" | "byom" }
 *   POST /admin/datasource/toggle   - Toggle datasource
 *   POST /admin/streaming           - Set streaming { enabled: boolean }
 *   POST /admin/streaming/toggle    - Toggle streaming
 */

import { NextFunction, Request, Response, Router } from "express";

import { config, DataSource } from "../utils/datasources";

const router = Router();

// Check if admin routes are allowed
const isAdminEnabled = (): boolean => {
  const isDev = process.env.NODE_ENV !== "production";
  const explicitlyEnabled = process.env.ENABLE_ADMIN_ROUTES === "true";
  return isDev || explicitlyEnabled;
};

// Middleware to protect admin routes
const adminGuard = (_req: Request, res: Response, next: NextFunction): void => {
  if (!isAdminEnabled()) {
    res.status(403).json({
      error: "Admin routes disabled in production",
      message: "Set ENABLE_ADMIN_ROUTES=true to enable",
    });
    return;
  }
  next();
};

// Apply guard to all admin routes
router.use(adminGuard);

/**
 * GET /admin/config - Get current configuration
 */
router.get("/config", (_req, res) => {
  res.json(config.getStatus());
});

const isAiConfigured = (): boolean => {
  return Boolean(process.env.AI_PROJECT_ENDPOINT && process.env.AI_AGENT_ID);
};

/**
 * POST /admin/datasource - Set datasource
 * Body: { source: "mock" | "api" }
 */
router.post("/datasource", (req, res) => {
  const { source } = req.body as { source?: DataSource };

  if (!source || (source !== "mock" && source !== "api" && source !== "byom")) {
    res.status(400).json({ error: "Invalid source. Use 'mock', 'api', or 'byom'" });
    return;
  }

  if (source === "api" && !isAiConfigured()) {
    res.status(400).json({
      error: "Cannot switch to API mode — AI_PROJECT_ENDPOINT and AI_AGENT_ID are not configured.",
      message: "Set the environment variables and restart, or stay in mock mode.",
    });
    return;
  }

  config.setDatasource(source);

  res.json({
    message: `Datasource set to: ${source}`,
    ...config.getStatus(),
  });
});

/**
 * POST /admin/datasource/toggle - Toggle between datasources
 */
router.post("/datasource/toggle", (_req, res) => {
  // Cycle through: mock → api → byom → mock
  const order: DataSource[] = ["mock", "api", "byom"];
  const current = config.getStatus().datasource;
  const currentIndex = order.indexOf(current);
  let nextSource = order[(currentIndex + 1) % order.length];

  // Skip api if not configured
  if (nextSource === "api" && !isAiConfigured()) {
    nextSource = order[(currentIndex + 2) % order.length];
  }

  config.setDatasource(nextSource);

  res.json({
    message: `Datasource toggled to: ${nextSource}`,
    ...config.getStatus(),
  });
});

/**
 * POST /admin/streaming - Set streaming enabled/disabled
 * Body: { enabled: boolean }
 */
router.post("/streaming", (req, res) => {
  const { enabled } = req.body as { enabled?: boolean };

  if (typeof enabled !== "boolean") {
    res.status(400).json({ error: "Invalid value. Use { enabled: true | false }" });
    return;
  }

  config.setStreaming(enabled);

  res.json({
    message: `Streaming ${enabled ? "enabled" : "disabled"}`,
    ...config.getStatus(),
  });
});

/**
 * POST /admin/streaming/toggle - Toggle streaming
 */
router.post("/streaming/toggle", (_req, res) => {
  const newValue = config.toggleStreaming();

  res.json({
    message: `Streaming toggled to: ${newValue ? "enabled" : "disabled"}`,
    ...config.getStatus(),
  });
});

export default router;
