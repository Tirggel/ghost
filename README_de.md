# Ghost 👻

<p align="center">
  <img src="app/assets/icons/logo/ghost-large.png" width="300" alt="Ghost Logo">
</p>

> [!WARNING]
> **Alpha-Version & Sicherheitshinweis**: Dies ist eine frühe Alpha-Version von Ghost. Die Software befindet sich in aktiver Entwicklung und kann kritische Fehler enthalten.
>
> *   **KI-Risiken**: KI-Modelle können "halluzinieren" (falsche Informationen als Fakten darstellen).
> *   **Sicherheit**: Prompt-Injection-Angriffe sind möglich, bei denen die KI durch manipulierte Eingaben zu unerwünschten Aktionen verleitet werden kann.
> *   **Konten & Daten**: Nutzen Sie Ghost ausschließlich mit **Test-Accounts** für verbundene Dienste (APIs, Google Workspace, etc.). Verwenden Sie niemals Ihre echten Primär- oder Produktions-Accounts.
> *   **Haftungsausschluss**: Die Nutzung erfolgt auf eigene Gefahr in einer **sicheren, isolierten Umgebung**. Es wird keine Haftung für Schäden, Datenverlust oder unerwartete Aktionen der KI übernommen.

<a href="https://aquawitchcode.dev/">Entwickler-Website</a> &nbsp; &bull; &nbsp; <a href="README.md">English</a>

