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

### 5. RAG & Workspace-RAG Einrichtung
Ghost enthält eine lokale Vektorsuchmaschine (RAG), die auf **ObjectBox** basiert.

1. **Native Bibliotheken**: Stelle vor der Aktivierung von RAG sicher, dass die native ObjectBox-C-Bibliothek für dein Betriebssystem installiert ist:
   - **Linux**: Führe `bash docs/installation/scripts/install_linux.sh` aus (installiert `libobjectbox.so` in Version `5.3.2`).
   - **macOS**: Führe `bash docs/installation/scripts/install_mac.sh` aus (installiert `libobjectbox.dylib` in Version `5.3.2`).
   - **Windows**: Führe `powershell docs/installation/scripts/install.ps1` aus (installiert `objectbox.dll` in Version `5.3.2`).
2. **Lokaler Provider erforderlich**: Um deine Privatsphäre zu schützen, erfordert das Indizieren lokaler Dokumente zwingend einen **lokalen Embedding-Provider** (z. B. Ollama oder LM Studio). Aktiviere Ollama/LM Studio und stelle sicher, dass ein gültiges Embedding-Modell (wie `qwen3-embedding` oder ähnlich) ausgewählt ist.
3. **Workspace-Ordner**:
   - Sobald RAG und Workspace-RAG in den Einstellungen (**Einstellungen > Gedächtnis**) aktiviert sind, erstelle einen Ordner namens `rag` in deinem konfigurierten Workspace-Verzeichnis.
   - Lege dort beliebige `.txt`, `.md`, `.json` oder `.pdf` Dateien ab. Diese werden inkrementell gescannt und indiziert (Shortest Job First: Kleine Dateien werden zuerst verarbeitet).
   - Alle Änderungen oder Löschungen von Dateien in diesem Ordner werden automatisch beim Start des Agenten oder bei neuen Nachrichten-Turns synchronisiert.

---

### 6. System-1 Entscheidungs-Middleware Einrichtung (Optional)
Ghost unterstützt eine lokale, nicht-autoregressive Entscheidungs-Middleware basierend auf ModernBERT INT8 ONNX:
1. **Python-Abhängigkeiten**:
   Installiere die benötigten Inferenz-Pakete:
   ```bash
   pip install -r docs/installation/requirements.txt
   ```
   (Erfordert `onnxruntime`, `transformers` und `numpy`).
2. **Modell-Datei**:
   Stelle sicher, dass `ghost_system1_int8.onnx` im Verzeichnis `scripts/models/ghost_system1_int8.onnx` liegt.
3. **Aktivierung**:
   Navigiere in der Ghost-App zu **Einstellungen > Sicherheit** und aktiviere die **System-1 Entscheidungs-Middleware**.

---

### 7. Desktop-Releases erstellen (Linux, Windows, macOS)

#### Lokaler Release-Build
Um ein eigenständiges Release-Paket für dein aktuelles Betriebssystem zu kompilieren (inklusive gebündelter nativer Bibliotheken und Laufzeit-Skripte in `ghost-releases/`):
- **Linux & macOS**:
  ```bash
  ./scripts/build_release.sh
  ```
- **Windows (PowerShell)**:
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\scripts\build_release.ps1
  ```

#### Multi-Plattform CI/CD via GitHub Actions
Da Flutter Desktop jeweils die nativen System-Compiler voraussetzt (MSVC unter Windows, Xcode unter macOS, Clang/GTK3 unter Linux), enthält Ghost eine vollautomatische Multi-Plattform-Pipeline unter [`.github/workflows/build-releases.yml`](../../.github/workflows/build-releases.yml):
- **Automatisches GitHub Release per Tag**: Beim Pushen eines Versions-Tags (`git tag v0.1.0 && git push origin v0.1.0`) baut GitHub Actions parallel **Linux (`x64`)**, **Windows (`x64`)** und **macOS (`Universal`)** auf nativen Cloud-Runnern und veröffentlicht die fertigen Archive (`ghost-linux-x64.tar.gz`, `ghost-windows-x64.zip`, `ghost-macos-universal.zip`) direkt unter **GitHub Releases**.
- **Manueller Start**: Alternativ lässt sich der Build jederzeit im Reiter **Actions** auf GitHub über **Run workflow** starten.

---

## 📚 Spezialisierte Anleitungen
Entdecke unsere spezialisierte Dokumentation für erweiterte Konfiguration und Entwicklung:
- **[System-1 Entscheidungs-Middleware](../SYSTEM1_MIDDLEWARE_DE.md)**: Detaillierte Architektur der lokalen ModernBERT-INT8-Entscheidungs-Engine.
- **[Skills Development Guide](../SKILLS_GUIDE_DE.md)**: Erstelle deine eigenen KI-Funktionen.
- **[STT & TTS Setup](../STT_TTS_SETUP_DE.md)**: Lokale Hochleistungs-Spracherkennung/-synthese.
- **[RPC API Referenz](../RPC_API_REFERENCE_DE.md)**: Dokumentation der JSON-RPC 2.0 Schnittstelle.

---
