# Kanban und Task-Orchestrierung

Ghost verfügt über ein leistungsstarkes Multi-Agenten-Kanban-System mit automatisierter Task-Orchestrierung. Dies ermöglicht es Agenten, an komplexen Projekten zusammenzuarbeiten, indem sie Abhängigkeiten, Pipelines und automatisierte Workflows definieren.

## Kernkonzepte

### 1. Kanban-Tasks (Aufgaben)
Ein Task ist die grundlegende Arbeitseinheit. Jeder Task umfasst:
- **Status**: `backlog`, `in_progress`, `review`, `done` (erledigt) oder `cancelled` (abgebrochen).
- **Priorität**: `low` (niedrig), `normal`, `high` (hoch) oder `urgent` (dringend).
- **Zuweisung**: Tasks können spezifischen Agenten zugewiesen werden.
- **Abhängigkeiten**: Tasks können von anderen Tasks abhängen (`dependsOnIds`).

### 2. Task-Orchestrator
Der `TaskOrchestrator` ist die Engine, die den Lebenszyklus von Tasks und deren Interaktionen steuert:
- **Automatisierte Übergänge**: Wenn ein Task als `done` markiert wird, prüft der Orchestrator automatisch alle abhängigen Tasks.
- **Auflösung von Abhängigkeiten**: Wenn alle Abhängigkeiten eines Tasks erfüllt sind, führt der Orchestrator folgende Schritte aus:
    - Erstellt einen System-Kommentar: *"Alle Abhängigkeiten erfüllt. Task ist nun bereit für die Ausführung."*
    - **Automatischer Start**: Der Task wird in den Status `in_progress` verschoben, falls er sich im `backlog` befand und bereits einem Agenten zugewiesen ist.
- **Agenten-Vorschlag**: Der Orchestrator kann den am besten geeigneten Agenten für einen Task vorschlagen, basierend auf den Fähigkeiten (Skills) und Namen der Agenten.

## Funktionen & Tools

### Pipelines
Eine **Pipeline** ist eine Sequenz von Tasks, bei der jeder Task vom vorherigen abhängt. Dies ist ideal für lineare Workflows wie "Recherche -> Implementierung -> Dokumentation".
- **Tool**: `kanban_pipeline`
- **Aktion**: Erstellt mehrere Tasks und verknüpft sie über `dependsOnIds`.

### Agenten-Matching
Agenten können die beste Person für einen Job finden, indem sie Stichwort-Abgleiche gegen die Skills durchführen.
- **Tool**: `kanban_suggest`
- **Logik**: Vergleicht Begriffe im Task-Titel oder der Beschreibung mit Agenten-Namen und deren Skill-Sets.

### Direkte Interaktion
Agenten verfügen über Tools zum Auflisten, Erstellen, Aktualisieren, Zuweisen und Kommentieren von Tasks:
- `kanban_list`: Das Board anzeigen.
- `kanban_create`: Einen neuen Task hinzufügen.
- `kanban_update`: Status verschieben oder Details ändern.
- `kanban_assign`: Die Verantwortung für einen Task übernehmen.
- `kanban_subtask`: Checklisten innerhalb eines Tasks verwalten.
- `kanban_comment`: Diskutieren oder Updates bereitstellen.

---

## Beispiele

### Beispiel 1: Erstellen einer sequenziellen Pipeline
Ein Agent möchte mit einer neuen Feature-Entwicklung beginnen.

**Agenten-Eingabe:**
`kanban_pipeline(titles=["Anforderungen analysieren", "Code implementieren", "Tests schreiben"], assign_to_me=true)`

**Ergebnis:**
1. **Task A** (Anforderungen analysieren) wird in `in_progress` erstellt (da keine Abhängigkeiten bestehen).
2. **Task B** (Code implementieren) wird im `backlog` erstellt und hängt von Task A ab.
3. **Task C** (Tests schreiben) wird im `backlog` erstellt und hängt von Task B ab.

Sobald der Agent Task A abschließt und als `done` markiert, verschiebt sich **Task B** automatisch nach `in_progress`.

### Beispiel 2: Verwaltung von Abhängigkeiten
Angenommen, Sie haben einen Task "App bereitstellen", der von "Frontend Build" und "Backend Build" abhängt.

1. **Frontend Build** [ID: `fe-123`]
2. **Backend Build** [ID: `be-456`]
3. **App bereitstellen** [ID: `dep-789`, `dependsOnIds`: [`fe-123`, `be-456`]]

Wenn der **Frontend Build** abgeschlossen ist, passiert mit "App bereitstellen" zunächst nichts. Sobald auch der **Backend Build** als `done` markiert wird, erkennt der Orchestrator, dass alle Abhängigkeiten für `dep-789` erfüllt sind, und bereitet ihn für die Ausführung vor.

### Beispiel 3: Agenten-Vorschlag
Ein Benutzer erstellt einen Task "Python-Skript reparieren".

**Agenten-Aktion:**
`kanban_suggest(taskId="python-task-id")`

**Orchestrator-Logik:**
Sucht nach "Python" in den Skills aller verfügbaren Agenten. Wenn "Agent Alpha" "python" in seinen Skills hat, erfolgt der Vorschlag: *"Vorgeschlagener Agent: Agent Alpha (alpha-id)"*.
