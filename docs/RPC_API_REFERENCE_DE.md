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
- `service`: (String, z.B. "openai", "google_workspace", "telegram", "reown_project_id", "payment_card_number", "payment_card_holder", "payment_card_expiry", "payment_card_cvv", "agent_wallet_private_key", "binance_api_key", "binance_secret_key", "binance_demo_api_key", "binance_demo_secret_key")
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

### `config.updateAgent` / `config.updateUser` / `config.updateIdentity` / `config.updateIntegrations` / `config.updateChannels` / `config.updateMemory` / `config.updateTools` / `config.updateSecurity` / `config.updateBilling`
Aktualisiert spezifische Konfigurationsblöcke. Alle sensiblen Daten (Schlüssel, Token) werden automatisch in den verschlüsselten Tresor gefiltert und niemals im Klartext gespeichert.

### `config.updateBilling`
Aktualisiert die autonome Abrechnungs- und Zahlungskonfiguration.
**Parameter:**
- `limit`: (Double, optional) Das maximale Abrechnungsbudget.
- `balance`: (Double, optional) Das aktuell verfügbare Budget.
- `autonomous`: (Boolean, optional) Falls true, werden Zahlungen selbstständig ohne HITL-Freigabe (Human-In-The-Loop) ausgeführt.

**Antwort:**
- `status`: "ok"
- `billing`: (Object) Die aktualisierten Details der Abrechnungskonfiguration.

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

### `agent.setSessionModel`
Aktualisiert das LLM-Modell und den Provider für eine aktive Sitzung.
**Parameter:**
- `sessionId`: (String)
- `model`: (String)
- `provider`: (String, optional)

### `agent.setSessionTitle`
Aktualisiert manuell den Titel einer Sitzung.
**Parameter:**
- `sessionId`: (String)
- `title`: (String)

### `agent.stop`
Stoppt oder unterbricht die aktive Agenten-Ausführung / das Streaming der Antwort für eine Sitzung.
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

### `skills.create`
Erstellt einen neuen Skill aus einer Vorlage.
**Parameter:**
- `name`: (String)
- `description`: (String, optional)
- `type`: (String, z.B. "python", "node", "markdown")
- `emoji`: (String, optional)

### `skills.install` / `skills.import` / `skills.downloadFromGithub`
Installiert einen neuen Skill aus einem ZIP, einem lokalen Verzeichnis oder einer GitHub-URL.

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

## 🎨 Design-System-Management

### `design.list`
Listet alle installierten Design-Systeme auf.

### `design.get`
Ruft ein spezifisches Design-System ab.
**Parameter:**
- `id`: (String)

### `design.save`
Erstellt oder aktualisiert ein Design-System.
**Parameter:**
- `id`: (String)
- `name`: (String)
- `content`: (String, Markdown)

### `design.delete`
Löscht ein Design-System.
**Parameter:**
- `id`: (String)

### `design.addFromUrl`
Importiert ein Design-System von einer URL (z. B. einer Markdown-Datei).
**Parameter:**
- `url`: (String)

### `design.backup` / `design.restore`
Sichert oder stellt die gesamte Design-System-Bibliothek wieder her.

### `design.install`
Installiert ein Design-System aus einem ZIP-Archiv.
**Parameter:**
- `zip`: (String, Base64)

---

## 📋 Kanban & Aufgaben-Management

### `kanban.list`
Listet Aufgaben mit optionaler Filterung auf.
**Parameter:**
- `status`: (String, optional) z.B. "backlog", "todo", "inProgress", "done".
- `agentId`: (String, optional) Filtert nach zugewiesenem Agenten.

### `kanban.get`
Ruft eine spezifische Aufgabe ab.
**Parameter:**
- `id`: (String)

### `kanban.create`
Erstellt eine neue Aufgabe.
**Parameter:**
- `title`: (String)
- `description`: (String, optional)
- `priority`: (String, "urgent"|"high"|"normal"|"low")
- `status`: (String, "backlog"|"todo"|"inProgress"|"done")
- `labels`: (Array von Strings, optional)
- `assignedAgentId`: (String, optional)
- `dependsOnIds`: (Array von Strings, optional) Liste von Aufgaben-IDs, von denen diese Aufgabe abhängt.

