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
│             Ghost Pure-Dart Engine (`lib/engine.dart`) │
│  - TaskManager & Ontology Kanban Pipeline Bridge       │
│  - ObjectBox Vector RAG, Ontology & Secure Storage     │
│  - Tools: ApplyPatch, EditFile, Exec, WebSearch, Vault │
└────────────────────────────────────────────────────────┘
```

> [!NOTE]
> `bin/ghost_acp.dart` and `lib/engine/**` are strictly decoupled from Flutter (`dart:ui`), using conditional stubs such as `lib/engine/infra/objectbox_flutter_libs_stub.dart` so the headless ACP binary compiles and runs purely on the Dart VM.

---

## 2. Launching the Ghost ACP Server

Ghost provides a dedicated executable entrypoint: [`bin/ghost_acp.dart`](../bin/ghost_acp.dart).

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

Additionally, Ghost's core gateway exposes an ACP WebSocket route at `ws://127.0.0.1:3000/acp` and bridges `acp.*` methods on `/`.

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
          "/path/to/ghost/bin/ghost_acp.dart",
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
   * Execution halts until the user approves or rejects the change (`session/review_response` with `decision: "accept"` or `"reject"`) in the IDE diff viewer.
2. **`autoAccept`:**
   * Autonomous execution for trusted workflows or CI environments.

Switch modes dynamically via `session/set_autopilot_mode`:
```json
{
  "jsonrpc": "2.0",
  "method": "session/set_autopilot_mode",
  "params": {
    "sessionId": "session-123",
    "mode": "autoAccept"
  },
  "id": 10
}
```

---

## 5. Workspace-RAG Context Provider

Ghost registers its ObjectBox vector store via [`acp_context_provider.dart`](../lib/engine/acp/acp_context_provider.dart) as an Antigravity Context Provider:
* **Provider ID:** `ghost-rag`
* **Features:** Semantic search across codebase chunks, symbol definitions, and documentation.
* **Fallback:** When chunks are unindexed, generates a directory structure and project summary.

---

## 6. Antigravity Tools & Kanban Bridge

Ghost exposes specialized tool definitions via [`antigravity_tools.dart`](../lib/services/antigravity/antigravity_tools.dart):
* `ghost_apply_patch`: Atomic SEARCH/REPLACE diff applicator (`apply_patch`).
* `ghost_workspace_rag`: Semantic query tool against ObjectBox vector RAG.
* `ghost_kanban_pipeline`: Decomposes Antigravity plans into synced Ghost Kanban pipelines (`backlog` → `inProgress` → `done`) with optional agent/ontology assignment.
* `ghost_vault_keys`: Inspect available encrypted vault key names without exposing secret values.
* `ghost_exec`: Execute shell commands with automatic Python `.venv` and `node_modules/.bin` PATH injection.
* `ghost_web_search`: Real-time DuckDuckGo search integration.
