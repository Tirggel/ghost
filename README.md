# Ghost 👻

<p align="center">
  <img src="app/assets/icons/logo/ghost-large.png" width="300" alt="Ghost Logo">
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

Ghost follows a modular client-server architecture:
- **Gateway (Daemon)**: A high-performance, Dart-based WebSocket server that manages AI agents, memory, and tools.
- **App (UI)**: A modern, Flutter-based desktop application (Linux, macOS, Windows) and a web interface.
- **Agents & Skills**: Extensible AI brains and capabilities that can be added via a simple, Markdown-based system.
- **Memory Engine**: Dual-mode memory using Hive (standard) and ObjectBox (RAG) for secure, local knowledge.

---

## 🚀 Installation & Setup

> 💡 **Tip**: If you just want to use Ghost, you can download the ready-to-run programs for your platform (Linux, Windows, Mac) here: **[ghost-releases](./ghost-releases)** 😊
>
> *The following installation guide is intended for **developers** who want to build or modify Ghost themselves.*

To get started with Ghost, please follow our detailed installation guide:

👉 **[Installation & Setup Guide (English)](docs/installation/INSTALLATION_EN.md)**
👉 **[Installs- & Setup-Anleitung (Deutsch)](docs/installation/INSTALLATION_DE.md)**

### 📚 Further Documentation
- **[Skills Development Guide](docs/SKILLS_GUIDE.md)**: Learn how to create and package your own AI skills.
- **[STT & TTS Setup](docs/STT_TTS_SETUP.md)**: Configure local speech recognition and synthesis.
- **[RPC API Reference](docs/RPC_API_REFERENCE.md)**: Detailed documentation of the JSON-RPC 2.0 WebSocket API.
- **[Docker Setup Guide](docs/DOCKER_SETUP_EN.md)**: Deployment and management via Docker.

---

## 🌟 Features

- **Multi-Model Support**: Use Anthropic (Claude), OpenAI (GPT), Google (Gemini), DeepSeek, Mistral, Groq, Together AI, Perplexity, X.AI (Grok), or local models via Ollama and OpenRouter.
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
- **Secure Communication**:
    - **Telegram Bot**: Control your agent securely on the go.
        - **Voice Messages**: Agent supports receiving and sending voice messages.
    - **Google Chat**: Integration as an app in Google Chat spaces.
- **Automated Agent Scheduling**:
    - **Cron-based Automation**: Create custom agents with specialized skills and schedule them using unix-style cron expressions (e.g., every 5 minutes).
    - **Real-time UI Sync**: New agents and configuration changes are broadcasted immediately to the UI for a seamless experience.
- **Privacy & Security**:
    - **Secure Vault**: API keys, agent configurations, and memory settings are encrypted with AES-256-GCM and stored only on your machine.
    - **Encrypted Database**: Chat sessions and avatars are stored in a local Hive database with additional encryption.
    - **Avatar Management**: Images are stored directly in the database for maximum privacy.
    - **Self-hosted**: Full control over your data and codebase.

---

## 📜 License

Released under the permissive [MIT License](LICENSE), giving you full freedom to modify the code and distribute it without restrictions.