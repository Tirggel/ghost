#!/usr/bin/env bash
# Lokales Build-Skript für Ghost (Linux & macOS)
# Kompiliert die Flutter-Desktop-App sowie das ghost_acp CLI-Binary
# und legt das fertige Paket in ./ghost-releases/<platform>/ ab.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OS_NAME="$(uname -s)"

echo "🚀 Starte Ghost Release-Build auf $OS_NAME..."
flutter pub get

if [[ "$OS_NAME" == "Linux" ]]; then
  echo "📦 Kompiliere Linux Release (flutter build linux --release)..."
  flutter build linux --release

  mkdir -p ghost-releases/linux/scripts
  cp -r build/linux/x64/release/bundle/* ghost-releases/linux/
  cp scripts/stt.py scripts/tts.py scripts/system1_daemon.py ghost-releases/linux/scripts/
  if [ -d scripts/models ]; then
    mkdir -p ghost-releases/linux/scripts/models
    cp -r scripts/models/* ghost-releases/linux/scripts/models/ 2>/dev/null || true
  fi
  echo "✅ Linux Release fertiggestellt unter: ghost-releases/linux/"

elif [[ "$OS_NAME" == "Darwin" ]]; then
  echo "📦 Kompiliere macOS Release (flutter build macos --release)..."
  flutter build macos --release

  mkdir -p ghost-releases/mac/scripts
  cp -R build/macos/Build/Products/Release/Ghost.app ghost-releases/mac/
  cp scripts/stt.py scripts/tts.py scripts/system1_daemon.py ghost-releases/mac/scripts/
  mkdir -p ghost-releases/mac/Ghost.app/Contents/Resources/scripts
  cp scripts/stt.py scripts/tts.py scripts/system1_daemon.py ghost-releases/mac/Ghost.app/Contents/Resources/scripts/
  if [ -d scripts/models ]; then
    mkdir -p ghost-releases/mac/scripts/models
    cp -r scripts/models/* ghost-releases/mac/scripts/models/ 2>/dev/null || true
  fi
  echo "✅ macOS Release fertiggestellt unter: ghost-releases/mac/"
else
  echo "❌ Unbekanntes Betriebssystem: $OS_NAME (für Windows bitte scripts/build_release.ps1 nutzen)"
  exit 1
fi
