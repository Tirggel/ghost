# ⚡ Automations & Geplante Workflows — Ghost

Ghost bietet einen eigenen **Automations**-Arbeitsbereich für wiederkehrende KI-Workflows mit lesbaren Zeitplänen, KI-gestütztem Prompt-Assistenten, **ontologiegestütztem Agent-Routing**, individuellen Provider-/Modell-Overrides und einer persistenten Run-Historie inklusive vollständiger Chat-Transkripte.

---

## 🧭 Zugriff auf Automations

Öffne **Automations** direkt über die Haupt-Seitenleiste (Blitz-Symbol, direkt unterhalb von **Kanban Board**).

Die Übersicht bietet:
- Echtzeit-Suche über Titel, Instructions und Zeitpläne
- Zähler-Badge für die Anzahl der angezeigten Automations
- Strukturierte Tabelle mit **Titel**, **Agenten-Badge** (`🧭 Auto (Ontologie)`, `👻 Haupt-Agent` oder `🤖 Custom Agent`), **Zeitplan** (menschenlesbar), **Nächster Lauf**, **Letzter Lauf** (`success` / `failed` / `running` / `cancelled`) sowie einem **Aktiv**-Schalter zum sofortigen Pausieren oder Aktivieren.

---

## 🪄 Automations erstellen

### Option 1: `+ Create with Prompt` (KI-Assistent)
Implementiert in [`CreateWithPromptDialog`](../lib/ui/screens/automations/widgets/create_with_prompt_dialog.dart) und [`AutomationManager.generateFromPrompt`](../lib/engine/automations/automation_manager.dart):
1. Beschreibe kurz in natürlicher Sprache, was wann passieren soll (z. B. *„Fasse werktags um 08:15 und 17:15 Uhr meine ungelesenen E-Mails zusammen und markiere dringende Aufgaben.“*).
2. Ghost nutzt dein aktives LLM sowie den Agenten-Katalog und erstellt einen editierbaren Entwurf:
   - Prägnanter **Titel** (in der aktuellen UI-Sprache)
   - Detaillierte Schritt-für-Schritt-**Instructions**
   - Exakter **Zeitplan** (exakte Minuten und Intervalle bleiben unverändert ohne Rundung)
   - Passende **Agenten-Auswahl** (standardmäßig `Auto (Ontologie)`, sofern kein bestimmter Agent ausdrücklich passt) inkl. Live-Spezialisten-Vorschau
3. Du kannst alle Felder im Review-Schritt anpassen oder über **Neu generieren** einen frischen Entwurf erzeugen.

### Option 2: `+ New` (Manuelle Einrichtung)
Implementiert in [`CreateAutomationDialog`](../lib/ui/screens/automations/widgets/create_automation_dialog.dart):
- Direkte Konfiguration von **Titel**, **Zeitplan**, **Agent** (`Auto (Ontologie)`, Haupt-Agent oder aktiver Custom Agent), optionalem **Provider-Override** / **Modell-Override** und **Instructions**.

---

## 🗓️ Zeitplan-Modi (`SchedulePickerWidget` & `CronUtils`)

Jeder Zeitplan wird sauber in einen oder mehrere standardisierte 5-Feld-Unix-Cron-Ausdrücke (`Minute Stunde Tag Monat Wochentag`) kompiliert:

| Modus | Konfiguration | Beispiel-Cron |
|---|---|---|
| **Täglich (`daily`)** | Eine oder mehrere exakte `HH:mm`-Uhrzeiten | `15 8,17 * * *` (bei unterschiedlichen Minuten mehrere Cron-Trigger) |
| **Werktags (`weekdays`)** | Mo–Fr (`1-5`) mit einer oder mehreren exakten `HH:mm`-Uhrzeiten | `15 8,17 * * 1-5` |
| **Wöchentlich (`weekly`)** | Wählbare ISO-Wochentage (`1=Mo..7=So`) und exakte `HH:mm`-Zeiten | `0 9 * * 1,4` |
| **Stündlich (`hourly`)** | Alle `1–24` Stunden zur exakten Minute `:mm` | `12 */3 * * *` |
| **Intervall (`interval`)** | Frei wählbar: alle `1–59` Minuten oder alle `1–24` Stunden | `*/7 * * * *` oder `0 */2 * * *` |
| **Custom Cron (`custom`)** | Direkter 5-Feld-Unix-Cron-Ausdruck mit Live-Validierung | `30 6 1 * *` |

