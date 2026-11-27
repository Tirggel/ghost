# 🧠 Ontologie & Knowledge-Graph-Memory — Ghost

Ghost ergänzt das klassische Stichwortgedächtnis (Hive) und die semantische Vektorsuche (ObjectBox RAG) um eine **native ObjectBox-Ontologie & Knowledge-Graph-Memory**. Sie speichert strukturierte Entitäten, typisierte Relationen, Governance-Regeln und Multi-Hop-Fakten lokal mit strenger Sicherheitsabsicherung.

---

## 🏗️ Architektur-Überblick

Der Knowledge Graph basiert auf ObjectBox (`$stateDir/objectbox_ontology` bzw. einem geteilten ObjectBox-`Store`) und trennt sauber zwischen **T-Box** und **A-Box** in [`ontology_models.dart`](../lib/engine/agent/ontology/ontology_models.dart) und [`ontology_store_service.dart`](../lib/engine/agent/ontology/ontology_store_service.dart):

| Ebene | Modellklasse | Aufgabe |
|---|---|---|
| **T-Box (Schema & Regeln)** | `OntologyRelationDef` | Definiert Prädikate (`UPPER_SNAKE_CASE`), erwartete Typen (`domainType`, `rangeType`) sowie Semantik (`isFunctional`, `isTransitive`). |
| **A-Box (Entitäten)** | `OntologyNode` | Kanonische Entitäten mit eindeutigem `canonicalKey` (z. B. `user:primary`, `place:zuerich`), Anzeigename `label`, `entityType` und `metadataJson`. |
| **A-Box (Fakten & Kanten)** | `OntologyEdge` | Gerichtete Tripel `(subjectId) --[predicate]--> (objectId)` mit `confidence` (`0.0–1.0`) und `createdAt`. |

### Semantische Regeln (`isFunctional` & `isTransitive`)
- **Funktionale Prädikate (`isFunctional = true`)**: Maximal ein aktives Objekt pro `(Subject, Prädikat)`. Wird ein neuer Wert gespeichert, ersetzt er automatisch ältere Kanten (z. B. aktualisiert ein Umzug `WOHNT_IN` widerspruchsfrei).
- **Transitive Prädikate (`isTransitive = true`)**: Ermöglichen rekursive Multi-Hop-Traversierung (Tiefe `1–4`) über `queryFactsForEntity` (z. B. `Peter --[WOHNT_IN]--> Zürich` + `Zürich --[LIEGT_IN]--> Schweiz` ergibt automatisch die Länderzuordnung).

---

## 📋 Integrierte T-Box-Prädikate

Beim Start legt Ghost 17 Standard-Relationen an:

### Persönliches & Weltwissen (12 Prädikate)

| Prädikat | Domain → Range | Funktional | Transitive | Bedeutung |
|---|---|---|---|---|
| `WOHNT_IN` | `Person` → `Place` | ✅ | ❌ | Wohnort / Stadt |
| `HEISST` | `Entity` → `Text` | ✅ | ❌ | Kanonischer Name (aktualisiert das Node-Label ohne redundante Self-Edge) |
| `ARBEITET_AN` | `Person` → `Project` | ❌ | ❌ | Aktive Projekte |
| `ARBEITET_BEI` | `Person` → `Organization` | ✅ | ❌ | Arbeitgeber / Organisation |
| `LIEGT_IN` | `Place` → `Place` | ✅ | ✅ | Geografische Hierarchie (Stadt → Land) |
| `TEIL_VON` | `Entity` → `Entity` | ❌ | ✅ | Teil-von-Strukturen |
| `MAG` | `Person` → `Entity` | ❌ | ❌ | Vorlieben / Interessen |
| `MAG_NICHT` | `Person` → `Entity` | ❌ | ❌ | Abneigungen / Ausschlüsse |
| `HAT_BERUF` | `Person` → `Role` | ✅ | ❌ | Beruf / Rolle |
| `BENUTZT` | `Person` → `Technology` | ❌ | ❌ | Werkzeuge, Sprachen, Frameworks |
| `SPRICHT` | `Person` → `Language` | ❌ | ❌ | Gesprochene Sprachen |
| `KENNT` | `Person` → `Person` | ❌ | ❌ | Bekannte Personen / Kontakte |

### Governance, Skills & Multi-Agent-Routing (5 Prädikate)

| Prädikat | Domain → Range | Funktional | Transitive | Bedeutung |
|---|---|---|---|---|
| `DARF_NUTZEN` | `Agent` → `Skill` | ❌ | ❌ | Opt-Out-Skill-Berechtigung aus `disabledSkills` |
| `HAT_KOMPETENZ` | `Agent` → `Domain` | ❌ | ❌ | Abgeleitete Agenten-Kompetenz für `TaskOrchestrator`-Routing |
| `GEHOERT_ZU_DOMAIN` | `Skill` → `Domain` | ✅ | ❌ | Ordnet jede Skill-Kategorie einer kanonischen Routing-Domäne zu |
| `BENOETIGT_SKILL` | `Skill` → `Skill` | ❌ | ✅ | Transitive Skill-Abhängigkeiten für `ghost_load_skill` |
| `ERFORDERT_HITL` | `Skill` → `SecurityPolicy` | ✅ | ❌ | Erzwingt Human-In-The-Loop-Freigaben für High/Critical-Skills |

---

## 🔄 Pre-Turn-Injektion & Post-Turn-Extraktion

Implementiert durch [`OntologyExtractor`](../lib/engine/agent/ontology/ontology_extractor.dart) in der Agent-Schleife ([`agent.dart`](../lib/engine/agent/agent.dart)):

