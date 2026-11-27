# 🔌 RPC API Referenz — Ghost

Das Ghost Gateway kommuniziert mit Clients über **JSON-RPC 2.0** via **WebSockets**. Dies ermöglicht Echtzeit-Kommunikation in beide Richtungen zwischen App, IDE-/Browser-Erweiterungen und dem Backend.

---

## 🌐 Verbindungsdetails

- **Protokoll**: WebSocket (`ws://` oder `wss://`)
- **Port**: `3000` (Standard)
- **Endpunkt**: `/` (sowie `/acp` für das Agent Client Protocol)

---

## 🔐 Authentifizierung

Falls die Authentifizierung aktiviert ist, muss als erste Nachricht nach dem Verbindungsaufbau `auth.login` aufgerufen werden.

### `auth.login`
**Parameter:**
- `password`: (String) Das Gateway-Passwort.
- `token`: (String) Alternativ ein bestehender Sitzungs-Token.

**Antwort:**
- `authenticated`: (Boolean)

---

## 🛠️ Gateway-Steuerung

### `gateway.health`
Leichtgewichtiger Health-Check.
**Antwort:**
- `status`: `"ok"`
- `timestamp`: (ISO String)

### `gateway.status`
Liefert den aktuellen Status des Gateway-Servers.
**Antwort:**
- `status`: `"running"`
- `port`: (Int)
- `bind`: (String) Gebundene Adresse.
- `clients`: (Int) Anzahl verbundener Clients.
- `authMode`: (String) Aktiver Authentifizierungsmodus.
- `uptime`: (Int) Laufzeit in Sekunden.
- `startedAt`: (ISO String)

### `gateway.methods`
Listet alle registrierten RPC-Methoden auf (`methods`: Array von Strings).

### `gateway.restart`
Startet das Gateway (bzw. das Gesamtsystem über den Restart-Callback) neu.

---

## ⚙️ Konfigurations-Methoden

### `config.get`
Gibt den vollständigen Anwendungszustand zurück.
**Enthält u. a.:**
- `agent`, `memory`, `user`, `identity`, `integrations`, `channels`, `tools`, `security`, `customAgents`, `gateway`.
- `vault.keys`: Liste der Schlüssel im verschlüsselten Tresor.
- `detectedLocalProviders`: Automatisch erkannte lokale KI-Provider (z. B. Ollama, LM Studio).

### `config.getKey` / `config.setKey`
Verwaltet API-Schlüssel und Secrets im verschlüsselten Tresor (Vault).
**Parameter:**
- `service`: (String, z. B. `"openai"`, `"google_workspace"`, `"telegram"`, `"reown_project_id"`, `"payment_card_number"`, `"payment_card_holder"`, `"payment_card_expiry"`, `"payment_card_cvv"`, `"agent_wallet_private_key"`, `"binance_api_key"`, `"binance_secret_key"`, `"binance_demo_api_key"`, `"binance_demo_secret_key"`)
- `key`: (String; `""` löscht den Schlüssel, sofern er nicht von einem aktiven Agenten verwendet wird)

### `config.getChannelToken`
Ruft den sicheren Token für einen Kommunikationskanal ab (`channelId` → `token`).

### `config.testKey`
Testet eine Verbindung oder Schlüsselgültigkeit (`service`, `key`).

### `config.setModel`
Setzt das Modell (und optional den Provider) des Haupt-Agenten (`model`, optional `provider`).

### `config.listModels` / `config.listModelsDetailed`
Listet verfügbare Modelle für einen Provider auf (`provider`, optional `apiKey`).

### `config.getModelCapabilities`
Gibt Fähigkeiten eines Modells zurück (`provider`, `model`).

### `config.testEmbedding`
Testet, ob eine Provider-/Modell-Kombination Vektor-Embeddings unterstützt (`provider`, `model`).

### `config.updateAgent`
Aktualisiert die Konfiguration des Haupt-Agenten.
**Parameter:**
- `workspace`, `model`, `provider`, `designSystem`, `thinkingMode`: (String, optional)
- `maxTokens`: (Int, optional)
- `disabledSkills`: (Array von Strings, optional) Opt-Out-Skill-Slugs (standardmäßig sind alle installierten Skills erlaubt).
- `skills`: (Array von Strings, optional) Erlaubte Skill-Slugs (wird automatisch auf `disabledSkills` abgebildet).
- `competencies`: (Array von Strings, optional) Explizite Domänen-Tags für `HAT_KOMPETENZ`.

