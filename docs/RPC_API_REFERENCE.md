# 🔌 RPC API Reference — Ghost

The Ghost Gateway communicates with clients using **JSON-RPC 2.0** over **WebSockets**. This allows for real-time, bidirectional communication between the app and the backend.

---

## 🌐 Connection Details

- **Protocol**: WebSocket (ws:// or wss://)
- **Port**: 3000 (default)
- **Endpoint**: `/`

---

## 🔐 Authentication

If authentication is enabled, you must call `auth.login` as the first message after connecting.

### `auth.login`
**Params:**
- `password`: (String) The gateway password.
- `token`: (String) Alternatively, an existing session token.

**Response:**
- `authenticated`: (Boolean)

---

## 🛠️ Gateway Control

### `gateway.status`
Returns the current status of the gateway server.
**Response:**
- `status`: "running"
- `port`: (Int)
- `clients`: (Int) Count of connected clients.
- `uptime`: (Int) Seconds since start.
- `startedAt`: (ISO String)

### `gateway.methods`
Lists all registered RPC methods.
**Response:**
- `methods`: (Array of Strings)

### `gateway.restart`
Restarts the gateway process.

---

## ⚙️ Configuration Methods

### `config.get`
Returns the complete application state.
**Response includes:**
- `agent`, `user`, `identity`, `integrations`, `channels`, `tools`, `security`, `customAgents`.
- `vault.keys`: List of keys stored in the encrypted vault.
- `tokenUsage`: Real-time token usage stats (input/output).

### `config.getKey` / `config.setKey`
Manage API keys and secrets in the vault.
**Params:**
- `service`: (String, e.g., "openai", "google_workspace", "telegram", "reown_project_id", "payment_card_number", "payment_card_holder", "payment_card_expiry", "payment_card_cvv", "agent_wallet_private_key", "binance_api_key", "binance_secret_key", "binance_demo_api_key", "binance_demo_secret_key")
- `key`: (String)

### `config.getChannelToken`
Retrieves the secure token for a communication channel.
**Params:**
- `channelId`: (String, e.g., "telegram", "whatsapp")

**Response:**
- `token`: (String)

### `config.testKey`
Tests a connection or key validity.
**Params:**
- `service`: (String)
- `key`: (String)

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
Tests if a provider/model combination supports vector embeddings.
**Params:**
- `provider`: (String)
- `model`: (String)

### `config.updateAgent` / `config.updateUser` / `config.updateIdentity` / `config.updateIntegrations` / `config.updateChannels` / `config.updateMemory` / `config.updateTools` / `config.updateSecurity` / `config.updateBilling`
Update specific configuration blocks. All sensitive data (keys, tokens) is automatically filtered into the encrypted vault and never stored in plaintext.

### `config.updateBilling`
Updates the autonomous billing and payment configuration.
**Params:**
- `limit`: (Double, optional) The maximum billing limit budget.
- `balance`: (Double, optional) The current available budget balance.
- `autonomous`: (Boolean, optional) If true, payments will be executed autonomously without human-in-the-loop (HITL) confirmation.

**Response:**
- `status`: "ok"
- `billing`: (Object) The updated billing configuration details.

### `config.getGoogleCredentials`
Retrieves the Google OAuth client IDs and secrets from the vault.

---


## 🤖 Agent Methods

### `agent.chat`
Sends a message to an agent.
**Params:**
- `content`: (String) The message text.
- `agentId`: (String, optional) The target agent profile ID.
- `sessionId`: (String, optional) Target an existing session.

**Response:**
- `sessionId`: (String)
- `status`: "processing"

### `agent.history`
Retrieves the message history for a session.
**Params:**
- `sessionId`: (String) The ID of the session.
- `maxMessages`: (Int, optional) Defaults to 50.

---

## 📂 Session Management

### `agent.sessions`
Lists all active sessions.

### `agent.deleteSession`
Deletes a specific session.
**Params:**
- `sessionId`: (String)

---

## 🧠 Memory Management

### `memory.backup` / `memory.restore`
Back up or restore the Standard (Keyword) Memory database.

### `memory.rag.backup` / `memory.rag.restore`
Back up or restore the RAG (Vector) Memory database.

### `config.clearMemory`
Wipes the specified memory database.
**Params:**
- `type`: (String, "standard" or "rag")

---

## 🛠️ Agent Management

### `config.addCustomAgent`
Creates a new custom agent.
**Params:**
- `agent`: (Object) { `name`, `systemPrompt`, `skills`, `cronSchedule`, `cronMessage`, ... }

### `config.updateCustomAgent`
Updates an existing custom agent.
**Params:**
- `agent`: (Object) { `id`, ... }

### `config.deleteCustomAgent`
Deletes a custom agent.
**Params:**
- `id`: (String) The agent ID.

---

## 📦 Skills Management

### `skills.list`
Lists all installed skills.

### `skills.create`
Creates a new skill from a template.
**Params:**
- `name`: (String)
- `description`: (String, optional)
- `type`: (String, e.g., "python", "node", "markdown")
- `emoji`: (String, optional)

### `skills.install` / `skills.import` / `skills.downloadFromGithub`
Installs a new skill from a ZIP, local directory, or GitHub URL.

### `skills.getMarkdown` / `skills.updateMarkdown`
Read or modify the Markdown-based logic of a skill.
**Params:**
- `slug`: (String)
- `content`: (String, for update)

### `skills.backup` / `skills.restore`
Back up or restore the entire skills library.

### `skills.delete`
Deletes a skill.
**Params:**
- `slug`: (String) The skill slug.

---

## 🎨 Design Systems Management

### `design.list`
Lists all installed design systems.

### `design.get`
Retrieves a specific design system.
**Params:**
- `id`: (String)

### `design.save`
Creates or updates a design system.
**Params:**
- `id`: (String)
- `name`: (String)
- `content`: (String, Markdown)

### `design.delete`
Deletes a design system.
**Params:**
- `id`: (String)

### `design.addFromUrl`
Imports a design system from a URL (e.g., a Markdown file).
**Params:**
- `url`: (String)

### `design.backup` / `design.restore`
Back up or restore the entire design systems library.

### `design.install`
Installs a design system from a ZIP archive.
**Params:**
- `zip`: (String, base64)

---

## 📋 Kanban & Task Management

### `kanban.list`
Lists tasks with optional filtering.
**Params:**
- `status`: (String, optional) e.g., "backlog", "todo", "inProgress", "done".
- `agentId`: (String, optional) Filter by assigned agent.

### `kanban.get`
Retrieves a specific task.
**Params:**
- `id`: (String)

### `kanban.create`
Creates a new task.
**Params:**
- `title`: (String)
- `description`: (String, optional)
- `priority`: (String, "urgent"|"high"|"normal"|"low")
- `status`: (String, "backlog"|"todo"|"inProgress"|"done")
- `labels`: (Array of Strings, optional)
- `assignedAgentId`: (String, optional)
- `dependsOnIds`: (Array of Strings, optional) List of task IDs this task depends on.

### `kanban.update`
Updates an existing task.
**Params:**
- `id`: (String)
- `title`, `description`, `priority`, `labels`, `assignedAgentId`, `dependsOnIds`: (Optional)
- `dueDate`: (ISO String, optional)
- `clearAssignedAgent`: (Boolean, optional)
- `clearDueDate`: (Boolean, optional)

### `kanban.move`
Changes a task's status or position.
**Params:**
- `id`: (String)
- `status`: (String)
- `insertAt`: (Int, optional) Index in the target column.

### `kanban.assign`
Assigns a task to an agent.
**Params:**
- `id`: (String)
- `agentId`: (String, optional)
- `agentName`: (String, optional)

### `kanban.delete`
Deletes a task.
**Params:**
- `id`: (String)

### `kanban.addSubtask` / `kanban.toggleSubtask` / `kanban.removeSubtask`
Manage subtasks within a task.
**Params:**
- `taskId`: (String)
- `title`: (String, for add)
- `subtaskId`: (String, for toggle/remove)

### `kanban.addComment`
Adds a comment to a task.
**Params:**
- `taskId`: (String)
- `content`: (String)
- `authorId`: (String, optional)
- `authorName`: (String, optional)

---

## 🛠️ Maintenance & System

### `config.factoryReset`
Wipes the entire application state, including all databases and the vault. Reboots the gateway into "first start" mode.

### `config.backup`
Creates an encrypted ZIP archive of the system state.
**Params:**
- `sections`: (Array of Strings, optional) e.g., `["config", "sessions", "skills", "design", "memory", "vault"]`

**Response:**
- `path`: (String) Path to the temporary ZIP file on the host.
- `filename`: (String) Suggested filename.

### `config.restore`
Restores the system from a ZIP archive.
**Params:**
- `path`: (String) Path to the ZIP file on the host.
- `zip`: (String, optional) Alternatively, base64 encoded ZIP data.

---

## 💬 Channel Management

### `channels.getErrors`
Retrieves current connection errors for all active channels.
**Params:**
- `clear`: (Boolean, optional) If true, clears the errors after reading.
- `channelType`: (String, optional) Target a specific channel.

---

## 📡 Events (Server-to-Client)

The gateway broadcasts events to all authenticated clients.

### `agent.stream`
Sent when the agent is streaming a partial response.
```json
{ "sessionId": "...", "chunk": "..." }
```

### `agent.activity`
Sent when the agent performs an action (e.g., using a tool).
```json
{ "sessionId": "...", "activity": "Searching the web..." }
```

### `agent.response`
Sent when the agent has finished its final response.
```json
{ "sessionId": "...", "message": { ... } }
```

### `config.changed`
Broadcasted when the global or agent configuration has been updated. Clients should refresh their local state.

### `skills.changed`
Broadcasted when a new skill is installed or deleted.

### `kanban.changed`
Broadcasted when a task is created, updated, moved, or deleted.

### `gateway.error`
Broadcasted when a background error occurs (e.g., channel connection failure).
```json
{ "message": "...", "channelType": "..." }
```
