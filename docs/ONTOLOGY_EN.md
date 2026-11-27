# 🧠 Ontology & Knowledge Graph Memory — Ghost

Ghost complements traditional key-value memory (Hive) and semantic vector search (ObjectBox RAG) with a **Native ObjectBox Ontology & Knowledge Graph**. It stores structured entities, typed relations, governance rules, and multi-hop facts locally with strict security gating.

---

## 🏗️ Architecture Overview

The Knowledge Graph is backed by ObjectBox (`$stateDir/objectbox_ontology` or shared ObjectBox `Store`) and implements a classic **T-Box / A-Box** separation in [`ontology_models.dart`](../lib/engine/agent/ontology/ontology_models.dart) and [`ontology_store_service.dart`](../lib/engine/agent/ontology/ontology_store_service.dart):

| Layer | Entity Class | Responsibility |
|---|---|---|
| **T-Box (Schema & Rules)** | `OntologyRelationDef` | Defines predicates (`UPPER_SNAKE_CASE`), expected `domainType` & `rangeType`, and semantic constraints (`isFunctional`, `isTransitive`). |
| **A-Box (Entities)** | `OntologyNode` | Canonical entities with unique `canonicalKey` (e.g. `user:primary`, `place:zuerich`), display `label`, `entityType`, and `metadataJson`. |
| **A-Box (Facts & Edges)** | `OntologyEdge` | Directed triples `(subjectId) --[predicate]--> (objectId)` with `confidence` (`0.0–1.0`) and `createdAt`. |

### Semantic Rules (`isFunctional` & `isTransitive`)
- **Functional Predicates (`isFunctional = true`)**: At most one active object per `(subject, predicate)`. Asserting a new object automatically replaces prior edges (e.g., moving from Berlin to Zürich updates `WOHNT_IN` cleanly without stale contradictions).
- **Transitive Predicates (`isTransitive = true`)**: Supports recursive multi-hop traversal (depths `1–4`) via `queryFactsForEntity` (e.g., `Peter --[WOHNT_IN]--> Zürich` + `Zürich --[LIEGT_IN]--> Schweiz` yields inferred country knowledge).

---

## 📋 Built-In T-Box Predicates

Ghost seeds 17 default relation definitions on startup:

### Personal & World Knowledge (12 Predicates)

| Predicate | Domain → Range | Functional | Transitive | Purpose |
|---|---|---|---|---|
| `WOHNT_IN` | `Person` → `Place` | ✅ | ❌ | Residence / city |
| `HEISST` | `Entity` → `Text` | ✅ | ❌ | Canonical display name (updates node label without redundant self-edge) |
| `ARBEITET_AN` | `Person` → `Project` | ❌ | ❌ | Active projects |
| `ARBEITET_BEI` | `Person` → `Organization` | ✅ | ❌ | Employer / organization |
| `LIEGT_IN` | `Place` → `Place` | ✅ | ✅ | Geographic hierarchy (city → country) |
| `TEIL_VON` | `Entity` → `Entity` | ❌ | ✅ | Part-of composition hierarchy |
| `MAG` | `Person` → `Entity` | ❌ | ❌ | Preferences / interests |
| `MAG_NICHT` | `Person` → `Entity` | ❌ | ❌ | Dislikes / exclusions |
| `HAT_BERUF` | `Person` → `Role` | ✅ | ❌ | Profession / role |
| `BENUTZT` | `Person` → `Technology` | ❌ | ❌ | Tools, languages, frameworks |
| `SPRICHT` | `Person` → `Language` | ❌ | ❌ | Spoken languages |
| `KENNT` | `Person` → `Person` | ❌ | ❌ | Known contacts / relationships |

### Governance, Skills & Multi-Agent Routing (5 Predicates)

| Predicate | Domain → Range | Functional | Transitive | Purpose |
|---|---|---|---|---|
| `DARF_NUTZEN` | `Agent` → `Skill` | ❌ | ❌ | Opt-out skill permission synchronized from `disabledSkills` |
| `HAT_KOMPETENZ` | `Agent` → `Domain` | ❌ | ❌ | Agent domain competency used by `TaskOrchestrator` routing |
| `GEHOERT_ZU_DOMAIN` | `Skill` → `Domain` | ✅ | ❌ | Maps each skill category to a canonical routing domain |
| `BENOETIGT_SKILL` | `Skill` → `Skill` | ❌ | ✅ | Transitive skill dependency chain loaded by `ghost_load_skill` |
| `ERFORDERT_HITL` | `Skill` → `SecurityPolicy` | ✅ | ❌ | Governance policy forcing Human-In-The-Loop approval for high/critical skills |

---

## 🔄 Pre-Turn Injection & Post-Turn Extraction

