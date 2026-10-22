import os
import sys
import json
import time
import random
from typing import List, Optional, Literal
from pydantic import BaseModel, Field
from google import genai
from google.genai import types

# ---------------------------------------------------------------------------
# 1. KONFIGURATION & API-KEY
# ---------------------------------------------------------------------------
API_KEY = os.environ.get("GEMINI_API_KEY", "")
if not API_KEY:
    print("ERROR: GEMINI_API_KEY environment variable is not set. Please set it before running this script.")
    sys.exit(1)

client = genai.Client(api_key=API_KEY)
MODEL_NAME = "gemini-3.8-flash"
OUTPUT_FILE = "ghost_trading_dataset.jsonl"

# 50 Runden x 5 Kategorien x 20 Samples = 5.000 Samples
ROUNDS = 50
SAMPLES_PER_REQUEST = 20

# ---------------------------------------------------------------------------
# 2. SCHEMA DEFINITION (PYDANTIC FÜR STRUCTURED OUTPUTS)
# ---------------------------------------------------------------------------
class TradingItem(BaseModel):
    task: Literal["choice", "score", "noul"] = Field(
        ..., description="Klassifikation ('choice'), Regression/Confidence ('score') oder Binär/Hypothese ('noul')"
    )
    premise: str = Field(
        ..., description="Marktanalyse mit Zeitrahmen zu Beginn, z.B. 'BTC/USDT 15m: ...'"
    )
    options: Optional[List[str]] = Field(
        None, description="Mögliche Klassen bei task='choice'"
    )
    hypothesis: Optional[str] = Field(
        None, description="Hypothese für task='score' oder task='noul'"
    )
    label: str | float = Field(
        ..., description="Klassenlabel als String oder Score/Wahrscheinlichkeit als Float"
    )

class TradingBatchResponse(BaseModel):
    samples: List[TradingItem]

# ---------------------------------------------------------------------------
# 3. KATEGORIEN & DYNAMISCHE ASSETS / SZENARIEN
# ---------------------------------------------------------------------------
COIN_POOLS = [
    ["BTC/USDT", "ETH/USDT", "SOL/USDT"],
    ["AVAX/USDT", "LINK/USDT", "NEAR/USDT"],
    ["BNB/USDT", "SUI/USDT", "APT/USDT"],
    ["DOGE/USDT", "PEPE/USDT", "RENDER/USDT"]
]

MARKET_REGIMES = [
    "Macro Bull Market (starker übergeordneter Aufwärtstrend)",
    "Macro Bear Market (starker übergeordneter Abwärtstrend)",
    "High-Volatility / News Event Session (z.B. FOMC / CPI Release)",
    "Low-Volatility Weekend Chop (ausgetrocknetes Volumen)"
]

TRADING_TOPICS = [
    {
        "category": "Bullish Setups & Long Entries (15m, 1h, 4h, 1d)",
        "instructions": """
        Erzeuge klare Kauf- und Reversal-Gelegenheiten:
        - 15m: Flash-Drop / Wick, RSI < 20 (extrem überverkauft), schneller Bounce.
        - 1h: Pullback auf 50 EMA Support im Aufwärtstrend, MACD bullischer Crossover.
        - 4h: Bull-Flag Breakout mit Volumenanstieg, bullische Divergenz am 200 EMA.
        - 1d: Golden Cross (50 Day über 200 Day EMA), Makro-Bodenbildung, Breakout.
        Aufgaben:
        - Für 'choice': label MUSS 'STRONG_BUY' oder 'BUY' sein. options: ["STRONG_BUY", "BUY", "NEUTRAL", "SELL", "STRONG_SELL"].
        - Für 'score': Setup-Qualität (0.70 bis 0.98), hypothesis: 'Trading setup confluence and confidence score'.
        """
    },
    {
        "category": "Bearish Setups & Short / Exit Signals (15m, 1h, 4h, 1d)",
        "instructions": """
        Erzeuge Verkaufssignale und Short-Setups:
        - 15m: Schnelle Überhitzung (RSI > 80), bärische Ablehnung an lokalem Hoch.
        - 1h: Bruch unter den 50 EMA mit fallendem MACD unter die Nulllinie.
        - 4h: Bärische Divergenz an starkem Widerstand, Retest der 200 EMA abgewiesen.
        - 1d: Death Cross (50 Day kreuzt 200 Day EMA nach unten), Trendwende.
        Aufgaben:
        - Für 'choice': label MUSS 'STRONG_SELL' oder 'SELL' sein. options: ["STRONG_BUY", "BUY", "NEUTRAL", "SELL", "STRONG_SELL"].
        - Für 'score': Verlust-/Liquidationsrisiko (0.75 bis 1.0), hypothesis: 'Liquidation and capital destruction risk'.
        """
    },
    {
        "category": "Chop, Sideways & False Breakouts (NEUTRAL auf 15m, 1h, 4h, 1d)",
        "instructions": """
        Erzeuge unklare Seitwärtsphasen, in denen der Bot KEINESFALLS traden darf:
        - 15m / 1h: RSI zwischen 46 und 53, flache EMAs, extrem enge Bollinger Bands.
        - 4h: Unklares Wochenende-Rauschen, Fakeout über Range-High wird sofort abverkauft.
        - 1d: Wochenlange zähe Konsolidierung ohne Volumen vor Makro-Events.
        Aufgaben:
        - Für 'choice': label MUSS zwingend 'NEUTRAL' sein! options: ["STRONG_BUY", "BUY", "NEUTRAL", "SELL", "STRONG_SELL"].
        - Für 'score': Setup-Qualität (0.05 bis 0.30), hypothesis: 'Trading setup confluence and confidence score'.
        """
    },
    {
        "category": "Derivatives, Funding Rates & Liquidation Cascades",
        "instructions": """
        Futures-Markt-Psychologie & Hebel-Liquidationen:
        - 15m / 1h: Long-Liquidations-Kaskade (Short Squeeze Chance bei Funding < -0.03%).
        - 4h / 1d: Stark positive Funding Rate (> +0.06%), überhebelte Longs.
        - Stark steigendes Open Interest (OI) an Widerständen (Bullen-Falle).
        Aufgaben:
        - Für 'noul': hypothesis: 'The market conditions favor an imminent high-volatility liquidation cascade' (label 1.0 oder 0.0).
        - Für 'choice': Passendes Signal aus options zuweisen.
        """
    },
    {
        "category": "Multi-Timeframe Alignment & Confluence",
        "instructions": """
        Kombiniere Zeitebenen im Lagebericht:
        - Trendfolge: 1D bullisch über 200 EMA + 4H Pullback + 15m/1h RSI oversold -> STRONG_BUY.
        - Trendbruch: 1D bärisch unter 200 EMA + 1h überkauft an Widerstand -> STRONG_SELL.
        - Widerspruch: 1D bullisch, aber 4H und 1h bärisch gebrochen -> NEUTRAL.
        Aufgaben:
        - Für 'choice': Zuweisung zum passenden Signal.
        - Für 'score': Confluence-Score 0.10 bis 0.95, hypothesis: 'Multi-timeframe confluence score'.
        """
    }
]

