# Ghost AI Assistant — VS Code Extension 👻

[English Guide](../docs/VSCODE_EXTENSION_EN.md) &nbsp; &bull; &nbsp; [Deutsche Komplett-Anleitung](../docs/VSCODE_EXTENSION_DE.md)

Offizielle Visual Studio Code Erweiterung für den persönlichen KI-Assistenten **Ghost**.

Die Erweiterung bindet Ghost direkt in deine Entwicklungsumgebung ein und verbindet sich über das modulare **WebSocket JSON-RPC 2.0 Gateway** (`GatewayServer`) mit deiner lokalen Ghost-Instanz.

---

## 🚀 Features

### 1. 💬 Interaktive Chat-Seitenleiste
- **Echtzeit-Streaming, Stop & Bearbeiten**: Antworten werden verzögerungsfrei Token für Token gestreamt (`agent.stream`), lassen sich per Klick abbrechen (`agent.stop`) und vorherige Eingaben direkt bearbeiten (`agent.editMessage`).
- **Tool-Aktivitäten**: Visualisiert live, woran Ghost gerade arbeitet (z. B. Workspace-Dateien durchsuchen, Linter analysieren, Speicher/Ontologie abfragen).
- **Provider- & Modell-Auswahl + API-Keys**: Wechsle Provider und Modell direkt pro Session (`Ghost: Modell & Provider wechseln`) und verwalte API-Keys im Tresor (`Ghost: API-Keys verwalten`).
- **Sitzungsverwaltung & Löschung**: Wechsle nahtlos zwischen bestehenden Chat-Sitzungen, starte neue Sessions oder lösche einzelne bzw. alle Sitzungen (`Ghost: Aktuelle Sitzung löschen`, `Ghost: Alle Sitzungen löschen`).
- **Code-Aktionen**: Jeder Codeblock in den Antworten verfügt über Buttons zum sofortigen **Kopieren** oder **Einfügen in den aktiven Editor**.

### 2. ⚡ Inline Editor-Aktionen (Rechtsklick)
Markiere Code in einer beliebigen Datei und wähle im Kontextmenü **👻 Ghost AI**:
- **Code erklären**: Analysiert die ausgewählte Funktion oder Klasse verständlich und präzise.
- **Code refaktorisieren**: Schlägt Verbesserungen hinsichtlich Lesbarkeit, Performance und Typ-Sicherheit vor.
- **Unit-Tests generieren**: Schreibt vollständige Tests inklusive Randfälle und Fehlerbehandlung.
- **Linter-/Compiler-Fehler beheben**: Liest automatisch die VS Code Diagnostics (Fehlermeldungen) des Bereichs aus und weist Ghost an, diese zu beheben.

### 3. 🛡️ Google Antigravity & Guarded Autopilot
- **Antigravity IDE Kompatibilität**: Vollständig optimiert für die Google Antigravity IDE (VS Code Fork) und Standard-VS-Code.
- **Review-Mode (Guarded Autopilot)**: Bei Dateiänderungen (`apply_patch`, `edit_file`) oder Terminalbefehlen erscheint ein interaktiver Genehmigungsdialog mit Diff-Ansicht (`Accept` / `Reject`).
- **Autopilot-Modus umschalten**: Schnelles Umschalten zwischen `reviewMode` und `autoAccept` über `Ghost: Autopilot-Modus umschalten`.
- **Bidirektionaler Workspace & Kanban Sync**: Datei-Speicherungen und Task-Fortschritte werden live mit dem integrierten Ghost-Kanban synchronisiert.

### 4. 🎯 Slash-Commands
- `/plan <Ziel>`: Erstellt eine strukturierte Architekturanalyse und legt eine ontologie-geroutete Kanban-Aufgabe im Ghost-Backend an.
- `/goal <Ziel>`: Startet eine autonome Mehrschritt-Aktion (automatisches Ontologie-Routing an den besten Spezialisten).
- `/explain`, `/refactor`, `/tests`: Schnelle Vorlagen für gängige Coding-Aufgaben.

### 5. 📊 Statusleiste & Auto-Discovery
- Live-Status in der VS Code Fußleiste (`Bereit`, `Denkt...`, `Getrennt` mit Schnellmenü für Verbindung, Modellwechsel und Einstellungen).
- **Auto-Discovery**: Erkennt automatisch das lokale Ghost Gateway auf `ws://localhost:3000` und liest bei Bedarf den Autorisierungs-Token über den lokalen Endpunkt aus.

---

## 🛠️ Entwicklung & Testen in VS Code

### Vorbereitung
Stelle sicher, dass Ghost mit aktiviertem Gateway läuft:
```bash
# Im Projekt-Root (startet Ghost mit integriertem Gateway auf Port 3000):
flutter run
```

### Erweiterung starten (Debug-Modus)
1. Öffne den Ordner `vscode-extension` in VS Code.
2. Drücke **`F5`** (oder wähle **"Run Extension"**).
3. Ein neues **Extension Development Host** Fenster öffnet sich mit aktivierter Ghost-Erweiterung.
4. Klicke auf das **Ghost-Icon** in der rechten Seitenleiste (Auxiliary Bar) oder Aktivitätsleiste.

### Erweiterung paketieren (`.vsix`)
```bash
cd vscode-extension
npm run build
npx @vscode/vsce package
```
Die erzeugte `.vsix`-Datei kann direkt in VS Code via `Extensions → ... Menü → Install from VSIX...` installiert werden.

---

## ⚙️ Einstellungen (`settings.json`)

| Einstellung | Standard | Beschreibung |
|---|---|---|
| `ghost.gatewayUrl` | `"ws://localhost:3000"` | WebSocket-URL des Ghost Gateway Servers |
| `ghost.authToken` | `""` | Optionaler Auth-Token (wird bei leerem Wert automatisch ermittelt) |
| `ghost.autoConnect` | `true` | Automatisch beim Start von VS Code mit Ghost verbinden |
| `ghost.syncWithActiveEditor` | `true` | Aktiven Dateinamen und Cursor-Kontext an Prompts übergeben |
| `ghost.antigravity.enabled` | `true` | Google Antigravity & ACP Integration aktivieren |
| `ghost.antigravity.autopilotMode` | `"reviewMode"` | Autopilot-Sicherheitsstufe (`reviewMode` oder `autoAccept`) |
| `ghost.antigravity.syncKanban` | `true` | Antigravity-Tasks mit Ghost Kanban-Board synchronisieren |
| `ghost.antigravity.syncWorkspace` | `true` | Dateiänderungen live an Ghost melden |
