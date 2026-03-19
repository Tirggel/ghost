# Ghost Installs- & Setup-Anleitung (Deutsch)

Diese Anleitung führt dich schrittweise durch die Einrichtung von Ghost.

## 🚀 Schnellstart

### 1. Setup
Klone das Repository und installiere die Abhängigkeiten:
```bash
git clone https://github.com/your-username/ghost.git
cd ghost
dart pub get
cd ghost/app
flutter pub get
```

### 2. Voraussetzungen
- **Python 3.10+** (Erforderlich für STT/TTS und Skripte)
    - Installiere die Abhängigkeiten: `pip install -r requirements.txt`
- **Flutter SDK** (https://docs.flutter.dev/get-started/install)
- **ObjectBox Native Library:** Erforderlich für RAG Memory. Installiere sie für deine Plattform:
    - **Linux:** `bash docs/installation/scripts/install_linux.sh`
    - **macOS:** `bash docs/installation/scripts/install_mac.sh`
    - **Windows:** Führe `docs/installation/scripts/install.ps1` in der PowerShell aus

### 3. Gateway manuell starten
Falls du Docker nicht nutzt, kannst du das Gateway direkt starten.

**Wichtig beim ersten Start:**
Führe zuerst einen Reset aus, um die Datenbank korrekt zu initialisieren:
```bash
dart bin/ghost.dart gateway reset
# Beantworte die Fragen wie folgt:
# Are you sure you want to continue? (y/N): y
# Do you want to save the user and main agent configuration and restore them after reset? (y/N): n
# Do you want to start the gateway now? (y/N): y
```

**Normaler Start:**
Anschließend (oder bei jedem weiteren Mal) kannst du das Gateway so starten:
```bash
# Standard-Start (nutzt Standard-Config)
dart bin/ghost.dart gateway

# Starte die App (in einem neuen Terminal)
cd app
flutter run
```

### 4. Starten mit Docker (Empfohlen)
Du kannst das Ghost Backend (Gateway) über Docker starten, ohne Dart oder Flutter lokal zu installieren.

Für detaillierte Anweisungen (Linux, Windows, macOS), siehe: 👉 **[Docker Setup Guide](../DOCKER_SETUP.md)**

**Schnellstart:**
```bash
# Daemon im Hintergrund starten
docker-compose up -d ghost-daemon

# Logs einsehen
docker-compose logs -f
```

Starte dann die App für deine Plattform:
- **Linux:** `bash docs/installation/scripts/run.sh`
- **macOS:** `bash docs/installation/scripts/run_mac.sh`
- **Windows:** `docs/installation/scripts/run.bat`

### 5. Google Workspace Konfiguration (Optional)
Um Gmail, Kalender und Drive zu nutzen, musst du die entsprechenden APIs und OAuth-Clients in der Google Cloud Console konfigurieren.

Eine detaillierte Anleitung findest du hier:
👉 **[Detailliertes Google Workspace Setup (English)](../GOOGLE_WORKSPACE_SETUP_EN.md)**

Trage anschließend die **Client-IDs** und das **Client-Secret** in der Ghost App unter **Einstellungen > Integrationen** ein.

---

## 🛠️ Fehlerbehebung

Wenn etwas nicht wie erwartet funktioniert, versuche folgende Schritte:

### 1. Projekt bereinigen & Abhängigkeiten aktualisieren
Oft lösen veraltete Build-Artefakte Probleme. Führe dies im Hauptverzeichnis aus:
```bash
# Gateway & CLI Abhängigkeiten
dart pub get

# App Abhängigkeiten & Cleanup
cd app
flutter clean
flutter pub get
cd ..
```

### 2. System-Check (Doctor)
Nutze das eingebaute Diagnose-Werkzeug, um deine Konfiguration und den Status des Gateways zu prüfen:
```bash
dart bin/ghost.dart doctor
```

### 3. Kompletter Reset (Factory Reset)
**Achtung:** Dies löscht alle lokalen Daten, den Tresor und die Konfiguration!
```bash
dart bin/ghost.dart gateway reset
```

---

## 📚 Spezialisierte Anleitungen
Schau in unsere spezialisierte Dokumentation für fortgeschrittene Konfigurationen:
- **[Skills Development Guide](../SKILLS_GUIDE_DE.md)**: Erstelle deine eigenen KI-Funktionen.
- **[STT & TTS Setup](../STT_TTS_SETUP_DE.md)**: Lokale Hochleistungs-Spracherkennung/-synthese.
- **[RPC API Reference](../RPC_API_REFERENCE_DE.md)**: Baue deinen eigenen Client für das Gateway.
- **[Docker Setup Guide](../DOCKER_SETUP.md)**: Deployment via Docker.

---
