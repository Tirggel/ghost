# ⚡ Automations & Scheduled Workflows — Ghost

Ghost includes a dedicated **Automations** workspace for scheduling recurring AI workflows with human-readable timetables, AI prompt drafting, **Ontology-Driven Agent Routing**, per-automation provider/model overrides, and persistent run logs linked to full chat transcripts.

---

## 🧭 Accessing Automations

Open the **Automations** view directly from the main sidebar (bolt icon, positioned right below **Kanban Board**).

The Overview displays:
- Real-time search across automation titles, instructions, and schedules
- Active automation counter badge
- Tabular status rows showing **Title**, **Agent Badge** (`🧭 Auto (Ontology)`, `👻 Main Agent`, or `🤖 Custom Agent`), **Schedule** (human-readable), **Next Run**, **Last Run** (`success` / `failed` / `running` / `cancelled`), and an **Active** switch to pause or resume immediately.

---

## 🪄 Creating Automations

### Option 1: `+ Create with Prompt` (AI Wizard)
Implemented in [`CreateWithPromptDialog`](../lib/ui/screens/automations/widgets/create_with_prompt_dialog.dart) and [`AutomationManager.generateFromPrompt`](../lib/engine/automations/automation_manager.dart):
1. Describe what should happen and when in natural language (e.g., *"Every weekday at 8:15 AM and 5:15 PM, summarize my unread emails and highlight urgent action items"*).
2. Ghost uses your active LLM and agent catalog to generate an editable draft containing:
   - Concise **Title** (localized to your UI language)
   - Detailed step-by-step **Instructions**
   - Exact **Schedule** (preserving exact minute timestamps and intervals without rounding)
   - Best **Agent** selection (defaulting to `Auto (Ontology)` unless a specific agent is clearly required) and a live ontology specialist preview
3. Adjust any field in the review step or click **Regenerate** before saving.

### Option 2: `+ New` (Manual Setup)
Implemented in [`CreateAutomationDialog`](../lib/ui/screens/automations/widgets/create_automation_dialog.dart):
- Configure **Title**, **Schedule**, **Agent** (`Auto (Ontology)`, main agent, or any enabled custom agent), optional **Provider Override** and **Model Override**, and **Instructions** directly.

---

## 🗓️ Schedule Modes (`SchedulePickerWidget` & `CronUtils`)

Every schedule compiles cleanly into one or more standard 5-field Unix cron expressions (`minute hour day-of-month month day-of-week`):

| Mode | Configuration | Example Output |
|---|---|---|
| **Daily (`daily`)** | One or more exact `HH:mm` times | `15 8,17 * * *` (or multiple cron lines if minutes differ) |
| **Weekdays (`weekdays`)** | Mon–Fri (`1-5`) with one or more exact `HH:mm` times | `15 8,17 * * 1-5` |
| **Weekly (`weekly`)** | Custom ISO weekdays (`1=Mon..7=Sun`) and exact `HH:mm` times | `0 9 * * 1,4` |
| **Hourly (`hourly`)** | Every `1–24` hours at exact minute `:mm` | `12 */3 * * *` |
| **Interval (`interval`)** | Every `1–59` minutes or `1–24` hours | `*/7 * * * *` or `0 */2 * * *` |
| **Custom Cron (`custom`)** | Raw 5-field Unix cron expression with live validation | `30 6 1 * *` |

The picker renders a human-readable summary, validates the syntax in real time, and lets you preview the **next 3 scheduled execution times** (`CronUtils.computeNextRuns`).

---

## 🧠 Detail View, Execution & Transcripts

Clicking any row opens [`AutomationDetailView`](../lib/ui/screens/automations/automation_detail_view.dart):

- **Header Controls**: Inline-editable title, Active/Paused toggle, **Run Now** button (triggers an immediate background run), and **Delete** (stops active runs and removes the definition, run logs, and all linked `auto_<id>_*` chat sessions).
- **Settings Card**: Edit schedule, target agent (with live **Predicted Specialist** preview when `Auto (Ontology)` is selected), and optional Provider/Model overrides.
- **Instructions Card**: Collapsible viewer with inline editing.
- **Runs History Card**: Chronological log (up to 100 runs retained per automation) showing status, trigger (`Scheduled` / `Manual`), start time, duration, resolved agent/provider/model, and summary or error message.
  - Clicking any run opens its complete **`auto_<automationId>_<runId>` session transcript** directly in the Chat view.
  - Automated `auto_*` run sessions are kept separate and hidden from the regular chat sidebar so your daily chats stay clutter-free.

### Execution Safeguards
- **Overlap Prevention**: Concurrent runs of the same automation are prevented via `_activeRunIds`.
- **Dynamic Ontology Routing per Run**: When assigned to `Auto (Ontology)`, `TaskOrchestrator.evaluateRoutingForRequest` evaluates competencies (`HAT_KOMPETENZ`), skills (`DARF_NUTZEN` → `GEHOERT_ZU_DOMAIN`), and active workload at execution time.
- **Background Autonomy & Clean Recovery**: `auto_` sessions execute unattended without blocking on interactive HITL prompts and are excluded from post-turn `OntologyExtractor` updates. Any run left in `running` state after an unexpected shutdown is automatically marked `cancelled` (`"Interrupted by system restart"`) on startup.

---

## 💾 Persistence & Backups

- **Disk Storage** (`AutomationStore`):
  - Definitions: `<stateDir>/automations/definitions/<id>.json`
  - Run logs: `<stateDir>/automations/runs/<automationId>.json`
- **ZIP Backups**: Included as the selectable **`automations`** section in **Settings → Reset → Backup & Restore** and via `config.backup` / `config.restore`.

---

## 🔌 RPC API Methods & Events

Implemented in [`AutomationRouter`](../lib/engine/gateway/automation_router.dart):

- **Methods**: `automations.list`, `automations.get`, `automations.create`, `automations.update`, `automations.toggle`, `automations.delete`, `automations.runNow`, `automations.runs`, `automations.previewSchedule`, `automations.previewRouting`, `automations.generateFromPrompt`.
- **Broadcast Events**: `automations.changed`, `automations.run_updated`, `agent.session_deleted`.

See the **[RPC API Reference](RPC_API_REFERENCE.md)** for full parameter and response details.
