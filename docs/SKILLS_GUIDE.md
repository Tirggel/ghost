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

### 3. Adding Logic (Tools)
If your skill requires external tools (like a Python script), you can reference them in your instructions. The agent has access to an `exec` tool that can run scripts within your skill directory.

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
2.  In Ghost, use the **Download from GitHub** option.
3.  Provide the URL to your skill folder (e.g., `https://github.com/user/repo/tree/main/skills/my-skill`).

---

## 🌍 Global vs. Local Skills
- **Global Skills**: Enabled for all agent profiles by default.
- **Local Skills**: Can be enabled or disabled for specific agents in their profile settings.

---

## 💡 Best Practices
- **Be Descriptive**: A clear description helps the agent understand when to use the skill.
- **Concise Instructions**: Keep the markdown content focused. Too much irrelevant info can clutter the context window.
- **Use Emojis**: They make your skills easily recognizable in the UI.
