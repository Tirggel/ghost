import importlib.util

def check_faster_whisper():
    package_name = "faster_whisper"
    # Sucht nach der Spezifikation des Moduls
    spec = importlib.util.find_spec(package_name)

    if spec is not None:
        print(f"✅ '{package_name}' ist installiert!")
        # Optional: Version anzeigen
        try:
            import faster_whisper
            print(f"   Version: {faster_whisper.__version__}")
        except AttributeError:
            pass
    else:
        print(f"❌ '{package_name}' ist NICHT installiert.")
        print("   Nutze 'pip install faster-whisper' zum Installieren.")

if __name__ == "__main__":
    check_faster_whisper()
