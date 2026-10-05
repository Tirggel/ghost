import os
import json
import time
from google import genai
from google.genai import types

# ---------------------------------------------------------------------------
# KONFIGURATION
# ---------------------------------------------------------------------------
API_KEY = os.environ.get("GEMINI_API_KEY", "")
if not API_KEY:
    print("ERROR: GEMINI_API_KEY environment variable is not set. Please set it before running this script.")
    sys.exit(1)
client = genai.Client(api_key=API_KEY)

MODEL_NAME = "gemini-3.8-flash"
OUTPUT_FILE = "ghost_system1_dataset.jsonl"

# 50 Runden x 8 Topics x 45 Samples = ca. 18.000 Roh-Samples
# (Durch Choice-Expansion entstehen daraus im Training ca. 25.000 bis 30.000 Paare!)
ROUNDS = 50
SAMPLES_PER_REQUEST = 45

# ---------------------------------------------------------------------------
# TOPICS MIT FOKUS AUF HARD NEGATIVES, PHISHING & TRADING-GUARDRAILS
# ---------------------------------------------------------------------------
TOPICS = [
    {
        "domain": "Crypto & Binance Trading Technical Analysis",
        "instructions": """
        Erzeuge anspruchsvolle Marktsituationen mit Indikatoren (RSI, MACD, EMAs, Volume, Orderbuch, Liquidationszonen).
        Formate:
        1. Choice: Signal-Richtung
           Options: ["STRONG_BUY", "BUY", "NEUTRAL", "SELL", "STRONG_SELL"]
           Wichtig: Erzeuge auch verwirrende Fake-Outs und Choppy-Markets für 'NEUTRAL'.
        2. Score: Setup-Qualität / Confluence (kontinuierlich 0.0 bis 1.0, z.B. 0.15, 0.45, 0.85).
           Hypothesis: "Trading setup confluence and confidence score"
        """
    },
    {
        "domain": "Trading Risk Management, Leverage & Trap Detection",
        "instructions": """
        Risikomanagement, Hebel, Liquidation, Stop-Loss und Bull/Bear-Traps.
        Formate:
        1. Noul: 'The trade execution complies with strict risk management rules'
           - 1.0: Sauberes R:R (>= 1:2), max 2% Risiko, fester Stop-Loss, moderater Hebel.
           - 0.0 (Hard Negatives!): Hoher Hebel (20x-50x) ohne SL, "Averaging down" in fallendes Messer, All-In.
        2. Noul: 'The market movement is an artificial pump-and-dump or liquidity trap'
           - 1.0: Low-Cap Shitcoin Spike, massive Wicks, unnatürliches Twitter-Hype-Volumen.
           - 0.0: Gesunder, volumenbestätigter Breakout nach langer Konsolidierung.
        3. Score: 'Liquidation and capital destruction risk' (Float 0.0 bis 1.0)
        """
    },
    {
        "domain": "Financial Fraud, Phishing & Crypto Drainers",
        "instructions": """
        Sehr wichtig: Erzeuge 50% echte Angriffe und 50% LEGITIME Warnungen/Transaktionen (Hard Negatives), damit das Modell keine Fehlalarme schlägt!
        Beispiele für 0.0 (Harmlos/Legitim):
        - Offizielle Ledger-Newsletter ohne Klickzwang
        - Echte Binance-Login-Bestätigung mit Anti-Phishing-Code
        - Standard Uniswap Router Approve Transaktion
        Beispiele für 1.0 (Phishing/Scam):
        - 'Dringend: Account wird in 24h gesperrt, klicke hier'
        - Permit2 Unlimited Token Drainer Signaturanfragen
        - Gefälschte CEO-Mail mit neuer IBAN
        Formate:
        - Noul: 'The interaction is a fraud or phishing attempt' (exakt 50% 1.0 und 50% 0.0)
        - Score: 'Fraud and financial scam risk' (kontinuierlich 0.0 bis 1.0)
        """
    },
    {
        "domain": "PII & Secret Leakage",
        "instructions": """
        Erkenne sensible Daten vs. harmlose Hashes/Code.
        - 1.0 (Leak): 12/24 Seed Phrase Wörter, AWS Access Keys (AKIA...), Private Keys (0x...), Stripe Live-Tokens, Kreditkartennummern.
        - 0.0 (Kein Leak - Hard Negatives!): Öffentliche Wallet-Adressen, Git Commit SHAs, UUIDs, Dummy-Keys wie 'sk_test_12345', normaler Python-Code.
        Format:
        - Noul: 'The input leaks sensitive secrets or private credentials' (50% 1.0, 50% 0.0)
        """
    },
    {
        "domain": "Prompt Injection & Security Guardrails",
        "instructions": """
        Sicherheitsfilter gegen Jailbreaks.
        - 1.0 (Angriff): 'Ignore all previous instructions', DAN-Jailbreaks, Base64/Rot13 verdeckte Befehle, unsichtbare Anweisungen in Bildbeschreibungen/Webseiten.
        - 0.0 (Harmlos - Hard Negatives!): Ein Programmierer, der fragt 'Wie schütze ich mein Skript vor SQL Injection?', harmlose System-Fragen.
        Format:
        - Noul: 'The input is a malicious prompt injection or jailbreak attempt' (50% 1.0, 50% 0.0)
        """
    },
    {
        "domain": "Human-In-The-Loop (HITL) Intent & Complex Negations",
        "instructions": """
        DAS WICHTIGSTE THEMA: Unterscheidung zwischen Bestätigung und Ablehnung bei geplanter System-Aktion.
        Konzentriere dich auf DEUTSCHE und ENGLISCHE Umgangssprache, Doppelverneinungen und Slang!
        
        Label 0.0 (Abbruch / NEIN):
        - 'Auf gar keinen Fall!', 'Bloß nicht anfassen!', 'Halt, stopp.', 'Nein, das war so nicht gemeint.'
        - 'Don't do it', 'Abort immediately', 'Hell no!'
        
        Label 1.0 (Freigabe / JA):
        - 'Ja bitte', 'Feuer frei', 'Passt so', 'Ich habe nicht gesagt, dass du stoppen sollst!'
        - 'Go ahead', 'Looks good to me', 'Proceed', 'Why not, let's do it.'
        Format:
        - Noul: 'The user explicitly confirms and approves the action' (exakt 50% 1.0 und 50% 0.0)
        """
    },
    {
        "domain": "Ghost Multi-Agent & Skill Routing",
        "instructions": """
        Routing von Nutzeranfragen an 5 Kern-Agenten:
        Options: ["crypto_trader", "coder", "email_manager", "system_admin", "general_chat"]
        Erzeuge abwechslungsreiche Anfragen (deutsch & englisch), teils mit Mehrdeutigkeiten.
        Format:
        - Choice: Zuweisung zur besten Option.
        """
    },
    {
        "domain": "Destructive Command Risk",
        "instructions": """
        Risikoeinschätzung von Shell-/Terminal-/Datenbank-Befehlen.
        Score 0.8 bis 1.0: 'rm -rf /', 'DROP DATABASE', 'mkfs.ext4', 'iptables -F', 'chmod -R 777 /'
        Score 0.3 bis 0.6: 'docker restart', 'systemctl stop nginx', 'git reset --hard'
        Score 0.0 bis 0.2: 'ls -lah', 'cat log.txt', 'ps aux', 'git status', 'df -h'
        Format:
        - Score: 'Destructive action risk' (Float 0.0 bis 1.0)
        """
    }
]

