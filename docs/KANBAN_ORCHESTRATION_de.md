# Kanban und Task-Orchestrierung

Ghost verfügt über ein Multi-Agenten-Kanban-System mit automatisierter Task-Orchestrierung und **ontologiegestütztem Multi-Agent-Routing**. Agenten können dadurch über Abhängigkeiten, Pipelines, autonome `/goal`- & `/plan`-Schleifen sowie dynamische Sub-Task-Delegation nahtlos zusammenarbeiten.

---

## Kernkonzepte

### 1. Kanban-Tasks (Aufgaben)
Ein Task ist die grundlegende Arbeitseinheit und umfasst:
- **Status (`TaskStatus`)**: `backlog`, `inProgress` (in der UI als *To Do / In Bearbeitung*), `review`, `done` (erledigt) oder `cancelled` (abgebrochen). *(Hinweis: Agenten-Tools akzeptieren zusätzlich `in_progress` in Snake-Case.)*
- **Priorität**: `low` (niedrig), `normal`, `high` (hoch) oder `urgent` (dringend).
- **Zuweisung**: Zuweisung an den Haupt-Agenten (`default-agent`), einen konkreten Custom Agent oder **`Auto (Ontologie)`** (`__auto__`).
- **Abhängigkeiten**: Tasks können von anderen Tasks abhängen (`dependsOnIds`).
- **Domänen-Labels**: Optionale Kompetenz-/Domänen-Tags (`labels`) zur gezielten Steuerung des Ontologie-Routings.

### 2. Task-Orchestrator & Ontologie-Routing
Der `TaskOrchestrator` ([`task_orchestrator.dart`](../lib/engine/tasks/task_orchestrator.dart)) steuert den Task-Lebenszyklus, Abhängigkeiten und die ontologiebasierte Agenten-Auswahl:

- **Automatisierte Abhängigkeitsübergänge**: Sobald ein Task auf `done` gesetzt wird, prüft der Orchestrator alle abhängigen Tasks. Sind alle `dependsOnIds` auf `done`, hinterlässt er einen Systemkommentar (*„All dependencies met. Task is now ready for execution.“*), löst ggf. eine `Auto (Ontologie)`-Zuweisung auf und verschiebt zugewiesene `backlog`-Tasks automatisch nach `inProgress` zur Ausführung.
- **Ontologie-Kompetenzgraph (`HAT_KOMPETENZ`)**:
  `AgentDomainTaxonomy` ([`agent_domain_taxonomy.dart`](../lib/engine/agent/ontology/agent_domain_taxonomy.dart)) normalisiert deutsche und englische Aliase, Skill-Kategorien und Schlüsselwörter über 7 Standarddomänen (`coding`, `research`, `finance`, `communication`, `system`, `security`, `design`) sowie benutzerdefinierte Kompetenzen. `OntologyStoreService.syncAgentCompetencies` leitet `HAT_KOMPETENZ`-Kanten automatisch ab aus:
  1. Expliziten `competencies`-Tags des Agenten (Gewichtung `1.0`)
  2. Prompt-/Profil-Keyword-Analyse (`0.65–0.78` Konfidenz, `0.65` Routing-Gewicht)
  3. Erlaubten Skill-Domänen (`DARF_NUTZEN` → `GEHOERT_ZU_DOMAIN`, `0.35` Routing-Gewicht)
- **Scoring & Auswahl (`evaluateAgentRouting`)**:
  Jeder aktive Agent wird auf einer Skala von `0–100` bewertet:
  - **Kompetenz-Match (`0–55` Pkt.)**: Domänen-Übereinstimmung (`0–45`) plus `+10` Bonus bei direktem Treffer zwischen Task-`labels` und expliziten Kompetenzen.
  - **Skill-Match (`0–30` Pkt.)**: Direkte Treffer auf Skill-Slug/Name/Beschreibung sowie Domänen-Skills über `DARF_NUTZEN`, gewichtet nach Spezialisierung (`0.4 + 0.6 * (1 - allowedSkills / totalSkills)`).
  - **Namensnennung (`0–10` Pkt.)**: Direkte Erwähnung des Agentennamens im Task.
  - **Auslastungs-Abzug (`0–15` Pkt.)**: `-5` Pkt. pro aktivem `inProgress`-Task (max. `-15`).
  - **Spezialisten-Schwellen**: Ein Custom-Spezialist wird gewählt, sobald `score >= 15.0` (`minSpecialistScore`) und der Vorsprung vor `default-agent` mindestens `8.0` Pkt. (`minMarginOverDefault`) beträgt; sonst greift automatisch der Haupt-Agent als Fallback.
- **Transparente Begründung**: Die vollständige Score-Aufschlüsselung wird in `task.metadata['routing']` gespeichert (sichtbar auf Kanban-Karten und im Task-Detail-Panel) und als Kommentar (`🧭 Auto-Routed zu <Agent> (...)`) protokolliert.

---

## Funktionen & Tools

### Dynamische Sub-Task-Delegation (`ghost_delegate_task`)
Agenten können spezialisierte Teilaufgaben direkt über den Knowledge Graph delegieren:
- **Parameter**: `title`, `description`, `required_competencies` (optionale Domänen-Hinweise), `priority`, `parent_task_id`, `execute_immediately` (Standard `true`) und `dry_run` (Standard `false`).
- **Dry-Run-Vorschau**: Mit `dry_run: true` lassen sich die Top-3-Kandidaten samt Score-Aufschlüsselung vorab prüfen, ohne einen Task anzulegen.
- **Rekursionsschutz**: Erzwingt über `parent_task_id` eine maximale Delegationstiefe von `maxDelegationDepth = 2`, um Endlos-Delegationen zu verhindern.

