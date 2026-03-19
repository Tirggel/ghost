# 🐳 Docker Setup — Ghost

This guide explains how to run Ghost using Docker — without needing to install Dart or Flutter locally.

---

## Architecture

Ghost consists of two parts:

| Component | Description | Runs in |
|---|---|---|
| **Backend (Gateway)** | Dart server, WebSocket on port 3000 | 🐳 Docker |
| **Frontend (App)** | Flutter Desktop GUI | 🖥️ Your operating system |

Why this separation? Desktop apps require direct access to the operating system's graphics system. While technically possible inside Docker, it is very complex and platform-dependent. The cleaner solution is: backend in Docker, GUI natively on the host.

---

## Prerequisites

### All Platforms
- **[Docker Desktop](https://www.docker.com/products/docker-desktop/)** (Windows & macOS) or **Docker + Docker Compose** (Linux)

### Linux (Fedora, Ubuntu, etc.)
```bash
# Install Docker
sudo dnf install docker docker-compose-plugin  # Fedora
# or
sudo apt install docker.io docker-compose-plugin  # Ubuntu/Debian

# Start and enable Docker service
sudo systemctl enable --now docker

# Add your user to the docker group (no more sudo needed)
sudo usermod -aG docker $USER
newgrp docker
```

### Windows
1. Install [Docker Desktop for Windows](https://www.docker.com/products/docker-desktop/).
2. Make sure **WSL 2** is enabled (Docker Desktop will prompt you on first launch).

### macOS
1. Install [Docker Desktop for macOS](https://www.docker.com/products/docker-desktop/).
2. Launch Docker Desktop and wait until the whale icon in the menu bar is stable.

---

## Installation & Startup

### Step 1: Clone the Repository

```bash
git clone https://github.com/your-username/ghost.git
cd ghost
```

### Step 2: Start the Backend Gateway

The backend (Dart gateway) runs inside a Docker container.

```bash
docker-compose up -d ghost-daemon
```

Verify that the gateway is running:
```bash
docker-compose logs -f
# You should see: 👻 Ghost Gateway running on ws://127.0.0.1:3000
```

### Step 3: Start the Flutter App

Choose the appropriate start script for your operating system:

**Linux:**
```bash
./run.sh
```

**macOS:**
```bash
chmod +x run_mac.sh
./run_mac.sh
```

**Windows:**
```bat
run.bat
```

> **Note:** On the first launch, no precompiled app bundle exists yet. The scripts will automatically fall back to `flutter run -d <platform>` (requires Flutter SDK on the host). See the next section to create a prebuilt binary.

---

## Build the Flutter App in Docker (Optional / Linux only)

You can compile the **Linux version** of the Flutter app entirely inside Docker — no local Flutter installation required:

```bash
# Builds the app and places the bundle into ./dist/
docker-compose --profile build run --rm builder
```

After the build, launch the app directly:
```bash
./dist/app
```

> **Note:** This Docker build only produces a **Linux binary**. For Windows and macOS, the app must be built natively on each platform (`flutter build windows` / `flutter build macos`).

---

## Management

### Stop the Gateway
```bash
docker-compose down
```

### Restart the Gateway
```bash
docker-compose restart ghost-daemon
```

### Factory Reset (delete all data)
```bash
# Stop the gateway
docker-compose down

# Run the reset command in a one-time container
docker-compose run --rm ghost-daemon reset

# Restart the gateway afterwards
docker-compose up -d ghost-daemon
```

### Set Configuration & API Keys
```bash
docker-compose run --rm ghost-daemon config set-key --service openai --key YOUR_KEY
docker-compose run --rm ghost-daemon config set-key --service anthropic --key YOUR_KEY
docker-compose run --rm ghost-daemon config set-key --service telegram --key YOUR_KEY
```

**Note:** The Docker image now automatically includes the native **ObjectBox** library required for RAG Memory. No additional native setup is needed inside the container.

### View Logs
```bash
docker-compose logs -f
```

---

## Where is Data Stored?

The `docker-compose.yml` stores all backend data (database, vault, configuration) in the `~/.ghost` directory **on your machine**. This directory is mounted into the container. Your data remains intact even if you remove the container.

| File/Folder | Contents |
|---|---|
| `~/.ghost/ghost.json` | General configuration |
| `~/.ghost/vault.enc` | Encrypted heart: API keys, agent profiles, memory settings |
| `~/.ghost/sessions.hive` | Chat history store (encrypted) |
| `~/.ghost/objectbox/` | High-performance RAG vector database |

---

## Troubleshooting

### `Permission denied` on Docker socket (Linux)
```bash
sudo usermod -aG docker $USER && newgrp docker
```

### `Cannot open display: :0` (Linux, GUI won't start)
On Linux with Wayland, Docker cannot directly render a window to the desktop. Use the native approach instead:
```bash
cd app && flutter run -d linux
```

### Fedora: File permission issues with the volume
The `:Z` suffix on the volume path in `docker-compose.yml` sets the correct SELinux labels and should resolve permission issues.
