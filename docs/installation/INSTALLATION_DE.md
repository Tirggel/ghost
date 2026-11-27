# Ghost Installations- & Setup-Anleitung (Deutsch)

Diese Anleitung führt dich schrittweise durch Einrichtung, Build und Konfiguration von Ghost aus dem Quellcode.

---

## 🚀 Schnellstart

### 1. Repository klonen & Abhängigkeiten installieren
```bash
git clone https://github.com/Tirggel/ghost.git
cd ghost
flutter pub get
```

### 2. Voraussetzungen
- **Dart SDK `^3.8.0` & Flutter SDK** ([Flutter Installation](https://docs.flutter.dev/get-started/install))
- **Python 3.10+** (Erforderlich für System-1 Entscheidungs-Middleware und Kanal-STT/TTS-Skripte):
  ```bash
  pip install -r docs/installation/requirements.txt
  ```
- **ObjectBox Native Library (`v5.3.2`)**: Erforderlich für RAG Memory und den nativen Ontologie Knowledge Graph.
  - **Linux:** `bash docs/installation/scripts/install_linux.sh`
  - **macOS:** `bash docs/installation/scripts/install_mac.sh`
  - **Windows:** `powershell -ExecutionPolicy Bypass -File docs/installation/scripts/install.ps1`

### 3. Ghost starten
Der einfachste Start erfolgt über die integrierte Anwendung. Die **integrierte Engine** (Gateway, Agent-Loop, ObjectBox-Stores, Kanban-Orchestrator und Automations-Scheduler) startet automatisch innerhalb der App:
```bash
flutter run
```
Beim ersten Start führt dich der interaktive **Einrichtungsassistent** durch das Setup. Falls du bereits ein Backup-ZIP besitzt, kannst du es direkt im ersten Schritt über **Wiederherstellen** einspielen.

### 4. Externe Integrationen (Optional)
- **Google Workspace (Gmail, Kalender, Drive)**: OAuth-Clients in der Google Cloud Console einrichten gemäß **[Google Workspace Einrichtung (Deutsch)](../GOOGLE_WORKSPACE_SETUP_DE.md)** und anschließend Client-IDs sowie Client-Secret unter **Einstellungen → Integrationen** hinterlegen.
- **Microsoft 365 (Outlook Mail, Kalender, OneDrive)**: App-Registrierung im Entra Admin Center einrichten gemäß **[Microsoft 365 Einrichtung (Deutsch)](../MICROSOFT_365_SETUP_DE.md)**.

---

## 🧠 Memory, RAG & Ontologie einrichten

Ghost nutzt **ObjectBox (`5.3.2`)** lokal sowohl für semantisches RAG (`objectbox_rag`) als auch für die strukturierte Ontologie (`objectbox_ontology`).

1. **Native Bibliotheken**: Stelle sicher, dass die ObjectBox-C-Bibliothek für dein Betriebssystem installiert ist (siehe Schritt 2).
2. **RAG & Pflicht zu lokalen Embeddings**: Wähle unter **Einstellungen → Toolbox → Speicher** einen Embedding-Provider und ein Modell aus. Aus Datenschutzgründen erfordert **Workspace-RAG** (automatische Indizierung von `.txt`, `.md`, `.json` und `.pdf` im Ordner `<workspace>/rag/`) zwingend einen lokalen Embedding-Provider wie **Ollama** oder **LM Studio**.
3. **Ontologie & Knowledge Graph**: Standardmäßig aktiv unter **Einstellungen → Toolbox → Speicher → Ontologie**. Bietet T-Box/A-Box-Persistenz, Multi-Hop-Inferenz und System-1-geschützte Post-Turn-Faktenextraktion (siehe **[Ontologie & Knowledge-Graph-Anleitung](../ONTOLOGY_DE.md)**).

---

## 🛡️ System-1 Entscheidungs-Middleware einrichten (Optional)

Ghost unterstützt eine lokale, nicht-autoregressive Entscheidungs-Middleware auf Basis von ModernBERT INT8 ONNX:
1. **Python-Abhängigkeiten**:
   ```bash
   pip install -r docs/installation/requirements.txt
   ```
   *(Installiert `onnxruntime`, `transformers` und `numpy` sowie `faster-whisper`, `piper-tts` und `pathvalidate`.)*
2. **Modell-Datei**: Stelle sicher, dass `ghost_system1_int8.onnx` unter `scripts/models/ghost_system1_int8.onnx` liegt.
3. **Aktivierung**: Öffne **Einstellungen → Sicherheit** und aktiviere die **System-1 Entscheidungs-Middleware**.

---

## 🤖 Headless ACP CLI (`bin/ghost_acp.dart`) starten

Ghost lässt sich auch komplett ohne Flutter-UI als **Agent Client Protocol (ACP)**-Server für Google Antigravity CLI (`agy`), Zed oder Dev-Container starten:
```bash
# STDIO-Modus
dart bin/ghost_acp.dart --workspace /pfad/zum/projekt

# WebSocket-Modus
dart bin/ghost_acp.dart --ws --port 3001 --workspace /pfad/zum/projekt
```
Details zur Konfiguration findest du in der **[Google Antigravity & ACP Anleitung](../ANTIGRAVITY_ACP_DE.md)**.

---

## 📦 Desktop-Releases erstellen (Linux, Windows, macOS)

### Lokaler Release-Build
Kompiliert ein eigenständiges Release-Paket für dein Betriebssystem (inklusive nativer Bibliotheken und Skripte unter `ghost-releases/`):
- **Linux & macOS** *(macOS erfordert Deployment-Target `11.0+`)*:
  ```bash
  ./scripts/build_release.sh
  ```
- **Windows (PowerShell)**:
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\scripts\build_release.ps1
  ```

### Multi-Plattform CI/CD via GitHub Actions
Da Flutter Desktop jeweils native Compiler erfordert (MSVC unter Windows, Xcode unter macOS, Clang/GTK3 unter Linux), enthält Ghost eine automatische Pipeline unter [`.github/workflows/build-releases.yml`](../../.github/workflows/build-releases.yml):
- **Automatisches GitHub Release per Tag**: Beim Pushen eines Tags (`git tag v0.1.0 && git push origin v0.1.0`) baut GitHub Actions parallel **Linux (`x64`)**, **Windows (`x64`)** und **macOS (`Universal`)** und veröffentlicht `ghost-linux-x64.tar.gz`, `ghost-windows-x64.zip` und `ghost-macos-universal.zip` unter **GitHub Releases**.
- **Manueller Start**: Der Workflow kann jederzeit auf GitHub unter **Actions → Run workflow** ausgelöst werden.

---

## 🛠️ Entwickler-Hinweise & Fehlerbehebung

### 1. Code-Generierung (`build_runner`) & Headless-ObjectBox-Regel
Nach Änderungen an ObjectBox-`@Entity()`-Klassen oder `@JsonSerializable()`-Modellen Code neu generieren:
```bash
dart run build_runner build --delete-conflicting-outputs
```
> [!IMPORTANT]
> `objectbox_generator` überschreibt `lib/objectbox.g.dart` mit einem unbedingten `objectbox_flutter_libs`-Import, wodurch `dart:ui` eingezogen wird und `bin/ghost_acp.dart` nicht mehr kompiliert. Stelle danach stets den bedingten Import über `lib/engine/infra/objectbox_flutter_libs_stub.dart` wieder her.

### 2. Projekt bereinigen & Abhängigkeiten aktualisieren
```bash
flutter clean
flutter pub get
```

### 3. Wartung, Backup & Reset
Unter **Einstellungen → Zurücksetzen** lassen sich selektive verschlüsselte ZIP-Backups (`config`, `vault`, `sessions`, `skills`, `design`, `automations`, `memory`) erstellen und wiederherstellen, Gateway-Logs prüfen sowie ein Factory Reset auslösen.

---

## 📚 Spezialisierte Anleitungen
- **[Ontologie & Knowledge-Graph-Anleitung](../ONTOLOGY_DE.md)**: T-Box/A-Box-Architektur, Graph-Explorer und Memory-Poisoning-Schutz.
- **[Automations & Geplante Workflows](../AUTOMATIONS_DE.md)**: Lesbare Cron-Zeitpläne, `+ Create with Prompt` und Lauf-Transkripte.
- **[Kanban & Task-Orchestrierung](../KANBAN_ORCHESTRATION_de.md)**: Multi-Agenten-Workflows, Ontologie-Routing, `/goal`, `/plan` und `ghost_delegate_task`.
- **[System-1 Entscheidungs-Middleware](../SYSTEM1_MIDDLEWARE_DE.md)**: Lokale ModernBERT-INT8-ONNX-Engine, Risiko-Scoring und Smart-HITL.
- **[Skills Development Guide](../SKILLS_GUIDE_DE.md)**: Opt-Out-Berechtigungen, Progressive Disclosure (`ghost_load_skill`) und eigene Skills.
- **[Google Antigravity & ACP Anleitung](../ANTIGRAVITY_ACP_DE.md)**: STDIO/WebSocket-ACP-Server und Guarded Autopilot.
- **[VS Code Extension](../VSCODE_EXTENSION_DE.md)** & **[Chrome Extension](../CHROME_EXTENSION_DE.md)**
- **[Multi-Channel Setup](../CHANNELS_DE.md)** & **[STT & TTS Setup](../STT_TTS_SETUP_DE.md)**
- **[Zahlungs-, Wallet- & Binance-Einrichtung](../PAYMENTS_SETUP_DE.md)**
- **[RPC API Referenz](../RPC_API_REFERENCE_DE.md)**
