# 🧩 Skills Development Guide — Ghost

Skills are the primary way to extend the capabilities of your Ghost AI Assistant. A skill is essentially a bundle of information, instructions, and tools that your agent can use to perform specific tasks.

---

## 🏗️ What is a Skill?

In Ghost, a skill is simply a directory containing at least one `SKILL.md` file. This file provides the agent with the necessary context and instructions to handle specific requests.

### Key Components:
1.  **`SKILL.md`**: The heart of the skill. Contains YAML frontmatter for metadata and Markdown for instructions.
2.  **`_meta.json`** (Optional): Alternative way to provide metadata (legacy support).
3.  **Additional Files**: You can include Python scripts, JSON data, or other text files that the agent can read.

---

## 🛠️ Creating a New Skill

### 1. Structure
Create a folder for your skill (e.g., `my-cool-skill/`). Inside, create a `SKILL.md` file.

```text
my-cool-skill/
└── SKILL.md
```

### 2. The `SKILL.md` Format
The `SKILL.md` file uses YAML frontmatter at the top to define its identity.

```markdown
---
name: "My Cool Skill"
slug: "my-cool-skill"
description: "Allows the agent to do amazing things."
emoji: "🚀"
---

# Instructions for the AI Agent
When asked for X, you should perform Y. 
Use the following logic:
...
```

### 3. Adding Logic (Tools & Runtimes)
If your skill requires external tools (like a Python script), you can reference them in your instructions. Ghost now automatically supports isolated environments:
- **Python**: If a `requirements.txt` is present in the skill folder, Ghost automatically creates a virtual environment (`.venv`) and installs the dependencies.
- **Node.js**: If a `package.json` is present, Ghost automatically runs `npm install`.

### 4. MCP Server Integration
You can configure your skill directly as a **Model Context Protocol (MCP)** server. Simply add the `mcp_command` to the YAML frontmatter:

```markdown
---
name: "My MCP Server"
slug: "my-mcp-server"
mcp_command: "npx tsx src/index.ts"
---
```
Ghost will then automatically start the server in the background and make its tools available to all agents.

---

## 🏗️ Creating Skills via UI (Recommended)

The easiest way to create a new skill is directly through the Ghost interface.

1.  Open the Ghost App and navigate to **Settings > Skills**.
2.  Click the **+ Create New** button.
3.  Choose a **Template** (e.g., Python, Node.js, or Markdown-only).
4.  Ghost will automatically generate the directory structure and required files (like `SKILL.md`).
5.  You can then edit the `SKILL.md` directly in the built-in editor or open the folder in your preferred IDE.

---

## 📦 Packaging & Installation

### Option 1: ZIP Archive
Compress your skill folder into a `.zip` file.
1.  Open the Ghost App.
2.  Go to **Settings > Skills**.
3.  Click **Install Skill** and upload your `.zip` file.

### Option 2: GitHub Synchronization
You can host your skills on GitHub.
1.  Push your skill folder to a public GitHub repository.
2.  In Ghost, use the **Import from URL** option.
3.  Provide the URL to your skill folder (e.g., `https://github.com/user/repo/tree/main/skills/my-skill`).

### Option 3: Backup & Restore
You can back up your entire skills library as a single archive.
1.  Go to **Settings > Maintenance**.
2.  Use the **Backup** feature to export your skills.
3.  Use the **Restore** feature to import them back later or on a different machine.

---

## 💡 Best Practices
- **Be Descriptive**: A clear description helps the agent understand when to use the skill.
- **Concise Instructions**: Keep the markdown content focused. Too much irrelevant info can clutter the context window.
- **Use Emojis**: They make your skills easily recognizable in the UI.
