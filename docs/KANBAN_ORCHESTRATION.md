# Kanban and Task Orchestration

Ghost features a Multi-Agent Kanban system with automated task orchestration and **Ontology-Driven Multi-Agent Routing**. This enables agents to collaborate on complex projects using dependencies, sequential pipelines, autonomous `/goal` & `/plan` loops, and dynamic sub-task delegation.

---

## Core Concepts

### 1. Kanban Tasks
A task is the fundamental unit of work. Each task includes:
- **Status (`TaskStatus`)**: `backlog`, `inProgress` (shown as *To Do / In Progress*), `review`, `done`, or `cancelled`. *(Note: agent tools also accept snake_case `in_progress`.)*
- **Priority**: `low`, `normal`, `high`, or `urgent`.
- **Assignment**: Assign explicitly to the main agent (`default-agent`), a specific custom agent, or **`Auto (Ontologie)`** (`__auto__`).
- **Dependencies**: Tasks can depend on other tasks (`dependsOnIds`).
- **Domain Labels**: Optional competency/domain tags (`labels`) used to guide ontology routing.

### 2. Task Orchestrator & Ontology Routing
The `TaskOrchestrator` ([`task_orchestrator.dart`](../lib/engine/tasks/task_orchestrator.dart)) manages task lifecycles, dependency progression, and ontology-based agent selection:

- **Automated Dependency Transitions**: When a task moves to `done`, the orchestrator checks all dependent tasks. Once all `dependsOnIds` are `done`, it adds a system comment (*"All dependencies met. Task is now ready for execution."*), resolves any pending `Auto (Ontologie)` assignment, and promotes `backlog` tasks with an assigned agent to `inProgress` for execution.
- **Ontology Competency Graph (`HAT_KOMPETENZ`)**:
  `AgentDomainTaxonomy` ([`agent_domain_taxonomy.dart`](../lib/engine/agent/ontology/agent_domain_taxonomy.dart)) maps German and English aliases, skill categories, and keywords across 7 standard domains (`coding`, `research`, `finance`, `communication`, `system`, `security`, `design`) plus custom competency tags. `OntologyStoreService.syncAgentCompetencies` automatically derives `HAT_KOMPETENZ` edges from:
  1. Explicit `competencies` tags configured on the agent (`1.0` weight)
  2. Prompt/profile keyword inference (`0.65–0.78` confidence, `0.65` routing weight)
  3. Allowed skill domains (`DARF_NUTZEN` → `GEHOERT_ZU_DOMAIN`, `0.35` routing weight)
- **Scoring & Selection (`evaluateAgentRouting`)**:
  Every enabled agent is scored on a `0–100` scale:
  - **Competency Match (`0–55` pts)**: Domain weight overlap (`0–45`) plus `+10` bonus when task `labels` match an explicit agent competency.
  - **Skill Match (`0–30` pts)**: Direct skill slug/name/description hits and domain-skill matches via `DARF_NUTZEN`, weighted by agent skill specificity (`0.4 + 0.6 * (1 - allowedSkills / totalSkills)`).
  - **Name Mention (`0–10` pts)**: Direct mention of the agent's name in the task text.
  - **Active Workload Penalty (`0–15` pts)**: `-5` pts per active `inProgress` task (capped at `-15`).
  - **Specialist Thresholds**: A custom specialist is selected when `score >= 15.0` (`minSpecialistScore`) and it leads `default-agent` by at least `8.0` pts (`minMarginOverDefault`); otherwise Ghost safely falls back to the main agent.
- **Transparent Decision Audit**: Routed tasks store the full decision breakdown in `task.metadata['routing']` (visible on Kanban cards and in the Task Detail routing panel) and record a system comment (`🧭 Auto-Routed zu <Agent> (...)`).

---

## Features & Tools

### Dynamic Sub-Task Delegation (`ghost_delegate_task`)
Agents can delegate specialized sub-tasks directly through the Knowledge Graph:
- **Parameters**: `title`, `description`, `required_competencies` (optional domain hints), `priority`, `parent_task_id`, `execute_immediately` (default `true`), and `dry_run` (default `false`).
- **Dry-Run Previews**: Set `dry_run: true` to inspect the top 3 ontology candidates and score breakdown without creating a task.
- **Recursion Guard**: Enforces `maxDelegationDepth = 2` via `parent_task_id` metadata so sub-agents cannot trigger infinite delegation loops.

