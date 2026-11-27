# 🎙️ STT & TTS Setup — Ghost

Ghost unterstützt hochperformante, lokale Spracherkennung (STT) und Sprachsynthese (TTS) für private, offline-fähige Sprachinteraktionen in Messenger-Kanälen sowie direkt in der App.

---

## ⚙️ Voraussetzungen

Für die Python-basierten Sprachskripte im Kanal-Gateway müssen folgende Komponenten auf dem Host-System installiert sein:

### 1. System-Abhängigkeiten
- **Python 3.10+**
- **FFmpeg**: Erforderlich für die Konvertierung von `.wav` nach `.ogg` (Opus) (`ffmpeg -version`).
- **Piper TTS**: Erforderlich für die lokale neuronale Sprachsynthese.

### 2. Python-Pakete
Installiere die Abhängigkeiten aus `docs/installation/requirements.txt`:

```bash
pip install -r docs/installation/requirements.txt
```
*Beinhaltet `faster-whisper` für Gateway-STT und `piper-tts` für TTS.*

---

## 🗣️ Sprachsynthese (TTS)

Ghost nutzt **Piper**, ein schnelles, lokales neuronales Text-to-Speech-System über [`scripts/tts.py`](../scripts/tts.py).

### Funktionsweise:
- Synthetisiert Text zunächst in eine `.wav`-Datei und konvertiert diese via FFmpeg in `.ogg` (Opus) für Messenger wie Telegram.
- Modelle werden unter `scripts/models/` abgelegt. Fehlt ein Modell, lädt `scripts/tts.py` es automatisch über `piper.download_voices` herunter.
- **Standard-Modell**: `de_DE-thorsten-low` (weitere Stimmen per `--model <stimme_oder_onnx_pfad>`, z. B. `en_US-lessac-low`).

---

## 👂 Spracherkennung (STT)

Ghost unterstützt zwei lokale Modi: **Gateway-/Kanal-STT** (Python) und **Lokale App-Diktierfunktion** (Sherpa-ONNX).

### 1. Gateway STT (`scripts/stt.py` via Faster-Whisper)
- **Verwendet für**: Transkription eingehender Sprachnachrichten über Telegram und weitere Kanäle.
- **CLI-Optionen**:
  - `--model`: Whisper-Modellgröße (`tiny`, `base` [Standard], `small`, `medium`, `large-v3`)
  - `--device`: Rechengerät (`auto`, `cpu`, `cuda`)
  - `--compute_type`: Quantisierung (`default`, `int8`, `float16`)

### 2. Lokale App-Diktierfunktion (Sherpa-ONNX)
- **Verwendet für**: Direkte Echtzeit-Spracheingabe über das Mikrofon-Symbol in der Chat-Eingabeleiste (`lib/providers/stt_provider.dart`).
- **Implementierung**: Integrierte [Sherpa-ONNX](https://github.com/k2-fsa/sherpa-onnx)-Unterstützung.
- **Modell**: Nutzt das **Whisper `base`**-Modell (`sherpa-onnx-whisper-base`).
- **Automatische Einrichtung**: Beim ersten Klick auf das Mikrofon lädt und entpackt die App das Modell (~150 MB) automatisch.

---

## 🛠️ Fehlerbehebung

### FFmpeg nicht gefunden
Prüfe, ob `ffmpeg` im System-`PATH` verfügbar ist:
```bash
ffmpeg -version
```
Schlägt `ffmpeg` fehl, nutzt `scripts/tts.py` automatisch die erzeugte `.wav`-Datei als Fallback.

### Piper-Befehl fehlgeschlagen
Falls `piper` im `PATH` fehlt, installiere `piper-tts` in der aktiven Python-Umgebung oder lade das Binary aus dem [Piper GitHub Repository](https://github.com/rhasspy/piper).

### Langsame Transkription
Für schnellere CPU-Transkription in `scripts/stt.py` kannst du `--model tiny` oder `--compute_type int8` bzw. `--device cuda` bei vorhandener GPU nutzen.
