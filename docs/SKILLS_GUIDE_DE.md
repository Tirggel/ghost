# 🧩 Skills Development Guide — Ghost

Skills sind der primäre Weg, um die Fähigkeiten deines Ghost KI-Assistenten zu erweitern. Ein Skill ist im Wesentlichen ein Bündel von Informationen, Anweisungen und Werkzeugen, die dein Agent nutzen kann, um spezifische Aufgaben auszuführen.

---

## 🏗️ Was ist ein Skill?

In Ghost ist ein Skill einfach ein Verzeichnis, das mindestens eine `SKILL.md`-Datei enthält. Diese Datei versorgt den Agenten mit dem notwendigen Kontext und den Anweisungen, um spezifische Anfragen zu bearbeiten.

### Kernkomponenten:
1.  **`SKILL.md`**: Das Herzstück des Skills. Enthält YAML-Frontmatter für Metadaten und Markdown für Anweisungen.
2.  **`_meta.json`** (Optional): Alternativer Weg für Metadaten (Legacy-Support).
3.  **Zusätzliche Dateien**: Du kannst Python-Skripte, JSON-Daten oder andere Textdateien einschließen, die der Agent lesen kann.

---

## 🛠️ Einen neuen Skill erstellen

### 1. Struktur
Erstelle einen Ordner für deinen Skill (z. B. `mein-cooler-skill/`). Erstelle darin eine `SKILL.md`-Datei.

```text
mein-cooler-skill/
└── SKILL.md
```

### 2. Das `SKILL.md`-Format
Die `SKILL.md`-Datei verwendet YAML-Frontmatter am Anfang, um ihre Identität zu definieren.

```markdown
---
name: "Mein cooler Skill"
slug: "mein-cooler-skill"
description: "Ermöglicht es dem Agenten, erstaunliche Dinge zu tun."
emoji: "🚀"
---

# Anweisungen für den KI-Agenten
Wenn der Benutzer nach X fragt, sollst du Y tun. 
Nutze die folgende Logik:
...
```

### 3. Logik hinzufügen (Werkzeuge & Runtimes)
Wenn dein Skill externe Werkzeuge benötigt (wie ein Python-Skript), kannst du diese in deinen Anweisungen referenzieren. Ghost unterstützt nun automatisch isolierte Umgebungen:
- **Python**: Wenn ein `requirements.txt` im Skill-Ordner liegt, erstellt Ghost automatisch eine virtuelle Umgebung (`.venv`) und installiert die Abhängigkeiten.
- **Node.js**: Wenn ein `package.json` vorhanden ist, führt Ghost automatisch `npm install` aus.

### 4. MCP Server Integration
Du kannst deinen Skill direkt als **Model Context Protocol (MCP)** Server konfigurieren. Füge dazu den `mcp_command` in den YAML-Frontmatter ein:

```markdown
---
name: "Mein MCP Server"
slug: "mein-mcp-server"
mcp_command: "npx tsx src/index.ts"
---
```
Ghost startet den Server dann automatisch im Hintergrund und stellt die Tools allen Agenten zur Verfügung.

---

## 📦 Paketierung & Installation

### Option 1: ZIP-Archiv
Komprimiere deinen Skill-Ordner in eine `.zip`-Datei.
1.  Öffne die Ghost App.
2.  Gehe zu **Einstellungen > Skills**.
3.  Klicke auf **Skill installieren** und lade deine `.zip`-Datei hoch.

### Option 2: GitHub-Synchronisation
Du kannst deine Skills auf GitHub hosten.
1.  Pushe deinen Skill-Ordner in ein öffentliches GitHub-Repository.
2.  Nutze in Ghost die Option **Von GitHub herunterladen**.
3.  Gib die URL zum Skill-Ordner an (z. B. `https://github.com/user/repo/tree/main/skills/mein-skill`).

---

## 🌍 Globale vs. Lokale Skills
- **Globale Skills**: Standardmäßig für alle Agenten-Profile aktiviert.
- **Lokale Skills**: Können für spezifische Agenten in deren Profileinstellungen aktiviert oder deaktiviert werden.

---

## 💡 Best Practices
- **Sei beschreibend**: Eine klare Beschreibung hilft dem Agenten zu verstehen, wann er den Skill nutzen sollte.
- **Präzise Anweisungen**: Halte den Markdown-Inhalt fokussiert. Zu viele irrelevante Informationen können das Kontextfenster überladen.
- **Nutze Emojis**: Sie machen deine Skills in der Benutzeroberfläche leicht erkennbar.
