# 🔌 RPC API Reference — Ghost

The Ghost Gateway communicates with clients using **JSON-RPC 2.0** over **WebSockets**. This enables real-time, bidirectional communication between UI clients, IDE/browser extensions, and the backend engine.

---

## 🌐 Connection Details

- **Protocol**: WebSocket (`ws://` or `wss://`)
- **Port**: `3000` (default)
- **Endpoint**: `/` (and `/acp` for Agent Client Protocol)

---

## 🔐 Authentication

If authentication is enabled, call `auth.login` as the first message after connecting.

### `auth.login`
**Params:**
- `password`: (String) The gateway password.
- `token`: (String) Alternatively, an existing session token.

**Response:**
- `authenticated`: (Boolean)

---

## 🛠️ Gateway Control

### `gateway.health`
Lightweight health probe.
**Response:**
- `status`: `"ok"`
- `timestamp`: (ISO String)

### `gateway.status`
Returns the current status of the gateway server.
**Response:**
- `status`: `"running"`
- `port`: (Int)
- `bind`: (String) Bound interface address.
- `clients`: (Int) Count of connected clients.
- `authMode`: (String) Active authentication mode.
- `uptime`: (Int) Seconds since start.
- `startedAt`: (ISO String)

### `gateway.methods`
Lists all registered RPC methods.
**Response:**
- `methods`: (Array of Strings)

### `gateway.restart`
Restarts the gateway server (and triggers full restart callback if attached).

---

## ⚙️ Configuration Methods

### `config.get`
Returns the complete application state.
**Response includes:**
- `agent`, `memory`, `user`, `identity`, `integrations`, `channels`, `tools`, `security`, `customAgents`, `gateway`.
- `vault.keys`: List of keys stored in the encrypted vault.
- `detectedLocalProviders`: Auto-detected local AI endpoints (e.g. Ollama, LM Studio).

### `config.getKey` / `config.setKey`
Manage API keys and secrets in the encrypted vault.
**Params:**
- `service`: (String, e.g., `"openai"`, `"google_workspace"`, `"telegram"`, `"reown_project_id"`, `"payment_card_number"`, `"payment_card_holder"`, `"payment_card_expiry"`, `"payment_card_cvv"`, `"agent_wallet_private_key"`, `"binance_api_key"`, `"binance_secret_key"`, `"binance_demo_api_key"`, `"binance_demo_secret_key"`)
- `key`: (String; passing `""` removes the key unless still referenced by an active agent)

### `config.getChannelToken`
Retrieves the secure token for a communication channel.
**Params:**
- `channelId`: (String, e.g., `"telegram"`, `"whatsapp"`)

**Response:**
- `token`: (String)

### `config.testKey`
Tests a connection or key validity (`service`, `key`).

### `config.setModel`
Updates the default agent's model (and optionally provider).
**Params:**
- `model`: (String)
- `provider`: (String, optional)

### `config.listModels` / `config.listModelsDetailed`
Lists available models for a provider.
**Params:**
- `provider`: (String)
- `apiKey`: (String, optional)

### `config.getModelCapabilities`
Returns details about what a specific model supports (e.g., tools, vision).
**Params:**
- `provider`: (String)
- `model`: (String)

### `config.testEmbedding`
Tests if a provider/model combination supports vector embeddings (`provider`, `model`).

### `config.updateAgent`
Updates the main agent configuration.
**Params:**
- `workspace`, `model`, `provider`, `designSystem`, `thinkingMode`: (String, optional)
- `maxTokens`: (Int, optional)
- `disabledSkills`: (Array of Strings, optional) Opt-out skill slugs (all installed skills allowed by default).
- `skills`: (Array of Strings, optional) Allowed skill slugs (automatically mapped to `disabledSkills`).
- `competencies`: (Array of Strings, optional) Explicit domain tags synced into `HAT_KOMPETENZ`.

### `config.updateUser` / `config.updateIdentity` / `config.updateIntegrations` / `config.updateChannels` / `config.updateTools`
Update specific configuration blocks. Sensitive keys and tokens are automatically filtered into the encrypted vault.

