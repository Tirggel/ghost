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

## 🎯 Autonome Codierung / Projekt-Ausführung (`/goal`)

Ghost unterstützt eine autonome, zielorientierte Ausführungsschleife, die über den Chat-Befehl `/goal` gestartet wird. Dies verbindet die Chat-Schnittstelle direkt mit dem Kanban-Aufgabenverwaltungssystem und ermöglicht es dem Agenten, komplexe, mehrstufige Ziele selbstständig zu bearbeiten und gleichzeitig volle Transparenz zu bieten.

### Funktionsweise

1. **Trigger & Initialisierung**:
   Wenn ein Benutzer eine Nachricht sendet, die mit `/goal <Zielbeschreibung>` beginnt, fängt das System die Anfrage ab und erstellt automatisch einen neuen Kanban-Task auf dem Board.
   - **Task-Titel**: `🎯 <Zieltext>` (zur besseren Lesbarkeit auf die ersten 60 Zeichen gekürzt).
   - **Task-Beschreibung**: Der vollständige Prompt mit dem Ziel.
   - **Anfangsstatus**: Wird sofort auf `in_progress` (in Bearbeitung) gesetzt.
   - **Zuweisung**: Wird dem aktuellen Agenten zugewiesen, der die Sitzung betreut.
   - **Kontext-Verknüpfung**: Der Task wird direkt mit der Chat-`sessionId` verknüpft, sodass die Arbeit des Agenten in Echtzeit mitverfolgt werden kann.

2. **Autonome Schleife**:
   Der Agent startet eine autonome Schleife aus Denkschritten (Reasoning) und Tool-Ausführungen. Er führt Shell-Befehle aus, liest/schreibt Dateien, führt Websuchen durch oder nutzt andere verfügbare Werkzeuge, um das Ziel zu erreichen.

3. **Abschluss & Nachverfolgung**:
   Sobald der Agent seine autonome Arbeit beendet hat, wird der Task basierend auf dem Ergebnis aktualisiert:
   - **Erfolg**: Der Task-Status wird auf `done` (erledigt) geändert, und der Agent fügt einen Kommentar mit einer Zusammenfassung hinzu: `Ziel erreicht ✅\n\nZusammenfassung: <Kurzzusammenfassung der Ergebnisse>`.
   - **Fehlgeschlagen / Unterbrochen**: Tritt während der Ausführung ein nicht behebbarer Fehler auf, wird der Task auf `review` (Überprüfung) gesetzt und ein Systemkommentar mit der Fehlermeldung hinterlassen: `Fehler bei der Ausführung: <Fehlermeldung>`.

Dadurch sind alle autonomen Aktionen auf dem Kanban-Board lückenlos nachvollziehbar, sodass Benutzer Ergebnisse prüfen, Fehler untersuchen oder Aufgaben fortsetzen können.

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