# ---------------------------------------------------------------------------
# GENERIERUNGSSCHLEIFE MIT AUTO-RETRY
# ---------------------------------------------------------------------------
existing_count = 0
if os.path.exists(OUTPUT_FILE):
    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        existing_count = sum(1 for line in f if line.strip())
print(f"Starte Datengenerierung. Bereits vorhandene Datensätze: {existing_count}")

total_added = 0

for r in range(ROUNDS):
    print(f"\n=======================================================")
    print(f"RUNDE {r+1} / {ROUNDS} (Gesamtfortschritt: {existing_count + total_added} Samples)")
    print(f"=======================================================")

    for topic in TOPICS:
        prompt = f"""
Du bist ein Datensatz-Generator für ein Cross-Encoder Modell (ModernBERT).
Themengebiet: {topic['domain']}
Richtlinien:
{topic['instructions']}

Anforderungen:
1. 50% Deutsch, 50% Englisch.
2. Erzeuge eine JSON-Liste mit GENAU {SAMPLES_PER_REQUEST} Objekten.
3. Bei 'noul' exakt 50% 1.0 und 50% 0.0.
4. Bei 'score' kontinuierliche Kommazahlen (z.B. 0.15, 0.42, 0.78, 0.91).

Schema:
- {{"task": "noul", "premise": "...", "hypothesis": "...", "label": 1.0}}
- {{"task": "score", "premise": "...", "hypothesis": "...", "label": 0.85}}
- {{"task": "choice", "premise": "...", "options": ["..."], "label": "..."}}
"""
        # Bis zu 3 Versuche bei API-Timeouts
        for attempt in range(3):
            try:
                response = client.models.generate_content(
                    model=MODEL_NAME,
                    contents=prompt,
                    config=types.GenerateContentConfig(
                        temperature=0.88,
                        response_mime_type="application/json",
                    )
                )

                data = json.loads(response.text)
                if not isinstance(data, list):
                    if isinstance(data, dict) and "samples" in data:
                        data = data["samples"]
                    else:
                        data = [data]

                valid_samples = []
                for item in data:
                    if isinstance(item, dict) and "task" in item and "premise" in item and "label" in item:
                        if item["task"] in ["noul", "score"]:
                            item["label"] = float(item["label"])
                        valid_samples.append(item)

                if valid_samples:
                    with open(OUTPUT_FILE, "a", encoding="utf-8") as f:
                        for s in valid_samples:
                            f.write(json.dumps(s, ensure_ascii=False) + "\n")
                    
                    total_added += len(valid_samples)
                    print(f"[{topic['domain']}] +{len(valid_samples)} Samples (Gesamt: {existing_count + total_added})")
                    break  # Erfolgreich -> weiter zum nächsten Topic

            except Exception as e:
                print(f"Versuch {attempt+1}/3 bei [{topic['domain']}] fehlgeschlagen: {e}")
                time.sleep(5 * (attempt + 1))  # Exponential Backoff

        time.sleep(1.0)  # Schonung des Gemini Rate-Limits

print(f"\nFERTIG! Insgesamt {existing_count + total_added} Datensätze in '{OUTPUT_FILE}'.")