### `config.updateMemory`
Updates standard memory, RAG, Workspace RAG, and Ontology settings.
**Params:**
- `enabled`: (Boolean, optional) Standard memory toggle.
- `ragEnabled`: (Boolean, optional) ObjectBox vector RAG toggle.
- `workspaceRagEnabled`: (Boolean, optional) Workspace `rag/` indexer toggle.
- `ontologyEnabled`: (Boolean, optional) Native ObjectBox Knowledge Graph toggle.
- `ontologyAutoExtract`: (Boolean, optional) System-1-gated post-turn fact extraction toggle.
- `backend`, `embeddingProvider`, `embeddingModel`: (String, optional)
- `chunkSize`, `chunkOverlap`: (Int, optional)
- `vectorWeight`, `bm25Weight`: (Double, optional)

### `config.updateBilling`
Updates the autonomous billing and payment configuration.
**Params:**
- `limit`: (Double, optional) Maximum billing limit budget.
- `balance`: (Double, optional) Available budget balance.
- `autonomous`: (Boolean, optional) If true, executes payments autonomously without HITL confirmation.

**Response:**
- `status`: `"ok"`
- `billing`: (Object) Updated billing configuration.

### `config.updateSecurity`
Updates security and execution policies, including Human-In-The-Loop gating and System-1 Decision Middleware.
**Params:**
- `level`: (String, optional) Security level preset (`"none"`, `"low"`, `"medium"`, `"high"`).
- `humanInTheLoop`: (Boolean, optional) Requires explicit user confirmation for sensitive actions and `ERFORDERT_HITL` skills.
- `promptHardening`: (Boolean, optional) Defends against prompt injection and jailbreak instructions.
- `restrictNetwork`: (Boolean, optional) Restricts outbound network access.
- `promptAnalyzers`: (Boolean, optional) Pre-flight prompt analyzers.
- `system1Middleware`: (Boolean, optional) Enables local ModernBERT INT8 ONNX middleware for pre-flight safety, payload risk scoring, smart HITL, and ontology memory-poisoning protection.

### `config.getGoogleCredentials`
Retrieves the Google OAuth client IDs and secrets from the vault.

---

## 🤖 Agent Methods

### `agent.chat`
Sends a message to an agent (supports `/goal` and `/plan` commands with automatic Ontology routing when no explicit `agentId` is pinned).
**Params:**
- `content`: (String) The message text.
- `agentId`: (String, optional) Target agent profile ID (`"__auto__"` triggers Ontology routing for `/goal`/`/plan`).
- `sessionId`: (String, optional) Target an existing session.
- `attachments`: (Array of Objects, optional) File/image attachments.
- `workspaceDir`: (String, optional) Dynamic workspace directory for filesystem tools and terminal commands.
- `channelType`: (String, optional) Channel identifier (e.g. `"gateway"`, `"vscode"`).
- `peerId`, `groupId`, `model`, `provider`: (String, optional)

**Response:**
- `sessionId`: (String)
- `status`: `"processing"`

### `agent.editMessage`
Edits a previous user message, truncates subsequent history, and re-runs the agent turn.
**Params:**
- `sessionId`: (String)
- `content`: (String)
- `userMessageIndex`: (Int, optional)
- `attachments`, `channelType`, `peerId`, `groupId`, `model`, `provider`, `agentId`, `workspaceDir`: (Optional)

### `agent.history`
Retrieves the message history for a session (`sessionId`, optional `maxMessages` default `50`).

---

## 📂 Session Management

### `agent.sessions`
Lists all active sessions.

### `agent.deleteSession`
Deletes a single session, a batch of sessions, or all sessions.
**Params:**
- `sessionId`: (String, optional) Single session ID to delete.
- `sessionIds`: (Array of Strings, optional) Batch deletion list.
- `all`: (Boolean, optional) If true, deletes all sessions.

### `agent.deleteAllSessions`
Deletes all persisted sessions and broadcasts `agent.sessions_cleared`.

### `agent.setSessionModel`
Updates the LLM model and optional provider for a specific session (`sessionId`, `model`, optional `provider`).

