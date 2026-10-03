# 👻 Ghost Chrome Extension

Official Google Chrome extension (Manifest V3) for the personal AI assistant **Ghost**.

Integrates Ghost directly into your browser — as a native Side Panel for research, code analysis, and context-menu actions.

---

## 🌟 Key Features

- **Chrome Side Panel**: Opens natively as a right sidebar in the browser and stays open across tab switches.
- **Real-Time Token Streaming**: Responses are streamed token by token without delay (`agent.stream`).
- **Live Tool Activities**: Shows in real-time what Ghost is doing.
- **Webpage Context (Page Q&A)**: Attach active tab URL, title, and page text snippet with a single click.
- **Context Menu Actions (Right-Click)**:
  - `👻 Ghost: Explain Text / Code`
  - `👻 Ghost: Summarize Selection`
  - `👻 Ghost: Create Kanban Task (/plan)`
  - `👻 Ghost: Analyze This Page`
- **Session Management**: Switch between chat sessions or start fresh sessions anytime.
- **Auto-Token Discovery**: Automatically connects to the local Gateway on `ws://localhost:3000` and retrieves authorization tokens.

---

## 📦 Installation & Setup

1. Ensure the Ghost application / Gateway is running:
   ```bash
   flutter run
   ```
2. In Google Chrome, navigate to: `chrome://extensions`
3. Enable **Developer mode** in the top right corner.
4. Click **Load unpacked** and select the `chrome-extension` directory:
   ```
   /home/peter/Developer/flutter-dev/ghost/chrome-extension
   ```
5. Pin the Ghost icon to your toolbar and click it to open the Side Panel!
