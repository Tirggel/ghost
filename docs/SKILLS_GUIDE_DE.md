# 🧩 Skills Development Guide — Ghost

Skills sind der primäre Weg, um die Fähigkeiten deines Ghost KI-Assistenten zu erweitern. Ghost kombiniert ein **Opt-Out-Berechtigungsmodell**, **ObjectBox-Ontologie-Governance** und **zweistufiges Progressive Disclosure**, sodass auch große Skill-Bibliotheken ohne unnötigen Token-Verbrauch nutzbar bleiben.

---

## 🏗️ Was ist ein Skill?

In Ghost ist ein Skill ein Verzeichnis unter `~/.ghost/skills/<slug>/`, das mindestens eine `SKILL.md`-Datei enthält.

### Kernkomponenten:
1. **`SKILL.md`**: Das Herzstück des Skills. Enthält YAML-Frontmatter (Metadaten, Domäne, Abhängigkeiten und HITL-Sicherheitsrichtlinie) sowie Markdown-Anweisungen.
2. **`_meta.json`** (Optional): Alternativer JSON-Metadaten-Fallback (Legacy).
3. **Zusätzliche Dateien**: Python-Skripte (`requirements.txt` → automatische `.venv`), Node.js-Pakete (`package.json` → automatisches `npm install`) oder MCP-Server.

---

## 🔐 Opt-Out-Zugriff & Progressive Disclosure

### 1. Opt-Out-Berechtigungen (`disabledSkills` → `DARF_NUTZEN`)
- Alle Agenten (Haupt-Agent und Custom-Agenten) erhalten standardmäßig Zugriff auf **alle** installierten Skills.
- Einzelne Skills lassen sich pro Agent gezielt über `disabledSkills` abwählen (unter **Einstellungen → Agenten-Profile → Identität / Eigene Agents**).
- `AgentManager.syncOntologySkillsAndPermissions` synchronisiert automatisch alle Skills und Berechtigungskanten (`DARF_NUTZEN`, `GEHOERT_ZU_DOMAIN`, `BENOETIGT_SKILL`, `ERFORDERT_HITL`) in den ObjectBox-Ontologie-Graphen.

### 2. Zweistufiges Progressive Disclosure (`ghost_load_skill`)
Für minimale Prompt-Größe bei maximaler Skill-Vielfalt:
- **Stufe 1 (Kompakt-Index)**: Ghost injiziert nur einzeilige Zusammenfassungen unter `[AVAILABLE SKILLS — PROGRESSIVE DISCLOSURE]` in den System-Prompt (z. B. `` - `binance-trader` [finance] [HITL]: Spot- und Demo-Orders ausführen ``).
- **Stufe 2 (On-Demand-Laden)**: Über das `SKILL PRIORITY MANDATE` angewiesen, ruft der Agent vor Nutzung eines Skills `ghost_load_skill(skill_name: "<slug>")` auf. Ghost prüft `DARF_NUTZEN` in der Ontologie und liefert vollständige `SKILL.md`-Anleitungen, Verzeichnispfad, `.venv/bin/python` / `node` / `mcp_command`-Laufzeitinfos, transitive `BENOETIGT_SKILL`-Abhängigkeiten und `ERFORDERT_HITL`-Sicherheitshinweise.

---

## 🛠️ Einen neuen Skill erstellen

### 1. Struktur
Erstelle einen Ordner für deinen Skill (z. B. `mein-cooler-skill/`) mit einer `SKILL.md`-Datei:

```text
mein-cooler-skill/
└── SKILL.md
```

### 2. Das `SKILL.md`-Format & Frontmatter-Felder
Ghost unterstützt erweitertes YAML-Frontmatter (mit `---` oder `+++`):

