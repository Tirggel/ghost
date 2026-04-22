# Ghost

<p align="center">
  <img src="assets/icons/logo/ghost.png" width="150" alt="Ghost Logo">
</p>

> [!WARNING]
> **Alpha Version & Security Notice**: This is an early alpha version of Ghost. The software is under active development and may contain critical bugs.
>
> *   **AI Risks**: AI models can "hallucinate" (presenting false information as facts).
> *   **Security**: Prompt injection attacks are possible, where the AI might be manipulated into performing unintended actions through malicious inputs.
> *   **Accounts & Data**: Use Ghost exclusively with **test accounts** for connected services (APIs, Google Workspace, etc.). Never use your primary or production accounts.
> *   **Disclaimer**: Use at your own risk in a **safe, isolated environment**. No responsibility or liability is accepted for any damage, data loss, or unintended actions performed by the AI.

[Developer Website](https://aquawitchcode.dev/) &nbsp; &bull; &nbsp; [Deutsch](README_de.md)

**Ghost** is a lightweight, self-hosted personal AI assistant built with Google's [Dart](https://github.com/dart-lang) and [Flutter](https://github.com/flutter) technologies.

### 🏗️ Architecture at a Glance

Ghost features a modern, integrated architecture:
- **Integrated Engine**: A high-performance backend managing AI agents, memory, and tools—built directly into the Flutter application.
- **Sleek UI**: A minimalist, high-performance interface for Desktop (Linux, macOS, Windows) and Web.
- **Agents & Skills**: Extensible AI capabilities added via a simple, Markdown-based system.
- **Memory Engine**: Dual-mode memory using Hive (standard) and ObjectBox (RAG) for secure, local knowledge.

---

## 🚀 Installation & Setup

> 💡 **Tip**: If you just want to use Ghost, you can download the ready-to-run programs for your platform (Linux, Windows, Mac) here: **[ghost-releases](./ghost-releases)** 😊
>
> *The following installation guide is intended for **developers** who want to build or modify Ghost themselves.*

To get started with Ghost, please follow our detailed installation guide:

👉 **[Installation & Setup Guide (English)](docs/installation/INSTALLATION_EN.md)**
👉 **[Installs- & Setup-Anleitung (Deutsch)](docs/installation/INSTALLATION_DE.md)**

### 🪄 First Start: Easy Setup
Ghost is designed to be plug-and-play. On your first start, an interactive **Setup Wizard** will guide you through the configuration.

If you are building from source, simply run:
```bash
flutter run
```

> [!IMPORTANT]

> **Review your security settings after the first install!**
> After a reset, all security settings are reset to **level "none" (everything disabled)**.
> Once the app is running, navigate to **Settings → Security** and configure them to your needs:
>
> | Setting | Description | Recommendation |
> |---|---|---|
> | **Human-In-The-Loop (HITL)** | Requires confirmation before sensitive actions | ✅ Enable |
> | **Prompt Hardening** | Protects against jailbreaks & prompt injection | ✅ Enable |
> | **Network Restriction** | Isolates web tools at high security level | ⚠️ As needed |
> | **Prompt Analyzers** | Advanced analysis of incoming prompts | ⚠️ As needed |
>
> For normal use, at least **level "medium"** is recommended (HITL + Prompt Hardening active).

### 🪄 Setup Wizard & System Restore
For new users, Ghost includes an interactive **Setup Wizard** that starts automatically if the application is not yet configured.

> [!TIP]
> **System Restore**: If you already have a backup, you can upload it in the very first step of the wizard. Ghost will automatically restore all agents, settings, and even your encrypted API tokens.

### 🛠️ Maintenance & Backup
Ghost features a dedicated **Maintenance Tab** in the settings, giving you full control over your system:
- **Factory Reset**: Wipe the entire application to its original state (deletes all local data & databases).
- **System Backup**: Create an encrypted ZIP archive of your entire configuration.
- **Restore**: Import a backup archive and seamlessly restore your Ghost assistant's state.

### 📚 Further Documentation
- **[Skills Development Guide](docs/SKILLS_GUIDE.md)**: Learn how to create and package your own AI skills.
- **[STT & TTS Setup](docs/STT_TTS_SETUP.md)**: Configure local speech recognition and synthesis.
- **[Multi-Channel Setup](docs/CHANNELS_EN.md)**: Detailed guide for connecting Telegram, Discord, WhatsApp, etc.
- **[RPC API Reference](docs/RPC_API_REFERENCE.md)**: Detailed documentation of the JSON-RPC 2.0 WebSocket API.

---

## 🌟 Features

- **Multi-Model Support**: Use Anthropic (Claude), OpenAI (GPT), Google (Gemini), DeepSeek, Mistral, Groq, Together AI, Perplexity, X.AI (Grok), or local models via **LM Studio**, Ollama, and OpenRouter.
- **Memory Engine (RAG & Standard)**: Expand your agent's knowledge through local vector and keyword storage.
    - **Standard Memory**: Keyword-based, encrypted local memory (Hive). Information is stored securely and retrieved via exact matches.
    - **RAG Memory (ObjectBox)**: Retrieval-Augmented Generation with semantic vector search, powered by a high-performance local ObjectBox database.
    - **Automatic Embeddings**: If an OpenRouter API key is available, RAG Memory defaults to the free `nvidia/llama-nemotron-embed-vl-1b-v2:free` model.
    - **Long-term Memory**: The agent can save important facts and find them later using semantic search.
- **Google Workspace Integration**:
    - **Gmail**: Read, search, **delete** (trash), and **send new emails**.
    - **Calendar**: List appointments, **add new events**, and **delete events**.
    - **Google Drive**: Search, list, and **delete** files.
- **Extensible Skills**:
    - **Modular System**: Load and manage skills to extend agent capabilities.
    - **Global & Agent-specific Skills**: Enable features for all agents or just specific profiles.
    - **Polyglot Runtimes**: Automatic management of **Python (venv)** and **Node.js (node_modules)** environments for skills.
    - **MCP Server Support**: Direct integration of Model Context Protocol servers as Ghost skills.
- **Advanced Tools**:
    - **Interactive Shell**: Execute shell scripts and Python code directly by the agent.
    - **Web Search**: Integrated web search via DuckDuckGo.
    - **File System**: Full access to read, write, and manage local files.
    - **GitHub**: Integration for managing repositories and issues.
    - **Chat Search (Ctrl+F)**: Fast in-session search with real-time highlighting and interactive navigation between matches.
- **Multi-Channel Messenger Support**:
    - **13 Channels**: Connect your agent to Telegram, Discord, WhatsApp (Meta), Slack, Signal, iMessage (BlueBubbles), MS Teams, Google Chat, Matrix, Nextcloud Talk, Tlon/Urbit, Zalo, and WebChat.
    - **Smart Sorting & Searching**: Easily manage your communication channels with integrated search filters and automated grouping by status.
    - **Resilient Connections**: Improved stability for messaging gateways (like Telegram), featuring automatic connection recovery and automated token/credential cleanup.
    - **DM Policies**: Granular control over who can message your bot (Pairing, Allowlist, Open, Disabled).
    - **Voice Messages & Local Dictation**: Supports receiving/sending voice messages and provides **high-performance local offline dictation** (Whisper `base` via Sherpa-ONNX) directly in the app.
- **Automated Agent Scheduling**:
    - **Cron-based Automation**: Create custom agents with specialized skills and schedule them using unix-style cron expressions (e.g., every 5 minutes).
    - **Real-time UI Sync**: New agents and reconfiguration changes are broadcasted immediately to the UI for a seamless experience.
    - **Interactive Error Recovery**: Resume long-running agent tasks after hits like rate-limits with manual "Continue" buttons directly in the UI.
- **Privacy & Security**:
    - **Human-In-The-Loop (HITL)**: Sensitive actions (file system, terminal, web access) require explicit user confirmation via interactive **YES / NO buttons** in the chat.
    - **Security Audit Logs**: Track and review all security-relevant actions and events directly in the UI.
    - **Prompt Hardening**: Advanced system prompts protect the agent from jailbreaks and instructions that attempt to bypass security rules.
    - **Network Restriction**: Complete isolation of the agent's web tools when high security is enabled to prevent unauthorized data exfiltration.
    - **Secure Vault**: API keys, agent configurations, and memory settings are encrypted with AES-256-GCM and stored only on your machine.
    - **AI Provider Search & Masking**: Sensitive API keys are masked by default and can be easily managed with a dedicated search filter.
- **Token Usage Tracking**: Monitor input and output tokens for every session to keep track of AI usage and costs.
    - **Real-time Monitoring**: Accurate token counting parsed directly from model response metadata.
    - **Cumulative Usage**: Integrated Usage Provider to track total consumption across sessions and restarts.
    - **Encrypted Database**: Chat sessions and avatars are stored in a local Hive database with additional encryption.
    - **Avatar Management**: Images are stored directly in the database for maximum privacy.
    - **Self-hosted**: Full control over your data and codebase.
- **Modern User Interface**:
    - **Clean Design**: A minimalist and intuitive "Monolith Black" interface for a distraction-free experience.
    - **Code Rendering**: Highlights and formats code blocks for easy reading.
    - **Settings Hub**: Centrally manage all your configurations, including dedicated tabs for Gateway, Security, and **Maintenance**.
- **System Stability & Maintenance**:
    - **Gateway Status & Live Logs**: Real-time monitoring of gateway performance, connected clients, and system logs directly in the app.
    - **Secure Shutdown**: Robust background shutdown process ensuring all databases are properly closed before the system exits or resets.
    - **Backups with Token Persistence**: Your API tokens are securely included in backups and automatically restored to the vault.


---

## 📜 License

Released under the permissive [MIT License](LICENSE), giving you full freedom to modify the code and distribute it without restrictions.