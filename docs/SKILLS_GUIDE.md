# 🧩 Skills Development Guide — Ghost

Skills are the primary way to extend the capabilities of your Ghost AI Assistant. Ghost combines an **Opt-Out Permission Model**, **ObjectBox Ontology Governance**, and **Two-Stage Progressive Disclosure** so you can install large skill libraries without bloating agent context windows.

---

## 🏗️ What is a Skill?

In Ghost, a skill is a directory under `~/.ghost/skills/<slug>/` containing at least a `SKILL.md` file.

### Key Components:
1. **`SKILL.md`**: The heart of the skill. Contains YAML frontmatter (metadata, domain, dependencies, and HITL security policy) and Markdown instructions.
2. **`_meta.json`** (Optional): Legacy JSON metadata fallback.
3. **Additional Files**: Python scripts (`requirements.txt` → auto `.venv`), Node.js packages (`package.json` → auto `npm install`), or MCP servers.

---

## 🔐 Opt-Out Access Model & Progressive Disclosure

### 1. Opt-Out Permissions (`disabledSkills` → `DARF_NUTZEN`)
- Every agent (the main agent and all custom agents) receives access to **all** installed skills by default.
- Instead of maintaining manual allowlists, agents selectively opt out via `disabledSkills` in **Settings → Agent Profiles → Identity / Custom Agents**.
- `AgentManager.syncOntologySkillsAndPermissions` automatically syncs all installed skills and allowed edges (`DARF_NUTZEN`, `GEHOERT_ZU_DOMAIN`, `BENOETIGT_SKILL`, `ERFORDERT_HITL`) into the ObjectBox Ontology Graph.

### 2. Two-Stage Progressive Disclosure (`ghost_load_skill`)
To minimize token usage while supporting dozens of skills:
- **Stage 1 (Compact Index)**: Ghost injects only single-line summaries into the system prompt under `[AVAILABLE SKILLS — PROGRESSIVE DISCLOSURE]` (e.g. `` - `binance-trader` [finance] [HITL]: Execute spot/demo trades ``).
- **Stage 2 (On-Demand Loading)**: Enforced by the `SKILL PRIORITY MANDATE`, the agent calls `ghost_load_skill(skill_name: "<slug>")` before using a skill. Ghost verifies `DARF_NUTZEN` permission in the ontology and returns the full `SKILL.md` instructions, skill directory path, `.venv/bin/python` / `node` / `mcp_command` runtime info, transitive `BENOETIGT_SKILL` dependencies, and `ERFORDERT_HITL` security notices.

---

## 🛠️ Creating a New Skill

### 1. Structure
Create a folder for your skill (e.g., `my-cool-skill/`) containing `SKILL.md`:

```text
my-cool-skill/
└── SKILL.md
```

### 2. The `SKILL.md` Format & Frontmatter Fields
Ghost supports rich YAML frontmatter (delimited by `---` or `+++`):

```markdown
---
name: "My Cool Skill"
slug: "my-cool-skill"
description: "Allows the agent to do amazing things."
emoji: "🚀"
category: "development"          # or domain: development, finance, communication, system, web, security, design, general
security_level: "standard"       # low | standard | high | critical
requires_hitl: false             # or hitl: true/false (auto-inferred true for finance/security/high/critical)
requires_skills:                 # or depends_on: transitive BENOETIGT_SKILL dependencies
  - "base-helper"
---

# Instructions for the AI Agent
When asked for X, you should perform Y.
```

> [!NOTE]
> If `category`, `security_level`, or `requires_hitl` are omitted, [`SkillManager`](../lib/engine/agent/skills.dart) automatically infers them from the skill's slug, description, and Markdown content (for example, `finance` and `security` skills or destructive/payment commands automatically infer `requires_hitl: true` and `ERFORDERT_HITL` ontology governance).

### 3. Adding Logic (Tools & Isolated Runtimes)
Ghost automatically provisions isolated runtimes for skills:
- **Python**: If `requirements.txt` (or `scripts/requirements.txt`) is present, Ghost creates a `.venv` inside the skill folder and installs the dependencies.
- **Node.js**: If `package.json` (or `scripts/package.json`) is present, Ghost automatically runs `npm install`.

### 4. MCP Server Integration
You can configure a skill directly as a **Model Context Protocol (MCP)** server via `mcp_command` in the YAML frontmatter:

```markdown
---
name: "My MCP Server"
slug: "my-mcp-server"
mcp_command: "npx tsx src/index.ts"
---
```
Ghost automatically manages the background MCP process and exposes its tools according to agent permissions.

---

## 🏗️ Creating & Managing Skills via UI (Recommended)

1. Open the Ghost App and navigate to **Settings → Toolbox → Skills**.
2. Click **+ Create New** and choose a template (Python, Node.js, or Markdown-only).
3. Edit `SKILL.md` directly in the built-in Markdown editor (changes automatically trigger ontology re-sync) or open the folder in your IDE.

### Built-in Agent Skill Tools
Agents themselves also have access to skill tools: `ghost_load_skill`, `list_skills`, `create_skill_template`, `import_skill`, `debug_skill`, and `download_github_skill`.

---

## 📦 Packaging, Import & Backup

### Option 1: ZIP Archive
Compress your skill folder into a `.zip` file and upload it under **Settings → Toolbox → Skills → Install Skill**.

### Option 2: GitHub Synchronization
Push your skill folder to GitHub and use **Import from URL** (e.g., `https://github.com/user/repo/tree/main/skills/my-skill`).

### Option 3: Skills or Full System Backup
- Export/import skills alone under **Settings → Toolbox → Skills → Backup / Restore** (`ghost_skills.json`).
- Or back up your entire system (including `skills`, `automations`, `design`, `memory`, `sessions`, `config`, `vault`) under **Settings → Reset → Backup & Restore**.

---

## 💡 Best Practices
- **Set `category` & `requires_hitl` Explicitly**: Explicit categories improve Ontology Domain Routing (`HAT_KOMPETENZ`), and `requires_hitl: true` guarantees `ERFORDERT_HITL` safety gating.
- **Write a Clear First Sentence**: Stage 1 Progressive Disclosure shows the frontmatter `description` (or first sentence of `SKILL.md`, up to 160 chars) so agents know immediately when to call `ghost_load_skill`.
- **Use Emojis**: They make your skills easily recognizable in the UI.
