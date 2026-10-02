# Ghost AI Assistant — VS Code Extension 👻

Offizielle Visual Studio Code Erweiterung für den persönlichen KI-Assistenten **Ghost**.

Die Erweiterung bindet Ghost direkt in deine Entwicklungsumgebung ein und verbindet sich über das modulare **WebSocket JSON-RPC 2.0 Gateway** (`GatewayServer`) mit deiner lokalen Ghost-Instanz.

---

## 🚀 Features

### 1. 💬 Interaktive Chat-Seitenleiste
- **Echtzeit-Streaming**: Antworten werden verzögerungsfrei Token für Token gestreamt (`agent.stream`).
- **Tool-Aktivitäten**: Visualisiert live, woran Ghost gerade arbeitet (z. B. Workspace-Dateien durchsuchen, Linter analysieren, Speicher abfragen).
- **Sitzungsverwaltung**: Wechsle nahtlos zwischen bestehenden Chat-Sitzungen oder erstelle mit einem Klick eine neue Session.
- **Code-Aktionen**: Jeder Codeblock in den Antworten verfügt über Buttons zum sofortigen **Kopieren** oder **Einfügen in den aktiven Editor**.

### 2. ⚡ Inline Editor-Aktionen (Rechtsklick)
Markiere Code in einer beliebigen Datei und wähle im Kontextmenü **👻 Ghost AI**:
- **Code erklären**: Analysiert die ausgewählte Funktion oder Klasse verständlich und präzise.
- **Code refaktorisieren**: Schlägt Verbesserungen hinsichtlich Lesbarkeit, Performance und Typ-Sicherheit vor.
- **Unit-Tests generieren**: Schreibt vollständige Tests inklusive Randfälle und Fehlerbehandlung.
- **Linter-/Compiler-Fehler beheben**: Liest automatisch die VS Code Diagnostics (Fehlermeldungen) des Bereichs aus und weist Ghost an, diese zu beheben.

### 3. 🎯 Slash-Commands
- `/plan <Ziel>`: Erstellt eine strukturierte Architekturanalyse und legt eine Kanban-Aufgabe im Ghost-Backend an.
- `/goal <Ziel>`: Startet eine autonome Mehrschritt-Aktion zur Erreichung eines Ziels.
- `/explain`, `/refactor`, `/tests`: Schnelle Vorlagen für gängige Coding-Aufgaben.

### 4. 📊 Statusleiste & Auto-Discovery
- Live-Status in der VS Code Fußleiste:
  - `$(pass-filled) Ghost`: Bereit und verbunden.
  - `$(loading~spin) Ghost: Denkt...`: Führt Berechnungen oder Tools aus.
  - `$(plug) Ghost: Getrennt`: Zeigt Verbindungsstatus an. Klick öffnet ein Schnellmenü zum Wiederverbinden, Modell-Wechseln oder Einstellungen.
- **Auto-Discovery**: Erkennt automatisch das lokale Ghost Gateway auf `ws://localhost:3000` und liest bei Bedarf den Autorisierungs-Token über den lokalen Endpunkt aus.

---

## 🛠️ Entwicklung & Testen in VS Code

### Vorbereitung
Stelle sicher, dass die Ghost-Hauptanwendung oder das Gateway läuft:
```bash
# Im Projekt-Root (startet Ghost mit integriertem Gateway auf Port 3000):
flutter run
```

### Erweiterung starten (Debug-Modus)
1. Öffne den Ordner `vscode-extension` in VS Code.
2. Drücke **`F5`** (oder wähle in der Ausführen-Ansicht **"Run Extension"**).
3. Ein neues **Extension Development Host** Fenster von VS Code öffnet sich mit aktivierter Ghost-Erweiterung!
4. Klicke auf das **Ghost-Icon** in der Aktivitätsleiste links oder öffne die Statusleiste unten rechts.

### Erweiterung paketieren (.vsix)
Wenn du eine installierbare VSIX-Datei für dich oder dein Team erstellen möchtest:
```bash
cd vscode-extension
npx @vscode/vsce package
```
Die erzeugte `.vsix`-Datei kann anschließend direkt in VS Code via:
`Extensions → ... Menü → Install from VSIX...` installiert werden.

---

## ⚙️ Einstellungen (`settings.json`)

| Einstellung | Standard | Beschreibung |
|---|---|---|
| `ghost.gatewayUrl` | `"ws://localhost:3000"` | WebSocket-URL des Ghost Gateway Servers |
| `ghost.authToken` | `""` | Optionaler Auth-Token (wird bei leerem Wert automatisch ermittelt) |
| `ghost.autoConnect` | `true` | Automatisch beim Start von VS Code mit Ghost verbinden |
| `ghost.syncWithActiveEditor` | `true` | Aktiven Dateinamen und Cursor-Kontext an Prompts übergeben |