### `agent.setSessionTitle`
Manually renames a session (`sessionId`, `title`) and broadcasts `agent.session_updated`.

### `agent.stop`
Interrupts active generation/streaming for a session (`sessionId`).

---

## 🧠 Memory & Ontology Management

### `memory.backup` / `memory.restore`
Back up or restore the Standard (Hive) Memory database (`data` JSON string).

### `memory.rag.backup` / `memory.rag.restore`
Back up or restore the RAG (ObjectBox Vector) Memory database (`data` JSON string).

### `memory.ontology.backup` / `memory.ontology.restore`
Export or import the portable Knowledge Graph JSON (`relations`, `nodes`, `edges`).
**Params (restore):**
- `data`: (String) JSON string exported by `memory.ontology.backup`.

### `memory.ontology.stats`
Returns counts for `relations`, `nodes`, `edges`, `skills`, `linkedSkills`, `personalEdges`, and `governanceEdges`.

### `memory.ontology.list`
Lists Knowledge Graph triples, entity nodes, and T-Box relation definitions.
**Params:**
- `category`: (String, optional) `"all"`, `"personal"`, `"governance"`, or `"rules"`.
- `query`: (String, optional) Case-insensitive filter across labels, keys, types, or predicates.
- `limit`: (Int, optional) Default `200`.
- `offset`: (Int, optional) Default `0`.

### `memory.ontology.assert`
Asserts or updates a Knowledge Graph triple (`ontology.changed` broadcasted).
**Params:**
- `subject`, `predicate`, `object`: (String, required)
- `subjectType`, `objectType`, `subjectKey`: (String, optional)
- `confidence`: (Double, optional) Default `1.0`.

### `memory.ontology.deleteEdge`
Deletes a single triple edge (`edgeId`: Int).

### `memory.ontology.deleteNode`
Deletes an entity node and all incident edges (`canonicalKey`: String).

### `memory.ontology.query`
Executes a multi-hop graph traversal (`1–4` hops) and returns both `result` and `promptPreview`.
**Params:**
- `entity`: (String) Entity label or `canonicalKey`.
- `maxDepth`: (Int, optional) `1–4` (default `2`).
- `maxResults`: (Int, optional) Default `30`.
- `includeIncoming`: (Boolean, optional) Default `true`.

### `config.clearMemory`
Wipes the specified memory database.
**Params:**
- `type`: (String) `"standard"`, `"rag"`, or `"ontology"`.

---

## 🛠️ Agent Management

### `config.addCustomAgent`
Creates a new custom agent.
**Params:**
- `agent`: (Object) `{ name, systemPrompt, provider, model, disabledSkills, skills, competencies, cronSchedule, cronMessage, designSystem, enabled, ... }`

### `config.updateCustomAgent`
Updates an existing custom agent (`agent`: `{ id, ... }`) and re-syncs Ontology permissions/competencies.

### `config.deleteCustomAgent`
Deletes a custom agent (`id`: String) and its avatar.

---

## 📦 Skills Management

### `skills.list`
Lists all installed skills (including `category`, `requiresHitl`, `securityLevel`, `requiredSkills`).

### `skills.create`
Creates a new skill from a template (`name`, optional `description`, `type`: `"python"|"node"|"markdown"`, optional `emoji`).

### `skills.install` / `skills.import` / `skills.downloadFromGithub`
Installs a skill from base64 ZIP (`zip`), local directory (`path`), or GitHub URL (`url`) and syncs Ontology permissions.

### `skills.getMarkdown` / `skills.updateMarkdown`
Read or modify `SKILL.md` (`slug`, and `content` for update).

### `skills.backup` / `skills.restore`
Back up or restore the entire skills library.

### `skills.delete`
Deletes a skill (`slug`: String) and removes its node from the Ontology Graph.

---

## 🎨 Design Systems Management

### `design.list` / `design.get` / `design.save` / `design.delete` / `design.addFromUrl` / `design.backup` / `design.restore` / `design.install`
Manage Markdown-based Design Systems (`id`, `name`, `content`, `url`, `data`, or base64 `zip`).