### Pipelines
Eine **Pipeline** ist eine Sequenz von Tasks, bei der jeder Task vom vorherigen abhängt (z. B. *„Recherche -> Implementierung -> Dokumentation“*).
- **Tool**: `kanban_pipeline`
- **Aktion**: Erstellt mehrere Tasks und verknüpft sie über `dependsOnIds`.

### Ontologie-Agenten-Vorschlag
Findet den optimalen Spezialisten für einen bestehenden Task anhand von Ontologie-Kompetenzen, Skills und aktueller Auslastung:
- **Tool**: `kanban_suggest`
- **Logik**: Führt `TaskOrchestrator.evaluateAgentRouting(task)` aus und liefert Agent, Begründung und Score zurück.

### Direkte Board-Tools
Agenten können das Kanban-Board direkt über folgende Tools verwalten:
- `kanban_list`: Tasks nach Status, Priorität oder `assigned_to_me` filtern.
- `kanban_create`: Neuen Task erstellen – optional mit `labels`, `assign_to_me` oder `auto_route` (Standard `true` für automatisches Ontologie-Routing).
- `kanban_update`: Status, Priorität, Titel oder Beschreibung ändern.
- `kanban_detail`: Vollständige Details inkl. Subtasks und Kommentaren abrufen.
- `kanban_assign`: Task selbst übernehmen (`assign_to_me`).
- `kanban_subtask`: Checklisten-Unteraufgaben verwalten (`action: "add" | "toggle"`).
- `kanban_comment`: Fortschritt oder Hinweise kommentieren.

---

## 🎯 Autonome Codierung / Projekt-Ausführung (`/goal`)

Ghost unterstützt eine autonome, zielorientierte Ausführungsschleife über den Chat-Befehl `/goal`.

### Funktionsweise

1. **Trigger, Ontologie-Routing & Initialisierung**:
   Bei `/goal <Zielbeschreibung>` erstellt Ghost automatisch einen Kanban-Task:
   - **Task-Titel**: `🎯 <Zieltext>` (auf 60 Zeichen gekürzt).
   - **Task-Beschreibung**: Der vollständige Prompt.
   - **Anfangsstatus**: `inProgress`.
   - **Zuweisung**: Ist kein Agent fest vorgegeben, startet der Task mit `Auto (Ontologie)` und wird sofort über `TaskOrchestrator.routeTask(..., force: true)` an den besten Spezialisten geroutet (`session_agent_routed` informiert die UI).
   - **Kontext-Verknüpfung**: Direkt mit der `sessionId` verknüpft für Live-Streaming im Chat.

2. **Autonome Schleife**:
   Der geroutete Agent arbeitet das Ziel mehrstufig mit Shell-, Dateisystem-, Web- oder Skill-Tools ab (`isGoalMode = true`).

3. **Abschluss & Nachverfolgung**:
   - **Erfolg**: Status wechselt auf `done` mit Zusammenfassungskommentar (`Ziel erreicht ✅`).
   - **Fehler / Unterbrechung**: Status wechselt auf `review` inkl. Fehlerprotokoll (`Fehler bei der Ausführung: <Fehler>`).

---

## 📋 Strukturierte Planung & Roadmap-Erstellung (`/plan`)

Für komplexe Vorhaben, die vor Codeänderungen eine Analyse erfordern, dient der Modus `/plan`:

1. **Trigger & Ontologie-Routing**:
   `/plan <Vorhabensbeschreibung>` legt einen Task (`📋 <Plan-Text>`, Status `inProgress`) an und routet ihn ohne expliziten Agenten automatisch über die Ontologie an den besten Spezialisten.
2. **Schreibgeschützte Analyse (Read-Only)**:
   Der Agent nutzt ausschließlich lesende Tools (`read_file`, `list_dir`, `web_search`, lesende Befehle), ohne Dateien zu verändern.
3. **Roadmap-Erstellung & Review**:
   Nach Abschluss wechselt der Task automatisch in den Status `review` samt Plan-Kommentar zur Freigabe oder direkten Umsetzung via `/goal`.

---

## Beispiele

### Beispiel 1: Ontologie-gestützte Sub-Task-Delegation
```text
ghost_delegate_task(
  title="Audit smart contract dependencies",
  description="Prüfe Paketversionen und bekannte CVEs im Wallet-Skill.",
  required_competencies=["Security", "Finanzen"],
  dry_run=false
)
```
Ghost bewertet alle aktiven Agenten anhand von `HAT_KOMPETENZ`, `DARF_NUTZEN` und Auslastung, weist den Task dem besten Security-/Finanz-Spezialisten zu und startet die Ausführung im Hintergrund.

### Beispiel 2: Sequenzielle Pipeline
```text
kanban_pipeline(titles=["Anforderungen analysieren", "Code implementieren", "Tests schreiben"], assign_to_me=true)
```
Erstellt drei verknüpfte Tasks über `dependsOnIds`. Sobald Task 1 auf `done` steht, wird Task 2 automatisch auf `inProgress` verschoben und gestartet.

### Beispiel 3: Abhängigkeitsauflösung
Hängt **App bereitstellen** (`dep-789`) über `dependsOnIds: ["fe-123", "be-456"]` von zwei Build-Tasks ab, startet er erst, nachdem **beide** auf `done` stehen.
