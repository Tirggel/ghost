# Ghost 👻 × Google Antigravity & Agent Client Protocol (ACP)

Dieses Handbuch beschreibt die Integration von Ghost in die Agentic-Entwicklungsplattform **Google Antigravity** sowie die Nutzung des **Agent Client Protocol (ACP)** für standardisierte Interaktionen mit Entwicklungsumgebungen (Antigravity IDE, Zed, VS Code).

---

## 1. Architektur & Überblick

Ghost agiert sowohl als autonomer Coding-Agent in Antigravity-kompatiblen Editoren als auch als Gateway-Orchestrator für Dart/Flutter- und KI-Workflows:

```
┌────────────────────────────────────────────────────────┐
│        Google Antigravity IDE / agy CLI / Zed          │
└───────────────────────────▲────────────────────────────┘
                            │
               JSON-RPC 2.0 (STDIO / WS)
                            │
┌───────────────────────────▼────────────────────────────┐
│                  Ghost ACP Adapter                     │
│  - Handshake (`initialize`)                            │
│  - Guarded Autopilot (`reviewMode` / `autoAccept`)    │
│  - Session & Streaming (`session/prompt`, deltas)     │
│  - Context Provider (`context/query` via RAG)          │
└───────────────────────────▲────────────────────────────┘
                            │
┌───────────────────────────▼────────────────────────────┐
│            Ghost Pure-Dart Engine (`lib/engine.dart`)  │
│  - TaskManager & Ontologie-Kanban-Pipeline-Bridge      │
│  - ObjectBox Vektor-RAG, Ontologie & Tresor            │
│  - Tools: ApplyPatch, EditFile, Exec, WebSearch, Vault │
└────────────────────────────────────────────────────────┘
```

> [!NOTE]
> `bin/ghost_acp.dart` und `lib/engine/**` sind strikt von Flutter (`dart:ui`) entkoppelt und nutzen bedingte Imports über `lib/engine/infra/objectbox_flutter_libs_stub.dart`, sodass der Headless-ACP-Server direkt auf der reinen Dart-VM läuft.

---

## 2. Ghost ACP Server starten

Ghost stellt ein dediziertes Binary bereit: [`bin/ghost_acp.dart`](../bin/ghost_acp.dart).

### 2.1 Standard-Betrieb via STDIO (für `agy` & Zed)
Im STDIO-Modus werden alle Diagnose-Logs nach `stderr` umgeleitet, sodass `stdout` strikt der JSON-RPC 2.0 Spezifikation folgt:

```bash
dart bin/ghost_acp.dart --workspace /pfad/zum/projekt
```

Optionen:
* `-w, --workspace`: Arbeitsverzeichnis (Standard: `.`)
* `-g, --guardrails`: Autopilot-Modus (`reviewMode` [Standard] oder `autoAccept`)
* `-h, --help`: Hilfe & Argumentübersicht

### 2.2 Betrieb via WebSocket (Port 3001)
Für Multi-Client-Setups oder Remote-Container kann Ghost als WebSocket-Server gestartet werden:

```bash
dart bin/ghost_acp.dart --ws --port 3001 --workspace /pfad/zum/projekt
```

Zusätzlich stellt das integrierte Ghost-Gateway den Endpunkt unter `ws://127.0.0.1:3000/acp` bereit und brückt `acp.*`-Methoden auch über `/`.

---

## 3. Anbindung an Google Antigravity (`agy`)

In Antigravity-Projekten kann Ghost als benutzerdefinierter Subagent oder ACP-Agent konfiguriert werden.

### Konfiguration in `.antigravity/config.json` oder `settings.json`:
```json
{
  "acp": {
    "agents": {
      "ghost": {
        "command": "dart",
        "args": [
          "/pfad/zu/ghost/bin/ghost_acp.dart",
          "--workspace",
          "${workspaceFolder}",
          "--guardrails",
          "reviewMode"
        ],
        "capabilities": {
          "tools": true,
          "contextProviders": true,
          "editReview": true,
          "terminal": true
        }
      }
    }
  }
}
```

Ausführen eines Tasks mit dem Antigravity CLI:
```bash
agy run --agent ghost "Implementiere eine Authentifizierungs-Middleware in lib/auth.dart"
```

---

## 4. Guarded Autopilot & Sicherheitsstufen

Ghost implementiert analog zum Guarded Autopilot von Antigravity feingranulare Sicherheits-Gatings:

1. **`reviewMode` (Standard):**
   * Änderungen an Dateien (`apply_patch`, `edit_file`) oder die Ausführung von Shell-Befehlen lösen eine `session/review_request`-Benachrichtigung an den Client aus.
   * Der Client/Editor visualisiert den Diff und pausiert die Ausführung, bis der Benutzer bestätigt (`session/review_response` mit `decision: "accept"` oder `"reject"`).
2. **`autoAccept`:**
   * Autonome Ausführung für CI/CD-Pipelines oder vertrauenswürdige Refactorings.

Der Modus kann dynamisch über `session/set_autopilot_mode` umgeschaltet werden:
```json
{
  "jsonrpc": "2.0",
  "method": "session/set_autopilot_mode",
  "params": {
    "sessionId": "session-123",
    "mode": "autoAccept"
  },
  "id": 10
}
```

---

## 5. Workspace-RAG Context Provider

Ghost registriert sein ObjectBox-Vektor-RAG über [`acp_context_provider.dart`](../lib/engine/acp/acp_context_provider.dart) als Antigravity Context-Provider:

* **Provider-ID:** `ghost-rag`
* **Funktion:** Semantische Suche nach Code-Ausschnitten, Symboldefinitionen und Dokumentationen direkt im Projektindex.
* **Fallback:** Gibt bei noch unindizierten Projekten automatisch eine strukturierte Workspace-Übersicht zurück.

---

## 6. Antigravity Tools & Kanban-Bridge

Ghost exportiert spezialisierte Tools über [`antigravity_tools.dart`](../lib/services/antigravity/antigravity_tools.dart):

* `ghost_apply_patch`: Atomares Anwenden von SEARCH/REPLACE-Blöcken (`apply_patch`).
* `ghost_workspace_rag`: Abfragen des semantischen ObjectBox-Projektindex.
* `ghost_kanban_pipeline`: Zerlegung eines Antigravity-Plans in verknüpfte Ghost-Kanban-Tasks (`backlog` → `inProgress` → `done`).
* `ghost_vault_keys`: Sichere Auflistung gespeicherter Schlüsselnamen im Tresor ohne Offenlegung von Secrets.
* `ghost_exec`: Shell-Befehlsausführung mit automatischer Python-`.venv`- und `node_modules/.bin`-Umgebungsinjektion.
* `ghost_web_search`: DuckDuckGo Web-Recherche in Echtzeit.
