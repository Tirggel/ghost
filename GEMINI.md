# GEMINI.md — Ghost Architecture & Development Guide

This document is a concise architectural reference and ruleset for AI coding agents working in the **Ghost** repository (`Dart ^3.8.0` / `Flutter`).

---

## 1. Architecture Overview

Ghost is an integrated Dart/Flutter application combining a desktop/web Flutter UI with an embedded backend engine and a standalone headless CLI adapter:

| Layer | Key Paths | Responsibility |
|---|---|---|
| **Flutter UI & State** | `lib/main.dart`, `lib/ui/**`, `lib/providers/**`, `lib/core/**` | Riverpod (`flutter_riverpod`) state, `easy_localization` (`assets/translations/{de,en}.json`), Monolith theme & shared widgets |
| **Integrated Engine** | `lib/engine.dart`, `lib/engine/**` | Agent loop, LLM providers, ObjectBox RAG & Ontology, Hive sessions, Kanban orchestrator, Automations scheduler (`lib/engine/automations/**`), WebSocket/JSON-RPC gateway, channels, tools |
| **Headless ACP CLI** | `bin/ghost_acp.dart`, `lib/engine/acp/**` | Pure Dart STDIO/WebSocket Agent Client Protocol server for Antigravity CLI (`agy`), Antigravity IDE, and Zed |

### Strict Decoupling Rule (`lib/engine/**` & `bin/**`)
- `lib/engine.dart` and everything under `lib/engine/**` and `bin/**` **must remain free of `package:flutter/...` and `dart:ui` imports** (use conditional imports with stubs where platform bindings exist, e.g. `lib/engine/agent/pdf/pdf_extractor.dart`, `lib/engine/infra/objectbox_flutter_libs_stub.dart`).
- Never break headless compilation of `bin/ghost_acp.dart` by pulling Flutter dependencies into engine code.

---

## 2. Code Generation & Headless ObjectBox Rule

### Running `build_runner`
Whenever you add or modify ObjectBox `@Entity()` classes (`lib/engine/agent/rag_memory.dart`, `lib/engine/agent/ontology/ontology_models.dart`) or `@JsonSerializable()` models (`lib/engine/models/skill.dart`, etc.), regenerate code via:

```bash
dart run build_runner build --delete-conflicting-outputs
```

### Mandatory Conditional Import in `lib/objectbox.g.dart`
`objectbox_generator` overwrites `lib/objectbox.g.dart` with an unconditional `import 'package:objectbox_flutter_libs/objectbox_flutter_libs.dart';`, which pulls in Flutter (`dart:ui`) and breaks the headless CLI (`bin/ghost_acp.dart`).

**After every `build_runner` run**, inspect `lib/objectbox.g.dart` and restore the conditional import using `lib/engine/infra/objectbox_flutter_libs_stub.dart`:

```dart
import 'engine/infra/objectbox_flutter_libs_stub.dart'
    if (dart.library.ui) 'package:objectbox_flutter_libs/objectbox_flutter_libs.dart';
```

Never delete `lib/engine/infra/objectbox_flutter_libs_stub.dart`.

---

## 3. Native ObjectBox Ontology & Memory-Poisoning Protection

- **Models & Store**: `lib/engine/agent/ontology/ontology_models.dart` (`OntologyRelationDef` T-Box, `OntologyNode` & `OntologyEdge` A-Box) and `lib/engine/agent/ontology/ontology_store_service.dart`.
- **T-Box Semantics**:
  - `isFunctional = true` (e.g., `WOHNT_IN`, `HEISST`, `ARBEITET_BEI`, `LIEGT_IN`, `HAT_BERUF`, `GEHOERT_ZU_DOMAIN`, `ERFORDERT_HITL`): asserting a new object replaces prior edges for `(subject, predicate)`.
  - `isTransitive = true` (e.g., `LIEGT_IN`, `TEIL_VON`, `BENOETIGT_SKILL`): supports recursive multi-hop traversal (`queryFactsForEntity`, up to depth 4).
- **Pre/Post-Turn Pipeline (`lib/engine/agent/ontology/ontology_extractor.dart`)**:
  - Pre-turn injects compact non-governance triples as `[KNOWLEDGE GRAPH (VERIFIED STRUCTURED FACTS)]`.
  - Post-turn async extraction (`OntologyExtractor.extractAndAssertFacts`) in `lib/engine/agent/agent.dart` **must remain strictly gated** behind System-1 security checks (`security.system1Middleware && !system1SecurityFlagged && !hitlWasTriggered && !isAborted()`) to prevent **Memory Poisoning** (and skipped for `cron_`, `run_`, `auto_` sessions).
- **UI**: `lib/ui/screens/shell/settings/widgets/ontology_section.dart`, `ontology_explorer_panel.dart`, and `ontology_query_inspector.dart`.

---

## 4. System-1 Security Gates & HITL

- **Engine**: `System1Service` (`lib/engine/system1/system1_service.dart`) communicates over IPC with `scripts/system1_daemon.py` (`scripts/models/ghost_system1_int8.onnx`).
- **Pre-Flight Checks (`lib/engine/agent/agent.dart`)**:
  - Choice routing (`>= 0.65`)
  - Language-aware prompt injection / jailbreak check (`>= 0.65` sets `system1SecurityFlagged = true`; `>= 0.88` blocks turn immediately)
  - Phishing / fraud check