Der Picker zeigt eine menschenlesbare Zusammenfassung, validiert Eingaben in Echtzeit und berechnet auf Wunsch die **nächsten 3 Ausführungszeiten** (`CronUtils.computeNextRuns`).

---

## 🧠 Detailansicht, Ausführung & Transkripte

Ein Klick auf eine Zeile öffnet die [`AutomationDetailView`](../lib/ui/screens/automations/automation_detail_view.dart):

- **Header-Aktionen**: Inline editierbarer Titel, Aktiv/Pausiert-Schalter, **Run Now** (sofortige Hintergrund-Ausführung) und **Löschen** (stoppt laufende Prozesse und entfernt Definition, Run-Historie sowie alle verknüpften `auto_<id>_*`-Sessions).
- **Einstellungen**: Zeitplan, Agent (inkl. **Voraussichtlicher Spezialist**-Anzeige bei `Auto (Ontologie)`) sowie Provider- und Modell-Overrides.
- **Instructions**: Einklappbare Ansicht mit direkter Inline-Bearbeitung.
- **Runs-Historie**: Chronologische Liste (bis zu 100 Läufe pro Automation) mit Status, Auslöser (`Geplant` / `Manuell`), Startzeit, Laufzeit, zugewiesenem Agent/Provider/Modell sowie Zusammenfassung oder Fehlertext.
  - Ein Klick auf einen Run öffnet das komplette **`auto_<automationId>_<runId>`-Chat-Transkript** direkt im Chat.
  - Automatisierte `auto_*`-Sessions bleiben in der regulären Chat-Seitenleiste ausgeblendet, um deine normalen Chats übersichtlich zu halten.

### Sicherheits- & Ausführungsregeln
- **Überlappungsschutz**: `_activeRunIds` verhindert parallele Doppelausführungen derselben Automation.
- **Dynamisches Ontologie-Routing je Lauf**: Bei `Auto (Ontologie)` bewertet `TaskOrchestrator.evaluateRoutingForRequest` zur Laufzeit alle Kompetenzen (`HAT_KOMPETENZ`), Skills (`DARF_NUTZEN` → `GEHOERT_ZU_DOMAIN`) und aktive Auslastungen.
- **Autonomer Hintergrundbetrieb & Neustart-Recovery**: `auto_`-Sessions laufen unbeaufsichtigt ohne interaktive HITL-Blockaden und sind von der Post-Turn-`OntologyExtractor`-Extraktion ausgeschlossen. Bei unerwartetem Neustart verbliebene `running`-Einträge werden beim Hochfahren automatisch als `cancelled` (*„Interrupted by system restart“*) bereinigt.

---

## 💾 Persistenz & Backups

- **Dateispeicher** (`AutomationStore`):
  - Definitionen: `<stateDir>/automations/definitions/<id>.json`
  - Run-Historie: `<stateDir>/automations/runs/<automationId>.json`
- **ZIP-Backups**: Als eigene Sektion **`automations`** in **Einstellungen → Zurücksetzen → Backup & Wiederherstellung** sowie über `config.backup` / `config.restore` wählbar.

---

## 🔌 RPC API Methoden & Events

Implementiert im [`AutomationRouter`](../lib/engine/gateway/automation_router.dart):

- **Methoden**: `automations.list`, `automations.get`, `automations.create`, `automations.update`, `automations.toggle`, `automations.delete`, `automations.runNow`, `automations.runs`, `automations.previewSchedule`, `automations.previewRouting`, `automations.generateFromPrompt`.
- **Broadcast-Events**: `automations.changed`, `automations.run_updated`, `agent.session_deleted`.

Alle Parameter und Antwortformate sind in der **[RPC API Referenz](RPC_API_REFERENCE_DE.md)** dokumentiert.
