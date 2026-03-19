#!/bin/bash
# run_mac.sh — Ghost Starter für macOS
# Startet das Backend in Docker und die Flutter-App nativ

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"

# Schritt 1: Gateway starten
echo "🐳 Starting Ghost Gateway in Docker..."
docker-compose up -d ghost-daemon

# Schritt 2: Flutter App starten
# Auf macOS heißt die gebaute App "app.app" im dist/-Ordner (gebaut per 'flutter build macos')
if [ -d "$DIST_DIR/app.app" ]; then
    echo "🖥️  Starting Flutter App (macOS bundle)..."
    open "$DIST_DIR/app.app"
else
    echo "ℹ️  No prebuilt macOS app found in ./dist/app.app."
    echo "   Building locally with Flutter (requires Flutter SDK on macOS)..."
    cd "$SCRIPT_DIR/app"
    flutter run -d macos
fi