### `kanban.update`
Aktualisiert eine bestehende Aufgabe.
**Parameter:**
- `id`: (String)
- `title`, `description`, `priority`, `labels`, `assignedAgentId`, `dependsOnIds`: (Optional)
- `dueDate`: (ISO String, optional)
- `clearAssignedAgent`: (Boolean, optional)
- `clearDueDate`: (Boolean, optional)

### `kanban.move`
Ändert den Status oder die Position einer Aufgabe.
**Parameter:**
- `id`: (String)
- `status`: (String)
- `insertAt`: (Int, optional) Index in der Zielspalte.

### `kanban.assign`
Weist einer Aufgabe einen Agenten zu.
**Parameter:**
- `id`: (String)
- `agentId`: (String, optional)
- `agentName`: (String, optional)

### `kanban.delete`
Löscht eine Aufgabe.
**Parameter:**
- `id`: (String)

### `kanban.addSubtask` / `kanban.toggleSubtask` / `kanban.removeSubtask`
Verwaltet Unteraufgaben (Subtasks).
**Parameter:**
- `taskId`: (String)
- `title`: (String, für add)
- `subtaskId`: (String, für toggle/remove)

### `kanban.addComment`
Fügt einer Aufgabe einen Kommentar hinzu.
**Parameter:**
- `taskId`: (String)
- `content`: (String)
- `authorId`: (String, optional)
- `authorName`: (String, optional)

---

## 📧 E-Mail-Integration

### `email.listAccounts`
Listet alle konfigurierten IMAP/SMTP-E-Mail-Konten auf.
**Antwort:**
- `accounts`: (Array of Objects) Liste der konfigurierten E-Mail-Konten.

### `email.getAccount`
Ruft die Konfiguration eines bestimmten E-Mail-Kontos ab.
**Parameter:**
- `id`: (String) Die ID des Kontos.
**Antwort:**
- `account`: (Object) Kontodetails.

### `email.saveAccount`
Speichert oder aktualisiert die Konfiguration eines E-Mail-Kontos. Vertrauliche Passwörter (IMAP/SMTP) werden sicher im Tresor (Vault) hinterlegt.
**Parameter:**
- `account`: (Object) Konfigurationsfelder des Kontos.
- `imapPassword`: (String, optional) IMAP-Passwort.
- `smtpPassword`: (String, optional) SMTP-Passwort.

### `email.deleteAccount`
Löscht ein konfiguriertes E-Mail-Konto.
**Parameter:**
- `id`: (String) Die ID des Kontos.

### `email.testAccount`
Testet die Verbindung und die Zugangsdaten für IMAP- und SMTP-Server.
**Parameter:**
- `account`: (Object) Konfigurationsfelder des Kontos.
- `imapPassword`: (String, optional) IMAP-Passwort.
- `smtpPassword`: (String, optional) SMTP-Passwort.
**Antwort:**
- `success`: (Boolean) True, wenn die Verbindungstests erfolgreich sind.

### `email.listFolders`
Listet die E-Mail-Ordner auf dem IMAP-Server auf.
**Parameter:**
- `accountId`: (String) Die ID des E-Mail-Kontos.
**Antwort:**
- `folders`: (Array of Objects) Ordnernamen und E-Mail-Zähler.

### `email.listEmails`
Listet die zwischengespeicherten E-Mails eines bestimmten Ordners auf. Unterstützt Paginierung und Filterung.
**Parameter:**
- `accountId`: (String)
- `folder`: (String, optional) z.B. "INBOX".
- `limit`: (Int, optional) Standard ist 50.
- `offset`: (Int, optional) Standard ist 0.
- `filter`: (String, optional) Suchbegriff.
**Antwort:**
- `emails`: (Array of Objects) Liste der zwischengespeicherten E-Mails.