**Ghost** ist ein schlanker, selbst-gehosteter persönlicher KI-Assistent, der mit den von Google entwickelten Technologien [Dart](https://github.com/dart-lang) und [Flutter](https://github.com/flutter) realisiert wurde.

### 🏗️ Architektur auf einen Blick

Ghost folgt einer modularen Client-Server-Architektur:
- **Gateway (Daemon)**: Ein hochperformanter, Dart-basierter WebSocket-Server, der KI-Agenten, Speicher und Werkzeuge verwaltet.
- **App (UI)**: Eine moderne, Flutter-basierte Desktop-Anwendung (Linux, macOS, Windows) und eine Web-Oberfläche.
- **Agenten & Skills**: Erweiterbare KI-Gehirne und Fähigkeiten, die über ein einfaches, Markdown-basiertes System hinzugefügt werden können.
- **Memory Engine**: Dual-Modus-Speicher mit Hive (Standard) und ObjectBox (RAG) für sicheres, lokales Wissen.

---

## 🚀 Installation & Setup

> 💡 **Tipp**: Wenn du Ghost einfach nur nutzen möchtest, kannst du die fertig zusammengestellten Programme für dein Betriebssystem (Linux, Windows, Mac) hier herunterladen: **[ghost-releases](./ghost-releases)** 😊
>
> *Die folgende Installationsanleitung richtet sich an **Entwickler**, die Ghost selbst bauen oder modifizieren möchten.*

Um mit Ghost zu starten, folge bitte unserer detaillierten Installationsanleitung:

👉 **[Installation & Setup Guide (English)](docs/installation/INSTALLATION_EN.md)**
👉 **[Installs- & Setup-Anleitung (Deutsch)](docs/installation/INSTALLATION_DE.md)**

### 🪄 Einrichtungsassistent (Setup Wizard)
Für neue Benutzer bietet Ghost jetzt einen interaktiven **Einrichtungsassistenten**, der dich bei der Erstausführung der Anwendung durch den Konfigurationsprozess führt. Dies hilft dir, deinen Arbeitsbereich und deine Verbindungen mühelos einzurichten!

### 📚 Weiterführende Dokumentation
- **[Skills Development Guide](docs/SKILLS_GUIDE_DE.md)**: Erfahre, wie du eigene KI-Skills erstellst und paketierst.
- **[STT & TTS Setup](docs/STT_TTS_SETUP_DE.md)**: Konfiguriere lokale Spracherkennung und -synthese.
- **[RPC API Reference](docs/RPC_API_REFERENCE_DE.md)**: Detaillierte Dokumentation der JSON-RPC 2.0 WebSocket-API.
- **[Docker Setup Guide](docs/DOCKER_SETUP.md)**: Deployment und Verwaltung via Docker.

---

## 🌟 Funktionen

- **Multi-Modell-Unterstützung**: Nutze Anthropic (Claude), OpenAI (GPT), Google (Gemini), DeepSeek, Mistral, Groq, Together AI, Perplexity, X.AI (Grok) oder lokale Modelle via Ollama und OpenRouter.
- **Memory Engine (RAG & Standard)**: Erweitere das Wissen deines Agenten durch lokale Vektor- und Stichwortspeicher.
    - **Standard Memory**: Stichwortbasiertes, verschlüsseltes lokales Gedächtnis (Hive). Informationen werden sicher gespeichert und über exakte Treffer abgerufen.
    - **RAG Memory (ObjectBox)**: Retrieval-Augmented Generation mit semantischer Vektorsuche, betrieben durch eine hochleistungsfähige lokale ObjectBox-Datenbank.
    - **Automatische Embeddings**: Wenn ein OpenRouter-API-Schlüssel vorhanden ist, nutzt RAG Memory standardmäßig das kostenlose Modell `nvidia/llama-nemotron-embed-vl-1b-v2:free`.
    - **Langzeitgedächtnis**: Der Agent kann wichtige Fakten speichern und später mittels semantischer Suche wiederfinden.
- **Google Workspace Integration**:
    - **Gmail**: E-Mails lesen, suchen, **löschen** (Papierkorb) und **neue E-Mails senden**.
    - **Kalender**: Termine auflisten, **neue Events hinzufügen** und **Events löschen**.
    - **Google Drive**: Dateien suchen, auflisten und **löschen**.
- **Erweiterbare Skills**:
    - **Modulares System**: Laden und Verwalten von Skills zur Erweiterung der Fähigkeiten des Agenten.
    - **Globale & Agenten-spezifische Skills**: Aktiviere Funktionen für alle Agenten oder nur für bestimmte Profile.
    - **Polyglot Runtimes**: Automatisches Management von **Python (venv)** und **Node.js (node_modules)** Umgebungen für Skills.
    - **MCP Server Support**: Direkte Integration von Model Context Protocol Servern als Ghost Skills.
- **Erweiterte Werkzeuge**:
    - **Interaktive Shell**: Ausführung von Shell-Skripten und Python-Code direkt durch den Agenten.
    - **Websuche**: Integrierte Websuche via DuckDuckGo.
    - **Dateisystem**: Vollständiger Zugriff zum Lesen, Schreiben und Verwalten lokaler Dateien.
    - **GitHub**: Integration zur Verwaltung von Repositories und Issues.
- **Sichere Kommunikation**:
    - **Telegram Bot**: Steuere deinen Agenten sicher von unterwegs.
      - **Sprachnachrichten**: Der Agent unterstützt den Empfang und den Versand von Sprachnachrichten.
    - **Google Chat**: Integration als App in Google Chat Räumen.
- **Automatisierte Agenten-Zeitpläne**:
    - **Cron-basierte Automatisierung**: Erstelle eigene Agenten mit spezialisierten Skills und plane deren Ausführung mittels Unix-Cron-Ausdrücken (z.B. alle 5 Minuten).
    - **Echtzeit-UI-Synchronisierung**: Neue Agenten und Konfigurationsänderungen werden sofort an das UI übertragen für ein nahtloses Erlebnis.
- **Privacy & Security**:
    - **Sicherheits-Audit-Protokolle**: Verfolge und überprüfe alle sicherheitsrelevanten Aktionen und Ereignisse direkt in der Benutzeroberfläche.
    - **Sicherer Tresor**: API-Schlüssel, Agenten-Konfigurationen und Memory-Einstellungen sind mit AES-256-GCM verschlüsselt und nur auf deinem Rechner gespeichert.
    - **Verschlüsselte Datenbank**: Chat-Sitzungen und Avatare werden in einer lokalen Hive-Datenbank mit zusätzlicher Verschlüsselung gespeichert.
    - **Avatar-Management**: Bilder werden direkt in der Datenbank gespeichert, um maximale Privatsphäre zu gewährleisten.
    - **Selbstgehostet**: Volle Kontrolle über deine Daten und die Codebasis.
- **Moderne Benutzeroberfläche**:
    - **Klares Design**: Eine minimalistische und intuitive Oberfläche für ein ablenkungsfreies Erlebnis.
    - **Code-Darstellung**: Hebt Code-Blöcke hervor und formatiert sie für eine bessere Lesbarkeit.
    - **Einstellungszentrale**: Verwalte alle deine Konfigurationen zentral, einschließlich eines dedizierten Gateway-Tabs.

---

## 📜 Lizenz

Veröffentlicht unter der freizügigen [MIT-Lizenz](LICENSE), die dir volle Freiheit gibt, den Code zu ändern und ohne Einschränkungen zu verteilen.
