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
- **Agents & Skills**: Extensible AI capabilities via a modular, Markdown-based system with **Opt-Out Progressive Skill Loading** (`disabledSkills` & on-demand `ghost_load_skill`).
- **Kanban & Task Orchestration**: Integrated Multi-Agent Kanban system for automated task management, dependency tracking (`dependsOnIds`), autonomous workflow transitions, and **Ontology-Driven Multi-Agent Routing & Delegation** (`HAT_KOMPETENZ`, `ghost_delegate_task`).
- **Automations & Scheduled Workflows**: Dedicated Automations workspace with human-friendly schedule modes, `+ Create with Prompt` AI drafting, dynamic `Auto (Ontology)` agent routing, provider/model overrides, and persistent run logs with full chat transcripts.
- **Design Systems**: Centralized theme management with custom branding, Markdown-based styling ("The Monolith"), and unified token distribution.
- **Memory Engine**: Triple-layer local knowledge powered by Hive (standard), ObjectBox (Workspace & long-term RAG), and a **Native ObjectBox Ontology & Knowledge Graph** (T-Box/A-Box rules, multi-hop inference, and Monolith Graph Explorer).
- **System-1 Decision Middleware**: Ultra-fast, non-autoregressive local ModernBERT INT8 ONNX engine for sub-15ms pre-flight security checks, categorical choice routing, tool payload risk scoring, smart HITL intent verification, and Memory-Poisoning protection.
- **Google Antigravity & ACP**: Native Agent Client Protocol (ACP) adapter over STDIO and WebSocket, connecting Ghost as an autonomous coding agent to Antigravity CLI (`agy`), Antigravity IDE, and Zed.

---

## 🚀 Installation & Setup

