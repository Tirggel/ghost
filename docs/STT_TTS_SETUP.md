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
- **Default Model**: `de_DE-thorsten-low` (German).
- To change the model, update the settings in the Ghost App under **Settings > Voice**.

---

## 👂 Speech-to-Text (STT)

Ghost uses **Faster-Whisper**, a high-performance implementation of OpenAI's Whisper model.

### How it works:
- Scripts are located in `scripts/stt.py`.
- It transcribes audio files sent via Telegram or recorded in the app.

### Model Sizes:
You can choose different model sizes (tiny, base, small, medium, large-v3) depending on your hardware:
- **Tiny/Base**: Fast, lower accuracy (good for simple commands).
- **Small/Medium**: Balanced performance.
- **Large-v3**: High accuracy, requires more VRAM/RAM.

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