```markdown
---
name: "Mein cooler Skill"
slug: "mein-cooler-skill"
description: "Ermöglicht es dem Agenten, erstaunliche Dinge zu tun."
emoji: "🚀"
category: "development"          # oder domain: development, finance, communication, system, web, security, design, general
security_level: "standard"       # low | standard | high | critical
requires_hitl: false             # oder hitl: true/false (wird bei finance/security/high/critical automatisch auf true gesetzt)
requires_skills:                 # oder depends_on: transitive BENOETIGT_SKILL-Abhängigkeiten
  - "basis-helper"
---

# Anweisungen für den KI-Agenten
Wenn der Benutzer nach X fragt, sollst du Y tun.
```

> [!NOTE]
> Wenn `category`, `security_level` oder `requires_hitl` nicht angegeben werden, leitet [`SkillManager`](../lib/engine/agent/skills.dart) sie automatisch aus Slug, Beschreibung und Markdown-Inhalt ab (z. B. erhalten `finance`- und `security`-Skills automatisch `requires_hitl: true` sowie `ERFORDERT_HITL`-Governance).

### 3. Logik hinzufügen (Werkzeuge & Isolierte Runtimes)
Ghost richtet automatisch isolierte Umgebungen ein:
- **Python**: Bei vorhandener `requirements.txt` (oder `scripts/requirements.txt`) erstellt Ghost automatisch eine `.venv` im Skill-Ordner und installiert die Pakete.
- **Node.js**: Bei vorhandener `package.json` (oder `scripts/package.json`) führt Ghost automatisch `npm install` aus.

### 4. MCP Server Integration
Skills können direkt als **Model Context Protocol (MCP)** Server über `mcp_command` im YAML-Frontmatter definiert werden:

```markdown
---
name: "Mein MCP Server"
slug: "mein-mcp-server"
mcp_command: "npx tsx src/index.ts"
---
```
Ghost startet den Server im Hintergrund und stellt seine Werkzeuge entsprechend den Agenten-Berechtigungen bereit.

---

## 🏗️ Skills über das UI erstellen & verwalten (Empfohlen)

1. Öffne die Ghost App und navigiere zu **Einstellungen → Toolbox → Skills**.
2. Klicke auf **+ Neu erstellen** und wähle eine Vorlage (Python, Node.js oder nur Markdown).
3. Bearbeite `SKILL.md` direkt im integrierten Markdown-Editor (Änderungen triggern automatisch ein Ontologie-Resync) oder öffne den Ordner in deiner IDE.

### Integrierte Skill-Tools für Agenten
Agenten können Skills auch direkt per Tool verwalten: `ghost_load_skill`, `list_skills`, `create_skill_template`, `import_skill`, `debug_skill` und `download_github_skill`.

---

## 📦 Paketierung, Import & Backup

### Option 1: ZIP-Archiv
Komprimiere den Skill-Ordner als `.zip` und lade ihn unter **Einstellungen → Toolbox → Skills → Skill installieren** hoch.

### Option 2: GitHub-Synchronisation
Pushe deinen Skill-Ordner auf GitHub und nutze **Von URL importieren** (z. B. `https://github.com/user/repo/tree/main/skills/mein-skill`).

### Option 3: Skill- oder System-Backup
- Skills einzeln exportieren/importieren unter **Einstellungen → Toolbox → Skills → Backup / Wiederherstellen** (`ghost_skills.json`).
- Oder das komplette System (inklusive `skills`, `automations`, `design`, `memory`, `sessions`, `config`, `vault`) unter **Einstellungen → Zurücksetzen → Backup & Wiederherstellung** sichern.

---

## 💡 Best Practices
- **`category` & `requires_hitl` explizit setzen**: Präzise Kategorien verbessern das Ontologie-Domänen-Routing (`HAT_KOMPETENZ`), und `requires_hitl: true` garantiert `ERFORDERT_HITL`-Freigaben.
- **Präziser erster Satz**: Stufe 1 von Progressive Disclosure nutzt `description` (bzw. den ersten Satz aus `SKILL.md`, bis 160 Zeichen), damit Agenten sofort erkennen, wann `ghost_load_skill` aufgerufen werden muss.
- **Nutze Emojis**: Sie machen deine Skills in der Benutzeroberfläche schnell wiedererkennbar.
