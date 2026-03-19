# 🎙️ STT & TTS Setup — Ghost

Ghost unterstützt hochperformante, lokale Spracherkennung (STT) und Sprachsynthese (TTS) mittels Python-basierter Engines. Dies ermöglicht private, offline-fähige Interaktionen per Stimme.

---

## ⚙️ Voraussetzungen

Bevor du Sprachfunktionen nutzen kannst, stelle sicher, dass Folgendes auf deinem Host-System installiert oder in deiner Docker-Umgebung zugänglich ist:

### 1. System-Abhängigkeiten
- **Python 3.10+**
- **FFmpeg**: Erforderlich für die Konvertierung von Audioformaten.
- **Piper TTS**: Erforderlich für die Sprachsynthese.

### 2. Python-Pakete
Installiere die erforderlichen Bibliotheken über die bereitgestellte `requirements.txt`:

```bash
pip install -r requirements.txt
```
*Hinweis: Dies beinhaltet `faster-whisper` für STT und `piper-tts` für TTS.*

---

## 🗣️ Sprachsynthese (TTS)

Ghost nutzt **Piper**, ein schnelles, lokales neuronales Text-to-Speech-System.

### So funktioniert es:
- Skripte befinden sich in `scripts/tts.py`.
- Die Engine synthetisiert Text in eine `.wav`-Datei und konvertiert diese anschließend mit FFmpeg in `.ogg` (Opus) für optimale Telegram-Kompatibilität.

### Modell-Konfiguration:
Modelle werden in `scripts/models/` gespeichert. Falls ein Modell fehlt, versucht das Skript, es automatisch herunterzuladen.
- **Standard-Modell**: `de_DE-thorsten-low` (Deutsch).
- Um das Modell zu ändern, aktualisiere die Einstellungen in der Ghost App unter **Einstellungen > Stimme**.

---

## 👂 Spracherkennung (STT)

Ghost nutzt **Faster-Whisper**, eine hochperformante Implementierung von OpenAIs Whisper-Modell.

### So funktioniert es:
- Skripte befinden sich in `scripts/stt.py`.
- Es transkribiert Audiodateien, die über Telegram gesendet oder in der App aufgenommen wurden.

### Modell-Größen:
Du kannst je nach Hardware verschiedene Modellgrößen wählen (tiny, base, small, medium, large-v3):
- **Tiny/Base**: Schnell, geringere Genauigkeit (gut für einfache Befehle).
- **Small/Medium**: Ausgewogene Leistung.
- **Large-v3**: Höchste Genauigkeit, erfordert mehr VRAM/RAM.

---

## 🛠️ Fehlerbehebung

### FFmpeg nicht gefunden
Stelle sicher, dass `ffmpeg` in deinem System-`PATH` vorhanden ist. Du kannst dies prüfen mit:
```bash
ffmpeg -version
```

### Piper-Befehl fehlgeschlagen
Falls der Befehl `piper` nicht gefunden wird, stelle sicher, dass er über pip installiert wurde oder in deiner Umgebung verfügbar ist. Ggf. musst du ihn manuell aus dem [Piper GitHub Repository](https://github.com/rhasspy/piper) installieren.

### Langsame Transkription
Falls STT zu langsam ist, versuche ein kleineres Whisper-Modell (z. B. `tiny`) oder stelle sicher, dass eine GPU genutzt wird, falls vorhanden (erfordert CUDA-Setup).
