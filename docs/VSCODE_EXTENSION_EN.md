# 👻 Ghost VS Code Extension

Official Visual Studio Code extension for the personal AI assistant **Ghost**.

Integrates Ghost directly into your developer environment — as a secondary sidebar chat (alongside *Antigravity* and *Chat*) and as an intelligent assistant in the code editor.

---

## 🌟 Key Features

- **Secondary Sidebar (Auxiliary Bar)**: Appears as a native tab on the right side next to *Antigravity* and *Chat*.
- **Real-Time Token Streaming & Stop/Edit Controls**: Stream responses token by token (`agent.stream`), stop generation mid-turn (`agent.stop`), or edit previous user messages (`agent.editMessage`).
- **Live Tool Activities**: Shows in real-time what Ghost is doing (e.g. searching workspace files, analyzing diagnostics).
- **Provider & Model Switching + API Key Management**: Switch LLM providers/models directly per session (`agent.setSessionModel`) and manage vault API keys (`Ghost: API-Keys verwalten`).
- **Session Management & Deletion**: Switch between unlimited sessions, create new chats, or delete individual / all sessions (`Ghost: Aktuelle Sitzung löschen`, `Ghost: Alle Sitzungen löschen`).
- **Dynamic Workspace Detection**: Automatically identifies the open VS Code workspace folder (`workspaceDir`) and sets it for filesystem tools (`read_file`, `write_file`, `list_dir`) and terminal commands (`bash`).
- **Codeblock Actions**: Every generated code block provides 1-click buttons for **"Insert into Editor"** and **"Copy"**.
- **Google Antigravity IDE Compatibility**: Fully optimized for Google Antigravity IDE (VS Code Fork).
- **Guarded Autopilot**: Interactive diff inspection (`reviewMode`) before applying file patches or terminal executions with approval dialogs (`Accept` / `Reject`).
- **Workspace & Kanban Synchronization**: Automatically syncs saved files and Antigravity plan steps with the Ghost backend.
- **Auto-Token Discovery**: Automatically discovers the local Gateway on `ws://localhost:3000` and retrieves the authorization token via the client-token endpoint.

---

## 🛡️ Guarded Autopilot & Antigravity

The extension supports the safety levels of the Google Antigravity platform:
- **`reviewMode` (Default):** Modifications to workspace files (`apply_patch`, `edit_file`) and terminal commands are intercepted and displayed as an in-editor diff review. The user must explicitly approve or reject the change.
- **`autoAccept`:** Autonomous mode where changes are applied directly.

Useful Commands (`Ctrl+Shift+P`):
- **`Ghost: Autopilot-Modus umschalten (Review vs. Auto-Accept)`** (`ghost.toggleAutopilotMode`)
- **`Ghost: Workspace-RAG synchronisieren`** (`ghost.syncWorkspace`)
- **`Ghost: Modell & Provider wechseln`** (`ghost.changeModel`)
- **`Ghost: API-Keys verwalten`** (`ghost.manageApiKeys`)

For complete architecture and CLI details, see **[Google Antigravity & ACP Guide](ANTIGRAVITY_ACP_EN.md)**.

---

## ⚡ Editor Actions (Right-Click Context Menu)

Select code in any file and choose **`👻 Ghost AI`** in the context menu:

| Action | Description |
|---|---|
| **Ghost: Code erklären** | Explains the selected code snippet clearly and thoroughly. |
| **Ghost: Code refaktorisieren** | Proposes clean improvements for readability, performance, and type safety. |
| **Ghost: Unit-Tests generieren** | Writes comprehensive unit tests covering edge cases and error handling. |
| **Ghost: Linter-/Compiler-Fehler beheben** | Reads active VS Code Diagnostics (linter/compiler errors) and prompts Ghost to fix them. |

---

## 🎯 Slash Commands in Chat

- `/explain <code/topic>`: Explain code or architectural concepts.
- `/refactor`: Refactor selected code.
- `/tests`: Generate unit tests.
- `/plan <target>`: Creates a structured architectural analysis and an ontology-routed Kanban task in Ghost (status: `review`).
- `/goal <target>`: Autonomous multi-step execution routed to the best specialist via the Ontology Graph (status: `done` on completion).

---

## 📦 Installation & Setup

### Prerequisites
Make sure Ghost is running with the internal Gateway enabled:
```bash
flutter run
```

### Install Extension (`.vsix`)
From the Ghost repository root:
```bash
code --install-extension vscode-extension/ghost-vscode-0.1.0.vsix
```

Then reload the VS Code window (`Ctrl+Shift+P` → **"Developer: Reload Window"**).

---

## ⚙️ Configuration (`settings.json`)

| Setting | Default | Description |
|---|---|---|
| `ghost.gatewayUrl` | `"ws://localhost:3000"` | WebSocket URL of Ghost Gateway. |
| `ghost.authToken` | `""` | Optional token (auto-discovered if empty). |
| `ghost.autoConnect` | `true` | Automatically connect on VS Code startup. |
| `ghost.syncWithActiveEditor` | `true` | Provide active filename and cursor context to prompts. |
| `ghost.antigravity.enabled` | `true` | Enable Google Antigravity & ACP integration. |
| `ghost.antigravity.autopilotMode` | `"reviewMode"` | Autopilot safety mode (`reviewMode` or `autoAccept`). |
| `ghost.antigravity.syncKanban` | `true` | Sync Antigravity tasks with Ghost Kanban board. |
| `ghost.antigravity.syncWorkspace` | `true` | Sync file edits and saves live with Ghost state. |
