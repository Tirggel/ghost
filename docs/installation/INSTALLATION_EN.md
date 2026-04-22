# Ghost Installation Guide (English)

This guide provides detailed instructions on how to set up and run Ghost.

## 🚀 Quick Start

### 1. Setup
Clone the repository and install dependencies:
```bash
git clone https://github.com/your-username/ghost.git
cd ghost
flutter pub get
```

### 2. Prerequisites
- **Python 3.10+** (Required for STT/TTS and scripts)
    - Install dependencies: `pip install -r requirements.txt`
- **Flutter SDK** (https://docs.flutter.dev/get-started/install)
- **ObjectBox Native Library:** Required for RAG Memory. Install it for your platform:
    - **Linux:** `bash docs/installation/scripts/install_linux.sh`
    - **macOS:** `bash docs/installation/scripts/install_mac.sh`
    - **Windows:** Run `scripts/install.ps1` in PowerShell

### 3. Run Ghost
The easiest way to run Ghost is to start the integrated application. The **Integrated Engine** (server logic) starts automatically within the app.

1. Start the app:
   ```bash
   flutter run
   ```
2. On your first start, the **Setup Wizard** will automatically launch to guide you through the configuration.
    - **Tip**: If you have a backup, you can upload it directly in the first step of the wizard (**Restore**).

---

### 4. Google Workspace Configuration (Optional)
To use Gmail, Calendar, and Drive, you must configure the corresponding APIs and OAuth clients in the Google Cloud Console.

A detailed step-by-step guide can be found here:
👉 **[Detailed Google Workspace Setup (English)](../GOOGLE_WORKSPACE_SETUP_EN.md)**

Then enter the corresponding **Client IDs** and the **Client Secret** in the Ghost app under **Settings > Integrations**.

---

## 🛠️ Troubleshooting

If something isn't working as expected, try the following steps:

### 1. Clean Project & Update Dependencies
Stale build artifacts often cause issues. Run these commands in the root directory:
```bash
flutter clean
flutter pub get
```

### 2. Maintenance & Reset
If you need to perform a factory reset or want to check the system status, use the integrated **Maintenance Tab** in the settings of the Ghost app:
- **Factory Reset**: Wipe all local data and configurations.
- **System Logs**: View live gateway logs and status.
- **Backup & Restore**: Create and import system backups.

---

## 📚 Specialized Guides
Check out our specialized documentation for advanced configuration and development:
- **[Skills Development Guide](../SKILLS_GUIDE.md)**: Create your own AI capabilities.
- **[STT & TTS Setup](../STT_TTS_SETUP.md)**: Local high-performance speech recognition/synthesis.
- **[RPC API Reference](../RPC_API_REFERENCE.md)**: Detailed documentation of the JSON-RPC 2.0 WebSocket API.

---
