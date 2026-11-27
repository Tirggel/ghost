# 🎙️ STT & TTS Setup — Ghost

Ghost supports high-performance, local Speech-to-Text (STT) and Text-to-Speech (TTS) for private, offline-capable voice interactions across both messaging channels and in-app dictation.

---

## ⚙️ Prerequisites

Before using Python-based voice scripts on messaging channels, ensure the following are installed on your host system:

### 1. System Dependencies
- **Python 3.10+**
- **FFmpeg**: Required for `.wav` → `.ogg` (Opus) conversion (`ffmpeg -version`).
- **Piper TTS**: Required for local neural speech synthesis.

### 2. Python Packages
Install the required libraries from `docs/installation/requirements.txt`:

```bash
pip install -r docs/installation/requirements.txt
```
*Includes `faster-whisper` for gateway STT and `piper-tts` for TTS.*

---

## 🗣️ Text-to-Speech (TTS)

Ghost uses **Piper**, a fast, local neural text-to-speech engine invoked via [`scripts/tts.py`](../scripts/tts.py).

### How it works:
- Synthesizes text into a temporary `.wav` file and converts it to `.ogg` (Opus) using FFmpeg for messaging platforms such as Telegram.
- Models are stored in `scripts/models/`. If a requested model is missing, `scripts/tts.py` automatically downloads it via `piper.download_voices`.
- **Default Model**: `de_DE-thorsten-low` (or specify a custom voice via `--model <voice_name_or_onnx_path>`, e.g., `en_US-lessac-low`).

---

## 👂 Speech-to-Text (STT)

Ghost supports two local STT modes: **Gateway/Channel STT** (Python) and **Local App Dictation** (Sherpa-ONNX).

### 1. Gateway STT (`scripts/stt.py` via Faster-Whisper)
- **Used for**: Transcribing incoming voice messages sent via Telegram or other messaging channels.
- **CLI Options**:
  - `--model`: Whisper model size (`tiny`, `base` [default], `small`, `medium`, `large-v3`)
  - `--device`: Computation backend (`auto`, `cpu`, `cuda`)
  - `--compute_type`: Quantization type (`default`, `int8`, `float16`)

### 2. Local App Dictation (Sherpa-ONNX)
- **Used for**: Direct real-time voice dictation inside the Ghost desktop chat input bar (`lib/providers/stt_provider.dart`).
- **Implementation**: Built-in [Sherpa-ONNX](https://github.com/k2-fsa/sherpa-onnx) integration.
- **Model**: Uses the **Whisper `base`** model (`sherpa-onnx-whisper-base`).
- **Automatic Setup**: Click the microphone button in the chat input bar—Ghost automatically downloads and extracts the model (~150 MB) on first use.

---

## 🛠️ Troubleshooting

### FFmpeg not found
Ensure `ffmpeg` is in your system `PATH`:
```bash
ffmpeg -version
```
If `ffmpeg` fails during TTS synthesis, `scripts/tts.py` falls back to saving the `.wav` output file.

### Piper command failure
If `piper` is not found in your `PATH`, install `piper-tts` into the active Python environment or verify the binary from the [Piper GitHub repository](https://github.com/rhasspy/piper).

### Slow transcription
For faster CPU transcription in `scripts/stt.py`, use `--model tiny` or `--compute_type int8`, or `--device cuda` when an NVIDIA GPU is available.
