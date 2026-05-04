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
- `service`: (String, e.g., "openai", "google_workspace", "telegram")
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

### `config.updateAgent` / `config.updateUser` / `config.updateIdentity` / `config.updateIntegrations` / `config.updateChannels` / `config.updateMemory` / `config.updateTools` / `config.updateSecurity`
Update specific configuration blocks. All sensitive data (keys, tokens) is automatically filtered into the encrypted vault and never stored in plaintext.

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

### `skills.install` / `skills.import` / `skills.downloadFromGithub`
Installs a new skill from a ZIP, local directory, or GitHub URL.

### `skills.updateGlobal`
Enables or disables a skill globally for all agents.
**Params:**
- `slug`: (String)
- `isGlobal`: (Boolean)

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

## 🛠️ Maintenance & System

### `config.factoryReset`
Wipes the entire application state, including all databases and the vault. Reboots the gateway into "first start" mode.

### `config.backup`
Creates an encrypted ZIP archive of the system state.
**Params:**
- `sections`: (Array of Strings, optional) e.g., `["config", "sessions", "skills", "memory", "vault"]`

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

### `gateway.error`
Broadcasted when a background error occurs (e.g., channel connection failure).
```json
{ "message": "...", "channelType": "..." }
```
