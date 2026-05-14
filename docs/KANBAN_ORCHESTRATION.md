# Kanban and Task Orchestration

Ghost features a powerful Multi-Agent Kanban system with automated task orchestration. This allows agents to collaborate on complex projects by defining dependencies, pipelines, and automated workflows.

## Core Concepts

### 1. Kanban Tasks
A task is the fundamental unit of work. Each task includes:
- **Status**: `backlog`, `in_progress`, `review`, `done`, or `cancelled`.
- **Priority**: `low`, `normal`, `high`, or `urgent`.
- **Assignment**: Tasks can be assigned to specific agents.
- **Dependencies**: Tasks can depend on other tasks (`dependsOnIds`).

### 2. Task Orchestrator
The `TaskOrchestrator` is the engine that manages the lifecycle of tasks and their interactions:
- **Automated Transitions**: When a task is marked as `done`, the orchestrator automatically checks all dependent tasks.
- **Dependency Resolution**: If all dependencies for a task are met, the orchestrator:
    - Adds a system comment: *"All dependencies met. Task is now ready for execution."*
    - **Auto-starts** the task (moves it to `in_progress`) if it was in `backlog` and already has an assigned agent.
- **Agent Suggestion**: The orchestrator can suggest the best agent for a task based on matching skills and agent names.

## Features & Tools

### Pipelines
A **Pipeline** is a sequence of tasks where each task depends on the previous one. This is ideal for linear workflows like "Research -> Implementation -> Documentation".
- **Tool**: `kanban_pipeline`
- **Action**: Creates multiple tasks and links them via `dependsOnIds`.

### Agent Matching
Agents can find the best person for a job using keyword matching against skills.
- **Tool**: `kanban_suggest`
- **Logic**: Matches words in the task title/description with agent names and their skillsets.

### Direct Manipulation
Agents have tools to list, create, update, assign, and comment on tasks:
- `kanban_list`: View the board.
- `kanban_create`: Add a new task.
- `kanban_update`: Move status or change details.
- `kanban_assign`: Take ownership of a task.
- `kanban_subtask`: Manage checklists within a task.
- `kanban_comment`: Discuss or provide updates.

---

## Examples

### Example 1: Creating a Sequential Pipeline
An agent wants to start a new feature development.

**Agent Input:**
`kanban_pipeline(titles=["Analyze Requirements", "Implement Code", "Write Tests"], assign_to_me=true)`

**Result:**
1. **Task A** (Analyze Requirements) created in `in_progress` (since it has no dependencies).
2. **Task B** (Implement Code) created in `backlog`, depends on Task A.
3. **Task C** (Write Tests) created in `backlog`, depends on Task B.

When the agent finishes Task A and marks it as `done`, **Task B** will automatically move to `in_progress`.

### Example 2: Dependency Management
Suppose you have a task "Deploy App" that depends on "Frontend Build" and "Backend Build".

1. **Frontend Build** [ID: `fe-123`]
2. **Backend Build** [ID: `be-456`]
3. **Deploy App** [ID: `dep-789`, `dependsOnIds`: [`fe-123`, `be-456`]]

If **Frontend Build** is finished, nothing happens to "Deploy App" yet. Once **Backend Build** is also marked as `done`, the Orchestrator notices all dependencies for `dep-789` are met and readies it for execution.

### Example 3: Agent Suggestion
A user creates a task "Fix Python Script".

**Agent Action:**
`kanban_suggest(taskId="python-task-id")`

**Orchestrator Logic:**
Matches "Python" against all available agents. If "Agent Alpha" has "python" in their skills, it suggests: *"Suggested agent: Agent Alpha (alpha-id)"*.
