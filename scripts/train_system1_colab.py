import json
import math
import numpy as np
import torch
import torch.nn as nn
from datasets import Dataset
from transformers import (
    AutoTokenizer,
    AutoModelForSequenceClassification,
    Trainer,
    TrainingArguments,
    DataCollatorWithPadding
)
import onnx
import onnxruntime as ort
from onnxruntime.quantization import quantize_dynamic, QuantType

device = "cuda" if torch.cuda.is_available() else "cpu"
print(f"Verwende Hardware: {device}")

# ---------------------------------------------------------------------------
# 1. DATEN LADEN & UNIFIED CROSS-ENCODER FORMATIERUNG
# ---------------------------------------------------------------------------
print("\nLade Datensatz...")
raw_samples = []
with open("ghost_system1_dataset.jsonl", "r", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if line:
            raw_samples.append(json.loads(line))

print(f"{len(raw_samples)} Roh-Datensätze geladen.")

training_pairs = []
for sample in raw_samples:
    task = sample.get("task")
    premise = sample.get("premise", "")

    if task in ["noul", "score"]:
        training_pairs.append({
            "premise": premise,
            "hypothesis": sample.get("hypothesis", ""),
            "label": float(sample.get("label", 0.0))
        })
    elif task == "choice":
        target_opt = sample.get("label")
        options = sample.get("options", [])
        for opt in options:
            training_pairs.append({
                "premise": premise,
                "hypothesis": f"Selected option: {opt}",
                "label": 1.0 if opt == target_opt else 0.0
            })

print(f"Insgesamt {len(training_pairs)} Trainings-Paare erstellt (inkl. Choice-Expansion).")

# ---------------------------------------------------------------------------
# 2. EFFIZIENTE TOKENISIERUNG (DYNAMIC PADDING)
# ---------------------------------------------------------------------------
MODEL_ID = "answerdotai/ModernBERT-base"
print(f"\nInitialisiere Tokenizer für {MODEL_ID}...")
tokenizer = AutoTokenizer.from_pretrained(MODEL_ID)

raw_dataset = Dataset.from_list(training_pairs)

def preprocess_function(batch):
    # Dynamisches Abschneiden auf max 256 Tokens (deckt 99% aller System-1 Prompts ab)
    return tokenizer(
        batch["premise"],
        batch["hypothesis"],
        truncation=True,
        max_length=256
    )

print("Tokenisiere Datensatz...")
tokenized_dataset = raw_dataset.map(preprocess_function, batched=True, remove_columns=["premise", "hypothesis"])
split_dataset = tokenized_dataset.train_test_split(test_size=0.10, seed=42)

# DataCollator für blitzschnelles dynamisches Padding
data_collator = DataCollatorWithPadding(tokenizer=tokenizer)

# ---------------------------------------------------------------------------
# 3. MODELL INITIALISIEREN & TRAINIEREN (SKALIERTE HYPERPARAMETER)
# ---------------------------------------------------------------------------
print("\nLade Basismodell...")
model = AutoModelForSequenceClassification.from_pretrained(
    MODEL_ID,
    num_labels=1,
    problem_type="regression"
)

BATCH_SIZE = 16    # 16 für optimale GPU-Auslastung
EPOCHS = 4        # 4 Epochen genügen bei >20k Datensätzen perfekt
total_steps = (len(split_dataset["train"]) // BATCH_SIZE) * EPOCHS
calc_warmup_steps = int(total_steps * 0.06)  # 6% Warmup

training_args = TrainingArguments(
    output_dir="./ghost-system1-checkpoints",
    eval_strategy="epoch",
    save_strategy="epoch",
    learning_rate=3e-5,
    warmup_steps=calc_warmup_steps,
    per_device_train_batch_size=BATCH_SIZE,
    per_device_eval_batch_size=BATCH_SIZE,
    num_train_epochs=EPOCHS,
    weight_decay=0.01,
    fp16=torch.cuda.is_available(),
    logging_steps=50,
    save_total_limit=1,
    load_best_model_at_end=True,
    metric_for_best_model="eval_loss",
    report_to="none"
)

trainer = Trainer(
    model=model,
    args=training_args,
    train_dataset=split_dataset["train"],
    eval_dataset=split_dataset["test"],
    tokenizer=tokenizer,
    data_collator=data_collator
)

print(f"\n--- Starte Großskaliertes Feintuning ({total_steps} Schritte) ---")
trainer.train()

OUTPUT_DIR = "./ghost_system1_model"
model.save_pretrained(OUTPUT_DIR)
tokenizer.save_pretrained(OUTPUT_DIR)
print(f"Modell gespeichert in '{OUTPUT_DIR}'")

# ---------------------------------------------------------------------------
# 4. EXPORT NACH ONNX & INT8 QUANTISIERUNG
# ---------------------------------------------------------------------------
print("\nExportiere nach ONNX...")
model.eval()
model_cpu = model.to("cpu")

dummy_inputs = tokenizer(
    "System state", 
    "Hypothesis test", 
    return_tensors="pt", 
    padding="max_length", 
    max_length=128
)

onnx_path = "ghost_system1.onnx"
int8_onnx_path = "ghost_system1_int8.onnx"

torch.onnx.export(
    model_cpu,
    (dummy_inputs["input_ids"], dummy_inputs["attention_mask"]),
    onnx_path,
    input_names=["input_ids", "attention_mask"],
    output_names=["logits"],
    dynamic_axes={
        "input_ids": {0: "batch_size", 1: "sequence_length"},
        "attention_mask": {0: "batch_size", 1: "sequence_length"},
        "logits": {0: "batch_size"}
    },
    opset_version=18,
    dynamo=False,
    do_constant_folding=True
)

print("Quantisiere Modell auf INT8...")
quantize_dynamic(
    model_input=onnx_path,
    model_output=int8_onnx_path,
    weight_type=QuantType.QInt8,
    extra_options={"ShapeInference": False}
)

print(f"ERFOLG! Produktionsreifes INT8-Modell: {int8_onnx_path}")
model.to(device)

# ---------------------------------------------------------------------------
# 5. LIVE-TEST DES FERTIGEN SYSTEMS
# ---------------------------------------------------------------------------
print("\n================ LIVE-TEST MIT PRODUCTION GUARDRAILS ================")

def predict_score(premise, hypothesis):
    inputs = tokenizer(premise, hypothesis, return_tensors="pt", truncation=True, max_length=256).to(device)
    with torch.no_grad():
        out = model(**inputs)
        return float(np.clip(out.logits.squeeze().item(), 0.0, 1.0))

def predict_choice(premise, options, temperature=0.15):
    scores = np.array([predict_score(premise, f"Selected option: {opt}") for opt in options])
    exp_scores = np.exp((scores - np.max(scores)) / temperature)
    probs = exp_scores / np.sum(exp_scores)
    best_idx = int(np.argmax(probs))
    return options[best_idx], probs[best_idx], scores[best_idx]

# 1. HITL Test
hitl_score = predict_score(
    "Aktion: DB löschen. User: Nein, bloß nicht ausführen!", 
    "The user explicitly confirms and approves the action"
)
decision = "BLOCKIERT" if hitl_score <= 0.40 else ("AUSFÜHREN" if hitl_score >= 0.65 else "UNSICHER")
print(f"1. HITL Bestätigung:  Score = {hitl_score:.4f} -> Status: {decision}")

# 2. Trading Signal
signal, conf, raw = predict_choice(
    "BTC 4H: RSI bei 22, bullische Divergenz am 200 EMA Support", 
    ["STRONG_BUY", "BUY", "NEUTRAL", "SELL", "STRONG_SELL"],
    temperature=0.15
)
print(f"2. Trading Signal:    {signal} (Konfidenz: {conf:.2%}, Rohwert: {raw:.4f})")

# 3. Phishing Guardrail
phish_score = predict_score(
    "E-Mail: Dein Binance Account ist gesperrt, klicke hier und gib Seed Phrase ein.", 
    "The interaction is a fraud or phishing attempt"
)
status = "ALARM: PHISHING" if phish_score >= 0.70 else "SICHER"
print(f"3. Fraud/Phishing:    Score = {phish_score:.4f} -> Status: {status}")

# 4. CPU-Inferenz-Check mit ONNX
session = ort.InferenceSession(int8_onnx_path, providers=["CPUExecutionProvider"])
ort_inputs = {
    "input_ids": dummy_inputs["input_ids"].numpy().astype(np.int64),
    "attention_mask": dummy_inputs["attention_mask"].numpy().astype(np.int64)
}
ort_out = session.run(None, ort_inputs)
print(f"\n[ONNX Runtime CPU Check]: Erfolgreich initialisiert (Output Shape: {ort_out[0].shape})")