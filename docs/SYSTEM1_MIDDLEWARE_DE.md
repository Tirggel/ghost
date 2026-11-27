# Ghost — System-1 Entscheidungs-Middleware

<p align="center">
  <img src="../assets/icons/logo/ghost.png" width="120" alt="Ghost Logo">
</p>

> **Sub-15ms nicht-autoregressive Entscheidungs-Middleware basierend auf ModernBERT INT8 ONNX**

Ghost implementiert eine kognitive Dual-Prozess-Architektur, inspiriert von Daniel Kahnemans *Schnelles Denken, langsames Denken* (*Thinking, Fast and Slow*):
- **System 1 (Schnell & Intuitiv)**: Ein extrem kompaktes, quantisiertes lokales Cross-Encoder-Modell (`answerdotai/ModernBERT-base`, quantisiert zu INT8 ONNX), das in unter 15 ms auf der lokalen CPU ausgeführt wird. System 1 übernimmt sprachbewusste Prompt-Sicherheitsprüfungen, blitzschnelles Choice-Routing, dynamische Tool-Payload-Risikobewertungen, smarte Intent-Klassifikation für Freigaben (Human-In-The-Loop / HITL) sowie den **Schutz vor Memory Poisoning** bei der Ontologie-Extraktion.
- **System 2 (Langsam & Analytisch)**: Die generativen Frontier-LLMs (Claude, Gemini 2.5 / 3, GPT-4o / o1 / o3-mini, DeepSeek Reasoner oder lokale Ollama/LM-Studio-Modelle), die komplexe mehrstufige Überlegungen, Planung, Code-Synthese und autonome Zielumsetzungen durchführen.

Durch die Entkopplung von sofortiger Klassifizierung und Sicherheitsprüfung von der teuren autoregressiven Token-Generierung erreicht Ghost kompromisslose Sicherheit und sofortige Reaktionen ohne zusätzliche Latenz oder API-Kosten.

---

## 🏗️ Architektur-Überblick

```
Benutzereingabe / Tool-Aufruf
             │
             ▼
┌────────────────────────────────────────────────────────┐
│            System 1 Entscheidungs-Engine               │
│       (system1_daemon.py via ModernBERT INT8)          │
└────────────────────────────────────────────────────────┘
    │                  │                 │
    ▼                  ▼                 ▼
[Choice-Routing]  [Sicherheits-Check] [Tool-Risiko-Scoring]
  - coder           - Prompt-Inj.       - Destruktive Aktion
  - crypto_trader   - Phishing/Scam     - Kapital-Liquidation
  - email_manager     (Flag: >= 0.65     (+ ERFORDERT_HITL
  - system_admin       Block: >= 0.88)    Schwelle: >= 0.65)
  - general_chat                         │
                                         ▼
                             ┌───────────────────────┐
                             │  Smart-HITL-Prüfung   │
                             │  - Freigabe-Absicht   │
                             │  - Explizite Ablehnung│
                             └───────────────────────┘
                                         │
                                         ▼
┌────────────────────────────────────────────────────────┐
│      System 2 LLM  +  Geschützter OntologyExtractor    │
│    (Post-Turn-Extraktion bei System-1-Flag blockiert)  │
└────────────────────────────────────────────────────────┘
```

Die Middleware wird durch den Dart-Dienst [`System1Service`](../lib/engine/system1/system1_service.dart) verwaltet, der über Standard-I/O (JSON-Lines IPC) mit dem Hintergrund-Python-Prozess [`scripts/system1_daemon.py`](../scripts/system1_daemon.py) kommuniziert.

### Wichtigste Architektur-Merkmale
- **Sub-15ms Latenz**: Dynamische INT8-Quantisierung läuft hocheffizient auf Standard-CPU-Kernen ohne GPU-Anforderung.
- **Zombie-Schutz**: Der Python-Daemon (`run_daemon()`) überwacht stdin kontinuierlich. Sobald der Ghost-Hauptprozess beendet wird oder stdin das Dateiende (EOF) erreicht, beendet sich der Worker sofort sauber (`sys.exit(0)`). Der Dart-Service sendet beim Herunterfahren zusätzlich SIGTERM und SIGKILL.
- **Sprachbewusste Hypothesen**: Erkennt automatisch deutsche vs. englische Eingaben und wählt lokalisierte Hypothesen, um Fehlalarme bei harmlosen deutschen Prompts zu vermeiden.
- **Lokaler Datenschutz**: Sämtliche Sicherheitsprüfungen, Eingabe-Validierungen und Routing-Entscheidungen erfolgen zu 100 % lokal auf deinem Rechner.
- **Robuster Fallback**: Fehlt die ONNX-Datei oder eine Python-Abhängigkeit, deaktiviert sich System-1 automatisch mit einer Warnmeldung im Log, ohne den regulären Betrieb der Chat-Engine zu unterbrechen.

