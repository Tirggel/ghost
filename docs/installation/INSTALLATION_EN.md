# Ghost Installation Guide (English)

This guide provides detailed instructions on how to set up, build, and configure Ghost from source.

---

## 🚀 Quick Start

### 1. Clone & Install Dependencies
Clone the repository and install Flutter/Dart dependencies:
```bash
git clone https://github.com/Tirggel/ghost.git
cd ghost
flutter pub get
```

### 2. Prerequisites
- **Dart SDK `^3.8.0` & Flutter SDK** ([Flutter Install](https://docs.flutter.dev/get-started/install))
- **Python 3.10+** (Required for System-1 Decision Middleware and channel STT/TTS scripts):
  ```bash
  pip install -r docs/installation/requirements.txt
  ```
- **ObjectBox Native Library (`v5.3.2`)**: Required for RAG Memory and the Native Ontology Knowledge Graph.
  - **Linux:** `bash docs/installation/scripts/install_linux.sh`
  - **macOS:** `bash docs/installation/scripts/install_mac.sh`
  - **Windows:** `powershell -ExecutionPolicy Bypass -File docs/installation/scripts/install.ps1`

### 3. Run Ghost
The easiest way to run Ghost is to start the integrated application. The **Integrated Engine** (gateway, agent loop, ObjectBox stores, Kanban orchestrator, and Automations scheduler) starts automatically within the app:
```bash
flutter run
```
On first launch, the interactive **Setup Wizard** guides you through configuration. If you already have a backup ZIP, you can upload it on step 1 via **Restore**.

### 4. External Integrations (Optional)
- **Google Workspace (Gmail, Calendar, Drive)**: Configure OAuth clients in Google Cloud Console following **[Google Workspace Setup (English)](../GOOGLE_WORKSPACE_SETUP_EN.md)**, then enter your Client IDs and Client Secret under **Settings → Integrations**.
- **Microsoft 365 (Outlook Mail, Calendar, OneDrive)**: Configure an Entra ID app registration following **[Microsoft 365 Setup (English)](../MICROSOFT_365_SETUP_EN.md)**.

---

## 🧠 Memory, RAG & Ontology Setup

Ghost uses **ObjectBox (`5.3.2`)** locally for both semantic RAG (`objectbox_rag`) and the structured Ontology Knowledge Graph (`objectbox_ontology`).

1. **Native Libraries**: Ensure the ObjectBox C library is installed for your OS (see Step 2 above).
2. **RAG & Local Embedding Requirement**: Under **Settings → Toolbox → Memory**, select an embedding provider/model and click Test & Enable. To protect local privacy, **Workspace RAG** (automatically indexing `.txt`, `.md`, `.json`, and `.pdf` files placed inside `<workspace>/rag/`) requires a local embedding provider such as **Ollama** or **LM Studio**.
3. **Ontology & Knowledge Graph**: Enabled by default under **Settings → Toolbox → Memory → Ontology**. Includes T-Box/A-Box persistence, multi-hop inference, and System-1-gated post-turn fact extraction (see **[Ontology & Knowledge Graph Guide](../ONTOLOGY_EN.md)**).

---

## 🛡️ System-1 Decision Middleware Setup (Optional)

Ghost includes a local non-autoregressive decision middleware powered by ModernBERT INT8 ONNX:
1. **Python Dependencies**:
   ```bash
   pip install -r docs/installation/requirements.txt
   ```
   *(Installs `onnxruntime`, `transformers`, and `numpy`, along with `faster-whisper`, `piper-tts`, and `pathvalidate`.)*
2. **Model File**: Ensure `ghost_system1_int8.onnx` is placed at `scripts/models/ghost_system1_int8.onnx`.
3. **Activation**: Open **Settings → Security** and toggle **System-1 Decision Middleware**.

---

## 🤖 Running the Headless ACP CLI (`bin/ghost_acp.dart`)

Ghost can also run headlessly (without Flutter UI) as an **Agent Client Protocol (ACP)** server for Google Antigravity CLI (`agy`), Zed, or Dev Containers:
```bash
# STDIO mode
dart bin/ghost_acp.dart --workspace /path/to/project

# WebSocket mode
dart bin/ghost_acp.dart --ws --port 3001 --workspace /path/to/project
```
See **[Google Antigravity & ACP Guide](../ANTIGRAVITY_ACP_EN.md)** for full configuration details.

---

## 📦 Building Desktop Releases (Linux, Windows, macOS)

### Local Release Build
To compile a standalone release bundle for your current OS (including bundled native libraries and runtime scripts in `ghost-releases/`):
- **Linux & macOS** *(macOS requires deployment target `11.0+`)*:
  ```bash
  ./scripts/build_release.sh
  ```
- **Windows (PowerShell)**:
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\scripts\build_release.ps1
  ```

### Multi-Platform CI/CD via GitHub Actions
Because Flutter Desktop requires native platform toolchains (MSVC on Windows, Xcode on macOS, Clang/GTK3 on Linux), Ghost includes an automated workflow in [`.github/workflows/build-releases.yml`](../../.github/workflows/build-releases.yml):
- **Automatic Release on Tag**: Pushing a version tag (`git tag v0.2.0 && git push origin v0.2.0`) compiles **Linux (`x64`)**, **Windows (`x64`)**, and **macOS (`Universal`)** in parallel and publishes `ghost-linux-x64.tar.gz`, `ghost-windows-x64.zip`, and `ghost-macos-universal.zip` to **GitHub Releases**.
- **Manual Trigger**: Run the workflow anytime under the **Actions** tab on GitHub via **Run workflow**.

---

## 🛠️ Developer Notes & Troubleshooting

### 1. Code Generation (`build_runner`) & Headless ObjectBox Rule
Whenever you modify ObjectBox `@Entity()` classes or `@JsonSerializable()` models, regenerate code with:
```bash
dart run build_runner build --delete-conflicting-outputs
```
> [!IMPORTANT]
> `objectbox_generator` overwrites `lib/objectbox.g.dart` with an unconditional `objectbox_flutter_libs` import, which pulls in `dart:ui` and breaks `bin/ghost_acp.dart`. Always restore the conditional import via `lib/engine/infra/objectbox_flutter_libs_stub.dart` immediately after running `build_runner`.

### 2. Clean Project & Update Dependencies
```bash
flutter clean
flutter pub get
```

### 3. Maintenance, Backup & Reset
Open **Settings → Reset** inside the Ghost app to create selective encrypted ZIP backups (`config`, `vault`, `sessions`, `skills`, `design`, `automations`, `memory`), restore archives, inspect live Gateway logs, or perform a Factory Reset.

---

## 📚 Specialized Guides
- **[Ontology & Knowledge Graph Guide](../ONTOLOGY_EN.md)**: T-Box/A-Box architecture, graph explorer, and Memory-Poisoning protection.
- **[Automations & Scheduled Workflows](../AUTOMATIONS_EN.md)**: Human-friendly cron schedules, `+ Create with Prompt`, and run transcripts.
- **[Kanban & Task Orchestration](../KANBAN_ORCHESTRATION.md)**: Multi-agent workflows, ontology routing, `/goal`, `/plan`, and `ghost_delegate_task`.
- **[System-1 Decision Middleware](../SYSTEM1_MIDDLEWARE_EN.md)**: Local ModernBERT INT8 ONNX engine, risk scoring, and smart HITL.
- **[Skills Development Guide](../SKILLS_GUIDE.md)**: Opt-out permissions, Progressive Disclosure (`ghost_load_skill`), and custom skills.
- **[Google Antigravity & ACP Guide](../ANTIGRAVITY_ACP_EN.md)**: STDIO/WebSocket ACP server and Guarded Autopilot.
- **[VS Code Extension](../VSCODE_EXTENSION_EN.md)** & **[Chrome Extension](../CHROME_EXTENSION_EN.md)**
- **[Multi-Channel Setup](../CHANNELS_EN.md)** & **[STT & TTS Setup](../STT_TTS_SETUP.md)**
- **[Payments, Wallet & Binance Setup](../PAYMENTS_SETUP_EN.md)**
- **[RPC API Reference](../RPC_API_REFERENCE.md)**
