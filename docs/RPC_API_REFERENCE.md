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
- `service`: (String, e.g., "openai", "anthropic", "telegram")
- `key`: (String)

### `config.updateAgent` / `config.updateUser` / `config.updateIdentity`
Update specific configuration blocks. All sensitive data is automatically filtered into the vault.

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

---

## 🛠️ Agent Management

### `config.addCustomAgent`
Creates a new custom agent.
**Params:**
- `agent`: (Object) { `name`, `systemPrompt`, `skills`, `cronSchedule`, `cronMessage`, ... }

### `config.deleteCustomAgent`
Deletes a custom agent.
**Params:**
- `id`: (String) The agent ID.

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