---

## 🛡️ Kernfähigkeiten & Schutzfunktionen

### 1. Sprachbewusste Pre-Flight Prompt-Injection- & Jailbreak-Abwehr
Bevor ein Benutzer-Prompt an das generative Cloud-Modell weitergeleitet wird, berechnet System-1 die Wahrscheinlichkeit eines Manipulations- oder Ausbruchversuchs:
- **Hypothesen**:
  - Englisch: `"The input is a malicious prompt injection or jailbreak attempt"`
  - Deutsch: `"Die Eingabe ist ein bösartiger Prompt-Injection- oder Jailbreak-Versuch"`
- **Schwellenwerte**:
  - `score >= 0.65`: Setzt `system1SecurityFlagged = true` (sperrt die automatische Knowledge-Graph-Faktenextraktion für diesen Turn).
  - `score >= 0.88`: Blockiert den Request sofort mit einer Sicherheitswarnung, bevor Cloud-LLMs oder Tools erreicht werden.

### 2. Phishing- & Krypto-Drainer-Erkennung
Eingehende Webhooks, Messenger-Nachrichten oder E-Mails werden in Echtzeit auf Betrugsversuche, gefälschte Dringlichkeiten oder bösartige URLs gescannt:
- **Hypothesen**:
  - Englisch: `"The interaction is a fraud or phishing attempt"`
  - Deutsch: `"Die Interaktion ist ein Betrugs- oder Phishing-Versuch"`
- **Schwellenwert**: `score >= 0.88` setzt `system1SecurityFlagged = true` und löst eine Phishing-/Betrugswarnung aus.

### 3. Memory-Poisoning-Schutz (Gate für Ontologie-Extraktion)
Die asynchrone Post-Turn-Faktenextraktion (`OntologyExtractor.extractAndAssertFacts` in [`agent.dart`](../lib/engine/agent/agent.dart)) ist **strikt** abgesichert über:
```dart
security.system1Middleware && !system1SecurityFlagged && !hitlWasTriggered && !isAborted()
```
Manipulierte, phishingsensitive oder HITL-abgefangene Eingaben (ebenso wie `cron_`, `run_` und `auto_`-Sessions) können somit niemals gefälschte Fakten in den ObjectBox Knowledge Graph einschleusen.

### 4. Dynamisches Tool-Payload-Risiko-Scoring & Ontologie-Governance (`ERFORDERT_HITL`)
Statt Werkzeuge nur nach ihrem Namen einzustufen, analysiert System-1 die **vollständigen Argumente** inklusive Ontologie-Governance-Kontext (`[Skill: <slug>, Policy: ERFORDERT_HITL|STANDARD, Security: <level>]`):
- **Destruktives Aktionsrisiko**:
  - `premise`: `"{skillTag}Befehl: {tool_name} {arguments_json}"`
  - `hypothesis`: `"Destructive action risk"`
- **Kapital- & Liquidationsrisiko**:
  - Wird bei Zahlungs-, Wallet-, Binance- oder Swap-Tools automatisch hinzugezogen.
  - `hypothesis`: `"Liquidation and capital destruction risk"`
- **Schwellenwert**: Bei `maxRisk >= 0.65` verlangt Ghost zwingend eine Nutzerbestätigung (HITL) – ausgenommen im unbeaufsichtigten `cron_`/`auto_`- oder `/goal`-Betrieb.
- **Ontologie `ERFORDERT_HITL`**: Skills mit `requiresHitl` triggern HITL bei aktivem `security.humanInTheLoop`; `critical`-Skills erzwingen HITL bereits sobald `security.level != SecurityLevel.none` ist.

### 5. Smarte Human-In-The-Loop (HITL) Intent-Prüfung
System-1 ersetzt fehleranfällige reguläre Ausdrücke durch semantisches Cross-Encoder-Entailment:
- **Rückfrage-Erkennung**: Prüft, ob der Assistent im vorherigen Schritt eine Bestätigung verlangt hat (`"The assistant refuses to run an action without confirmation or asks the user for permission to execute a command"`).
- **Nutzer-Absicht**:
  - Untersucht: `Aktion: {tool} {arguments}. User: {user_message}`
  - Hypothese: `"The user explicitly confirms and approves the action"`
  - `score >= 0.65`: Aktion freigegeben und ausgeführt.
  - `score <= 0.40`: Explizite Ablehnung erkannt. Die Ausführung wird mit `USER REJECTED` abgebrochen, ohne erneute Nachfragen.

