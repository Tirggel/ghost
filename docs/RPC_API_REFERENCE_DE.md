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

## ⚙️ Konfigurations-Methoden

### `config.get`
Gibt den vollständigen Anwendungszustand zurück.

### `config.getKey` / `config.setKey`
Verwaltet API-Schlüssel im verschlüsselten Tresor (Vault).
**Parameter:**
- `service`: (String, z.B. "openai", "google_workspace", "telegram")
- `key`: (String)

### `config.getChannelToken`
Ruft den sicheren Token für einen Kommunikationskanal ab.
**Parameter:**
- `channelId`: (String, z.B. "telegram", "whatsapp")

**Antwort:**
- `token`: (String)

### `config.testKey`
Testet eine Verbindung oder die Gültigkeit eines Schlüssels.

### `config.listModels` / `config.listModelsDetailed`
Listet verfügbare Modelle für einen Provider auf.
**Parameter:**
- `provider`: (String)
- `apiKey`: (String, optional)

### `config.getModelCapabilities`
Gibt Details darüber zurück, was ein bestimmtes Modell unterstützt (z. B. Tools, Vision).
**Parameter:**
- `provider`: (String)
- `model`: (String)

### `config.testEmbedding`
Testet, ob eine Provider/Modell-Kombination Vektor-Embeddings unterstützt.
**Parameter:**
- `provider`: (String)
- `model`: (String)

### `config.updateAgent` / `config.updateUser` / `config.updateIdentity` / `config.updateIntegrations` / `config.updateChannels` / `config.updateMemory` / `config.updateTools` / `config.updateSecurity`
Aktualisiert spezifische Konfigurationsblöcke. Alle sensiblen Daten (Schlüssel, Token) werden automatisch in den verschlüsselten Tresor gefiltert und niemals im Klartext gespeichert.

### `config.getGoogleCredentials`
Ruft die Google OAuth Client-IDs und Secrets aus dem Tresor ab.

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

### `config.clearMemory`
Löscht die angegebene Memory-Datenbank.
**Parameter:**
- `type`: (String, "standard" oder "rag")

---

## 🛠️ Agenten-Management

### `config.addCustomAgent`
Erstellt einen neuen Custom Agent.
**Parameter:**
- `agent`: (Object) { `name`, `systemPrompt`, `skills`, `cronSchedule`, `cronMessage`, ... }

### `config.updateCustomAgent`
Aktualisiert einen bestehenden Custom Agent.
**Parameter:**
- `agent`: (Object) { `id`, ... }

### `config.deleteCustomAgent`
Löscht einen Custom Agent.
**Parameter:**
- `id`: (String) Die Agenten-ID.

---

## 📦 Skills Management

### `skills.list`
Listet alle installierten Skills auf.

### `skills.install` / `skills.import` / `skills.downloadFromGithub`
Installiert einen neuen Skill aus einem ZIP, einem lokalen Verzeichnis oder einer GitHub-URL.

### `skills.updateGlobal`
Aktiviert oder deaktiviert einen Skill global für alle Agenten.
**Parameter:**
- `slug`: (String)
- `isGlobal`: (Boolean)

### `skills.getMarkdown` / `skills.updateMarkdown`
Liest oder ändert die Markdown-basierte Logik eines Skills.
**Parameter:**
- `slug`: (String)
- `content`: (String, für Update)

### `skills.backup` / `skills.restore`
Sichert oder stellt die gesamte Skill-Bibliothek wieder her.

### `skills.delete`
Löscht einen Skill.
**Parameter:**
- `slug`: (String) Der Skill-Slug.

---

## 🛠️ Wartung & System

### `config.factoryReset`
Löscht den gesamten Anwendungszustand, einschließlich aller Datenbanken und des Tresors. Startet das Gateway im "Erststart"-Modus neu.

### `config.backup`
Erstellt ein verschlüsseltes ZIP-Archiv des Systemzustands.
**Parameter:**
- `sections`: (Array von Strings, optional) z.B. `["config", "sessions", "skills", "memory", "vault"]`

**Antwort:**
- `path`: (String) Pfad zur temporären ZIP-Datei auf dem Host.
- `filename`: (String) Vorgeschlagener Dateiname.

### `config.restore`
Stellt das System aus einem ZIP-Archiv wieder her.
**Parameter:**
- `path`: (String) Pfad zur ZIP-Datei auf dem Host.
- `zip`: (String, optional) Alternativ Base64-kodierte ZIP-Daten.

---

## 💬 Kanal-Management

### `channels.getErrors`
Ruft aktuelle Verbindungsfehler für alle aktiven Kanäle ab.
**Parameter:**
- `clear`: (Boolean, optional) Wenn true, werden die Fehler nach dem Lesen gelöscht.
- `channelType`: (String, optional) Zielt auf einen bestimmten Kanal ab.

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