### `config.updateUser` / `config.updateIdentity` / `config.updateIntegrations` / `config.updateChannels` / `config.updateTools`
Aktualisiert spezifische Konfigurationsblöcke. Sensible Zugangsdaten und Token werden automatisch in den verschlüsselten Tresor verlagert.

### `config.updateMemory`
Aktualisiert Standard-Memory, RAG, Workspace-RAG und Ontologie-Einstellungen.
**Parameter:**
- `enabled`: (Boolean, optional) Standard-Speicher.
- `ragEnabled`: (Boolean, optional) ObjectBox-Vektor-RAG.
- `workspaceRagEnabled`: (Boolean, optional) Workspace-`rag/`-Indexer.
- `ontologyEnabled`: (Boolean, optional) Native ObjectBox Knowledge-Graph-Ontologie.
- `ontologyAutoExtract`: (Boolean, optional) System-1-geschützte Post-Turn-Faktenextraktion.
- `backend`, `embeddingProvider`, `embeddingModel`: (String, optional)
- `chunkSize`, `chunkOverlap`: (Int, optional)
- `vectorWeight`, `bm25Weight`: (Double, optional)

### `config.updateBilling`
Aktualisiert die autonome Abrechnungs- und Zahlungskonfiguration (`limit`, `balance`, `autonomous`).

### `config.updateSecurity`
Aktualisiert Sicherheitsrichtlinien inklusive Human-In-The-Loop und System-1 Entscheidungs-Middleware.
**Parameter:**
- `level`: (String, optional) `"none"`, `"low"`, `"medium"`, `"high"`.
- `humanInTheLoop`: (Boolean, optional) Verlangt Bestätigung vor sensiblen Aktionen und `ERFORDERT_HITL`-Skills.
- `promptHardening`: (Boolean, optional) System-Prompt-Schutz gegen Prompt-Injections/Jailbreaks.
- `restrictNetwork`: (Boolean, optional) Isoliert ausgehende Netzwerkzugriffe.
- `promptAnalyzers`: (Boolean, optional) Vorab-Analyse eingehender Prompts.
- `system1Middleware`: (Boolean, optional) Aktiviert ModernBERT INT8 ONNX für Pre-Flight-Sicherheit, Risiko-Scoring, Smart-HITL und Memory-Poisoning-Schutz.

### `config.getGoogleCredentials`
Ruft Google OAuth Client-IDs und Secret aus dem Tresor ab.

---

## 🤖 Agenten-Methoden

### `agent.chat`
Sendet eine Nachricht an einen Agenten (unterstützt `/goal` und `/plan` mit automatischem Ontologie-Routing, sofern kein Agent fest vorgegeben ist).
**Parameter:**
- `content`: (String)
- `agentId`: (String, optional; `"__auto__"` erzwingt Ontologie-Routing bei `/goal`/`/plan`)
- `sessionId`: (String, optional)
- `attachments`: (Array von Objekten, optional)
- `workspaceDir`: (String, optional)
- `channelType`, `peerId`, `groupId`, `model`, `provider`: (String, optional)

**Antwort:**
- `sessionId`: (String)
- `status`: `"processing"`

### `agent.editMessage`
Bearbeitet eine frühere Benutzernachricht, kürzt den nachfolgenden Verlauf und startet die Antwort neu.
**Parameter:**
- `sessionId`, `content`: (String)
- `userMessageIndex`: (Int, optional)
- `attachments`, `channelType`, `peerId`, `groupId`, `model`, `provider`, `agentId`, `workspaceDir`: (Optional)

### `agent.history`
Ruft den Nachrichtenverlauf einer Sitzung ab (`sessionId`, optional `maxMessages` Standard `50`).

---

## 📂 Sitzungs-Management

### `agent.sessions`
Listet alle aktiven Sitzungen auf.

### `agent.deleteSession`
Löscht eine einzelne Sitzung (`sessionId`), eine Liste im Batch (`sessionIds`) oder alle Sitzungen (`all: true`).

### `agent.deleteAllSessions`
Löscht alle gespeicherten Sitzungen und sendet `agent.sessions_cleared`.

### `agent.setSessionModel`
Aktualisiert LLM-Modell und optional Provider für eine aktive Sitzung (`sessionId`, `model`, optional `provider`).

### `agent.setSessionTitle`
Setzt manuell den Titel einer Sitzung (`sessionId`, `title`) und sendet `agent.session_updated`.

### `agent.stop`
Stoppt die laufende Ausführung/das Streaming für eine Sitzung (`sessionId`).

---

## 🧠 Memory- & Ontologie-Management

### `memory.backup` / `memory.restore`
Sichert oder stellt die Standard-Datenbank (Hive) wieder her (`data` JSON-String).

