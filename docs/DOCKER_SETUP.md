# 🐳 Docker Setup — Ghost

Diese Anleitung erklärt, wie du Ghost vollständig über Docker starten kannst — ohne Dart oder Flutter lokal zu installieren.

---

## Architektur

Ghost besteht aus zwei Teilen:

| Komponente | Beschreibung | Läuft in |
|---|---|---|
| **Backend (Gateway)** | Dart-Server, WebSocket auf Port 3000 | 🐳 Docker |
| **Frontend (App)** | Flutter Desktop-App (GUI) | 🖥️ Dein Betriebssystem |

Warum diese Trennung? Desktop-Apps benötigen direkten Zugriff auf das Grafik-System des Betriebssystems. Das lässt sich technisch in Docker abbilden, ist aber sehr aufwändig. Die sauberere Lösung ist: das pure Backend in Docker, grafische Oberfläche nativ.

---

## Voraussetzungen

### Auf allen Plattformen
- **[Docker Desktop](https://www.docker.com/products/docker-desktop/)** (Windows & macOS) oder **Docker + Docker Compose** (Linux)

### Linux (Fedora, Ubuntu, etc.)
```bash
# Docker installieren
sudo dnf install docker docker-compose-plugin  # Fedora
# oder
sudo apt install docker.io docker-compose-plugin  # Ubuntu/Debian

# Docker-Dienst starten und beim Systemstart aktivieren
sudo systemctl enable --now docker

# Eigenen User zur docker-Gruppe hinzufügen (kein sudo mehr nötig)
sudo usermod -aG docker $USER
newgrp docker
```

### Windows
1. [Docker Desktop für Windows](https://www.docker.com/products/docker-desktop/) installieren.
2. Sicherstellen, dass **WSL 2** aktiviert ist (Docker Desktop fragt beim ersten Start).

### macOS
1. [Docker Desktop für macOS](https://www.docker.com/products/docker-desktop/) installieren.
2. Docker Desktop starten und auf das Whale-Icon in der Menüleiste warten bis es stabil ist.

---

## Installation & Start

### Schritt 1: Repository klonen

```bash
git clone https://github.com/your-username/ghost.git
cd ghost
```

### Schritt 2: Backend-Gateway starten

Das Backend (Dart-Gateway) läuft im Docker-Container.

```bash
docker-compose up -d ghost-daemon
```

Prüfen ob der Gateway läuft:
```bash
docker-compose logs -f
# Du solltest sehen: 👻 Ghost Gateway running on ws://127.0.0.1:3000
```

### Schritt 3: Flutter-App starten

Wähle je nach Betriebssystem das passende Startskript:

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

> **Hinweis:** Beim ersten Start ist noch keine vorkompilierte App vorhanden. Die Skripte fallen dann automatisch auf `flutter run -d <platform>` zurück (Flutter SDK auf dem Host nötig). Wie du eine fertige Binary erzeugst, siehst du im nächsten Abschnitt.

---

## Flutter-App in Docker bauen (optional)

Du kannst die **Linux-Version** der Flutter-App vollständig in Docker kompilieren, ohne Flutter lokal installiert zu haben:

```bash
# Baut die App und legt das Bundle in ./dist/ ab
docker-compose --profile build run --rm builder
```

Nach dem Build kannst du die App direkt starten:
```bash
./dist/app
```

> **Wichtig:** Dieser Docker-Build erzeugt nur eine **Linux-Binary**. Für Windows und macOS muss die App auf dem jeweiligen Betriebssystem nativ gebaut werden (`flutter build windows` / `flutter build macos`).

---

## Verwaltung

### Gateway stoppen
```bash
docker-compose down
```

### Gateway neu starten
```bash
docker-compose restart ghost-daemon
```

### Factory Reset (alle Daten löschen)
```bash
# Gateway stoppen
docker-compose down

# Reset-Befehl als Einmal-Container ausführen
docker-compose run --rm ghost-daemon reset

# Gateway danach neu starten
docker-compose up -d ghost-daemon
```

### Konfiguration & API-Keys setzen
```bash
docker-compose run --rm ghost-daemon config set-key --service openai --key DEIN_KEY
docker-compose run --rm ghost-daemon config set-key --service anthropic --key DEIN_KEY
docker-compose run --rm ghost-daemon config set-key --service telegram --key DEIN_KEY
```

**Hinweis:** Das Docker-Image enthält nun automatisch die native **ObjectBox**-Library, die für RAG Memory benötigt wird. Es ist kein manuelles Setup der nativen Abhängigkeiten im Container nötig.

### Logs ansehen
```bash
docker-compose logs -f
```

---

## Wo werden die Daten gespeichert?

Das `docker-compose.yml` legt alle Daten des Backends (Datenbank, Vault, Konfiguration) im Verzeichnis `~/.ghost` auf **deinem Rechner** ab. Das Verzeichnis wird in den Container gemounted. Beim Löschen des Containers bleiben deine Daten erhalten.

| Datei/Ordner | Inhalt |
|---|---|
| `~/.ghost/ghost.json` | Allgemeine Konfiguration |
| `~/.ghost/vault.enc` | Verschlüsseltes Herzstück: API-Keys, Agentenprofile, Memory-Einstellungen |
| `~/.ghost/sessions.hive` | Chat-Verlauf (verschlüsselt) |
| `~/.ghost/objectbox/` | Hochleistungs-Vektordatenbank für RAG |

---

## Fehlerbehebung

### `Permission denied` beim Docker-Socket (Linux)
```bash
sudo usermod -aG docker $USER && newgrp docker
```

### `Cannot open display: :0` (Linux, GUI startet nicht)
Auf Linux mit Wayland kann Docker nicht direkt auf dem Desktop zeichnen. Nutze stattdessen:
```bash
cd app && flutter run -d linux
```

### Auf Fedora: Probleme mit Dateiberechtigungen im Volume
Das `:Z` am Ende des Volume-Pfades in `docker-compose.yml` sorgt für die richtigen SELinux-Labels und sollte das Problem beheben.
