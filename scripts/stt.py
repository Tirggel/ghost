import sys
import argparse
from faster_whisper import WhisperModel

def main():
    parser = argparse.ArgumentParser(description="Transcribe audio using faster-whisper")
    parser.add_argument("audio_file", help="Path to the audio file to transcribe")
    parser.add_argument("--model", default="base", help="Model size to use (e.g., tiny, base, small, medium, large-v3)")
    parser.add_argument("--device", default="auto", help="Device to use for computation (cpu, cuda, auto)")
    parser.add_argument("--compute_type", default="default", help="Type of quantization to use (default, int8, float16)")
    args = parser.parse_args()

    try:
        model = WhisperModel(args.model, device=args.device, compute_type=args.compute_type)

        segments, info = model.transcribe(args.audio_file, beam_size=5)

        # Print language detected
        print(f"Detected language '{info.language}' with probability {info.language_probability}", file=sys.stderr)

        # Print solely the transcription on stdout
        transcription = " ".join([segment.text for segment in segments])
        print(transcription.strip())

    except Exception as e:
        print(f"Error during transcription: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
