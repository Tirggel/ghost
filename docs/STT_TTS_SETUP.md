# 🎙️ STT & TTS Setup — Ghost

Ghost supports high-performance, local Speech-to-Text (STT) and Text-to-Speech (TTS) using Python-based engines. This allows for private, offline-capable voice interactions.

---

## ⚙️ Prerequisites

Before you can use voice features, ensure you have the following installed on your host system or accessible within your Docker environment:

### 1. System Dependencies
- **Python 3.10+**
- **FFmpeg**: Required for audio format conversion.
- **Piper TTS**: Required for speech synthesis.

### 2. Python Packages
Install the required libraries using the provided `requirements.txt`:

```bash
pip install -r requirements.txt
```
*Note: This includes `faster-whisper` for STT and `piper-tts` for TTS.*

---

## 🗣️ Text-to-Speech (TTS)

Ghost uses **Piper**, a fast, local neural text-to-speech system.

### How it works:
- Scripts are located in `scripts/tts.py`.
- The engine synthesizes text into a `.wav` file and then converts it to `.ogg` (Opus) using FFmpeg for optimal Telegram compatibility.

### Model Configuration:
Models are stored in `scripts/models/`. If a model is missing, the script will attempt to download it automatically.
- **Default Model**: `de_DE-thorsten-low` (Premium voice for German).
- **Advantage**: Provides a very natural, human-like voice with minimal CPU usage.
- To change the model, update the settings in the Ghost App under **Settings > Voice**.

---

---

## 👂 Speech-to-Text (STT)

Ghost supports two modes for speech recognition: **Gateway-Client-Side** (Python) and **Local App Dictation** (Sherpa-ONNX).

### 1. Gateway STT (Faster-Whisper)
- **Used for**: Transcribing messages sent via Telegram or other messaging channels.
- **Implementation**: Python-based scripts in `scripts/stt.py`.
- **Model Sizes**: You can choose model sizes (tiny, base, small, medium, large-v3) in the Ghost App settings.

### 2. Local App Dictation (Sherpa-ONNX)
- **Used for**: Direct real-time transcription within the Ghost Desktop App (Linux).
- **Implementation**: Built-in [Sherpa-ONNX](https://github.com/k2-fsa/sherpa-onnx) integration.
- **Model**: Uses the high-accuracy **Whisper `base`** model (ONNX format).
- **Setup**: The app will automatically download the necessary model files (~150MB) on the first use.
- **Advantage**: In-app dictation is ready to use instantly, extremely fast, and provides more accurate offline transcription than traditional CPU-based methods.
- **Features**: Optimized for performance and low latency on desktop CPUs.

---

## 🛠️ Troubleshooting

### FFmpeg not found
Ensure `ffmpeg` is in your system `PATH`. You can verify this by running:
```bash
ffmpeg -version
```

### Piper command failure
If the `piper` command is not found, ensure it was installed via pip or is available in your environment. You might need to install it manually from the [Piper GitHub repository](https://github.com/rhasspy/piper).

### Slow transcription
If STT is slow, try using a smaller Whisper model (e.g., `tiny`) or ensure you are utilizing a GPU if available (requires CUDA setup).