- **Tool Execution & HITL (`_executeToolWithHITL`)**:
  - Sensitive tools (`bash`, `write_file`, `edit_file`, `delete_file`, `browser*`, `binance_*`, `execute_blockchain_payment`, `execute_token_swap`, etc.) require HITL when `security.humanInTheLoop` is enabled (unless `isCron` or `isGoalMode`).
  - **Ontology HITL Governance (`ERFORDERT_HITL`)**: Skills marked `requiresHitl` in ObjectBox trigger HITL; `critical` skills enforce HITL whenever `security.level != SecurityLevel.none`.
  - **Dynamic Payload Risk Scoring**: System-1 scores full tool payloads (`Destructive action risk`, plus `Liquidation and capital destruction risk` for financial/wallet tools); scores `>= 0.65` force HITL.
  - **Smart HITL Confirmation**: System-1 verifies follow-up user intent before executing pending HITL actions.

---

## 5. Opt-Out Skill Model & Progressive Disclosure

- **Opt-Out Permissions (`disabledSkills`)**: Both `AgentConfig` and `CustomAgentConfig` (`lib/engine/config/config.dart`, `lib/core/models/config_models.dart`) store `disabledSkills` and resolve allowed skills via `resolveAllowedSkills(allInstalledSlugs)` (`allInstalledSlugs - disabledSkills`). Newly installed skills are enabled by default for all agents unless opted out.
- **Ontology Sync**: `AgentManager.syncOntologySkillsAndPermissions` (`lib/engine/agent/manager.dart`) syncs all skills, `DARF_NUTZEN`, `GEHOERT_ZU_DOMAIN`, `BENOETIGT_SKILL`, `ERFORDERT_HITL`, and `HAT_KOMPETENZ` edges into ObjectBox.
- **Two-Stage Progressive Disclosure**:
  1. System prompts inject only compact `[AVAILABLE SKILLS — PROGRESSIVE DISCLOSURE]` index lines (`SkillOntologySummary.toCompactIndexLine()`).
  2. Agents call `ghost_load_skill` (`lib/engine/tools/skills.dart`) to load full `SKILL.md` instructions, `.venv`/Node/MCP paths, transitive `BENOETIGT_SKILL` dependencies, and `ERFORDERT_HITL` notices on demand after verifying `DARF_NUTZEN`.

---

## 6. Ontology-Driven Multi-Agent Routing & Delegation

- **Domain Taxonomy**: `AgentDomainTaxonomy` (`lib/engine/agent/ontology/agent_domain_taxonomy.dart`) normalizes domains (`coding`, `research`, `finance`, etc.) across German/English labels, aliases, skill categories, and keywords.
- **Automatic `HAT_KOMPETENZ` Derivation**: `OntologyStoreService.syncAgentCompetencies` merges explicit `competencies` (`1.0`), prompt/profile keyword inference (`0.65..0.78`), and skill-domain distribution (`DARF_NUTZEN` → `GEHOERT_ZU_DOMAIN`).
- **Routing & Delegation**:
  - `TaskOrchestrator.evaluateAgentRouting` (`lib/engine/tasks/task_orchestrator.dart`) scores enabled agents by competency match, skill match, name match, and active workload penalty (`minSpecialistScore = 15.0`, `minMarginOverDefault = 8.0`).
  - Automatically routes `/goal`, `/plan` (`lib/engine/gateway/agent_router.dart`), `Auto (Ontologie)` Kanban tasks, and `ghost_delegate_task` (`lib/engine/tools/kanban.dart`, `maxDelegationDepth = 2`).

---

## 7. "The Monolith" Design Tokens (`DESIGN.md`)

All Flutter UI work must adhere strictly to **Ghost Minimalist Noir ("The Monolith")** defined in `DESIGN.md`, `lib/core/constants.dart`, `lib/core/theme.dart`, and `lib/ui/widgets/app_styles.dart`:

- **Monochromatic Zinc Palette (`AppColors`)**:
  - `background`: `#09090B` (Deep Zinc 950)
  - `surface`: `#18181B` (Zinc 900)
  - `surfaceLight` / `border`: `#27272A` (Zinc 800)
  - `primary`: `#FFFFFF` (Pure White)
  - `textMain`: `#FAFAFA` | `textDim`: `#A1A1AA` (Zinc 400)
  - Semantic / Priority accents only where functional: `error` (`Colors.redAccent`), `success` (`Colors.green`), `warning` (`Colors.orange`), Kanban `urgent` (`#ef4444`), `high` (`#f97316`).
- **Tonal Architecture ("No-Line" Rule)**: Separate sections with tonal surface shifts (`surface` on `background`) and spacing tokens (`settingsSectionSpacing = 32.0`, `settingsHeaderSpacing = 12.0`, `settingsContentSpacing = 20.0`, `settingsElementSpacing = 16.0`), avoiding heavy divider lines (`dividerTheme` is transparent).
- **Geometry & Motion**: Sharp rectangular buttons (`AppConstants.buttonBorderRadius = 0.0`), subtle borders (`0.5px`–`1px` `AppColors.border`), 150ms tonal transitions without bouncy curves.
- **Typography (`Inter`)**: `fontSizeDisplay = 28.0`, `fontSizeHeading = 22.0`, `fontSizeTitle = 16.0`, `fontSizeSubhead = 14.0`, `fontSizeBody/Small/Caption = 13.0`, `fontSizeSidebarLabel = 12.0`, `fontSizeLabelTiny = 11.0` (uppercase, `FontWeight.w900`).
- **Reuse Shared Widgets**: Always prefer `AppSectionLabel`, `AppFormLabel`, `AppFormField`, `AppInputDecoration`, `AppSaveButton`, `AppActionButton`, `AppUnifiedPicker`, and `AppHoverCard` from `lib/ui/widgets/app_styles.dart` instead of ad-hoc styling.
