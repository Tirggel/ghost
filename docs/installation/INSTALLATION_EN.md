# Ghost Installation Guide (English)

This guide provides detailed instructions on how to set up and run Ghost.

## 🚀 Quick Start

### 1. Setup
Clone the repository and install dependencies:
```bash
git clone https://github.com/your-username/ghost.git
cd ghost
dart pub get
cd ghost/app
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

### 3. Run the Gateway (Manually)
If you are not using Docker, you can start the gateway directly.

**Option A: Setup Wizard (Recommended)**
The easiest way to configure Ghost for the first time is to use the built-in **Setup Wizard**.
1. Start the gateway: `dart bin/ghost.dart gateway`
2. Start the app: `cd app && flutter run`
3. The app will automatically detect if a setup is required and guide you through the process.

**Option B: Manual Reset (CLI)**
If you prefer the command line, perform a reset to correctly initialize the database:
```bash
dart bin/ghost.dart gateway reset
# Answer the questions as follows:
# Are you sure you want to continue? (y/N): y
# Do you want to save the user and main agent configuration and restore them after reset? (y/N): n
# Do you want to start the gateway now? (y/N): y
```

**Normal Start:**
Afterwards (or every other time), you can start the gateway like this:
```bash
# Standard start (uses default config)
dart bin/ghost.dart gateway

# Start the app (in a new terminal)
cd app
flutter run
```

### 4. Run with Docker (Recommended)
You can run the Ghost backend daemon using Docker without installing Dart or Flutter.

For full instructions (Linux, Windows, macOS), see: 👉 **[Docker Setup Guide](../DOCKER_SETUP_EN.md)**

**Quick Start:**
```bash
# Start the daemon in the background
docker-compose up -d ghost-daemon

# View the logs
docker-compose logs -f
```

Then start the app on your platform:
- **Linux:** `bash docs/installation/scripts/run.sh`
- **macOS:** `bash docs/installation/scripts/run_mac.sh`
- **Windows:** `docs/installation/scripts/run.bat`

### 5. Google Workspace Configuration (Optional)
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
# Gateway & CLI dependencies
dart pub get

# App dependencies & cleanup
cd app
flutter clean
flutter pub get
cd ..
```

### 2. System Check (Doctor)
Use the built-in diagnostic tool to check your configuration and gateway status:
```bash
dart bin/ghost.dart doctor
```

### 3. Complete Reset (Factory Reset)
**Warning:** This will delete all local data, the vault, and your configuration!
```bash
dart bin/ghost.dart gateway reset
```

---

## 📚 Specialized Guides
Check out our specialized documentation for advanced configuration and development:
- **[Skills Development Guide](../SKILLS_GUIDE.md)**: Create your own AI capabilities.
- **[STT & TTS Setup](../STT_TTS_SETUP.md)**: Local high-performance speech recognition/synthesis.
- **[RPC API Reference](../RPC_API_REFERENCE.md)**: Build your own client for the Gateway.
- **[Docker Setup Guide](../DOCKER_SETUP_EN.md)**: Deployment via Docker.

---
