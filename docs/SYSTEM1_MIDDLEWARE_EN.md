# Ghost — System-1 Decision Middleware

<p align="center">
  <img src="../assets/icons/logo/ghost.png" width="120" alt="Ghost Logo">
</p>

> **Sub-15ms Non-Autoregressive Decision Middleware Powered by ModernBERT INT8 ONNX**

Ghost incorporates a dual-process cognitive architecture inspired by Daniel Kahneman's *Thinking, Fast and Slow*:
- **System 1 (Fast & Intuitive)**: A lightweight, quantized local Cross-Encoder model (`answerdotai/ModernBERT-base` quantized to INT8 ONNX) running on CPU in under 15ms. System 1 handles language-aware pre-flight prompt security checks, rapid categorical choice routing, dynamic tool-payload risk scoring, smart Human-In-The-Loop (HITL) intent classification, and **Ontology Memory-Poisoning Protection**.
- **System 2 (Slow & Deliberative)**: The generative Frontier LLMs (Claude, Gemini 2.5 / 3, GPT-4o / o1 / o3-mini, DeepSeek Reasoner, or local Ollama/LM Studio models) that perform complex multi-turn reasoning, planning, code synthesis, and goal execution.

By decoupling immediate classification and safety gating from heavy autoregressive token generation, Ghost achieves enterprise-grade security and instant response gating without incurring cloud LLM latency or cost.

---

## 🏗️ Architecture Overview

```
User Input / Tool Call
         │
         ▼
┌────────────────────────────────────────────────────────┐
│              System 1 Decision Engine                  │
│       (system1_daemon.py via ModernBERT INT8)          │
└────────────────────────────────────────────────────────┘
    │                  │                 │
    ▼                  ▼                 ▼
[Choice Routing]  [Safety Checks]   [Tool Risk Scoring]
  - coder           - Prompt Inj.     - Destructive Action
  - crypto_trader   - Phishing/Scam   - Capital Liquidation
  - email_manager     (Flag: >= 0.65    (+ ERFORDERT_HITL
  - system_admin       Block: >= 0.88)   Threshold: >= 0.65)
  - general_chat                         │
                                         ▼
                             ┌───────────────────────┐
                             │  Smart HITL Evaluator │
                             │  - Approval Intent    │
                             │  - Explicit Refusal   │
                             └───────────────────────┘
                                         │
                                         ▼
┌────────────────────────────────────────────────────────┐
│       System 2 LLM  +  Gated Ontology Extractor        │
│    (Post-turn extraction blocked if System-1 flagged)  │
└────────────────────────────────────────────────────────┘
```

The middleware is managed by the Dart service [`System1Service`](../lib/engine/system1/system1_service.dart), which communicates with the background Python worker [`scripts/system1_daemon.py`](../scripts/system1_daemon.py) over standard I/O (JSON-Lines IPC).

### Key Architectural Characteristics
- **Sub-15ms Latency**: Native INT8 dynamic quantization runs efficiently on local CPU cores without requiring a dedicated GPU.
- **Zombie-Proof Lifecycle**: The Python daemon continuously monitors standard input (`run_daemon()`). If the parent Ghost process terminates or stdin reaches EOF, the daemon immediately exits cleanly (`sys.exit(0)`). The Dart service also enforces SIGTERM and SIGKILL termination on shutdown.
- **Language-Aware Hypotheses**: Automatically detects German vs. English input patterns and evaluates localized hypotheses for higher cross-encoder precision without false positives on benign German prompts.
- **Zero Cloud Leakage**: All security evaluations, input vetting, and routing determinations occur 100% locally on your machine.
- **Graceful Fallback**: If the ONNX model file or Python dependencies are missing, the system gracefully logs a warning and disables System-1 checks without interrupting the core generative workflow.

---

## 🛡️ Core Capabilities & Interventions

### 1. Language-Aware Pre-Flight Prompt Injection & Jailbreak Defense
Before any user prompt reaches the external generative model, System-1 computes the probability that the input is an adversarial attempt to override instructions:
- **Hypotheses**:
  - English: `"The input is a malicious prompt injection or jailbreak attempt"`
  - German: `"Die Eingabe ist ein bösartiger Prompt-Injection- oder Jailbreak-Versuch"`
- **Thresholds**:
  - `score >= 0.65`: Sets `system1SecurityFlagged = true` (disables automatic Knowledge Graph fact extraction for this turn).
  - `score >= 0.88`: Intercepts and blocks the request immediately with a security alert before reaching cloud providers or tools.

### 2. Financial Phishing & Crypto Drainer Detection
Incoming webhooks, channel messages, or emails are screened for malicious phishing campaigns, fake urgency prompts, or drainer URLs:
- **Hypotheses**:
  - English: `"The interaction is a fraud or phishing attempt"`
  - German: `"Die Interaktion ist ein Betrugs- oder Phishing-Versuch"`
- **Threshold**: `score >= 0.88` sets `system1SecurityFlagged = true` and raises a real-time phishing/fraud alert.

### 3. Memory-Poisoning Protection (Ontology Extraction Gate)
Automatic post-turn fact extraction (`OntologyExtractor.extractAndAssertFacts` in [`agent.dart`](../lib/engine/agent/agent.dart)) is **strictly gated** behind:
```dart
security.system1Middleware && !system1SecurityFlagged && !hitlWasTriggered && !isAborted()
```
Untrusted, injection-flagged, or HITL-interrupted prompts (as well as `cron_`, `run_`, and `auto_` sessions) can never persist forged facts into the ObjectBox Knowledge Graph.

