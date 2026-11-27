# Ghost

<p align="center">
  <img src="assets/icons/logo/ghost.png" width="150" alt="Ghost Logo">
</p>

> [!WARNING]
> **Alpha-Version & Sicherheitshinweis**: Dies ist eine frühe Alpha-Version von Ghost. Die Software befindet sich in aktiver Entwicklung und kann kritische Fehler enthalten.
>
> *   **KI-Risiken**: KI-Modelle können "halluzinieren" (falsche Informationen als Fakten darstellen).
> *   **Sicherheit**: Prompt-Injection-Angriffe sind möglich, bei denen die KI durch manipulierte Eingaben zu unerwünschten Aktionen verleitet werden kann.
> *   **Konten & Daten**: Nutzen Sie Ghost ausschließlich mit **Test-Accounts** für verbundene Dienste (APIs, Google Workspace, etc.). Verwenden Sie niemals Ihre echten Primär- oder Produktions-Accounts.
> *   **Haftungsausschluss**: Die Nutzung erfolgt auf eigene Gefahr in einer **sicheren, isolierten Umgebung**. Es wird keine Haftung für Schäden, Datenverlust oder unerwartete Aktionen der KI übernommen.

<a href="https://aquawitchcode.dev/">Entwickler-Website</a> &nbsp; &bull; &nbsp; <a href="README.md">English</a>

