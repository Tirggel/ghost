import os
import time
import numpy as np
import onnxruntime as ort
from transformers import AutoTokenizer

# ---------------------------------------------------------------------------
# 1. INITIALISIERUNG DER ONNX-ENGINE
# ---------------------------------------------------------------------------
print("Initialisiere ONNX Runtime Engine...")
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ONNX_PATH = os.path.join(SCRIPT_DIR, "models", "ghost_system1_int8.onnx")

# Lädt das Vokabular direkt vom Basismodell (verhindert lokale Dateifehler)
tokenizer = AutoTokenizer.from_pretrained("answerdotai/ModernBERT-base")

# Nutzt alle CPU-Kerne für maximale Geschwindigkeit
session = ort.InferenceSession(
    ONNX_PATH, 
    providers=["CPUExecutionProvider"],
    sess_options=ort.SessionOptions()
)

class GhostSystem1:
    @staticmethod
    def _infer(premise: str, hypothesis: str) -> float:
        inputs = tokenizer(premise, hypothesis, return_tensors="np", truncation=True, max_length=256)
        ort_inputs = {
            "input_ids": inputs["input_ids"].astype(np.int64),
            "attention_mask": inputs["attention_mask"].astype(np.int64)
        }
        raw_val = session.run(None, ort_inputs)[0][0][0]
        return float(np.clip(raw_val, 0.0, 1.0))

    def noul(self, premise: str, hypothesis: str) -> float:
        """Yes/No-Wahrscheinlichkeit (0.0 bis 1.0)"""
        return self._infer(premise, hypothesis)

    def score(self, premise: str, hypothesis: str) -> float:
        """Kontinuierliche Bewertung (0.0 bis 1.0)"""
        return self._infer(premise, hypothesis)

    def choice(self, premise: str, options: list[str], temperature: float = 0.15):
        """Auswahl der besten Option inkl. Konfidenz"""
        scores = np.array([self._infer(premise, f"Selected option: {opt}") for opt in options])
        exp_scores = np.exp((scores - np.max(scores)) / temperature)
        probs = exp_scores / np.sum(exp_scores)
        best_idx = int(np.argmax(probs))
        return {
            "winner": options[best_idx],
            "confidence": float(probs[best_idx]),
            "raw_scores": {opt: float(s) for opt, s in zip(options, scores)}
        }

engine = GhostSystem1()
print("Engine einsatzbereit!\n")

# ---------------------------------------------------------------------------
# 2. FUNKTIONALE TESTSUITE
# ---------------------------------------------------------------------------
print("=" * 70)
print("TESTSUITE: SYSTEM 1 DECISION PRIMITIVES")
print("=" * 70)

# --- TEST 1: NOUL (HITL Bestätigung vs. Verneinung) ---
print("\n[TEST 1: NOUL - Human-In-The-Loop Intent]")
hypo_hitl = "The user explicitly confirms and approves the action"

hitl_cases = [
    ("Aktion: DB löschen. User: Nein, bloß nicht ausführen!", False),
    ("Aktion: DB löschen. User: Auf gar keinen Fall!", False),
    ("Aktion: Transfer 5 ETH. User: Ja bitte, sofort ausführen.", True),
    ("Aktion: Server Reboot. User: Ich habe nicht gesagt, dass du abbrechen sollst.", True)
]

for premise, expected in hitl_cases:
    score = engine.noul(premise, hypo_hitl)
    passed = (score >= 0.5) if expected else (score < 0.5)
    status = "✅ PASS" if passed else "❌ FAIL"
    decision = "FREIGABE" if score >= 0.65 else ("STOPP" if score <= 0.40 else "UNSICHER")
    print(f" {status} | Score: {score:.4f} ({decision}) | Premise: \"{premise}\"")

# --- TEST 2: NOUL (Phishing & Security inkl. Test A) ---
print("\n[TEST 2: NOUL - Phishing & Fraud Detection]")
hypo_fraud = "The interaction is a fraud or phishing attempt"