> 💡 **Tip**: If you just want to use Ghost, you can download the ready-to-run desktop releases for **Linux**, **Windows**, and **macOS** directly from **[GitHub Releases](https://github.com/Tirggel/ghost/releases)** (or locally from **[ghost-releases](./ghost-releases)**) 😊
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
> | **System-1 Middleware** | Sub-15ms local ModernBERT INT8 model for pre-flight safety & smart HITL | ✅ Enable (if model present) |
> | **Network Restriction** | Isolates web tools at high security level | ⚠️ As needed |
> | **Prompt Analyzers** | Advanced analysis of incoming prompts | ⚠️ As needed |
>
> For normal use, at least **level "medium"** is recommended (HITL + Prompt Hardening active).

### 🪄 Setup Wizard & System Restore
For new users, Ghost includes an interactive **Setup Wizard** that starts automatically if the application is not yet configured.

> [!TIP]
> **System Restore**: If you already have a backup, you can upload it in the very first step of the wizard. Ghost will automatically restore all agents, settings, and even your encrypted API tokens.

### 🛠️ Maintenance & Backup
Ghost features a dedicated **Reset / Maintenance Tab** (**Settings → Reset**) giving you full control over your system:
- **Factory Reset**: Completely wipe the application state and databases with explicit confirmation protection (`CONFIRM_RESET`), silent high-performance reset, and automatic reboot.
- **System Backup**: Create a selective, encrypted ZIP archive of your configuration (`config`, `vault`, `sessions`, `skills`, `design`, `automations`, and `memory` including portable `ontology_backup.json`).
- **Restore**: Import a backup archive and seamlessly restore your Ghost assistant's state without UI disruptions.
- **Design Systems**: Manage, export, and restore visual themes independently.

### 📚 Further Documentation
- **[Ontology & Knowledge Graph Guide](docs/ONTOLOGY_EN.md)**: T-Box/A-Box schema, 17 default predicates, multi-hop graph explorer, and System-1 Memory-Poisoning protection.
- **[Automations & Scheduled Workflows](docs/AUTOMATIONS_EN.md)**: Dedicated Automations workspace, `+ Create with Prompt` AI wizard, 6 cron schedule modes, `Auto (Ontology)` routing, and run transcripts.
- **[System-1 Decision Middleware](docs/SYSTEM1_MIDDLEWARE_EN.md)**: Deep dive into the local ModernBERT INT8 ONNX architecture, dataset generation, training in Colab, and sub-15ms pre-flight safety & smart HITL.
- **[Google Workspace Setup](docs/GOOGLE_WORKSPACE_SETUP_EN.md)**: Guide for configuring Gmail, Calendar, and Drive.
- **[Microsoft 365 Setup](docs/MICROSOFT_365_SETUP_EN.md)**: Guide for configuring Outlook and OneDrive via Azure AD.
- **[Payments, Wallet & Binance Setup](docs/PAYMENTS_SETUP_EN.md)**: Guide for configuring credit cards, EVM blockchain wallets, and Binance API trading (including spot and demo accounts).
- **[Skills Development Guide](docs/SKILLS_GUIDE.md)**: Learn about Opt-Out permissions, Progressive Disclosure (`ghost_load_skill`), and packaging custom AI skills.
- **[STT & TTS Setup](docs/STT_TTS_SETUP.md)**: Configure local speech recognition and synthesis.
- **[Multi-Channel Setup](docs/CHANNELS_EN.md)**: Detailed guide for connecting Telegram, Discord, WhatsApp, etc.
- **[RPC API Reference](docs/RPC_API_REFERENCE.md)**: Complete documentation of the JSON-RPC 2.0 WebSocket API (including Automations, Ontology, Kanban, Email, and ACP).
- **[VS Code Extension](docs/VSCODE_EXTENSION_EN.md)**: Official Visual Studio Code extension with sidebar chat, model switching, session controls, and editor actions.
- **[Chrome Extension](docs/CHROME_EXTENSION_EN.md)**: Official Google Chrome extension with Side Panel chat, web context, model switcher, and context-menu actions.
- **[Kanban & Task Orchestration](docs/KANBAN_ORCHESTRATION.md)**: How Multi-Agent Kanban, ontology routing, `/goal`, `/plan`, and `ghost_delegate_task` work.
- **[Google Antigravity & ACP Guide](docs/ANTIGRAVITY_ACP_EN.md)**: Connect Ghost to Google Antigravity CLI (`agy`), Zed, and Antigravity IDE with Guarded Autopilot.
- **[Design System Guidelines](DESIGN.md)**: Specifications and customization guide for the visual theme ("The Monolith").


---

## 🌟 Features

- **Multi-Model Support**: Use Anthropic (Claude), OpenAI (GPT), Google (Gemini), DeepSeek, Mistral, Groq, Together AI, Perplexity, X.AI (Grok), or local models via **LM Studio**, Ollama, and OpenRouter.
    - **Google Gemini 2.5 & 3**: Comprehensive support for Gemini 1.5, 2.0, 2.5 (`gemini-2.5-flash`), and Gemini 3 models. Features native Multi-Turn Function Calling with cryptographic Thought Signature preservation (`thought_signature`), automated resilience fallback (`skip_thought_signature_validator`), and clean separation of internal reasoning tokens (`reasoningContent`) from visible text.
    - **Streaming & Reasoning Models**: Real-time SSE streaming with chunk buffering, multi-turn tool call accumulation, and dedicated support for reasoning models (e.g. DeepSeek Reasoner, OpenAI o1/o3-mini).
    - **Tool-Call History Hygiene**: Automated multi-turn message cleansing across Anthropic, Gemini, and OpenAI providers. Assistant tool calls are strictly paired with succeeding tool response turns, preventing provider validation errors when loading historical sessions from disk.
    - **Local AI Sovereignty**: Complete offline privacy with LM Studio, Ollama, and vLLM.
- **Multi-Agent Kanban System**: 
    - **Task Orchestration**: Phase 3 task orchestration with automated status transitions.
    - **Dependencies**: Tasks can depend on other tasks (`dependsOnIds`), allowing for complex project workflows.
    - **Automated Execution**: The background `TaskOrchestrator` automatically moves tasks from "Backlog" to "To Do" when prerequisites are met.
    - **Goal-Oriented Execution (`/goal`)**: Messages starting with `/goal` automatically create a Kanban task. The agent enters an autonomous, multi-turn loop to implement the goal, updating status/comments. Tasks are set to `done` on success or `review` with detailed error traces on failure.
    - **Structured Planning Mode (`/plan`)**: Messages starting with `/plan` create a Kanban task and prompt the agent to perform read-only architectural analysis and generate a step-by-step roadmap without modifying the codebase. Once complete, the task is moved to `review` ready for user approval or `/goal` execution.
    - **Ontology-Driven Multi-Agent Routing & Delegation**:
        - **Automatic Competency Derivation (`HAT_KOMPETENZ`)**: Automatically derives agent domain competencies in the Knowledge Graph by combining explicit `competencies` tags, prompt/profile keyword analysis (`AgentDomainTaxonomy`), and allowed skill domains (`DARF_NUTZEN` → `GEHOERT_ZU_DOMAIN`).
        - **Intelligent `/goal`, `/plan` & Kanban Routing**: `TaskOrchestrator` evaluates all enabled agents across competency match, skill match, name match, and current workload penalty to automatically assign `/goal`, `/plan`, and `Auto (Ontologie)` Kanban tasks to the best-suited specialist.
        - **Dynamic Sub-Task Delegation (`ghost_delegate_task`)**: Agents can delegate specialized sub-tasks to the top-scoring specialist via the ontology graph, complete with `dry_run` routing previews and recursion depth protection (`maxDelegationDepth`).
- **Native ObjectBox Ontology & Knowledge Graph Memory**: Structured symbolic memory alongside vector RAG and standard key-value storage.
    - **T-Box & A-Box Rules**: Local ObjectBox graph (`OntologyRelationDef`, `OntologyNode`, `OntologyEdge`) with functional predicates (e.g., `WOHNT_IN`, `HEISST`, `ARBEITET_BEI` automatically replacing prior values) and transitive predicates (e.g., `LIEGT_IN`, `TEIL_VON`, `BENOETIGT_SKILL`) for multi-hop reasoning.
    - **Automatic Fact Extraction with System-1 Memory-Poisoning Protection**: Pre-turn graph context injection (`[KNOWLEDGE GRAPH]`) and async post-turn LLM fact extraction (`OntologyExtractor`), strictly gated behind System-1 security checks (`system1Middleware`, injection/HITL flags) so malicious or untrusted prompts cannot poison long-term memory.
    - **Graph Tools**: Agents can directly assert and traverse structured facts via `ghost_ontology_assert` and `ghost_ontology_query`.
    - **Multi-Hop Query Inspector & Monolith Graph Explorer**: Dedicated Settings UI (**Settings → Toolbox → Memory → Ontology**) to filter facts and entities (`All`, `Personal`, `Governance`, `Rules`), test 1–4 hop graph traversals with prompt previews, add facts manually, and import/export JSON backups.
- **Memory Engine (RAG & Standard)**: Expand your agent's knowledge through local vector and keyword storage.
    - **Standard Memory**: Keyword-based, encrypted local memory (Hive). Information is stored securely and retrieved via exact matches.
    - **RAG Memory (ObjectBox)**: Retrieval-Augmented Generation with semantic vector search, powered by a high-performance local ObjectBox database.
    - **Workspace RAG**: Automatically index files in a folder named `rag` within your workspace directory. Plain text files (`.txt`, `.md`, `.json` etc.) and PDFs will be parsed and indexed.
    - **Shortest Job First (SJF) Indexing**: Scanned files to index are sorted by size. Small files are indexed immediately, guaranteeing instant availability of lightweight documents while large files process in the background.
    - **Local Privacy Enforcement**: Workspace RAG is restricted to local embedding providers (e.g. Ollama, LM Studio) to ensure entire local documents are never sent to third-party cloud APIs.
    - **Automatic Embeddings**: If an OpenRouter API key is available, RAG Memory defaults to the free `nvidia/llama-nemotron-embed-vl-1b-v2:free` model.
    - **Long-term Memory**: The agent can save important facts and find them later using semantic search.
- **Google Workspace Integration**:
    - **Gmail**: Read, search, **delete** (trash), and **send new emails**.
    - **Calendar**: List appointments, **add new events**, and **delete events**.
    - **Google Drive**: Search, list, and **delete** files.
- **Microsoft 365 / Outlook Integration**:
    - **Outlook Mail**: Read, search, and **send emails** via Microsoft Graph.
    - **Outlook Calendar**: List appointments and **add new events**.
    - **OneDrive**: Search and list files in your cloud storage.
- **Google Antigravity & ACP (Agent Client Protocol)**:
    - **Standalone ACP Server (`bin/ghost_acp.dart`)**: Headless STDIO and WebSocket JSON-RPC 2.0 server directly spawnable by Google Antigravity CLI (`agy`), Zed, and editors.
    - **Guarded Autopilot**: Antigravity-style confirmation gating (`reviewMode` vs. `autoAccept`) for file modifications and terminal command execution.
    - **Workspace RAG Context Provider**: ObjectBox vector search exposed as an ACP context provider (`ghost-rag`) to feed relevant codebase context directly into prompts.
    - **Kanban-to-Task Bridge**: Seamlessly translates Antigravity multi-step plans into linked Ghost Kanban task pipelines with bidirectional progress synchronization.
    - **Registered Tools**: Exposes Ghost skills (`ghost_apply_patch`, `ghost_workspace_rag`, `ghost_kanban_pipeline`, `ghost_vault_keys`, `ghost_exec`, `ghost_web_search`) as native Antigravity tools.
- **Visual Studio Code & Google Antigravity IDE Integration**:
    - **Secondary Sidebar**: Embedded as a native tab in the Auxiliary Bar alongside Antigravity and Chat.
    - **Antigravity IDE Compatibility**: Fully compatible with the Google Antigravity IDE (VS Code fork) and standard VS Code.
    - **Guarded Autopilot Integration**: Review-mode dialogs with integrated diff view and confirmation gating before patches are applied.
    - **Dynamic Workspace Sync**: Real-time workspace file saving and state synchronization with Ghost's internal state.
    - **Editor Actions**: Right-click context menu (`👻 Ghost AI`) for code explanation, refactoring, unit test generation, and diagnostics error fixing.
    - **Real-Time Streaming**: Live token streaming (`agent.stream`) and tool execution activities (`agent.activity`).
- **Email Integration**:
    - **IMAP/SMTP Support**: Configure multiple standard email accounts directly in settings (using secure storage for credentials).
    - **Background Syncing**: The background `EmailPoller` automatically syncs mailboxes and stores cached emails locally.
    - **AI Processing**: Automated AI email analysis including priority classification, urgency checks, spam filtering, calendar detection, and generation of reply drafts based on the user's preferred writing style.
    - **Attachments**: List and download email attachments directly to your workspace.
- **Extensible Skills & Progressive Loading (Opt-Out)**:
    - **Opt-Out Skill Access (`disabledSkills`)**: Every agent (default and custom) receives access to all installed skills by default and can selectively opt out via `disabledSkills` (synchronized as `DARF_NUTZEN` permission edges in the Ontology Graph).
    - **Token-Efficient Progressive Disclosure (`ghost_load_skill`)**: Only a compact `[AVAILABLE SKILLS]` index is injected into the system prompt; agents load full `SKILL.md` instructions, `.venv`/Node/MCP runtime metadata, `BENOETIGT_SKILL` dependencies, and `ERFORDERT_HITL` security policies on demand via `ghost_load_skill`.
    - **Modular System**: Load and manage skills to extend agent capabilities.
    - **Agent-specific Skills**: Enable or disable features for specific agent profiles.
    - **UI-based Creation**: Create new skills directly in the app using pre-defined templates (Python/Node.js).
    - **Polyglot Runtimes**: Automatic management of **Python (venv)** and **Node.js (node_modules)** environments for skills.
    - **MCP Server Support**: Direct integration of Model Context Protocol servers as Ghost skills.
- **Design Systems**:
    - **Centralized Management**: Manage multiple visual themes in a dedicated settings hub.
    - **Markdown-based Styling**: Create and edit design systems using a simple, structured Markdown format (`DESIGN.md`).
    - **Backup & Restore**: Securely back up your design systems and restore them to any Ghost instance.
    - **Unified Branding**: Apply a consistent look and feel across all agents with standardized design tokens based on "The Monolith" aesthetic.
- **Advanced Tools**:
    - **Interactive Shell**: Execute shell scripts and Python code directly by the agent.
    - **Web Search**: Integrated web search via DuckDuckGo.
    - **File System**: Full access to read, write, and manage local files.
    - **Chat Search (Ctrl+F)**: Fast in-session search with real-time highlighting and interactive navigation between matches.
    - **GitHub**: Integration for managing repositories and issues.
- **Multi-Channel Messenger Support**:
    - **13 Channels**: Connect your agent to Telegram, Discord, WhatsApp (Meta), Slack, Signal, iMessage (BlueBubbles), MS Teams, Google Chat, Matrix, Nextcloud Talk, Tlon/Urbit, Zalo, and WebChat.
    - **Smart Sorting & Searching**: Easily manage your communication channels with integrated search filters and automated grouping by status.
    - **Resilient Connections**: Improved stability for messaging gateways (like Telegram), featuring automatic connection recovery and automated token/credential cleanup.
    - **DM Policies**: Granular control over who can message your bot (Pairing, Allowlist, Open, Disabled).
    - **Voice Messages & Local Dictation**: Supports receiving/sending voice messages and provides **high-performance local offline dictation** (Whisper `base` via Sherpa-ONNX) directly in the app.
- **Automations & Scheduled Workflows**:
    - **Dedicated Automations Workspace**: Accessible directly from the sidebar (`Automations`), offering real-time search, active/paused toggles, status badges, and one-click manual triggers (`Run Now`).
    - **`+ Create with Prompt` AI Wizard**: Describe a recurring workflow in plain language and let Ghost draft the title, exact non-rounded schedule, step-by-step instructions, and Ontology specialist match automatically.
    - **Human-Readable Schedule Picker**: Configure **Daily**, **Weekdays** (multi-time), **Weekly**, **Hourly**, **Interval** (1–59 min / 1–24 h), or **Custom Cron** schedules with live validation and next-3-runs prediction.
    - **Ontology Routing & Model Overrides**: Assign automations to **`Auto (Ontology)`** for dynamic specialist selection per run (or pin a specific agent plus provider/model overrides).
    - **Persistent Run History & Full Transcripts**: Inspect every run's status, duration, resolved agent/model, and summary—and click any run to view its complete `auto_*` chat transcript (kept separate from the main chat sidebar) with full ZIP backup support (`automations` section).
    - **Scheduled Custom Agents & Recovery**: Supports background cron schedules on custom agents (`cronSchedule`), real-time gateway sync, and interactive "Continue" recovery after rate limits.
- **Privacy & Security**:
    - **System-1 Decision Middleware**: Ultra-fast non-autoregressive local Cross-Encoder engine (`ModernBERT INT8 ONNX`) operating in sub-15ms on CPU. Features pre-flight prompt injection / jailbreak blocking, phishing & crypto-drainer screening, dynamic tool payload risk scoring (evaluating full shell commands, financial amounts, and contracts), and smart Human-In-The-Loop (HITL) semantic intent verification (distinguishing explicit approval from refusal).
    - **Human-In-The-Loop (HITL)**: Sensitive actions (file system, terminal, web access) require explicit user confirmation via interactive **YES / NO buttons** in the chat.
    - **Security Audit Logs**: Track and review all security-relevant actions and events directly in the UI.
    - **Prompt Hardening**: Advanced system prompts protect the agent from jailbreaks and instructions that attempt to bypass security rules.
    - **Network Restriction**: Complete isolation of the agent's web tools when high security is enabled to prevent unauthorized data exfiltration.
    - **Secure Vault**: API keys, agent configurations, and memory settings are encrypted with AES-256-GCM and stored only on your machine.
    - **AI Provider Search & Masking**: Sensitive API keys are masked by default and can be easily managed with a dedicated search filter.
- **Autonomous Billing & Payments**:
    - **Payment Execution**: Agents can perform online transactions on behalf of the user using the `execute_payment` tool if credit card credentials are configured in the secure vault.
    - **Budget Control**: Limits are configured via `BillingConfig`. Agents cannot exceed the balance, and users are notified to top up if transactions fail due to insufficient funds.
    - **HITL Integration**: Payments require explicit confirmation unless autonomous billing is explicitly enabled.
    - **Credit Card Transactions**: Persistent local tracking of credit card transaction history (SUCCESS/FAILED) with scrolling UI and automatic user notifications.
    - **Web3 & Crypto Integration**: Connecting decentralized crypto wallets via **Reown AppKit** (formerly WalletConnect) to view ERC-20 token balances and perform crypto top-ups directly in the app.
    - **Agent EVM Wallet (Autonomous Blockchain Payments)**: Configure a private key in the secure vault (`agent_wallet_private_key`) to allow the agent to run autonomous native/ERC-20 token payments (`execute_blockchain_payment`) and token swaps (`execute_token_swap`) on chains like BSC, Polygon, and Ethereum.
    - **Binance & Demo Trading**: Integrate Binance Spot and Demo Trading APIs (`binance_get_balances`, `binance_get_ticker`, `binance_create_order`, `binance_demo_get_balances`, `binance_demo_create_order`) allowing agents to query spot/demo balances, check tickers, and place live/simulated orders.
- **Token Usage Tracking**: Monitor input and output tokens for every session to keep track of AI usage and costs.
    - **Real-time Monitoring**: Accurate token counting parsed directly from model response metadata.
    - **Cumulative Usage**: Integrated Usage Provider to track total consumption across sessions and restarts.
    - **Encrypted Database**: Chat sessions and avatars are stored in a local Hive database with additional encryption.
    - **Avatar Management**: Images are stored directly in the database for maximum privacy.
    - **Self-hosted**: Full control over your data and codebase.
- **Modern User Interface & Session Management**:
    - **"The Monolith" Design**: A minimalist, high-contrast interface inspired by "Ghost Minimalist Noir" for a distraction-free experience.
    - **Folder Organization & Batch Deletion**: Group chats into folders and batch-delete entire session trees permanently from disk, guaranteeing complete transcript cleanup without reappearance.
    - **Smart Autoscroll**: Intelligent viewport tracking that respects your reading position during history inspection and automatically scrolls only on new prompts or active bottom streaming.
    - **Chat, Kanban, Automations & Email Navigation**: Quick access to conversations, Kanban tasks, scheduled Automations, and Email directly from the sidebar.
    - **Code Rendering**: Highlights and formats code blocks for easy reading.
    - **Settings Hub**: Centrally manage all configurations across dedicated tabs for **Profile**, **Agent Profiles** (`Main Agent`, `Custom Agents`), **API Management**, **Integrations**, **Channels**, **Payments**, **Toolbox** (`Skills`, `Design Systems`, `Memory` & Ontology, `Browser`, `Filesystem`), **Security**, **Gateway**, and **Reset**.
- **System Stability & Maintenance**:
    - **Gateway Status & Live Logs**: Real-time monitoring of gateway performance, connected clients, and system logs directly in the app.
    - **Secure Shutdown**: Robust background shutdown process ensuring all databases are properly closed before the system exits or resets.
    - **Backups with Token Persistence**: Your API tokens are securely included in backups and automatically restored to the vault.


---

## 📜 License

Released under the permissive [MIT License](LICENSE), giving you full freedom to modify the code and distribute it without restrictions.