### 1. Pre-Turn-Kontextinjektion
Vor jedem regulären Turn (`rawPromptText.length >= 4`, max. 2 Sekunden Timeout):
- Fragt `user:primary`, den konfigurierten Benutzernamen (`userConfig.name`) sowie bis zu 5 im Prompt erkannte Graph-Entitäten (`findMatchingNodesInText`) ab.
- Traversiert bis zu `maxDepth: 2` (`maxFacts: 15`).
- Filtert interne Governance-Prädikate (`DARF_NUTZEN`, `HAT_KOMPETENZ`, `GEHOERT_ZU_DOMAIN`, `BENOETIGT_SKILL`, `ERFORDERT_HITL`) heraus.
- Injiziert kompakte Tripel unter `[KNOWLEDGE GRAPH (VERIFIED STRUCTURED FACTS)]` in den System-Prompt.

### 2. Asynchrone Post-Turn-Extraktion & Memory-Poisoning-Schutz
Nach der Antwort extrahiert `OntologyExtractor.extractAndAssertFacts` asynchron dauerhafte Fakten (`temperature: 0.0`, Mindestlänge `12` Zeichen, Konfidenz `>= 0.7`).

> [!IMPORTANT]
> **Strenger System-1 Memory-Poisoning-Schutz**: Die automatische Post-Turn-Extraktion ist **strikt** gekoppelt an:
> `security.system1Middleware && !system1SecurityFlagged && !hitlWasTriggered && !isAborted()`
> und wird bei kurzen Begrüßungen sowie in `cron_`, `run_` und `auto_`-Sessions übersprungen. Prompt-Injections oder Phishing-Eingaben können das Langzeitgedächtnis niemals vergiften.

---

## 🛠️ Agenten-Werkzeuge

Agenten können Fakten direkt über zwei native Tools speichern und abfragen ([`ontology.dart`](../lib/engine/tools/ontology.dart)):

- **`ghost_ontology_assert`**: Speichert oder aktualisiert ein Tripel `(subject, predicate, object)` mit optionalem `subject_type`, `object_type` und `confidence`. Referenzen wie `user:primary`, `user`, `ich` oder `me` werden automatisch auf den primären Nutzer gemappt; funktionale Relationen ersetzen ältere Werte.
- **`ghost_ontology_query`**: Fragt direkte und transitive Multi-Hop-Fakten zu einer Entität ab (`max_depth` `1–4`, Standard `2`; `include_incoming`, Standard `true`).

---

## 🖥️ Einstellungen: Monolith Graph-Explorer & Query-Inspector

Unter **Einstellungen → Toolbox → Speicher → Ontologie** steht die komplette grafische Verwaltung zur Verfügung:

1. **Master- & Auto-Extraktions-Schalter**: Aktiviert/deaktiviert die Knowledge-Graph-Injektion (`ontologyEnabled`) und die System-1-geschützte Auto-Extraktion (`ontologyAutoExtract`).
2. **Statistiken & Explorer-Panel**:
   - Filter-Tabs: **Alle**, **Persönlich**, **Governance** und **Regeln** (T-Box-Definitionen).
   - Ansichten: **Fakten** (Tripel mit Konfidenz, Funktional-/Inferenz-Badges und Löschfunktion), **Entitäten** (Knoten mit Kantenanzahl und Kaskadenlöschung) sowie **Regeln** (`isFunctional` / `isTransitive`).
   - **+ Fakt hinzufügen**: Manuelles Erfassen oder Aktualisieren strukturierter Tripel.
3. **Multi-Hop-Query-Inspector**:
   - Beliebige Entität testen (z. B. `Peter`, `user:primary`, `Zürich`) mit wählbarer Tiefe (`1–4` Hops).
   - Zeigt gefundene Root-Knoten, direkte Fakten, transitive/inferierte Pfade (`[via: ...]`) und die exakte **Pre-Turn-System-Prompt-Vorschau**.
4. **Backup, Restore & Zurücksetzen**:
   - Portabler JSON-Export/-Import (`ghost_ontology.json`) mit `canonicalKey`-Neuzuordnung.
   - Automatisch Teil von **Einstellungen → Zurücksetzen → Backup & Wiederherstellung** (`ontology_backup.json` innerhalb von `memory`).
   - Zurücksetzen löscht A-Box-Daten und erhält die Standard-T-Box-Regeln (`config.clearMemory` mit `type: "ontology"`).

---

## 🔌 RPC API Methoden

| Methode | Funktion |
|---|---|
| `memory.ontology.stats` | Liefert Zähler für Relationen, Knoten, Kanten, Skills sowie persönliche und Governance-Fakten |
| `memory.ontology.list` | Listet Fakten, Entitäten und T-Box-Regeln gefiltert nach `category` (`all`, `personal`, `governance`, `rules`) und `query` |
| `memory.ontology.assert` | Speichert oder aktualisiert ein Tripel (sendet Event `ontology.changed`) |
| `memory.ontology.deleteEdge` | Löscht eine einzelne Kante anhand `edgeId` |
| `memory.ontology.deleteNode` | Löscht einen Knoten samt aller verbundenen Kanten anhand `canonicalKey` |
| `memory.ontology.query` | Führt eine 1–4-Hop-Abfrage aus und liefert `result` + `promptPreview` |
| `memory.ontology.backup` / `restore` | Exportiert oder importiert den portablen Knowledge Graph als JSON |

Vollständige Parameter und Payloads finden sich in der **[RPC API Referenz](RPC_API_REFERENCE_DE.md)**.
