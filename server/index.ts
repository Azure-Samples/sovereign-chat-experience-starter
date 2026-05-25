// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
/**
 * Sovereign Chat Experience Starter Server
 *
 * Reference implementation for Microsoft Foundry integration.
 * See /server/routes for API endpoints.
 */

// Load env FIRST using top-level await (ESM hoists imports, so we need this)
import dotenv from "dotenv";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load .env BEFORE any other imports that use process.env
dotenv.config({ path: path.join(__dirname, ".env") });

// Now dynamically import everything else AFTER env is loaded
const [{ default: express }, { default: cookieParser }, { default: morgan }, { corsMiddleware, errorHandler, sessionMiddleware }, { registerRoutes }, , { config }] = await Promise.all([
  import("express"),
  import("cookie-parser"),
  import("morgan"),
  import("./middleware"),
  import("./routes"),
  import("./services"),
  import("./utils/datasources"),
]);

const app = express();
// Azure App Service provides PORT, local uses SERVER_PORT
const PORT = process.env.PORT || process.env.SERVER_PORT || 3001;

// ============================================
// Middleware
// ============================================

app.use(morgan("dev")); // HTTP request logging
app.use(corsMiddleware);
app.use(express.json());
app.use(cookieParser());
app.use(sessionMiddleware);

// ============================================
// Health Check (for deployment)
// ============================================

app.get("/health", (_req, res) => {
  res.json({ status: "ok", timestamp: new Date().toISOString() });
});

// ============================================
// Routes
// ============================================

registerRoutes(app);

// ============================================
// Error Handler
// ============================================

app.use(errorHandler);

// ============================================
// Start Server
// ============================================

app.listen(PORT, () => {
  console.log(`🚀 Server running on port ${PORT}`);
  if (config.isApi()) {
    console.log(`📡 AI Project: ${process.env.AI_PROJECT_ENDPOINT || "(not configured)"}`);
    console.log(`🤖 Agent: ${process.env.AI_AGENT_ID || "(not configured)"}`);
  } else if (config.isByom()) {
    console.log(`🔌 BYOM Endpoint: ${process.env.BYOM_ENDPOINT}`);
    console.log(`🤖 Model: ${process.env.BYOM_MODEL}`);
    console.log(`🔐 Auth: ${process.env.BYOM_AUTH_MODE || "apikey"}`);
  }
  config.log();
});
