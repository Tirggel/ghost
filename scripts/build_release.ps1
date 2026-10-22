# Lokales Build-Skript für Ghost unter Windows (PowerShell)
# Kompiliert die Flutter-Windows-App sowie ghost_acp.exe
# und legt das fertige Paket in .\ghost-releases\windows\ ab.

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

Write-Host "🚀 Starte Ghost Release-Build für Windows..."
flutter pub get

Write-Host "📦 Kompiliere Windows Release (flutter build windows --release)..."
flutter build windows --release

New-Item -ItemType Directory -Force -Path "ghost-releases/windows/scripts" | Out-Null
Copy-Item -Path "build/windows/x64/runner/Release/*" -Destination "ghost-releases/windows/" -Recurse -Force
Copy-Item -Path "scripts/stt.py", "scripts/tts.py", "scripts/system1_daemon.py" -Destination "ghost-releases/windows/scripts/" -Force

if (Test-Path "scripts/models") {
    New-Item -ItemType Directory -Force -Path "ghost-releases/windows/scripts/models" | Out-Null
    Copy-Item -Path "scripts/models/*" -Destination "ghost-releases/windows/scripts/models/" -Recurse -Force
}

Write-Host "✅ Windows Release fertiggestellt unter: ghost-releases\windows\"