### `memory.rag.backup` / `memory.rag.restore`
Sichert oder stellt die RAG-Vektordatenbank (ObjectBox) wieder her (`data` JSON-String).

### `memory.ontology.backup` / `memory.ontology.restore`
Exportiert oder importiert den portablen Knowledge Graph als JSON (`relations`, `nodes`, `edges`).
**Parameter (restore):**
- `data`: (String) JSON-Export von `memory.ontology.backup`.

### `memory.ontology.stats`
Gibt Zähler für `relations`, `nodes`, `edges`, `skills`, `linkedSkills`, `personalEdges` und `governanceEdges` zurück.

### `memory.ontology.list`
Listet Tripel, Entitäten und T-Box-Regeln aus dem Knowledge Graph.
**Parameter:**
- `category`: (String, optional) `"all"`, `"personal"`, `"governance"` oder `"rules"`.
- `query`: (String, optional) Suchfilter über Labels, Keys, Typen oder Prädikate.
- `limit`: (Int, optional) Standard `200`.
- `offset`: (Int, optional) Standard `0`.

### `memory.ontology.assert`
Speichert oder aktualisiert ein Wissens-Tripel (sendet `ontology.changed`).
**Parameter:**
- `subject`, `predicate`, `object`: (String, erforderlich)
- `subjectType`, `objectType`, `subjectKey`: (String, optional)
- `confidence`: (Double, optional) Standard `1.0`.

### `memory.ontology.deleteEdge`
Löscht eine einzelne Kante (`edgeId`: Int).

### `memory.ontology.deleteNode`
Löscht eine Entität samt aller verknüpften Kanten (`canonicalKey`: String).

### `memory.ontology.query`
Führt eine Multi-Hop-Abfrage (`1–4` Hops) aus und liefert `result` sowie `promptPreview`.
**Parameter:**
- `entity`: (String) Entitätsname oder `canonicalKey`.
- `maxDepth`: (Int, optional) `1–4` (Standard `2`).
- `maxResults`: (Int, optional) Standard `30`.
- `includeIncoming`: (Boolean, optional) Standard `true`.

### `config.clearMemory`
Löscht die angegebene Memory-Datenbank (`type`: `"standard"`, `"rag"` oder `"ontology"`).

---

## 🛠️ Agenten-Management

### `config.addCustomAgent`
Erstellt einen neuen Custom Agent (`agent`: `{ name, systemPrompt, provider, model, disabledSkills, skills, competencies, cronSchedule, cronMessage, designSystem, enabled, ... }`).

### `config.updateCustomAgent`
Aktualisiert einen Custom Agent (`agent`: `{ id, ... }`) und synchronisiert Ontologie-Rechte und Kompetenzen.

### `config.deleteCustomAgent`
Löscht einen Custom Agent (`id`: String) inklusive Avatar.

---

## 📦 Skills Management

### `skills.list`
Listet alle installierten Skills (inkl. `category`, `requiresHitl`, `securityLevel`, `requiredSkills`).

### `skills.create`
Erstellt einen neuen Skill aus einer Vorlage (`name`, optional `description`, `type`: `"python"|"node"|"markdown"`, optional `emoji`).

### `skills.install` / `skills.import` / `skills.downloadFromGithub`
Installiert einen Skill aus Base64-ZIP (`zip`), lokalem Pfad (`path`) oder GitHub-URL (`url`) und synchronisiert Ontologie-Berechtigungen.

### `skills.getMarkdown` / `skills.updateMarkdown`
Liest oder ändert die `SKILL.md` (`slug`, sowie `content` beim Update).

### `skills.backup` / `skills.restore`
Sichert oder stellt die gesamte Skill-Bibliothek wieder her.

### `skills.delete`
Löscht einen Skill (`slug`: String) und entfernt ihn aus dem Ontologie-Graphen.

---

## 🎨 Design-System-Management

### `design.list` / `design.get` / `design.save` / `design.delete` / `design.addFromUrl` / `design.backup` / `design.restore` / `design.install`
Verwaltet Markdown-basierte Design-Systeme (`id`, `name`, `content`, `url`, `data` oder Base64-`zip`).

---

## ⚡ Automations & Zeitpläne

### `automations.list`
Listet alle Automations inklusive `humanSchedule`, `cronExpressions`, `nextRunAt` und `isRunning`.
**Parameter:**
- `locale`: (String, optional) `"de"` oder `"en"`.

### `automations.get`
Ruft eine einzelne Automation, ihre letzten `runs` sowie bis zu 3 kommende `nextRuns` ab (`id`, optional `locale`, `runsLimit` Standard `50`).

