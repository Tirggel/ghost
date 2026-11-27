# 👻 Ghost Chrome Extension

Official Google Chrome extension (Manifest V3) for the personal AI assistant **Ghost**.

Integrates Ghost directly into your browser — as a native Side Panel for research, code analysis, and context-menu actions.

---

## 🌟 Key Features

- **Chrome Side Panel**: Opens natively as a right sidebar in the browser and stays open across tab switches.
- **Real-Time Token Streaming**: Responses are streamed token by token (`agent.stream`), with live tool activities (`agent.activity`) and generation stop support (`agent.stop`).
- **Provider & Model Switching + API Key Management**: Select AI providers and models directly in the Side Panel (`agent.setSessionModel`) and manage vault keys in Extension Options (`options/options.html`).
- **Webpage Context (Page Q&A)**: Attach active tab URL, title, and page text snippet with a single click.
- **Context Menu Actions (Right-Click)**:
  - `👻 Ghost: Text / Code erklären` (Explain Text / Code)
  - `👻 Ghost: Auswahl zusammenfassen` (Summarize Selection)
  - `👻 Ghost: Als Kanban-Task anlegen (/plan)` (Create Kanban Task `/plan`)
  - `👻 Ghost: Diese Seite analysieren` (Analyze This Page)
- **Session Management & Deletion**: Switch between chat sessions, start fresh chats, or delete individual / all sessions via the built-in deletion modal.
- **Auto-Token Discovery**: Automatically connects to the local Gateway on `ws://localhost:3000` and retrieves authorization tokens via `http://localhost:3000/client-token`.

---

## 📦 Installation & Setup

1. Ensure the Ghost application / Gateway is running:
   ```bash
   flutter run
   ```
2. In Google Chrome, navigate to: `chrome://extensions`
3. Enable **Developer mode** in the top right corner.
4. Click **Load unpacked** and select the `chrome-extension/` directory from the Ghost repository.
5. Pin the Ghost icon to your toolbar and click it to open the Side Panel!
