# Ghost Installs- & Setup-Anleitung (Deutsch)

Diese Anleitung führt dich schrittweise durch die Einrichtung von Ghost.

## 🚀 Schnellstart

### 1. Setup
Klone das Repository und installiere die Abhängigkeiten:
```bash
git clone https://github.com/your-username/ghost.git
cd ghost
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

### 3. Ghost starten
Der einfachste Weg, Ghost zu nutzen, ist der Start der integrierten Anwendung. Die **integrierte Engine** (Server-Logik) startet automatisch innerhalb der App.

1. Starte die App:
   ```bash
   flutter run
   ```
2. Beim ersten Start öffnet sich automatisch der **Einrichtungsassistent**, der dich durch die Konfiguration führt.
    - **Tipp**: Falls du ein Backup hast, kannst du dieses direkt im ersten Schritt des Assistenten hochladen (**Wiederherstellen**).

---

### 4. Google Workspace Konfiguration (Optional)
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
flutter clean
flutter pub get
```

### 2. Wartung & Reset
Falls du einen Factory Reset durchführen möchtest oder den Systemstatus prüfen willst, nutze den integrierten **Wartungs-Tab** in den Einstellungen der Ghost App:
- **Factory Reset**: Alle lokalen Daten und Konfigurationen löschen.
- **System-Logs**: Live-Gateway-Protokolle und Status einsehen.
- **Backup & Wiederherstellung**: System-Backups erstellen und importieren.

---

## 📚 Spezialisierte Anleitungen
Schau in unsere spezialisierte Dokumentation für fortgeschrittene Konfigurationen:
- **[Skills Development Guide](../SKILLS_GUIDE_DE.md)**: Erstelle deine eigenen KI-Funktionen.
- **[STT & TTS Setup](../STT_TTS_SETUP_DE.md)**: Lokale Hochleistungs-Spracherkennung/-synthese.
- **[RPC API Referenz](../RPC_API_REFERENCE_DE.md)**: Dokumentation der JSON-RPC 2.0 Schnittstelle.

---
