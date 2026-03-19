@echo off
:: run.bat — Ghost Starter für Windows
:: Startet das Backend in Docker und die Flutter-App nativ

setlocal

set SCRIPT_DIR=%~dp0
set DIST_DIR=%SCRIPT_DIR%dist

:: Schritt 1: Gateway starten
echo 🐳 Starting Ghost Gateway in Docker...
docker-compose up -d ghost-daemon
if %ERRORLEVEL% neq 0 (
    echo ❌ Failed to start Docker container. Is Docker Desktop running?
    pause
    exit /b 1
)

:: Schritt 2: Flutter App starten
:: Auf Windows heißt die exe "app.exe" im dist/-Ordner (gebaut per 'flutter build windows')
if exist "%DIST_DIR%\app.exe" (
    echo 🖥️ Starting Flutter App from dist\app.exe ...
    start "" "%DIST_DIR%\app.exe"
) else (
    echo ℹ️ No prebuilt app found in .\dist\app.exe
    echo    Building locally with Flutter (requires Flutter SDK on Windows)...
    cd /d "%SCRIPT_DIR%app"
    flutter run -d windows
)

endlocal