### 4. Dynamic Tool-Payload Risk Scoring & Ontology Governance (`ERFORDERT_HITL`)
Unlike naive permission systems that only look at tool names, System-1 inspects the **entire tool invocation payload** enriched with Ontology skill governance metadata (`[Skill: <slug>, Policy: ERFORDERT_HITL|STANDARD, Security: <level>]`):
- **Destructive Action Risk**:
  - `premise`: `"{skillTag}Befehl: {tool_name} {arguments_json}"`
  - `hypothesis`: `"Destructive action risk"`
- **Capital & Liquidation Risk**:
  - Automatically triggered for payment, Binance, wallet, or crypto swap tools.
  - `hypothesis`: `"Liquidation and capital destruction risk"`
- **Threshold**: If `maxRisk >= 0.65`, the call is escalated to Human-In-The-Loop (HITL) confirmation (unless running inside unattended `cron_`/`auto_` or `/goal` execution).
- **Ontology `ERFORDERT_HITL`**: Skills marked `requiresHitl` trigger HITL whenever `security.humanInTheLoop` is active, and `critical` skills enforce HITL whenever `security.level != SecurityLevel.none`.

### 5. Smart Human-In-The-Loop (HITL) Intent Verification
System-1 replaces fragile regex confirmation matching with cross-encoder semantic entailment:
- **Assistant Confirmation Detection**: Detects if the assistant asked for explicit confirmation in the preceding turn (`"The assistant refuses to run an action without confirmation or asks the user for permission to execute a command"`).
- **User Intent Confirmation**:
  - Evaluates: `Aktion: {tool} {arguments}. User: {user_message}`
  - Hypothesis: `"The user explicitly confirms and approves the action"`
  - `score >= 0.65`: Action confirmed and executed.
  - `score <= 0.40`: Hard rejection detected. The action is cancelled with `USER REJECTED`, preventing repeated nagging.

### 6. Instant Categorical Choice Routing
Enables sub-15ms intent classification across candidate categories (`["coder", "crypto_trader", "email_manager", "system_admin", "general_chat"]`, confidence `>= 0.65`) using temperature-scaled softmax.

---

## 🔌 API & Methods (`System1Service`)

The service provides three core inference primitives:

### `noul({required String premise, required String hypothesis, Duration timeout})`
Binary entailment probability between `0.0` and `1.0`.
```dart
final score = await System1Service.instance.noul(
  premise: 'rm -rf /var/log/*',
  hypothesis: 'The action is destructive',
);
// returns e.g. 0.96
```

### `score({required String premise, required String hypothesis, Duration timeout})`
Continuous risk rating from `0.0` to `1.0`.
```dart
final risk = await System1Service.instance.score(
  premise: 'Befehl: execute_payment {"amount": 2500, "currency": "EUR"}',
  hypothesis: 'Liquidation and capital destruction risk',
);
```

### `choice({required String premise, required List<String> options, double temperature, Duration timeout})`
Categorical classification selecting the winning option with confidence score and raw scores.
```dart
final choice = await System1Service.instance.choice(
  premise: 'Can you refactor this Flutter widget to use Riverpod?',
  options: ['coder', 'crypto_trader', 'email_manager', 'system_admin', 'general_chat'],
);
// choice.winner -> "coder"
// choice.confidence -> 0.982
```

---

## ⚙️ Configuration & UI

System-1 can be enabled or disabled globally in the Ghost settings:
1. Open **Settings → Security**.
2. Toggle **System-1 Decision Middleware** (`system1Middleware`).
3. If the model file is not found, the UI displays a warning:
   `⚠️ Model file missing in scripts/models/ (ghost_system1_int8.onnx)`

Via JSON-RPC 2.0 API:
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

## 🛠️ Dataset, Training & Benchmarking

Ghost includes complete tooling to generate synthetic datasets, fine-tune the cross-encoder, and export the INT8 ONNX model:

### 1. Synthetic Dataset Generation
- **General Security & Routing (`scripts/generate_dataset.py`)**: Generates balanced bilingual (German/English) samples with hard negatives across 8 specialized domains (`scripts/ghost_system1_dataset.jsonl`).
- **Trading & Financial Risk (`scripts/generate_trading_dataset.py`)**: Generates specialized trading risk, liquidation, and crypto-scam pairs (`scripts/ghost_trading_dataset.jsonl`).

Run generator:
```bash
export GEMINI_API_KEY="your-api-key"
python3 scripts/generate_dataset.py
python3 scripts/generate_trading_dataset.py
```

### 2. Model Training in Google Colab (`scripts/train_system1_colab.py`)
Fine-tunes `answerdotai/ModernBERT-base` with MSE loss on soft continuous scores and binary cross-entropy, then exports an optimized dynamic INT8 ONNX model:
```bash
# In Google Colab with GPU:
python3 scripts/train_system1_colab.py
```
Outputs:
- `ghost_system1.onnx` (FP32 model, ~450 MB)
- `ghost_system1_int8.onnx` (Quantized INT8 model, ~144 MB)

Copy `ghost_system1_int8.onnx` to:
```text
scripts/models/ghost_system1_int8.onnx
```

### 3. Local Verification & Benchmarking (`scripts/test-system1.py`)
Test inference speed and accuracy across all test scenarios:
```bash
python3 scripts/test-system1.py
```
Expected performance: **10ms - 15ms** per decision on standard modern multi-core CPUs.