### `automations.create`
Erstellt und plant eine neue Automation.
**Parameter:**
- `title`: (String, erforderlich)
- `instructions`: (String, optional)
- `schedule`: (Object) `{ mode, times, daysOfWeek, intervalValue, intervalUnit, customCron }`
- `agentId`: (String, optional) `"auto"` (Standard, Ontologie-Routing), `"default-agent"` oder Custom-Agent-ID.
- `agentName`, `providerOverride`, `modelOverride`: (String, optional)
- `enabled`: (Boolean, optional) Standard `true`.

### `automations.update`
Aktualisiert eine bestehende Automation (`id`, optional `title`, `instructions`, `schedule`, `enabled`, `agentId`, `agentName`, `providerOverride`, `clearProviderOverride`, `modelOverride`, `clearModelOverride`).

### `automations.toggle`
Aktiviert oder pausiert eine Automation (`id`: String, `enabled`: Boolean).

### `automations.delete`
Stoppt laufende Ausführungen und löscht eine Automation samt Run-Historie und `auto_<id>_*`-Sessions (`id`: String).

### `automations.runNow`
Startet sofort einen manuellen Hintergrundlauf.
**Parameter:**
- `id`: (String)
**Antwort:**
- `status`: `"started"`, `run`: (Object), `runId`: (String), `sessionId`: (String)

### `automations.runs`
Listet die Ausführungshistorie einer Automation (`automationId`: String, optional `limit` Standard `50`).

### `automations.previewSchedule`
Validiert ein `AutomationSchedule`-Objekt und liefert `valid`, `cronExpressions`, `humanSchedule` und `nextRuns`.

### `automations.previewRouting`
Führt eine Vorschau des Ontologie-Routings durch (`title`, `instructions`) und liefert `decision`.

### `automations.generateFromPrompt`
Erzeugt mithilfe des Standard-LLMs aus einer Kurzbeschreibung (`prompt`, optional `locale`) einen vollständigen Automation-Entwurf (`draft`).

---

## 📋 Kanban & Aufgaben-Management

### `kanban.list`
Listet Aufgaben mit optionaler Filterung (`status`: `"backlog"|"inProgress"|"review"|"done"|"cancelled"`, `agentId`).

### `kanban.get`
Ruft eine spezifische Aufgabe ab (`id`: String).

### `kanban.create`
Erstellt eine neue Aufgabe (`title`, optional `description`, `priority`, `status`, `labels`, `assignedAgentId` inkl. `"__auto__"` für Ontologie-Routing, `assignedAgentName`, `createdByAgentId`, `dependsOnIds`).

### `kanban.update`
Aktualisiert eine bestehende Aufgabe (`id`, optional `title`, `description`, `priority`, `labels`, `assignedAgentId`, `assignedAgentName`, `clearAssignedAgent`, `dependsOnIds`, `dueDate`, `clearDueDate`).

### `kanban.move`
Ändert Status oder Position einer Aufgabe (`id`, `status`, optional `insertAt`). Bei Wechsel von `backlog` nach `inProgress` wird `Auto (Ontologie)` automatisch aufgelöst.

### `kanban.assign`
Weist einer Aufgabe einen Agenten zu (`id`, `agentId`, `agentName`). Mit `agentId: "__auto__"` wird direkt über die Ontologie geroutet.

### `kanban.route`
Führt das Ontologie-Routing für eine Aufgabe gezielt aus oder simuliert es.
**Parameter:**
- `id`: (String) Aufgaben-ID.
- `dryRun`: (Boolean, optional) Bei `true` wird nur `decision` berechnet, ohne den Task zu ändern.

### `kanban.delete`
Löscht eine Aufgabe (`id`: String).

### `kanban.addSubtask` / `kanban.toggleSubtask` / `kanban.removeSubtask`
Verwaltet Unteraufgaben (`taskId`, `title` für add, `subtaskId` für toggle/remove).

### `kanban.addComment`
Fügt einen Kommentar hinzu (`taskId`, `content`, optional `authorId`, `authorName`).

---

## 📧 E-Mail-Integration

### `email.listAccounts` / `email.getAccount` / `email.saveAccount` / `email.deleteAccount` / `email.testAccount`
Verwaltet IMAP/SMTP-Konten (`id`, `account`, `imapPassword`, `smtpPassword`). Passwörter werden verschlüsselt im Tresor gespeichert.

