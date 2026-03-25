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
```json
{ "authenticated": true }
```

---

## 🤖 Agent Methods

### `agent.chat`
Sends a message to an agent.
**Params:**
- `content`: (String) The message text.
- `agentId`: (String, optional) The target agent profile ID.
- `sessionId`: (String, optional) Target an existing session.

**Response:**
```json
{ "sessionId": "...", "status": "processing" }
```

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
