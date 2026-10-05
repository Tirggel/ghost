#!/usr/bin/env python3
"""
Ghost — System-1 Decision Engine Daemon
High-performance, non-autoregressive decision worker using ModernBERT INT8 ONNX.
Listens on stdin for JSON-Lines requests and responds on stdout.
Automatically exits when stdin is closed (EOF) to prevent zombie processes.
"""

import os
import sys
import json
import time
import signal
import numpy as np

def handle_sigterm(signum, frame):
    sys.exit(0)

signal.signal(signal.SIGTERM, handle_sigterm)
signal.signal(signal.SIGINT, handle_sigterm)

# ---------------------------------------------------------------------------
# 1. PFADAUFLÖSUNG & MODELL-LADEN
# ---------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ONNX_PATH = os.path.join(SCRIPT_DIR, "models", "ghost_system1_int8.onnx")

if not os.path.exists(ONNX_PATH):
    # Fallback to local relative path if needed
    alt_path = os.path.join(os.getcwd(), "scripts", "models", "ghost_system1_int8.onnx")
    if os.path.exists(alt_path):
        ONNX_PATH = alt_path
    else:
        sys.stderr.write(f"ERROR: Model file not found at {ONNX_PATH}\n")
        sys.stderr.flush()
        sys.exit(2)

try:
    import onnxruntime as ort
    from transformers import AutoTokenizer
except ImportError as e:
    sys.stderr.write(f"ERROR: Missing Python dependencies: {e}\n")
    sys.stderr.flush()
    sys.exit(3)

# Initialisiere Tokenizer und ONNX Runtime Session
try:
    tokenizer = AutoTokenizer.from_pretrained("answerdotai/ModernBERT-base")
    sess_opts = ort.SessionOptions()
    sess_opts.inter_op_num_threads = 2
    sess_opts.intra_op_num_threads = 2
    session = ort.InferenceSession(
        ONNX_PATH,
        providers=["CPUExecutionProvider"],
        sess_options=sess_opts
    )
except Exception as e:
    sys.stderr.write(f"ERROR: Failed to initialize ModernBERT ONNX engine: {e}\n")
    sys.stderr.flush()
    sys.exit(4)

def infer_score(premise: str, hypothesis: str) -> float:
    inputs = tokenizer(premise, hypothesis, return_tensors="np", truncation=True, max_length=256)
    ort_inputs = {
        "input_ids": inputs["input_ids"].astype(np.int64),
        "attention_mask": inputs["attention_mask"].astype(np.int64)
    }
    raw_val = session.run(None, ort_inputs)[0][0][0]
    return float(np.clip(raw_val, 0.0, 1.0))

def infer_choice(premise: str, options: list, temperature: float = 0.15) -> dict:
    if not options:
        return {"winner": "", "confidence": 0.0, "raw_scores": {}}
    scores = np.array([infer_score(premise, f"Selected option: {opt}") for opt in options])
    exp_scores = np.exp((scores - np.max(scores)) / max(temperature, 0.01))
    probs = exp_scores / np.sum(exp_scores)
    best_idx = int(np.argmax(probs))
    return {
        "winner": options[best_idx],
        "confidence": float(probs[best_idx]),
        "raw_scores": {opt: float(s) for opt, s in zip(options, scores)}
    }

# Signal readiness to parent process
def run_daemon():
    sys.stderr.write("SYSTEM1_READY\n")
    sys.stderr.flush()

    # ---------------------------------------------------------------------------
    # 2. STDIO JSON-LINES EVENT LOOP (MIT ZOMBIE-SCHUTZ)
    # ---------------------------------------------------------------------------
    while True:
        try:
            line = sys.stdin.readline()
            # Zombie-Schutz: Wenn stdin geschlossen wird (EOF), sofort sauber beenden!
            if not line:
                break
            
            line = line.strip()
            if not line:
                continue
            
            req = json.loads(line)
            req_id = req.get("id")
            method = req.get("method")
            start_time = time.perf_counter()

            if method == "ping":
                resp = {"id": req_id, "status": "pong"}
            elif method in ("noul", "score"):
                premise = req.get("premise", "")
                hypothesis = req.get("hypothesis", "")
                score_val = infer_score(premise, hypothesis)
                resp = {
                    "id": req_id,
                    "status": "ok",
                    "score": score_val,
                    "elapsed_ms": (time.perf_counter() - start_time) * 1000
                }
            elif method == "choice":
                premise = req.get("premise", "")
                options = req.get("options", [])
                temp = float(req.get("temperature", 0.15))
                choice_data = infer_choice(premise, options, temperature=temp)
                resp = {
                    "id": req_id,
                    "status": "ok",
                    "winner": choice_data["winner"],
                    "confidence": choice_data["confidence"],
                    "raw_scores": choice_data["raw_scores"],
                    "elapsed_ms": (time.perf_counter() - start_time) * 1000
                }
            else:
                resp = {"id": req_id, "status": "error", "error": f"Unknown method: {method}"}

            sys.stdout.write(json.dumps(resp, ensure_ascii=False) + "\n")
            sys.stdout.flush()

        except json.JSONDecodeError as je:
            sys.stdout.write(json.dumps({"id": None, "status": "error", "error": f"Invalid JSON: {je}"}) + "\n")
            sys.stdout.flush()
        except Exception as e:
            sys.stdout.write(json.dumps({"id": None, "status": "error", "error": str(e)}) + "\n")
            sys.stdout.flush()

    # Sauberes Beenden bei EOF
    sys.exit(0)

if __name__ == "__main__":
    run_daemon()
