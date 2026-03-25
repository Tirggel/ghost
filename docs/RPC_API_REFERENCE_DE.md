# 🔌 RPC API Referenz — Ghost

Das Ghost Gateway kommuniziert mit Clients über **JSON-RPC 2.0** via **WebSockets**. Dies ermöglicht eine Echtzeit-Kommunikation zwischen der App und dem Backend.

---

## 🌐 Verbindungsdetails

- **Protokoll**: WebSocket (ws:// oder wss://)
- **Port**: 3000 (standard)
- **Endpunkt**: `/`

---

## 🔐 Authentifizierung

Falls die Authentifizierung aktiviert ist, muss als erste Nachricht nach dem Verbindungsaufbau `auth.login` aufgerufen werden.

### `auth.login`
**Parameter:**
- `password`: (String) Das Gateway-Passwort.
- `token`: (String) Alternativ ein bestehender Sitzungs-Token.

**Antwort:**
```json
{ "authenticated": true }
```

---

## 🤖 Agenten-Methoden

### `agent.chat`
Sendet eine Nachricht an einen Agenten.
**Parameter:**
- `content`: (String) Der Nachrichtentext.
- `agentId`: (String, optional) Die Profil-ID des Zielagenten.
- `sessionId`: (String, optional) Zielt auf eine bestehende Sitzung ab.

**Antwort:**
```json
{ "sessionId": "...", "status": "processing" }
```

### `agent.history`
Ruft den Nachrichtenverlauf einer Sitzung ab.
**Parameter:**
- `sessionId`: (String) Die ID der Sitzung.
- `maxMessages`: (Int, optional) Standard ist 50.

---

## 📂 Sitzungs-Management

### `agent.sessions`
Listet alle aktiven Sitzungen auf.

### `agent.deleteSession`
Löscht eine spezifische Sitzung.
**Parameter:**
- `sessionId`: (String)

---

## 🧠 Memory-Management

### `memory.backup` / `memory.restore`
Sichert oder stellt die Standard-Datenbank (Stichworte) wieder her.

### `memory.rag.backup` / `memory.rag.restore`
Sichert oder stellt die RAG-Datenbank (Vektoren) wieder her.

---

## 🛠️ Agenten-Management

### `config.addCustomAgent`
Erstellt einen neuen Custom Agent.
**Parameter:**
- `agent`: (Object) { `name`, `systemPrompt`, `skills`, `cronSchedule`, `cronMessage`, ... }

### `config.deleteCustomAgent`
Löscht einen Custom Agent.
**Parameter:**
- `id`: (String) Die Agenten-ID.

---

## 📡 Events (Server-zu-Client)

Das Gateway sendet Ereignisse (Broadcasts) an alle authentifizierten Clients.

### `agent.stream`
Gesendet, während der Agent eine Antwort streamt.
```json
{ "sessionId": "...", "chunk": "..." }
```

### `agent.activity`
Gesendet, wenn der Agent eine Aktion ausführt (z. B. ein Werkzeug nutzt).
```json
{ "sessionId": "...", "activity": "Suche im Internet..." }
```

### `agent.response`
Gesendet, wenn der Agent seine finale Antwort abgeschlossen hat.
```json
{ "sessionId": "...", "message": { ... } }
```
### `config.changed`
Wird gesendet (Broadcast), wenn sich die globale oder eine Agenten-Konfiguration geändert hat. Clients sollten ihren lokalen Zustand aktualisieren.

### `skills.changed`
Wird gesendet, wenn ein neuer Skill installiert oder gelöscht wurde.