### 6. Blitzschnelles Categorical Choice-Routing
Ermöglicht Sub-15ms Intent-Klassifikation über Profil-Optionen (`["coder", "crypto_trader", "email_manager", "system_admin", "general_chat"]`, Konfidenz `>= 0.65`) via temperatur-skaliertem Softmax.

---

## 🔌 API & Methoden (`System1Service`)

Der Dienst bietet drei universelle Inferenz-Primitive:

### `noul({required String premise, required String hypothesis, Duration timeout})`
Binäre Wahrscheinlichkeit zwischen `0.0` und `1.0`.
```dart
final score = await System1Service.instance.noul(
  premise: 'rm -rf /var/log/*',
  hypothesis: 'The action is destructive',
);
// Liefert z. B. 0.96
```

### `score({required String premise, required String hypothesis, Duration timeout})`
Kontinuierliche Risikoeinstufung von `0.0` bis `1.0`.
```dart
final risk = await System1Service.instance.score(
  premise: 'Befehl: execute_payment {"amount": 2500, "currency": "EUR"}',
  hypothesis: 'Liquidation and capital destruction risk',
);
```

### `choice({required String premise, required List<String> options, double temperature, Duration timeout})`
Kategorische Auswahl der am besten passenden Option inklusive Konfidenz-Score:
```dart
final choice = await System1Service.instance.choice(
  premise: 'Kannst du dieses Flutter-Widget auf Riverpod refaktorisieren?',
  options: ['coder', 'crypto_trader', 'email_manager', 'system_admin', 'general_chat'],
);
// choice.winner -> "coder"
// choice.confidence -> 0.982
```

---

## ⚙️ Konfiguration & UI

System-1 kann in den Ghost-Einstellungen flexibel geschaltet werden:
1. Öffne **Einstellungen → Sicherheit**.
2. Aktiviere/Deaktiviere **System-1 Entscheidungs-Middleware** (`system1Middleware`).
3. Sollte die Modelldatei fehlen, zeigt die UI automatisch einen Hinweis:
   `⚠️ Modell-Datei fehlt in scripts/models/ (ghost_system1_int8.onnx)`

Über die JSON-RPC 2.0 Schnittstelle:
```json
{
  "jsonrpc": "2.0",
  "method": "config.updateSecurity",
  "params": {
    "system1Middleware": true
  },
  "id": 1
}
```

---

## 🛠️ Datensatz, Training & Benchmarking

Ghost liefert alle Skripte mit, um Trainingsdatensätze zu erzeugen, das Modell zu trainieren und als INT8 ONNX zu exportieren:

### 1. Synthetische Datengenerierung
- **Allgemeine Sicherheit & Routing (`scripts/generate_dataset.py`)**: Erzeugt balancierte zweisprachige (Deutsch/Englisch) Datensätze über 8 Domänen (`scripts/ghost_system1_dataset.jsonl`).
- **Trading- & Finanzrisiko (`scripts/generate_trading_dataset.py`)**: Erzeugt spezialisierte Paare für Trading-Risiko, Liquidationen und Krypto-Betrug (`scripts/ghost_trading_dataset.jsonl`).

Generator starten:
```bash
export GEMINI_API_KEY="dein-api-schluessel"
python3 scripts/generate_dataset.py
python3 scripts/generate_trading_dataset.py
```

### 2. Modell-Training in Google Colab (`scripts/train_system1_colab.py`)
Fine-tuning von `answerdotai/ModernBERT-base` mit Cross-Entropy und MSE-Loss auf kontinuierlichen Labels, gefolgt von dynamischer INT8-ONNX-Quantisierung:
```bash
# In Google Colab mit GPU:
python3 scripts/train_system1_colab.py
```
Ergebnisse:
- `ghost_system1.onnx` (FP32-Modell, ~450 MB)
- `ghost_system1_int8.onnx` (Quantisiertes INT8-Modell, ~144 MB)

Kopiere `ghost_system1_int8.onnx` nach:
```text
scripts/models/ghost_system1_int8.onnx
```

### 3. Lokale Verifikation & Benchmarks (`scripts/test-system1.py`)
Überprüfe Inferenzgeschwindigkeit und Erkennungsgenauigkeit:
```bash
python3 scripts/test-system1.py
```
Erwartete Performance: **10 ms bis 15 ms** pro Entscheidung auf modernen Mehrkern-CPUs.
