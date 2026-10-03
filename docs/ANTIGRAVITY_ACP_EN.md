# Ghost 👻 × Google Antigravity & Agent Client Protocol (ACP)

This guide documents the integration of Ghost with the **Google Antigravity** agentic development platform and the **Agent Client Protocol (ACP)** for standardized interactions with editors and IDEs (Antigravity IDE, Zed, VS Code).

---

## 1. Overview & Architecture

Ghost functions both as an autonomous coding agent within Antigravity-compatible environments and as an orchestration gateway for Dart/Flutter and AI workflows:

```
┌────────────────────────────────────────────────────────┐
│        Google Antigravity IDE / agy CLI / Zed          │
└───────────────────────────▲────────────────────────────┘
                            │
               JSON-RPC 2.0 (STDIO / WS)
                            │
┌───────────────────────────▼────────────────────────────┐
│                  Ghost ACP Adapter                     │
│  - Handshake (`initialize`)                            │
│  - Guarded Autopilot (`reviewMode` / `autoAccept`)    │
│  - Session & Streaming (`session/prompt`, deltas)     │
│  - Context Provider (`context/query` via RAG)          │
└───────────────────────────▲────────────────────────────┘
                            │
┌───────────────────────────▼────────────────────────────┐
│                     Ghost Engine                       │
│  - TaskManager & Kanban Pipeline Bridge                │
│  - ObjectBox Vector RAG & Secure Storage               │
│  - Tools: ApplyPatch, EditFile, Exec, WebSearch, Vault │
└────────────────────────────────────────────────────────┘
```

---

## 2. Launching the Ghost ACP Server

Ghost provides a dedicated executable entrypoint: [`bin/ghost_acp.dart`](file:///home/peter/Developer/flutter-dev/ghost/bin/ghost_acp.dart).

### 2.1 Standard STDIO Mode (for `agy` & Zed)
In STDIO mode, all diagnostic and system logs are sent to `stderr`, keeping `stdout` strictly compliant with JSON-RPC 2.0:

```bash
dart bin/ghost_acp.dart --workspace /path/to/project
```

Options:
* `-w, --workspace`: Workspace root directory (default: `.`)
* `-g, --guardrails`: Autopilot execution mode (`reviewMode` [default] or `autoAccept`)
* `-h, --help`: Show usage and flag options

### 2.2 WebSocket Mode (Port 3001)
For multi-client or dev container setups:

```bash
dart bin/ghost_acp.dart --ws --port 3001 --workspace /path/to/project
```

Additionally, Ghost's core gateway exposes an ACP WebSocket route at `ws://127.0.0.1:3000/acp`.

---

## 3. Connecting to Google Antigravity (`agy`)

Configure Ghost in `.antigravity/config.json` or editor `settings.json`:

```json
{
  "acp": {
    "agents": {
      "ghost": {
        "command": "dart",
        "args": [
          "/home/peter/Developer/flutter-dev/ghost/bin/ghost_acp.dart",
          "--workspace",
          "${workspaceFolder}",
          "--guardrails",
          "reviewMode"
        ],
        "capabilities": {
          "tools": true,
          "contextProviders": true,
          "editReview": true,
          "terminal": true
        }
      }
    }
  }
}
```

Running tasks via Antigravity CLI:
```bash
agy run --agent ghost "Implement user authentication middleware in lib/auth.dart"
```

---

## 4. Guarded Autopilot & Safety Modes

Ghost supports Antigravity-aligned Guarded Autopilot modes:

1. **`reviewMode` (Default):**
   * Code modifications (`apply_patch`, `edit_file`) or terminal executions emit a `session/review_request` notification to the editor.
   * Execution halts until the user approves or rejects the change in the IDE diff viewer.
2. **`autoAccept`:**
   * Autonomous execution for trusted workflows or CI environments.

---

## 5. Workspace-RAG Context Provider

Ghost registers its ObjectBox vector store as an Antigravity Context Provider:
* **Provider ID:** `ghost-rag`
* **Features:** Semantic search across codebase chunks, symbol definitions, and documentations.
* **Fallback:** When chunks are unindexed, generates a directory structure and project summary.

---

## 6. Antigravity Tools & Kanban Bridge

Ghost exposes specialized tool definitions for Antigravity:
* [`ghost_apply_patch`](file:///home/peter/Developer/flutter-dev/ghost/lib/engine/tools/fs.dart): Precise SEARCH/REPLACE diff applicator.
* [`ghost_workspace_rag`](file:///home/peter/Developer/flutter-dev/ghost/lib/services/antigravity/antigravity_tools.dart): Semantic query tool.
* [`ghost_kanban_pipeline`](file:///home/peter/Developer/flutter-dev/ghost/lib/services/antigravity/antigravity_tools.dart): Decomposes Antigravity plans into synced Kanban tasks (`todo` -> `inProgress` -> `done`).
* [`ghost_vault_keys`](file:///home/peter/Developer/flutter-dev/ghost/lib/services/antigravity/antigravity_tools.dart): Key and secret management.
* [`ghost_web_search`](file:///home/peter/Developer/flutter-dev/ghost/lib/services/antigravity/antigravity_tools.dart): DuckDuckGo search integration.