### `email.markFlags`
Aktualisiert den Gelesen-Status oder die Markierung (Favorit) einer E-Mail.
**Parameter:**
- `accountId`: (String)
- `emailId`: (String)
- `isRead`: (Boolean, optional)
- `isFavorite`: (Boolean, optional)

### `email.moveEmail`
Verschiebt eine einzelne E-Mail in einen anderen Ordner.
**Parameter:**
- `accountId`: (String)
- `emailId`: (String)
- `targetFolder`: (String)

### `email.emptyFolder`
Löscht alle E-Mails in einem Ordner (z.B. Papierkorb oder Spam) unwiderruflich.
**Parameter:**
- `accountId`: (String)
- `folder`: (String)

### `email.deleteEmailPermanently`
Löscht eine E-Mail unwiderruflich vom Server.
**Parameter:**
- `accountId`: (String)
- `emailId`: (String)

### `email.moveEmails`
Verschiebt eine Liste von E-Mails in einen anderen Ordner.
**Parameter:**
- `accountId`: (String)
- `emailIds`: (Array von Strings)
- `targetFolder`: (String)

### `email.deleteEmailsPermanently`
Löscht eine Liste von E-Mails unwiderruflich vom Server.
**Parameter:**
- `accountId`: (String)
- `emailIds`: (Array von Strings)

### `email.sendEmail`
Sendet eine neue E-Mail via SMTP.
**Parameter:**
- `accountId`: (String)
- `to`: (String) Empfängeradresse.
- `subject`: (String) E-Mail-Betreff.
- `bodyMarkdown`: (String) E-Mail-Text in Markdown-Format.
- `attachmentPaths`: (Array von Strings, optional) Dateipfade von Anhängen auf dem Host-System.

### `email.generateReply`
Generiert mittels KI einen Antwortentwurf basierend auf der E-Mail und dem Schreibstil des Nutzers.
**Parameter:**
- `accountId`: (String)
- `emailId`: (String)
**Antwort:**
- `reply`: (String) Generierter Antwortentwurf.

### `email.downloadAttachment`
Lädt einen E-Mail-Anhang auf das Host-System herunter.
**Parameter:**
- `accountId`: (String)
- `emailId`: (String)
- `fileName`: (String) Name der Anhangsdatei.
**Antwort:**
- `path`: (String) Absoluter Pfad zur heruntergeladenen Datei.

### `email.getAttachmentNames`
Ruft alle Anhangsnamen für eine E-Mail ab.
**Parameter:**
- `accountId`: (String)
- `emailId`: (String)
**Antwort:**
- `names`: (Array von Strings) Liste von Dateinamen.

### `email.triggerScan`
Triggert manuell eine Postfach-Synchronisierung für einen Ordner.
**Parameter:**
- `accountId`: (String)
- `folder`: (String, optional) Standard ist "INBOX".
- `count`: (Int, optional) Anzahl der abzurufenden E-Mails.
**Antwort:**
- `status`: "synced"

---

## 🛠️ Wartung & System

### `config.factoryReset`
Löscht den gesamten Anwendungszustand, einschließlich aller Datenbanken und des Tresors. Startet das Gateway im "Erststart"-Modus neu.

### `config.backup`
Erstellt ein verschlüsseltes ZIP-Archiv des Systemzustands.
**Parameter:**
- `sections`: (Array von Strings, optional) z.B. `["config", "sessions", "skills", "design", "memory", "vault"]`

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

### `kanban.changed`
Wird gesendet, wenn eine Aufgabe erstellt, aktualisiert, verschoben oder gelöscht wurde.

### `gateway.error`
Wird gesendet, wenn ein Hintergrundfehler auftritt (z. B. Verbindungsfehler eines Kanals).

### `email.accountsChanged`
Wird gesendet, wenn E-Mail-Konten gespeichert oder gelöscht werden.

### `email.changed`
Wird gesendet, wenn E-Mails aktualisiert, gelöscht oder synchronisiert wurden.
```json
{ "accountId": "...", "emailId": "..." }
```