---

## ⚡ Automations & Scheduling

### `automations.list`
Lists all configured automations with serialized `humanSchedule`, `cronExpressions`, `nextRunAt`, and `isRunning`.
**Params:**
- `locale`: (String, optional) `"en"` or `"de"` (default `"en"`).

### `automations.get`
Returns a single automation, its recent `runs`, and up to 3 upcoming `nextRuns`.
**Params:**
- `id`: (String)
- `locale`: (String, optional)
- `runsLimit`: (Int, optional) Default `50`.

### `automations.create`
Creates and schedules a new automation.
**Params:**
- `title`: (String, required)
- `instructions`: (String, optional)
- `schedule`: (Object) `{ mode, times, daysOfWeek, intervalValue, intervalUnit, customCron }`
- `agentId`: (String, optional) `"auto"` (default, Ontology routing), `"default-agent"`, or custom agent ID.
- `agentName`, `providerOverride`, `modelOverride`: (String, optional)
- `enabled`: (Boolean, optional) Default `true`.

### `automations.update`
Updates an existing automation (`id`, plus optional `title`, `instructions`, `schedule`, `enabled`, `agentId`, `agentName`, `providerOverride`, `clearProviderOverride`, `modelOverride`, `clearModelOverride`).

### `automations.toggle`
Enables or pauses an automation (`id`: String, `enabled`: Boolean).

### `automations.delete`
Stops active runs and deletes an automation, its run history, and all linked `auto_<id>_*` sessions (`id`: String).

### `automations.runNow`
Triggers an immediate manual run in the background.
**Params:**
- `id`: (String)
**Response:**
- `status`: `"started"`, `run`: (Object), `runId`: (String), `sessionId`: (String)

### `automations.runs`
Lists execution history for an automation (`automationId`: String, optional `limit` default `50`).

### `automations.previewSchedule`
Validates an `AutomationSchedule` object and returns `valid`, `cronExpressions`, `humanSchedule`, and `nextRuns` (next 3 timestamps).

### `automations.previewRouting`
Runs a dry-run Ontology routing evaluation (`title`, `instructions`) and returns the `decision` breakdown.

### `automations.generateFromPrompt`
Uses the default AI provider and agent catalog to generate a complete editable automation `draft` from natural language (`prompt`, optional `locale`).

---

## 📋 Kanban & Task Management

### `kanban.list`
Lists tasks with optional filtering (`status`: `"backlog"|"inProgress"|"review"|"done"|"cancelled"`, `agentId`).

### `kanban.get`
Retrieves a specific task (`id`: String).

### `kanban.create`
Creates a new task (`title`, optional `description`, `priority`, `status`, `labels`, `assignedAgentId` incl. `"__auto__"` for Ontology routing, `assignedAgentName`, `createdByAgentId`, `dependsOnIds`).

### `kanban.update`
Updates an existing task (`id`, optional `title`, `description`, `priority`, `labels`, `assignedAgentId`, `assignedAgentName`, `clearAssignedAgent`, `dependsOnIds`, `dueDate`, `clearDueDate`).

### `kanban.move`
Changes a task's status or column position (`id`, `status`, optional `insertAt`). Automatically resolves `Auto (Ontologie)` when moving from `backlog` to `inProgress`.

### `kanban.assign`
Assigns a task to an agent (`id`, `agentId`, `agentName`). Passing `agentId: "__auto__"` triggers immediate Ontology routing.

### `kanban.route`
Explicitly runs or previews Ontology-based routing for a task.
**Params:**
- `id`: (String) Task ID.
- `dryRun`: (Boolean, optional) If true, returns the routing `decision` without modifying the task.

### `kanban.delete`
Deletes a task (`id`: String).

### `kanban.addSubtask` / `kanban.toggleSubtask` / `kanban.removeSubtask`
Manage checklist subtasks (`taskId`, `title` for add, `subtaskId` for toggle/remove).

### `kanban.addComment`
Adds a comment to a task (`taskId`, `content`, optional `authorId`, `authorName`).

---

## 📧 Email Integration