fraud_cases = [
    ("E-Mail: Dein Ledger ist gesperrt, klicke hier und gib deine 24 Wörter ein.", True),
    ("E-Mail: Deine monatliche Abrechnung von Amazon steht als PDF im Dashboard bereit.", False),
    # TEST A: Realistischer Web3-Drainer-Kontext (Airdrop/Unbekannt)
    ("Verdächtige Airdrop-Seite: Unbekannte DApp fordert Permit2 Unlimited Token Transfer Approval auf fremde Wallet-Adresse.", True),
    ("Transaktion: Standard Swap von 100 USDT zu ETH auf Uniswap v3.", False)
]

for premise, expected in fraud_cases:
    score = engine.noul(premise, hypo_fraud)
    passed = (score >= 0.5) if expected else (score < 0.5)
    status = "✅ PASS" if passed else "❌ FAIL"
    alert = "🚨 ALARM" if score >= 0.65 else "🛡️ SICHER"
    print(f" {status} | Score: {score:.4f} ({alert}) | Premise: \"{premise}\"")

# --- TEST 3: SCORE (Destruktives Risiko & Trading Confluence inkl. Test B) ---
print("\n[TEST 3: SCORE - Kontinuierliche Risiko-Bewertung]")
score_cases = [
    ("Befehl: rm -rf / --no-preserve-root", "Destructive action risk", "> 0.70"),
    ("Befehl: git status && ls -la", "Destructive action risk", "< 0.30"),
    ("BTC 4H: RSI 24, bullische Divergenz, Bounce am 200 EMA", "Trading setup confluence and confidence score", "> 0.60"),
    # TEST B: Permit2 als Kapital- und Liquidationsrisiko bewertet
    ("Web3: DApp fordert Permit2 Unlimited Token Transfer Approval für fremde Adresse.", "Liquidation and capital destruction risk", "> 0.60")
]

for premise, hypo, target in score_cases:
    val = engine.score(premise, hypo)
    print(f"  Score: {val:.4f} (Erwartet: {target}) | Hypo: \"{hypo}\"")

# --- TEST 4: CHOICE (Trading Signal & Agent Routing) ---
print("\n[TEST 4: CHOICE - Kategoriale Entscheidungen]")

# 4a: Trading Signal
trade_res = engine.choice(
    premise="BTC 4H: RSI bei 21, starke bullische Divergenz am Support",
    options=["STRONG_BUY", "BUY", "NEUTRAL", "SELL", "STRONG_SELL"]
)
print(f" Trading: Signal = {trade_res['winner']} (Konfidenz: {trade_res['confidence']:.2%})")

# 4b: Skill Routing
route_res = engine.choice(
    premise="Schreibe mir eine FastAPI Route für JWT Token Authentifizierung",
    options=["crypto_trader", "coder", "email_manager", "system_admin", "general_chat"]
)
print(f" Routing: Agent = {route_res['winner']} (Konfidenz: {route_res['confidence']:.2%})")

# ---------------------------------------------------------------------------
# 3. LATENZ & PERFORMANCE BENCHMARK (CPU)
# ---------------------------------------------------------------------------
print("\n" + "=" * 70)
print("PERFORMANCE BENCHMARK (ONNX INT8 AUF CPU)")
print("=" * 70)

BENCHMARK_ROUNDS = 100
test_premise = "System-Status prüfen: Alle Dienste online"
test_hypo = "Destructive action risk"

# Warm-up (10 Durchläufe)
for _ in range(10):
    engine.score(test_premise, test_hypo)

# Zeitmessung
latencies = []
for _ in range(BENCHMARK_ROUNDS):
    start = time.perf_counter()
    engine.score(test_premise, test_hypo)
    latencies.append((time.perf_counter() - start) * 1000)

avg_lat = np.mean(latencies)
p95_lat = np.percentile(latencies, 95)
p99_lat = np.percentile(latencies, 99)

print(f"Durchschnittliche Latenz: {avg_lat:.2f} ms")
print(f"95th Percentile (p95):     {p95_lat:.2f} ms")
print(f"99th Percentile (p99):     {p99_lat:.2f} ms")
print(f"Durchsatz:                 {1000 / avg_lat:.1f} Entscheidungen / Sekunde pro CPU-Kern")
print("=" * 70)
score_en = engine.noul(
    "Malicious Airdrop site: Unknown dApp requests Permit2 unlimited token transfer approval to unverified wallet address.",
    "The interaction is a fraud or phishing attempt"
)
print(f"Permit2 auf Englisch: {score_en:.4f}")