### `email.listFolders` / `email.listEmails` / `email.triggerScan`
Synchronisiert und listet IMAP-Ordner sowie zwischengespeicherte E-Mails (`accountId`, `folder`, `limit`, `offset`, `filter`, `count`).

### `email.markFlags` / `email.moveEmail` / `email.moveEmails` / `email.emptyFolder` / `email.deleteEmailPermanently` / `email.deleteEmailsPermanently`
Setzt Gelesen-/Favorit-Flags, verschiebt einzelne oder mehrere E-Mails, leert Ordner oder löscht Nachrichten endgültig.

### `email.sendEmail` / `email.generateReply` / `email.getAttachmentNames` / `email.downloadAttachment`
Sendet Markdown-E-Mails via SMTP (optional `attachmentPaths`), erstellt KI-Antwortentwürfe (`reply`), liest Anhangsnamen und lädt Anhänge herunter (`path`).

---

## 🛠️ Wartung & System

### `config.factoryReset`
Löscht den gesamten Anwendungszustand (inklusive Datenbanken, Automations, Ontologie-Store und Tresor) und startet im Setup-Modus neu.
**Parameter:**
- `confirm`: (String, erforderlich falls nicht authentifiziert) Muss `"CONFIRM_RESET"` lauten.

### `config.backup`
Erstellt ein verschlüsseltes ZIP-Archiv des Systemzustands.
**Parameter:**
- `sections`: (Array von Strings, optional) Beliebige Auswahl aus `["config", "vault", "sessions", "skills", "design", "automations", "memory"]` (Standard: alle). Bei `"memory"` wird zusätzlich ein portabler `ontology_backup.json`-Export eingebettet.

**Antwort:**
- `path`: (String) Pfad zur temporären ZIP-Datei.
- `filename`: (String) Vorgeschlagener Dateiname.

### `config.restore`
Stellt das System aus einem ZIP-Archiv (`path` oder Base64 `zip`) wieder her und startet sauber neu.

---

## 💬 Kanal-Management

### `channels.getErrors`
Ruft aktuelle Verbindungsfehler aktiver Kanäle ab (`clear`: Boolean, `channelType`: String).

---

## 📡 Events (Server-zu-Client)

Das Gateway sendet Echtzeit-Ereignisse an alle authentifizierten Clients:

- `agent.stream`: Streaming-Token `{ "sessionId": "...", "chunk": "..." }`
- `agent.activity`: Live-Aktivität / Tool-Ausführung `{ "sessionId": "...", "activity": "..." }`
- `agent.response`: Abgeschlossene Antwort `{ "sessionId": "...", "message": { ... } }`
- `agent.error`: Fehler während eines Turns `{ "sessionId": "...", "error": "..." }`
- `agent.session_updated`: Titel-, Routing- oder Bearbeitungs-Update `{ "sessionId": "...", ... }`
- `agent.session_deleted` / `agent.sessions_cleared`: Benachrichtigungen über gelöschte Sitzungen
- `config.changed` / `skills.changed` / `design.changed`: Konfigurations- oder Asset-Änderungen
- `ontology.changed`: Änderungen an Knoten, Kanten oder Regeln im Knowledge Graph
- `automations.changed`: Automation erstellt, aktualisiert, gelöscht oder Status geändert `{ "automationId": "...", "action": "..." }`
- `automations.run_updated`: Live-Updates zu einem Automation-Lauf `{ "automationId": "...", "run": { ... } }`
- `kanban.changed`: Aufgabe erstellt, aktualisiert, geroutet, verschoben oder gelöscht
- `email.accountsChanged` / `email.changed`: Änderungen an E-Mail-Konten oder Postfächern
- `gateway.error` / `gateway.log`: Kanalfehler und Live-Gateway-Logs

---

## 🤖 Agent Client Protocol (ACP) & Antigravity

Ghost unterstützt das standardisierte **Agent Client Protocol (ACP)** für KI-Entwicklungsumgebungen (Google Antigravity, Zed, VS Code).

### Endpunkte
- **WebSocket**: `ws://<host>:<port>/acp` (sowie `acp.*`-Methoden über `/`)
- **STDIO**: `dart bin/ghost_acp.dart --workspace <dir>`

### Zentrale ACP-Methoden
- `initialize` / `authenticate`
- `session/new` / `session/load` / `session/prompt` / `session/cancel`
- `session/review_response` / `session/set_autopilot_mode` (`reviewMode` / `autoAccept`)
- `context/providers` & `context/query` (Workspace-RAG Kontext)

Detaillierte Schemata und Beispiele siehe **[Google Antigravity & ACP Anleitung](ANTIGRAVITY_ACP_DE.md)**.
