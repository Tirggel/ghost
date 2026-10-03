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
│                     Ghost Engine                       │
│  - TaskManager & Kanban Pipeline Bridge                │
│  - ObjectBox Vector RAG & Secure Storage               │
│  - Tools: ApplyPatch, EditFile, Exec, WebSearch, Vault │
└────────────────────────────────────────────────────────┘
```

---

## 2. Ghost ACP Server starten

Ghost stellt ein dediziertes Binary bereit: [`bin/ghost_acp.dart`](file:///home/peter/Developer/flutter-dev/ghost/bin/ghost_acp.dart).

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

Alternativ stellt auch das integrierte Ghost-Gateway den WebSocket-Endpunkt unter `ws://127.0.0.1:3000/acp` zur Verfügung.

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
          "/home/peter/Developer/flutter-dev/ghost/bin/ghost_acp.dart",
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
   * Der Client/Editor visualisiert den Diff und blockiert die Ausführung, bis der Benutzer bestätigt (`decision: "accept"` oder `"reject"`).
2. **`autoAccept`:**
   * Autonome Ausführung für CI/CD-Pipelines oder vertrauenswürdige repetitive Refactorings.

Der Modus kann dynamisch über das Protokoll umgeschaltet werden:
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

Ghost registriert sein ObjectBox-Vektor-RAG als Antigravity Context-Provider:

* **Provider-ID:** `ghost-rag`
* **Funktion:** Semantische Suche nach Code-Ausschnitten, Dokumentationen und Kontexten direkt im Projektindex.
* **Fallback:** Gibt bei noch unindizierten Projekten automatisch eine strukturierte Workspace-Struktur mit Verzeichnisbaum und Projektdateien zurück.

---

## 6. Antigravity Tools & Kanban-Bridge

Ghost exportiert spezifische Fähigkeiten in Antigravity:

* [`ghost_apply_patch`](file:///home/peter/Developer/flutter-dev/ghost/lib/engine/tools/fs.dart): Atomares Anwenden von SEARCH/REPLACE-Blöcken oder Git-Diffs.
* [`ghost_workspace_rag`](file:///home/peter/Developer/flutter-dev/ghost/lib/services/antigravity/antigravity_tools.dart): Abfragen des semantischen Projektindex.
* [`ghost_kanban_pipeline`](file:///home/peter/Developer/flutter-dev/ghost/lib/services/antigravity/antigravity_tools.dart): Zerlegung eines Antigravity-Plans in verknüpfte Ghost-Kanban-Tasks (`todo` -> `inProgress` -> `done`).
* [`ghost_vault_keys`](file:///home/peter/Developer/flutter-dev/ghost/lib/services/antigravity/antigravity_tools.dart): Sicherer Zugriff auf verschlüsselte Projekt-Schlüssel und Tokens.
* [`ghost_web_search`](file:///home/peter/Developer/flutter-dev/ghost/lib/services/antigravity/antigravity_tools.dart): DuckDuckGo Web-Recherche mit Reranking.