Handled by [`OntologyExtractor`](../lib/engine/agent/ontology/ontology_extractor.dart) inside the agent loop ([`agent.dart`](../lib/engine/agent/agent.dart)):

### 1. Pre-Turn Context Injection
Before each non-greeting turn (`rawPromptText.length >= 4`, with a 2-second timeout):
- Queries `user:primary`, the configured user name (`userConfig.name`), and up to 5 entity nodes matched directly inside the user's message (`findMatchingNodesInText`).
- Performs multi-hop traversal (`maxDepth: 2`, `maxFacts: 15`).
- Filters out internal governance predicates (`DARF_NUTZEN`, `HAT_KOMPETENZ`, `GEHOERT_ZU_DOMAIN`, `BENOETIGT_SKILL`, `ERFORDERT_HITL`).
- Injects compact triples into the system prompt under `[KNOWLEDGE GRAPH (VERIFIED STRUCTURED FACTS)]`.

### 2. Async Post-Turn Extraction & Memory-Poisoning Protection
After the assistant responds, Ghost runs `OntologyExtractor.extractAndAssertFacts` asynchronously (at `temperature: 0.0`, minimum input length `12` chars, confidence threshold `>= 0.7`) to persist explicit durable user facts.

> [!IMPORTANT]
> **Strict System-1 Memory-Poisoning Protection**: Automatic post-turn fact extraction is **strictly gated** by:
> `security.system1Middleware && !system1SecurityFlagged && !hitlWasTriggered && !isAborted()`
> and is skipped for short greetings as well as automated `cron_`, `run_`, and `auto_` sessions. Prompt-injection or phishing-flagged inputs can **never** poison long-term Knowledge Graph memory.

---

## 🛠️ Agent Tools

Agents can read and write structured knowledge directly using two built-in tools ([`ontology.dart`](../lib/engine/tools/ontology.dart)):

- **`ghost_ontology_assert`**: Stores or updates a triple `(subject, predicate, object)` with optional `subject_type`, `object_type`, and `confidence`. Automatically maps `user:primary`, `user`, `ich`, and `me` to the primary user node and replaces prior edges for functional predicates.
- **`ghost_ontology_query`**: Queries direct and multi-hop inferred facts for an entity (`max_depth` `1–4`, default `2`; `include_incoming`, default `true`).

---

## 🖥️ Settings UI: Monolith Graph Explorer & Query Inspector

Navigate to **Settings → Toolbox → Memory → Ontology** to manage the Knowledge Graph interactively:

1. **Master & Auto-Extraction Toggles**: Enable/disable Ontology Knowledge Graph injection (`ontologyEnabled`) and System-1-gated auto-extraction (`ontologyAutoExtract`).
2. **Stats & Explorer Panel**:
   - Filter views: **All**, **Personal**, **Governance**, and **Rules** (T-Box definitions).
   - Switch between **Facts** (triples with confidence, functional/inferred badges, and delete action), **Entities** (nodes with incident edge counts and cascading delete), and **Rules** (`isFunctional` / `isTransitive` schemas).
   - **+ Add Fact**: Add or update structured triples manually via dialog.
3. **Multi-Hop Query Inspector**:
   - Enter any entity (e.g. `Peter`, `user:primary`, `Zürich`) and select traversal depth (`1–4` hops).
   - Displays matched root nodes, direct facts, transitive/inferred chains (`[via: ...]`), and the exact **Pre-Turn System Prompt Preview**.
4. **Backup, Restore & Clear**:
   - Export/import portable JSON backups (`ghost_ontology.json`) with canonical key remapping.
   - Included automatically in **Settings → Reset → Backup & Restore** (`ontology_backup.json` inside `memory` backups).
   - Clear the graph while preserving default T-Box rules (`config.clearMemory` with `type: "ontology"`).

---

## 🔌 RPC API Methods

| Method | Purpose |
|---|---|
| `memory.ontology.stats` | Return relation, node, edge, skill, personal, and governance counts |
| `memory.ontology.list` | List facts, nodes, and T-Box rules filtered by `category` (`all`, `personal`, `governance`, `rules`) and `query` |
| `memory.ontology.assert` | Assert or update a structured triple (broadcasts `ontology.changed`) |
| `memory.ontology.deleteEdge` | Delete a single edge by `edgeId` |
| `memory.ontology.deleteNode` | Delete a node and all incident edges by `canonicalKey` |
| `memory.ontology.query` | Run 1–4 hop query and return `result` + `promptPreview` |
| `memory.ontology.backup` / `restore` | Export or import portable Knowledge Graph JSON |

See the **[RPC API Reference](RPC_API_REFERENCE.md)** for full request parameters and payload details.
