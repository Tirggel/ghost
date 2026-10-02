# 👻 Ghost VS Code Extension

Official Visual Studio Code extension for the personal AI assistant **Ghost**.

Integrates Ghost directly into your developer environment — as a secondary sidebar chat (alongside *Antigravity* and *Chat*) and as an intelligent assistant in the code editor.

---

## 🌟 Key Features

- **Secondary Sidebar (Auxiliary Bar)**: Appears as a native tab on the right side next to *Antigravity* and *Chat*.
- **Real-Time Token Streaming**: Responses are streamed token by token without delay (`agent.stream`).
- **Live Tool Activities**: Shows in real-time what Ghost is doing (e.g. searching workspace files, analyzing diagnostics).
- **Dynamic Workspace Detection**: Automatically identifies the open VS Code workspace folder (`workspaceDir`) and sets it for filesystem tools (`read_file`, `write_file`, `list_dir`) and terminal commands (`bash`).
- **Codeblock Actions**: Every generated code block provides 1-click buttons for **"Insert into Editor"** and **"Copy"**.
- **Session Management**: Manage unlimited chats, switch between sessions seamlessly, and view full history.
- **Auto-Token Discovery**: Automatically discovers the local Gateway on `ws://localhost:3000` and retrieves the authorization token via the client-token endpoint.

---

## ⚡ Editor Actions (Right-Click Context Menu)

Select code in any file and choose **`👻 Ghost AI`** in the context menu:

| Action | Description |
|---|---|
| **Ghost: Explain Code** | Explains the selected code snippet clearly and thoroughly. |
| **Ghost: Refactor Code** | Proposes clean improvements for readability, performance, and type safety. |
| **Ghost: Generate Unit Tests** | Writes comprehensive unit tests covering edge cases and error handling. |
| **Ghost: Fix Errors** | Reads active VS Code Diagnostics (linter/compiler errors) and prompts Ghost to fix them. |

---

## 🎯 Slash Commands in Chat

- `/explain <code/topic>`: Explain code or architectural concepts.
- `/refactor`: Refactor selected code.
- `/tests`: Generate unit tests.
- `/plan <target>`: Creates a structured architectural analysis and creates a Kanban task in Ghost (status: `review`).
- `/goal <target>`: Autonomous multi-step execution to achieve a goal (status: `done` on completion).

---

## 📦 Installation & Setup

### Prerequisites
Make sure Ghost is running with the internal Gateway enabled:
```bash
flutter run
```

### Install Extension (`.vsix`)
From the VS Code project terminal:
```bash
code --install-extension /home/peter/Developer/flutter-dev/ghost/vscode-extension/ghost-vscode-0.1.0.vsix
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