### Pipelines
A **Pipeline** is a sequence of tasks where each task depends on the previous one (e.g., `"Research -> Implementation -> Documentation"`).
- **Tool**: `kanban_pipeline`
- **Action**: Creates multiple tasks and links them via `dependsOnIds`.

### Ontology Agent Suggestion
Find the best-suited specialist for an existing task using the Ontology Graph and live workload:
- **Tool**: `kanban_suggest`
- **Logic**: Runs `TaskOrchestrator.evaluateAgentRouting(task)` and returns the recommended agent, routing reason, and score.

### Direct Manipulation Tools
Agents can inspect and update the board via:
- `kanban_list`: Filter tasks by status, priority, or `assigned_to_me`.
- `kanban_create`: Create a task with optional `labels`, `assign_to_me`, or `auto_route` (default `true` for ontology routing).
- `kanban_update`: Change status, priority, title, or description.
- `kanban_detail`: View full task details, subtasks, and comments.
- `kanban_assign`: Take ownership of a task (`assign_to_me`).
- `kanban_subtask`: Add or toggle checklist subtasks (`action: "add" | "toggle"`).
- `kanban_comment`: Post progress updates or comments.

---

## 🎯 Autonomous Coding / Project Execution (`/goal`)

Ghost supports an autonomous goal-oriented execution loop triggered via the `/goal` chat command.

### How it Works

1. **Trigger, Ontology Routing & Initialization**:
   When a user sends `/goal <your goal description>`, Ghost intercepts the message and creates a Kanban task:
   - **Task Title**: `🎯 <goal text>` (truncated to 60 characters).
   - **Task Description**: Full prompt text.
   - **Initial Status**: `inProgress`.
   - **Assignee**: If no explicit agent is pinned to the session/request, the task is created with `Auto (Ontologie)` and immediately routed by `TaskOrchestrator.routeTask(..., force: true)` to the top-scoring specialist. A `session_agent_routed` update notifies the UI.
   - **Context Association**: Linked to the chat `sessionId` for live streaming visibility.

2. **Autonomous Loop**:
   The routed agent enters a multi-turn reasoning and tool-execution loop (`isGoalMode = true`), calling shell, filesystem, web, or skill tools to complete the goal.

3. **Resolution & Tracking**:
   - **Success**: Task moves to `done` with a summary comment (`Ziel erreicht ✅`).
   - **Failure / Interruption**: Task moves to `review` with the error trace attached (`Fehler bei der Ausführung: <error>`).

---

## 📋 Structured Planning & Roadmap Generation (`/plan`)

For complex tasks requiring architecture analysis before code edits, trigger planning mode with `/plan`:

1. **Trigger & Ontology Routing**:
   `/plan <your plan description>` creates a Kanban task (`📋 <plan text>`, initial status `inProgress`) and—if no agent is explicitly pinned—automatically routes it via the Ontology Graph to the best specialist.
2. **Read-Only Inspection Loop**:
   The agent inspects the codebase using read-only tools (`read_file`, `list_dir`, `web_search`, read-only terminal commands) without modifying files.
3. **Plan Formulation & Review**:
   The agent writes a structured roadmap and transitions the task to `review` with the summary attached so you can approve it or kick off execution via `/goal`.

---

## Examples

### Example 1: Ontology-Routed Sub-Task Delegation
```text
ghost_delegate_task(
  title="Audit smart contract dependencies",
  description="Check package versions and known CVEs in the wallet skill.",
  required_competencies=["Security", "Finance"],
  dry_run=false
)
```
Ghost scores all enabled agents via `HAT_KOMPETENZ`, `DARF_NUTZEN`, and active load, assigns the task to the top Security/Finance specialist, and launches background execution.

### Example 2: Sequential Pipeline
```text
kanban_pipeline(titles=["Analyze Requirements", "Implement Code", "Write Tests"], assign_to_me=true)
```
Creates Task A in `backlog` (or ready) and chains Task B → Task A and Task C → Task B via `dependsOnIds`. Finishing Task A automatically unblocks and starts Task B.

### Example 3: Dependency Management
If **Deploy App** (`dep-789`) has `dependsOnIds: ["fe-123", "be-456"]`, it remains waiting until **both** `fe-123` and `be-456` reach `done`, at which point the orchestrator marks it ready and starts its assigned (or ontology-routed) agent.
