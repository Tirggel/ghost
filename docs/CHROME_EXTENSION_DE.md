# 👻 Ghost Chrome Extension

Offizielle Google Chrome Erweiterung (Manifest V3) für den persönlichen KI-Assistenten **Ghost**.

Integriert Ghost direkt in deinen Browser — als natives Side Panel (Seitenleiste) für Recherchen, Code-Analysen und Kontextmenü-Aktionen.

---

## 🌟 Hauptfunktionen

- **Chrome Side Panel**: Öffnet sich nativ als Seitenleiste rechts im Browserfenster und bleibt beim Wechsel von Tabs geöffnet.
- **Echtzeit-Token-Streaming**: Antworten werden verzögerungsfrei Token für Token gestreamt (`agent.stream`).
- **Live Tool-Aktivitäten**: Visualisiert in Echtzeit, woran Ghost arbeitet.
- **Web-Kontext (Page Q&A)**: Hänge mit einem Klick die URL, den Titel und den Textinhalt des aktiven Tabs an Fragen an.
- **Kontextmenü-Aktionen (Rechtsklick)**:
  - `👻 Ghost: Text / Code erklären`
  - `👻 Ghost: Auswahl zusammenfassen`
  - `👻 Ghost: Als Kanban-Task anlegen (/plan)`
  - `👻 Ghost: Diese Seite analysieren`
- **Sitzungsverwaltung**: Wechsel nahtlos zwischen Chat-Sitzungen oder starte neue Sessions.
- **Auto-Token-Discovery**: Erkennt automatisch das lokale Gateway auf `ws://localhost:3000` und liest den Autorisierungs-Token über den lokalen Endpunkt aus.

---

## 📦 Installation & Setup

1. Stelle sicher, dass die Ghost-Hauptanwendung oder das Gateway läuft:
   ```bash
   flutter run
   ```
2. Öffne in Google Chrome: `chrome://extensions`
3. Aktiviere oben rechts den **Entwicklermodus**.
4. Klicke auf **Entpackte Erweiterung laden** und wähle den Ordner `chrome-extension` aus:
   ```
   /home/peter/Developer/flutter-dev/ghost/chrome-extension
   ```
5. Pinne das Ghost-Icon in der Browser-Symbolleiste an und klicke darauf, um das Side Panel zu öffnen!
