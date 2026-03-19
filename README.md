# Ghost 👻

<p align="center">
  <img src="app/assets/images/ghost-mini.png" alt="Ghost Logo" width="300">
</p>

<a href="https://aquawitchcode.dev/">Developer Website</a> &nbsp; &bull; &nbsp; <a href="README_de.md">Deutsch</a>

**Ghost** is a lightweight, self-hosted personal AI Assistant built with [Dart](https://github.com/dart-lang) and [Flutter](https://github.com/flutter) by Google.

### 🏗️ Architecture at a Glance

Ghost follows a modular, client-server architecture:
- **Gateway (Daemon)**: A high-performance Dart-based WebSocket server that manages AI agents, memories, and tools.
- **App (UI)**: A modern Flutter-based desktop application (Linux, macOS, Windows) and web interface.
- **Agents & Skills**: Pluggable AI brains and capabilities that can be extended via a simple markdown-based system.
- **Memory Engine**: Dual-mode storage using Hive (Standard) and ObjectBox (RAG) for secure, local knowledge.

---

## 🚀 Installation & Setup

To get started with Ghost, follow our detailed installation guide:

👉 **[Installation & Setup Guide (English)](docs/installation/INSTALLATION_EN.md)**
👉 **[Installs- & Setup-Anleitung (Deutsch)](docs/installation/INSTALLATION_DE.md)**

### 📚 Advanced Documentation
- **[Skills Development Guide](docs/SKILLS_GUIDE.md)**: Learn how to create and package your own AI skills.
- **[STT & TTS Setup](docs/STT_TTS_SETUP.md)**: Configure high-performance local speech recognition and synthesis.
- **[RPC API Reference](docs/RPC_API_REFERENCE.md)**: Detailed documentation for the JSON-RPC 2.0 WebSocket API.
- **[Docker Setup Guide](docs/DOCKER_SETUP_EN.md)**: Deployment and management via Docker.

---

## 🌟 Features

- **Multi-Model Support**: Use Anthropic (Claude), OpenAI (GPT), Google (Gemini), DeepSeek, Mistral, Groq, Together AI, Perplexity, X.AI (Grok), or local models via Ollama and OpenRouter.
- **Memory Engine (RAG & Standard)**: Enhance your agent's knowledge with local vector and keyword storage.
    - **Standard Memory**: Keyword-based encrypted local memory (Hive). Information is stored securely and retrieved via exact matches.
    - **RAG Memory (ObjectBox)**: Retrieval-Augmented Generation using semantic vector search powered by a high-performance local ObjectBox database.
    - **Automatic Embeddings**: If an OpenRouter API key is provided, RAG Memory automatically defaults to using the free `nvidia/llama-nemotron-embed-vl-1b-v2:free` model for producing vector embeddings.
    - **Long-Term Memory**: The agent can store important facts and retrieve them later using semantic search.
- **Google Workspace Integration**:
    - **Gmail**: Read, search, **delete** (trash), and **send new emails**.
    - **Calendar**: List upcoming meetings, **add new events**, and **delete events**.
    - **Google Drive**: Search, list, and **delete** files.
- **Extensible Skills**:
    - **Modular System**: Install and manage skills to expand the agent's capabilities.
    - **Global & Agent-Specific Skills**: Enable skills globally or for specific agent profiles.
- **Advanced Tools**:
    - **Interactive Shell**: Execute shell scripts and Python code directly through the agent.
    - **Web Search**: Integrated web search via DuckDuckGo.
    - **File System**: Full access to read, write, and manage local files.
    - **GitHub**: Integration for managing repositories and issues.
- **Secure Communication**:
    - **Telegram Bot**: Control your agent securely on the go.
      - **Voice Messages**: The agent supports receiving and sending voice messages.
    - **Google Chat**: Integration as an app in Google Chat spaces.
- **Privacy & Security**:
    - **Secure Vault**: API keys, individual **Agent** configurations, **Memory** settings, and **Custom Agents** are encrypted with AES-256-GCM and stored only on your machine.
    - **Encrypted Database**: Chat sessions and avatars are stored in a local Hive database with additional encryption.
    - **Avatar Management**: User, identity, and agent images are stored directly within the database for maximum privacy.
    - **Self-Hosted**: Full control over your data and codebase.

---

## 📜 License

Provided under the Permissive [MIT License](LICENSE) to allow full freedom to build, change, and distribute without restrictions.
