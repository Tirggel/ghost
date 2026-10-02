# 👻 Ghost VS Code Extension

Die offizielle Visual Studio Code Erweiterung für den persönlichen KI-Assistenten **Ghost**.

Sie integriert Ghost direkt in deine Entwicklungsumgebung – als Seitenleisten-Chat in der rechten Leiste (neben *Antigravity* und *Chat*) und als intelligenter Helfer im Code-Editor.

---

## 🌟 Hauptfunktionen

- **Rechte Seitenleiste (Auxiliary Bar)**: Erscheint als nativer Reiter neben *Antigravity* und *Chat*.
- **Echtzeit-Token-Streaming**: Antworten werden verzögerungsfrei Token für Token gestreamt (`agent.stream`).
- **Live-Tool-Aktivitäten**: Visualisiert in Echtzeit, welche Werkzeuge Ghost gerade ausführt (z. B. Workspace-Dateien durchsuchen, Linter analysieren).
- **Dynamische Workspace-Erkennung**: Erkennt automatisch den aktuell in VS Code geöffneten Projektordner (`workspaceDir`) und setzt ihn für Dateisystem-Tools (`read_file`, `write_file`, `list_dir`) und Terminal-Befehle (`bash`).
- **Codeblock-Aktionen**: Jeder generierte Codeblock bietet 1-Klick-Buttons für **"In Editor einfügen"** und **"Kopieren"**.
- **Sitzungsverwaltung**: Beliebig viele Chats verwalten, nahtlos zwischen Sitzungen wechseln und Historie abrufen.
- **Auto-Token-Discovery**: Erkennt automatisch das lokale Gateway auf `ws://localhost:3000` und liest bei Bedarf den Autorisierungs-Token über den lokalen Endpunkt aus.

---

## ⚡ Editor-Aktionen (Rechtsklick)

Markiere einen Codeabschnitt in einer beliebigen Datei und wähle im Kontextmenü **`👻 Ghost AI`**:

| Aktion | Beschreibung |
|---|---|
| **Ghost: Code erklären** | Erklärt den markierten Codeabschnitt präzise und verständlich. |
| **Ghost: Code refaktorisieren** | Schlägt saubere Verbesserungen für Lesbarkeit, Performance und Typ-Sicherheit vor. |
| **Ghost: Unit-Tests generieren** | Schreibt vollständige Tests inklusive Randfälle und Fehlerbehandlung. |
| **Ghost: Linter-/Compiler-Fehler beheben** | Liest automatisch VS Code Diagnostics (Fehlermeldungen) des Bereichs aus und weist Ghost an, diese zu beheben. |

---

## 🎯 Slash-Commands im Chat

- `/explain <code/thema>`: Code oder Konzept erklären.
- `/refactor`: Code optimieren.
- `/tests`: Tests generieren.
- `/plan <ziel>`: Erstellt eine strukturierte Architekturanalyse und legt eine Kanban-Aufgabe im Ghost-Backend an (Status: `review`).
- `/goal <ziel>`: Startet eine autonome Mehrschritt-Aktion zur Erreichung eines Ziels (Status: `done` bei Erfolg).

---

## 📦 Installation & Setup

### Voraussetzungen
Stelle sicher, dass Ghost mit aktiviertem Gateway läuft:
```bash
# Im Projektverzeichnis ausführen:
flutter run
```

### Extension installieren (`.vsix`)
Im Terminal des VS Code Projekts:
```bash
code --install-extension /home/peter/Developer/flutter-dev/ghost/vscode-extension/ghost-vscode-0.1.0.vsix
```

Danach in VS Code das Fenster kurz neu laden (`Ctrl+Shift+P` → **"Developer: Reload Window"**).

---

## ⚙️ Einstellungen (`settings.json`)

| Einstellung | Standard | Beschreibung |
|---|---|---|
| `ghost.gatewayUrl` | `"ws://localhost:3000"` | WebSocket-URL des Ghost Gateways. |
| `ghost.authToken` | `""` | Optionaler Token (wird standardmäßig automatisch ermittelt). |
| `ghost.autoConnect` | `true` | Automatisch beim Start von VS Code verbinden. |
| `ghost.syncWithActiveEditor` | `true` | Aktiven Dateinamen und Cursor-Kontext an Prompts übergeben. |

---

## 🛠️ Entwicklung & Debugging

1. Öffne den Ordner `vscode-extension` in einem separaten VS Code Fenster.
2. Drücke **`F5`** ("Run Ghost Extension").
3. Es öffnet sich ein neues Entwicklungsfenster mit aktivierter Erweiterung.
