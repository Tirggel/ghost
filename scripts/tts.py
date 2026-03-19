import sys
import argparse
import os
import subprocess

def main():
    parser = argparse.ArgumentParser(description="Synthesize speech using piper-tts")
    parser.add_argument("text", help="Text to synthesize")
    parser.add_argument("output_file", help="Path to save the output audio file (.ogg format)")
    parser.add_argument("--model", default="de_DE-thorsten-low", help="Piper model to use. e.g. en_US-lessac-low")
    args = parser.parse_args()
    
    # Piper models usually have an .onnx and .onnx.json file
    # If the model name is provided, we check if it's a local path or just a name.
    # For simplicity in this wrapper, we assume the user has downloaded the model or we download it if possible.
    
    model_name = args.model
    if not model_name.endswith(".onnx"):
        # We can construct a path. Let's store models in a 'models' directory inside scripts
        script_dir = os.path.dirname(os.path.abspath(__file__))
        models_dir = os.path.join(script_dir, "models")
        os.makedirs(models_dir, exist_ok=True)
        
        model_path = os.path.join(models_dir, f"{model_name}.onnx")
        
        if not os.path.exists(model_path):
            print(f"Downloading piper model {model_name}...", file=sys.stderr)
            dl_cmd = [sys.executable, "-m", "piper.download_voices", model_name, "--download-dir", models_dir]
            dl_process = subprocess.run(dl_cmd, stdout=sys.stderr, stderr=sys.stderr)
            if dl_process.returncode != 0:
                print(f"Error downloading model {model_name}. Please download it manually.", file=sys.stderr)
                sys.exit(dl_process.returncode)
            
        args.model = model_path
            
    # We use subprocess to call the piper cli because it's the most stable way to invoke it
    # `echo "text" | piper --model en_US-lessac-low --output_file output.wav`
    
    try:
        # Assuming piper is installed and in path
        temp_wav = args.output_file + ".wav"
        piper_cmd = ["piper", "--model", args.model, "--output_file", temp_wav]
        
        process = subprocess.Popen(piper_cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        stdout, stderr = process.communicate(input=args.text)
        
        if process.returncode != 0:
            print(f"Piper error: {stderr}", file=sys.stderr)
            sys.exit(process.returncode)
            
        # Convert to proper OGG OPUS for Telegram
        try:
            ffmpeg_cmd = ["ffmpeg", "-y", "-i", temp_wav, "-c:a", "libopus", "-b:a", "32k", args.output_file]
            subprocess.run(ffmpeg_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
            if os.path.exists(temp_wav):
                os.remove(temp_wav)
            print(f"Synthesis complete: {args.output_file}", file=sys.stderr)
        except Exception as fe:
            print(f"Failed to convert using ffmpeg (is ffmpeg installed?): {fe}", file=sys.stderr)
            # Fallback: just move the WAV to the target name if ffmpeg fails
            if os.path.exists(temp_wav):
                os.rename(temp_wav, args.output_file)
            print(f"Synthesis fallback complete (WAV format): {args.output_file}", file=sys.stderr)
        
    except FileNotFoundError:
        print("Error: 'piper' command not found. Please install piper-tts.", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error during synthesis: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