### `email.listAccounts` / `email.getAccount` / `email.saveAccount` / `email.deleteAccount` / `email.testAccount`
Manage IMAP/SMTP accounts (`id`, `account`, `imapPassword`, `smtpPassword`). Credentials are stored encrypted in the vault.

### `email.listFolders` / `email.listEmails` / `email.triggerScan`
Sync and list IMAP folders and cached emails (`accountId`, `folder`, `limit`, `offset`, `filter`, `count`).

### `email.markFlags` / `email.moveEmail` / `email.moveEmails` / `email.emptyFolder` / `email.deleteEmailPermanently` / `email.deleteEmailsPermanently`
Update read/favorite flags, move single/batch emails, empty folders, or permanently delete messages.

### `email.sendEmail` / `email.generateReply` / `email.getAttachmentNames` / `email.downloadAttachment`
Send Markdown emails via SMTP (with optional `attachmentPaths`), generate AI reply drafts (`reply`), inspect attachment names, and download attachments (`path`).

---

## 🛠️ Maintenance & System

### `config.factoryReset`
Wipes the entire application state, including all databases, automations, ontology store, and vault, then reboots into setup mode.
**Params:**
- `confirm`: (String, required if unauthenticated) Must be `"CONFIRM_RESET"`.

### `config.backup`
Creates an encrypted ZIP archive of the system state.
**Params:**
- `sections`: (Array of Strings, optional) Any combination of `["config", "vault", "sessions", "skills", "design", "automations", "memory"]` (defaults to all). When `"memory"` is included, also exports portable `ontology_backup.json`.

**Response:**
- `path`: (String) Path to the temporary ZIP file on the host.
- `filename`: (String) Suggested filename.

### `config.restore`
Restores the system from a ZIP archive (`path` or base64 `zip`) and restarts cleanly.

---

## 💬 Channel Management

### `channels.getErrors`
Retrieves current connection errors for active channels (`clear`: Boolean, `channelType`: String).

---

## 📡 Events (Server-to-Client)

The gateway broadcasts real-time events to all authenticated clients:

- `agent.stream`: Partial response token `{ "sessionId": "...", "chunk": "..." }`
- `agent.activity`: Live tool/status activity `{ "sessionId": "...", "activity": "..." }`
- `agent.response`: Final assistant message `{ "sessionId": "...", "message": { ... } }`
- `agent.error`: Turn execution error `{ "sessionId": "...", "error": "..." }`
- `agent.session_updated`: Session title, agent routing, or edit update `{ "sessionId": "...", "title": "...", ... }`
- `agent.session_deleted` / `agent.sessions_cleared`: Session deletion notifications
- `config.changed` / `skills.changed` / `design.changed`: Configuration or asset updates
- `ontology.changed`: Knowledge Graph nodes, edges, or rules updated
- `automations.changed`: Automation created, updated, deleted, or run state changed `{ "automationId": "...", "action": "..." }`
- `automations.run_updated`: Live run progress/completion `{ "automationId": "...", "run": { ... } }`
- `kanban.changed`: Task created, updated, routed, moved, or deleted
- `email.accountsChanged` / `email.changed`: Email account or mailbox updates
- `gateway.error` / `gateway.log`: Channel errors and live gateway logs

---

## 🤖 Agent Client Protocol (ACP) & Antigravity

Ghost supports the standard **Agent Client Protocol (ACP)** for AI coding environments (Google Antigravity, Zed, VS Code).

### Endpoints
- **WebSocket**: `ws://<host>:<port>/acp` (and `acp.*` methods bridged on `/`)
- **STDIO**: `dart bin/ghost_acp.dart --workspace <dir>`

### Core ACP Methods
- `initialize` / `authenticate`
- `session/new` / `session/load` / `session/prompt` / `session/cancel`
- `session/review_response` / `session/set_autopilot_mode` (`reviewMode` / `autoAccept`)
- `context/providers` & `context/query` (Workspace-RAG context)

For detailed schemas and examples, see **[Google Antigravity & ACP Guide](ANTIGRAVITY_ACP_EN.md)**.