# ---------------------------------------------------------------------------
# 4. BESTEHENDE DATEN LADEN & DEDUPLIZIERUNG
# ---------------------------------------------------------------------------
existing_premises = set()
if os.path.exists(OUTPUT_FILE):
    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                try:
                    entry = json.loads(line)
                    existing_premises.add(entry.get("premise", "").strip())
                except json.JSONDecodeError:
                    continue

print(f"Bestehende Datensätze geladen: {len(existing_premises)}")
total_added = 0

# ---------------------------------------------------------------------------
# 5. GENERIERUNGSSCHLEIFE
# ---------------------------------------------------------------------------
for r in range(ROUNDS):
    print(f"\n=======================================================")
    print(f"RUNDE {r+1} / {ROUNDS} (Aktueller Gesamtbestand: {len(existing_premises)})")
    print(f"=======================================================")

    selected_coins = random.choice(COIN_POOLS)
    current_regime = random.choice(MARKET_REGIMES)

    for topic in TRADING_TOPICS:
        prompt = f"""
Du bist ein quantitativer Krypto-Analyst und erstellst Finetuning-Trainingsdaten für ModernBERT.
Kategorie: {topic['category']}
Aktuelles Marktumfeld dieser Runde: {current_regime}
Fokus-Assets: {', '.join(selected_coins)}

Richtlinien:
{topic['instructions']}

WICHTIGE ANFORDERUNGEN:
1. Erzeuge genau {SAMPLES_PER_REQUEST} Samples.
2. Verteile sie gleichmäßig über die 4 Zeitebenen ('15m', '1h', '4h', '1d').
3. Die Zeitebene MUSS direkt am Anfang der Premise stehen (z. B. 'BTC/USDT 15m: ...').
4. Sprachmix: ca. 50% Deutsch, 50% Englisch.
5. Achte bei 'choice' darauf, dass das 'options'-Array immer genau alle 5 Klassen enthält:
   ["STRONG_BUY", "BUY", "NEUTRAL", "SELL", "STRONG_SELL"].
"""

        for attempt in range(3):
            try:
                response = client.models.generate_content(
                    model=MODEL_NAME,
                    contents=prompt,
                    config=types.GenerateContentConfig(
                        temperature=0.85,
                        response_mime_type="application/json",
                        response_schema=TradingBatchResponse,
                    )
                )

                parsed_data = json.loads(response.text)
                items = parsed_data.get("samples", [])

                new_samples = []
                for item in items:
                    premise_text = item.get("premise", "").strip()
                    if not premise_text or premise_text in existing_premises:
                        continue
                    
                    if item.get("task") in ["noul", "score"]:
                        try:
                            item["label"] = float(item["label"])
                        except (ValueError, TypeError):
                            continue

                    existing_premises.add(premise_text)
                    new_samples.append(item)

                if new_samples:
                    with open(OUTPUT_FILE, "a", encoding="utf-8") as f:
                        for s in new_samples:
                            f.write(json.dumps(s, ensure_ascii=False) + "\n")

                    total_added += len(new_samples)
                    print(f"[{topic['category'][:28]}...] +{len(new_samples)} neue Samples (Gesamt: {len(existing_premises)})")
                    break

            except Exception as e:
                wait_time = 4 * (2 ** attempt)
                print(f"Versuch {attempt+1}/3 fehlgeschlagen ({e}). Warte {wait_time}s...")
                time.sleep(wait_time)

        time.sleep(1.2)

print(f"\nFERTIG! {total_added} neue Datensätze hinzugefügt. Gesamter Datensatz umfasst jetzt {len(existing_premises)} Samples.")