**Ghost** ist ein schlanker, selbst-gehosteter persönlicher KI-Assistent, der mit den von Google entwickelten Technologien [Dart](https://github.com/dart-lang) und [Flutter](https://github.com/flutter) realisiert wurde.

### 🏗️ Architektur auf einen Blick

Ghost bietet eine moderne, integrierte Architektur:
- **Integrierte Engine**: Ein hochperformantes Backend, das KI-Agenten, Speicher und Werkzeuge verwaltet—direkt in die Anwendung integriert.
- **Sleek UI**: Eine minimalistische, leistungsstarke Benutzeroberfläche für Desktop (Linux, macOS, Windows) und Web.
- **Agenten & Skills**: Erweiterbare KI-Fähigkeiten über ein modulares, Markdown-basiertes System mit **Opt-Out Progressive Skill Loading** (`disabledSkills` & On-Demand-Laden via `ghost_load_skill`).
- **Kanban & Task-Orchestrierung**: Integriertes Multi-Agenten-Kanban-System für automatisiertes Aufgabenmanagement, Abhängigkeitsverfolgung (`dependsOnIds`), autonome Workflow-Übergänge sowie **ontologiegestütztes Multi-Agent-Routing & Delegation** (`HAT_KOMPETENZ`, `ghost_delegate_task`).
- **Automations & Geplante Workflows**: Eigener Automations-Arbeitsbereich mit lesbaren Zeitplänen, `+ Create with Prompt`-KI-Assistent, dynamischem `Auto (Ontologie)`-Agent-Routing, Provider-/Modell-Overrides und persistenter Run-Historie samt vollständigen Chat-Transkripten.
- **Design Systems**: Zentrale Theme-Verwaltung mit individuellem Branding, Markdown-basiertem Styling ("The Monolith") und einheitlicher Token-Verteilung.
- **Memory Engine**: Dreistufiges lokales Wissen mit Hive (Standard), ObjectBox (Workspace- & Langzeit-RAG) sowie einer **nativen ObjectBox-Ontologie & Knowledge-Graph-Memory** (T-Box/A-Box-Regeln, Multi-Hop-Inferenz und Monolith Graph-Explorer).
- **System-1 Entscheidungs-Middleware**: Ultraschnelle, nicht-autoregressive lokale ModernBERT INT8 ONNX Engine für Sub-15ms Vorab-Sicherheitsprüfungen, Choice-Routing, Tool-Payload-Risikobewertung, smarte HITL-Freigabeprüfung und Memory-Poisoning-Schutz.
- **Google Antigravity & ACP**: Nativer Agent Client Protocol (ACP) Adapter über STDIO und WebSocket, der Ghost als autonomen Coding-Agenten mit Antigravity CLI (`agy`), der Antigravity IDE und Zed verbindet.

---

## 🚀 Installation & Setup

> 💡 **Tipp**: Wenn du Ghost einfach nur nutzen möchtest, kannst du die fertig zusammengestellten Desktop-Programme für **Linux**, **Windows** und **macOS** direkt unter **[GitHub Releases](https://github.com/Tirggel/ghost/releases)** (oder lokal unter **[ghost-releases](./ghost-releases)**) herunterladen 😊
>
> *Die folgende Installationsanleitung richtet sich an **Entwickler**, die Ghost selbst bauen oder modifizieren möchten.*

Um mit Ghost zu starten, folge bitte unserer detaillierten Installationsanleitung:

👉 **[Installation & Setup Guide (English)](docs/installation/INSTALLATION_EN.md)**
👉 **[Installs- & Setup-Anleitung (Deutsch)](docs/installation/INSTALLATION_DE.md)**

### 🪄 Erststart: Einfache Einrichtung
Ghost ist so konzipiert, dass es direkt einsatzbereit ist. Beim ersten Start führt dich ein interaktiver **Einrichtungsassistent** durch die Konfiguration.

Wenn du das Projekt aus dem Quellcode baust, führe einfach Folgendes aus:
```bash
flutter run
```

> [!IMPORTANT]
> **Sicherheitseinstellungen nach der Erstinstallation überprüfen!**
> Nach einem Reset werden alle Sicherheitseinstellungen auf **Level "none" (alles deaktiviert)** zurückgesetzt.
> Öffne nach dem ersten Start die App und navigiere zu **Einstellungen → Sicherheit**, um die Einstellungen deinen Bedürfnissen anzupassen:
>
> | Einstellung | Beschreibung | Empfehlung |
> |---|---|---|
> | **Human-In-The-Loop (HITL)** | Fordert Bestätigung vor sensiblen Aktionen | ✅ Aktivieren |
> | **Prompt-Härtung** | Schützt vor Jailbreaks & Prompt-Injection | ✅ Aktivieren |
> | **System-1 Middleware** | Ultraschnelles ModernBERT-INT8-Modell für Pre-Flight-Sicherheit & smartes HITL | ✅ Aktivieren (sofern Modell vorhanden) |
> | **Netzwerk-Einschränkung** | Isoliert Web-Tools bei hohem Sicherheitsniveau | ⚠️ Nach Bedarf |
> | **Prompt-Analyzer** | Erweiterte Analyse eingehender Prompts | ⚠️ Nach Bedarf |
>
> Für normale Nutzung empfiehlt sich mindestens **Level "medium"** (HITL + Prompt-Härtung aktiv).

### 🪄 Setup-Assistent & Wiederherstellung
Für neue Benutzer bietet Ghost einen interaktiven **Einrichtungsassistenten**, der automatisch startet, wenn die Anwendung noch nicht konfiguriert ist.

> [!TIP]
> **System-Wiederherstellung**: Wenn du bereits ein Backup hast, kannst du dieses direkt im ersten Schritt des Assistenten hochladen. Ghost stellt dann automatisch alle Agenten, Einstellungen und sogar deine verschlüsselten API-Token wieder her.

### 🛠️ Wartung & Backup
Ghost verfügt über einen dedizierten **Zurücksetzen / Wartungs-Tab** (**Einstellungen → Zurücksetzen**), der dir volle Kontrolle über dein System gibt:
- **Factory Reset**: Vollständiges Zurücksetzen der Anwendung und Datenbanken mit explizitem Bestätigungsschutz (`CONFIRM_RESET`), geräuschlosem, hochperformantem Reset und automatischem Neustart.
- **System-Backup**: Erstellt ein selektives, verschlüsseltes ZIP-Archiv deiner Konfiguration (`config`, `vault`, `sessions`, `skills`, `design`, `automations` sowie `memory` inklusive portablem `ontology_backup.json`-Export).
- **Wiederherstellung**: Importiert ein Backup-Archiv und stellt den Zustand deines Ghost-Assistenten nahtlos und ohne UI-Unterbrechungen wieder her.
- **Design Systems**: Verwalte, exportiere und stelle visuelle Themes unabhängig wieder her.

### 📚 Weiterführende Dokumentation
- **[Ontologie & Knowledge-Graph-Anleitung](docs/ONTOLOGY_DE.md)**: T-Box/A-Box-Schema, 17 Standard-Prädikate, Multi-Hop Graph-Explorer und System-1 Memory-Poisoning-Schutz.
- **[Automations & Geplante Workflows](docs/AUTOMATIONS_DE.md)**: Eigener Automations-Arbeitsbereich, `+ Create with Prompt`-Assistent, 6 Zeitplan-Modi, `Auto (Ontologie)`-Routing und Lauf-Transkripte.
- **[System-1 Entscheidungs-Middleware](docs/SYSTEM1_MIDDLEWARE_DE.md)**: Detaillierte Architektur, Datensatzgenerierung, Training in Colab und Sub-15ms lokale ModernBERT-INT8-Entscheidungs-Engine.
- **[Google Workspace Setup](docs/GOOGLE_WORKSPACE_SETUP_DE.md)**: Anleitung zur Konfiguration von Gmail, Kalender und Drive.
- **[Microsoft 365 Setup](docs/MICROSOFT_365_SETUP_DE.md)**: Anleitung zur Konfiguration von Outlook und OneDrive via Azure AD.
- **[Zahlungs-, Wallet- & Binance-Einrichtung](docs/PAYMENTS_SETUP_DE.md)**: Anleitung zur Konfiguration von Kreditkarten, EVM-Blockchain-Wallets und Binance-API-Handel (einschließlich Spot- und Demo-Konten).
- **[Skills Development Guide](docs/SKILLS_GUIDE_DE.md)**: Erfahre alles über Opt-Out-Berechtigungen, Progressive Disclosure (`ghost_load_skill`) und das Erstellen eigener KI-Skills.
- **[STT & TTS Setup](docs/STT_TTS_SETUP_DE.md)**: Konfiguriere lokale Spracherkennung und -synthese.
- **[Multi-Channel Setup](docs/CHANNELS_DE.md)**: Detaillierte Anleitung für Telegram, Discord, WhatsApp & Co.
- **[RPC API Referenz](docs/RPC_API_REFERENCE_DE.md)**: Vollständige Dokumentation der JSON-RPC 2.0 Schnittstelle (inklusive Automations, Ontologie, Kanban, E-Mail und ACP).
- **[VS Code Extension](docs/VSCODE_EXTENSION_DE.md)**: Offizielle Erweiterung für Visual Studio Code mit Seitenleisten-Chat, Modellwechsel, Sitzungsverwaltung und Editor-Aktionen.
- **[Chrome Extension](docs/CHROME_EXTENSION_DE.md)**: Offizielle Erweiterung für Google Chrome mit Side Panel Chat, Web-Kontext, Modell-Auswahl und Kontextmenü-Aktionen.
- **[Kanban & Task-Orchestrierung](docs/KANBAN_ORCHESTRATION_de.md)**: Funktionsweise des Multi-Agenten-Kanban, Ontologie-Routing, `/goal`, `/plan` und `ghost_delegate_task`.
- **[Google Antigravity & ACP Anleitung](docs/ANTIGRAVITY_ACP_DE.md)**: Ghost mit Google Antigravity CLI (`agy`), Zed und Antigravity IDE mit Guarded Autopilot verbinden.
- **[Design-System-Richtlinien](DESIGN.md)**: Spezifikationen und Anpassungshandbuch für das visuelle Theme („The Monolith“).


---

## 🌟 Funktionen

- **Multi-Modell-Unterstützung**: Nutze Anthropic (Claude), OpenAI (GPT), Google (Gemini), DeepSeek, Mistral, Groq, Together AI, Perplexity, X.AI (Grok) oder lokale Modelle via **LM Studio**, Ollama und OpenRouter.
    - **Google Gemini 2.5 & 3**: Umfassende Unterstützung für Gemini 1.5, 2.0, 2.5 (`gemini-2.5-flash`) und Gemini 3 Modelle. Beinhaltet natives Multi-Turn Function Calling mit Erhaltung kryptografischer Thought-Signatures (`thought_signature`), automatischer Fallback-Absicherung (`skip_thought_signature_validator`) und sauberer Trennung interner Denk-Token (`reasoningContent`) von der sichtbaren Textausgabe.
    - **Streaming & Reasoning-Modelle**: Echtzeit-SSE-Streaming mit intelligenter Drosselung/Pufferung, paralleler Tool-Call-Akkumulation und dedizierter Unterstützung für Denk-Modelle (z. B. DeepSeek Reasoner, OpenAI o1/o3-mini).
    - **Tool-Call-Verlaufshygiene**: Automatisierte Bereinigung von Multi-Turn-Nachrichten für Anthropic-, Gemini- und OpenAI-Provider. Tool-Calls des Assistenten werden nur dann an die API übermittelt, wenn direkt eine zugehörige Tool-Response folgt. Dies verhindert Validierungsfehler beim Laden persistierter Verläufe.
    - **Lokale KI-Souveränität**: Vollständige Offline-Privatsphäre mit LM Studio, Ollama und vLLM.
- **Multi-Agenten-Kanban-System**:
    - **Task-Orchestrierung**: Phase 3 der Aufgaben-Orchestrierung mit automatisierten Statusübergängen.
    - **Abhängigkeiten**: Aufgaben können von anderen Aufgaben abhängen (`dependsOnIds`), was komplexe Projekt-Workflows ermöglicht.
    - **Automatisierte Ausführung**: Der Hintergrund-`TaskOrchestrator` verschiebt Aufgaben automatisch vom "Backlog" nach "To Do", sobald die Voraussetzungen erfüllt sind.
    - **Zielorientierte Ausführung (`/goal`)**: Nachrichten, die mit `/goal` beginnen, erstellen automatisch eine Kanban-Aufgabe. Der Agent startet eine autonome Schleife mit mehreren Schritten zur Erreichung des Ziels und aktualisiert den Status sowie die Kommentare. Nach erfolgreichem Abschluss wird die Aufgabe auf `done` (erledigt) gesetzt, bei Fehlern auf `review` (Überprüfung) mit detaillierten Fehlerspuren.
    - **Strukturierter Planungsmodus (`/plan`)**: Nachrichten, die mit `/plan` beginnen, erstellen eine Kanban-Aufgabe und weisen den Agenten an, eine schreibgeschützte Architekturanalyse und eine schrittweise Roadmap zu erstellen, ohne den Codebestand vorab zu verändern. Nach Fertigstellung wechselt die Aufgabe in den Status `review` (Überprüfung) zur Begutachtung durch den Nutzer oder zur `/goal`-Ausführung.
    - **Ontologiegestütztes Multi-Agent-Routing & Delegation**:
        - **Automatische Kompetenz-Ableitung (`HAT_KOMPETENZ`)**: Leitet Domänenkompetenzen im Knowledge Graph automatisch aus expliziten `competencies`-Tags, Profil-/Prompt-Schlüsselwörtern (`AgentDomainTaxonomy`) und erlaubten Skill-Domänen (`DARF_NUTZEN` → `GEHOERT_ZU_DOMAIN`) ab.
        - **Intelligentes `/goal`-, `/plan`- & Kanban-Routing**: Der `TaskOrchestrator` bewertet alle aktiven Agenten anhand von Kompetenz-, Skill- und Namens-Treffern sowie aktueller Auslastung und weist `/goal`-, `/plan`- und `Auto (Ontologie)`-Aufgaben automatisch dem passendsten Spezialisten zu.
        - **Dynamische Sub-Task-Delegation (`ghost_delegate_task`)**: Ermöglicht es Agenten, komplexe Teilaufgaben gezielt an den bestbewerteten Spezialisten im Knowledge Graph zu delegieren – inklusive `dry_run`-Routing-Vorschau und Rekursionstiefen-Schutz (`maxDelegationDepth`).
- **Native ObjectBox-Ontologie & Knowledge-Graph-Memory**: Strukturiertes symbolisches Langzeitgedächtnis ergänzend zu Vektor-RAG und Standard-Speicher.
    - **T-Box- & A-Box-Regeln**: Nativer ObjectBox-Graph (`OntologyRelationDef`, `OntologyNode`, `OntologyEdge`) mit funktionalen Prädikaten (z. B. `WOHNT_IN`, `HEISST`, `ARBEITET_BEI`, die ältere Werte automatisch ersetzen) und transitiven Prädikaten (z. B. `LIEGT_IN`, `TEIL_VON`, `BENOETIGT_SKILL`) für Multi-Hop-Inferenz.
    - **Automatische Faktenerkennung mit System-1 Memory-Poisoning-Schutz**: Pre-Turn-Kontextinjektion (`[KNOWLEDGE GRAPH]`) und asynchrone Post-Turn-Faktenextraktion (`OntologyExtractor`), streng abgesichert durch System-1-Sicherheitsprüfungen (`system1Middleware`, Injection-/HITL-Flags), damit manipulierte Eingaben niemals das Langzeitgedächtnis vergiften.
    - **Graph-Werkzeuge**: Agenten können strukturierte Fakten direkt über `ghost_ontology_assert` und `ghost_ontology_query` speichern und traversieren.
    - **Multi-Hop-Query-Inspector & Monolith Graph-Explorer**: Interaktive Oberfläche unter **Einstellungen → Toolbox → Speicher → Ontologie** zum Filtern von Fakten und Entitäten (`Alle`, `Persönlich`, `Governance`, `Regeln`), zum Testen von 1–4-Hop-Abfragen inklusive Prompt-Vorschau, zum manuellen Hinzufügen von Fakten sowie für JSON-Backup/Restore.
- **Memory Engine (RAG & Standard)**: Erweitere das Wissen deines Agenten durch lokale Vektor- und Stichwortspeicher.
    - **Standard Memory**: Stichwortbasiertes, verschlüsseltes lokales Gedächtnis (Hive). Informationen werden sicher gespeichert und über exakte Treffer abgerufen.
    - **RAG Memory (ObjectBox)**: Retrieval-Augmented Generation mit semantischer Vektorsuche, betrieben durch eine hochleistungsfähige lokale ObjectBox-Datenbank.
    - **Workspace RAG**: Indiziert automatisch Dateien im Ordner `rag` innerhalb deines Workspace-Verzeichnisses. Klartextdateien (`.txt`, `.md`, `.json` usw.) und PDFs werden analysiert und indiziert.
    - **Shortest-Job-First (SJF) Indizierung**: Zu indizierende Dateien werden nach Größe sortiert. Kleine Dateien werden sofort indiziert, was eine sofortige Verfügbarkeit von leichten Dokumenten garantiert, während große Dateien im Hintergrund verarbeitet werden.
    - **Lokaler Datenschutz**: Workspace-RAG ist auf lokale Embedding-Provider (z. B. Ollama, LM Studio) beschränkt, um sicherzustellen, dass keine vollständigen Dokumente an externe Cloud-APIs gesendet werden.
    - **Automatische Embeddings**: Wenn ein OpenRouter-API-Schlüssel vorhanden ist, nutzt RAG Memory standardmäßig das kostenlose Modell `nvidia/llama-nemotron-embed-vl-1b-v2:free`.
    - **Langzeitgedächtnis**: Der Agent kann wichtige Fakten speichern und später mittels semantischer Suche wiederfinden.
- **Google Workspace Integration**:
    - **Gmail**: E-Mails lesen, suchen, **löschen** (Papierkorb) und **neue E-Mails senden**.
    - **Kalender**: Termine auflisten, **neue Events hinzufügen** und **Events löschen**.
    - **Google Drive**: Dateien suchen, auflisten und **löschen**.
- **Microsoft 365 / Outlook Integration**:
    - **Outlook Mail**: E-Mails lesen, suchen und **senden** via Microsoft Graph.
    - **Outlook Kalender**: Termine auflisten und **neue Events hinzufügen**.
    - **OneDrive**: Dateien in deinem Cloud-Speicher suchen und auflisten.
- **Google Antigravity & ACP (Agent Client Protocol)**:
    - **Standalone ACP Server (`bin/ghost_acp.dart`)**: Headless STDIO- und WebSocket-JSON-RPC 2.0 Server, der direkt von Google Antigravity CLI (`agy`), Zed und Editoren gestartet werden kann.
    - **Guarded Autopilot**: Antigravity-konforme Bestätigungsstufen (`reviewMode` vs. `autoAccept`) für Datei-Patches und Terminalausführungen.
    - **Workspace-RAG Context Provider**: ObjectBox Vektorsuche als ACP Context-Provider (`ghost-rag`) registriert, um Codebasis-Kontext direkt in Prompts einzuspeisen.
    - **Kanban-to-Task Bridge**: Übersetzt Antigravity-Mehrschritt-Pläne nahtlos in verknüpfte Ghost-Kanban-Pipelines mit bidirektionaler Statussynchronisation.
    - **Registrierte Tools**: Exportiert Ghost-Fähigkeiten (`ghost_apply_patch`, `ghost_workspace_rag`, `ghost_kanban_pipeline`, `ghost_vault_keys`, `ghost_exec`, `ghost_web_search`) als native Antigravity-Tools.
- **Visual Studio Code & Google Antigravity IDE Integration**:
    - **Rechte Seitenleiste**: Nahtlose Einbettung als eigener Tab in der Auxiliary Bar neben Antigravity und Chat.
    - **Antigravity IDE Kompatibilität**: Vollständig kompatibel mit der Google Antigravity IDE (VS Code Fork) und Standard VS Code.
    - **Guarded Autopilot Integration**: Review-Modus-Dialoge mit integriertem Diff-Viewer und Bestätigungs-Gating vor Dateiänderungen.
    - **Dynamischer Workspace Sync**: Verzögerungsfreie Dateisynchronisation und Statusabgleich mit Ghosts internem State.
    - **Editor-Aktionen**: Rechtsklick-Menü (`👻 Ghost AI`) für Code-Erklärung, Refactoring, Unit-Test-Generierung und automatische Linter-Fehlerbehebung.
    - **Echtzeit-Streaming**: Live-Token-Streaming (`agent.stream`) und Aktivitätsanzeigen für Tool-Ausführungen (`agent.activity`).
- **E-Mail-Integration**:
    - **IMAP/SMTP-Support**: Konfiguriere mehrere Standard-E-Mail-Konten direkt in den Einstellungen (verschlüsselte Speicherung der Zugangsdaten).
    - **Hintergrund-Synchronisierung**: Der Hintergrund-`EmailPoller` synchronisiert Postfächer automatisch und speichert E-Mails lokal zwischen.
    - **KI-Verarbeitung**: Automatische E-Mail-Analyse durch KI, inklusive Priorisierung, Dringlichkeitsprüfung, Spam-Filterung, Erkennung von Terminen und Generierung von Antwortentwürfen im bevorzugten Schreibstil des Nutzers.
    - **Anhänge**: Liste und lade E-Mail-Anhänge direkt in deinen Workspace herunter.
- **Erweiterbare Skills & Progressive Loading (Opt-Out)**:
    - **Opt-Out-Skill-Zugriff (`disabledSkills`)**: Alle Agenten (Standard- und Custom-Agenten) erhalten standardmäßig Zugriff auf alle installierten Skills und können einzelne Skills gezielt über `disabledSkills` abwählen (synchronisiert als `DARF_NUTZEN`-Kanten im Ontologie-Graphen).
    - **Token-sparendes On-Demand-Laden (`ghost_load_skill`)**: Im System-Prompt wird nur ein kompakter `[AVAILABLE SKILLS]`-Index injiziert; vollständige `SKILL.md`-Anleitungen, `.venv`-/Node-/MCP-Laufzeitpfade, `BENOETIGT_SKILL`-Abhängigkeiten und `ERFORDERT_HITL`-Richtlinien werden erst bei Bedarf über `ghost_load_skill` geladen.
    - **Modulares System**: Laden und Verwalten von Skills zur Erweiterung der Fähigkeiten des Agenten.
    - **Agenten-spezifische Skills**: Aktiviere oder deaktiviere Funktionen für spezifische Agenten-Profile.
    - **UI-basierte Erstellung**: Erstelle neue Skills direkt in der App mithilfe von vordefinierten Vorlagen (Python/Node.js).
    - **Polyglot Runtimes**: Automatisches Management von **Python (venv)** und **Node.js (node_modules)** Umgebungen für Skills.
    - **MCP Server Support**: Direkte Integration von Model Context Protocol Servern als Ghost Skills.
- **Design Systems**:
    - **Zentrale Verwaltung**: Verwalte mehrere visuelle Themes in einem dedizierten Einstellungs-Hub.
    - **Markdown-basiertes Styling**: Erstelle und bearbeite Design-Systeme mit einem einfachen, strukturierten Markdown-Format (`DESIGN.md`).
    - **Backup & Restore**: Sichere deine Design-Systeme und stelle sie auf jeder Ghost-Instanz wieder her.
    - **Einheitliches Branding**: Wende ein konsistentes Look-and-Feel auf alle Agenten mit standardisierten Design-Tokens basierend auf der "The Monolith"-Ästhetik an.
- **Erweiterte Werkzeuge**:
    - **Interaktive Shell**: Ausführung von Shell-Skripten und Python-Code direkt durch den Agenten.
    - **Websuche**: Integrierte Websuche via DuckDuckGo.
    - **Dateisystem**: Vollständiger Zugriff zum Lesen, Schreiben und Verwalten lokaler Dateien.
    - **GitHub**: Integration zur Verwaltung von Repositories und Issues.
    - **Chat-Suche (Strg+F)**: Schnelle Suche innerhalb einer Sitzung mit Echtzeit-Hervorhebung und interaktiver Navigation.
- **Multi-Messenger-Unterstützung**:
    - **13 Kanäle**: Verbinde deinen Agenten mit Telegram, Discord, WhatsApp (Meta), Slack, Signal, iMessage (BlueBubbles), MS Teams, Google Chat, Matrix, Nextcloud Talk, Tlon/Urbit, Zalo und WebChat.
    - **Intelligente Suche & Sortierung**: Verwalte deine Kommunikationskanäle mühelos mit integrierten Suchfiltern und automatischer Gruppierung nach Status.
    - **Resiliente Verbindungen**: Verbesserte Stabilität für Messaging-Gateways (wie Telegram) durch automatische Verbindungswiederherstellung und automatische Bereinigung von Tokens/Zugangsdaten.
    - **DM-Richtlinien**: Granulare Kontrolle darüber, wer deinem Bot schreiben darf (Pairing, Allowlist, Open, Disabled).
    - **Sprachnachrichten & Lokales Diktieren**: Unterstützt das Empfangen/Senden von Sprachnachrichten und bietet eine **hochperformante lokale Offline-Diktierfunktion** (Whisper `base` via Sherpa-ONNX) direkt in der App.
- **Automations & Geplante Workflows**:
    - **Eigener Automations-Arbeitsbereich**: Direkt über die Seitenleiste (**Automations**) erreichbar – inklusive Echtzeit-Suche, Aktiv/Pausiert-Schaltern, Status-Badges und sofortigem manuellem Start (`Run Now`).
    - **`+ Create with Prompt`-KI-Assistent**: Beschreibe einen wiederkehrenden Ablauf in natürlicher Sprache; Ghost generiert Titel, exakten ungerundeten Zeitplan, detaillierte Instructions und passende Ontologie-Zuweisung automatisch.
    - **Lesbarer Zeitplan-Picker**: Unterstützt **Täglich**, **Werktags** (mehrere Uhrzeiten), **Wöchentlich**, **Stündlich**, **Intervall** (1–59 Min. / 1–24 Std.) oder **Custom Cron** inklusive Live-Validierung und Vorschau der nächsten 3 Ausführungszeiten.
    - **Ontologie-Routing & Modell-Overrides**: Wähle **`Auto (Ontologie)`** für dynamische Spezialisten-Auswahl pro Lauf (oder weise gezielt einen Agenten samt Provider-/Modell-Override zu).
    - **Persistente Run-Historie & Vollständige Transkripte**: Prüfe Status, Dauer, zugewiesenen Agenten/Modell und Zusammenfassung jedes Laufs – ein Klick öffnet das komplette `auto_*`-Chat-Transkript (getrennt von der regulären Chat-Liste), komplett im ZIP-Backup (`automations`) gesichert.
    - **Geplante Custom-Agenten & Fehler-Recovery**: Unterstützt Cron-Zeitpläne direkt an Custom-Agenten (`cronSchedule`), Echtzeit-Gateway-Sync sowie interaktives Fortsetzen nach Rate-Limits.
- **Privacy & Security**:
    - **System-1 Entscheidungs-Middleware**: Ultraschnelle nicht-autoregressive Cross-Encoder-Engine (`ModernBERT INT8 ONNX`) für Sub-15ms Entscheidungen auf lokaler CPU. Umfasst vorgelagerte Blockierung von Prompt-Injections und Jailbreaks, Phishing- & Krypto-Drainer-Erkennung, dynamisches Risiko-Scoring für Tool-Argumente (prüft vollständige Shell-Befehle, Beträge und Verträge) sowie semantische HITL-Freigabeprüfung (unterscheidet zuverlässig zwischen Bestätigung und Ablehnung).
    - **Human-In-The-Loop (HITL)**: Sensible Aktionen (Dateisystem, Terminal, Web-Zugriff) müssen über interaktive **JA / NEIN Buttons** direkt im Chat bestätigt werden.
    - **Sicherheits-Audit-Protokolle**: Verfolge und überprüfe alle sicherheitsrelevanten Aktionen und Ereignisse direkt in der Benutzeroberfläche.
    - **Prompt-Härtung**: Fortschrittliche System-Prompts schützen den Agenten vor Jailbreaks und Anweisungen, die versuchen Sicherheitsregeln zu umgehen.
    - **Netzwerk-Einschränkung**: Komplette Isolation der Web-Tools des Agenten bei hoher Sicherheitsstufe, um unbefugte Datenabflüsse zu verhindern.
    - **Sicherer Tresor**: API-Schlüssel, Agenten-Konfigurationen und Memory-Einstellungen sind mit AES-256-GCM verschlüsselt und nur auf deinem Rechner gespeichert.
    - **KI-Anbieter-Suche & Maskierung**: Sensible API-Schlüssel werden standardmäßig maskiert und können einfach über einen Filter gefunden werden.
- **Autonome Zahlungen & Budget**:
    - **Zahlungsabwicklung**: Agenten können im Auftrag des Benutzers Online-Transaktionen durchführen (über das Tool `execute_payment`), sofern die Kreditkartendaten im verschlüsselten Tresor hinterlegt sind.
    - **Budgetgrenzen**: Das Limit und Guthaben werden über `BillingConfig` verwaltet. Transaktionen über dem Limit schlagen fehl, und der Nutzer wird zum Aufladen benachrichtigt.
    - **HITL-Freigabe**: Sofern die autonome Abrechnung nicht explizit aktiviert ist, erfordern alle Zahlungsfreigaben eine manuelle Bestätigung im Chat.
    - **Kreditkarten-Transaktionen**: Lokale Speicherung des Kreditkarten-Transaktionsverlaufs (SUCCESS/FAILED) mit scrollbarem Verlauf und automatischen Benachrichtigungen.
    - **Web3- & Krypto-Integration**: Anbindung dezentraler Krypto-Wallets über das **Reown AppKit** (ehemals WalletConnect) zur Anzeige von ERC-20-Token-Guthaben und Durchführung von Krypto-Aufladungen direkt in der App.
    - **Agenten-EVM-Wallet (Autonome Blockchain-Zahlungen)**: Konfiguration eines Private Keys im verschlüsselten Tresor (`agent_wallet_private_key`), damit der Agent selbstständig Zahlungen (`execute_blockchain_payment`) und Token-Swaps (`execute_token_swap`) auf Ketten wie BSC, Polygon und Ethereum ausführen kann.
    - **Binance & Demo-Trading**: Integration von Binance-Spot- und Demo-Trading-APIs (`binance_get_balances`, `binance_get_ticker`, `binance_create_order`, `binance_demo_get_balances`, `binance_demo_create_order`), mit denen Agenten Guthaben abfragen, Ticker prüfen und echte oder simulierte Orders erteilen können.
- **Token-Verbrauchsüberwachung**: Behalte den Überblick über Eingabe- und Ausgabe-Token jeder Sitzung, um KI-Nutzung und Kosten zu kontrollieren.
    - **Echtzeit-Monitoring**: Präzise Token-Zählung direkt aus den Metadaten der Modellantworten.
    - **Gesamtverbrauch**: Integrierter "Usage Provider" zur Verfolgung des kumulativen Verbrauchs über Sitzungen hinweg.
    - **Verschlüsselte Datenbank**: Chat-Sitzungen und Avatare werden in einer lokalen Hive-Datenbank mit zusätzlicher Verschlüsselung gespeichert.
    - **Avatar-Management**: Bilder werden direkt in der Datenbank gespeichert, um maximale Privatsphäre zu gewährleisten.
    - **Selbstgehostet**: Volle Kontrolle über deine Daten und die Codebasis.
- **Moderne Benutzeroberfläche & Sitzungsverwaltung**:
    - **"The Monolith" Design**: Eine minimalistische, kontrastreiche Benutzeroberfläche im Stil von "Ghost Minimalist Noir" für ein ablenkungsfreies Erlebnis.
    - **Ordner-Organisation & Batch-Löschung**: Gruppiere Chats in Ordnern und lösche komplette Sitzungsverläufe unwiderruflich von der Festplatte – ohne dass gelöschte Transkripte nach Neustarts wieder auftauchen.
    - **Intelligenter Auto-Scroll**: Kontextbewusstes Viewport-Tracking, das deine Leseposition bei der Verlaufsansicht respektiert und nur bei neuen Eingaben oder aktivem Streaming am Chat-Ende automatisch mitscrollt.
    - **Chat-, Kanban-, Automations- & E-Mail-Navigation**: Schneller Zugriff auf Konversationen, Kanban-Tasks, geplante Automations und E-Mails direkt über die Seitenleiste.
    - **Code-Darstellung**: Hebt Code-Blöcke hervor und formatiert sie für eine bessere Lesbarkeit.
    - **Einstellungszentrale**: Verwalte alle Konfigurationen zentral über eigene Reiter für **Profil**, **Agenten-Profile** (`Haupt-Agent`, `Eigene Agents`), **API-Verwaltung**, **Integrationen**, **Kanäle**, **Zahlungen**, **Toolbox** (`Skills`, `Design Systems`, `Speicher` & Ontologie, `Browser`, `Dateisystem`), **Sicherheit**, **Gateway** und **Zurücksetzen**.
- **System-Stabilität & Wartung**:
    - **Gateway-Status & Live-Logs**: Echtzeit-Überwachung der Gateway-Leistung, verbundener Clients und Systemprotokolle direkt in der App.
    - **Sicherer Shutdown**: Robuster Hintergrund-Shutdown-Prozess, der sicherstellt, dass alle Datenbanken sauber geschlossen werden, bevor das System beendet oder zurückgesetzt wird.
    - **Backups mit Token-Erhalt**: Deine API-Token werden sicher im Backup gespeichert und beim Restore automatisch wieder in den Tresor importiert.

---

## 📜 Lizenz

Veröffentlicht unter der freizügigen [MIT-Lizenz](LICENSE), die dir volle Freiheit gibt, den Code zu ändern und ohne Einschränkungen zu verteilen.
