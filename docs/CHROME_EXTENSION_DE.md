# 👻 Ghost Chrome Extension

Offizielle Google Chrome Erweiterung (Manifest V3) für den persönlichen KI-Assistenten **Ghost**.

Integriert Ghost direkt in deinen Browser — als natives Side Panel (Seitenleiste) für Recherchen, Code-Analysen und Kontextmenü-Aktionen.

---

## 🌟 Hauptfunktionen

- **Chrome Side Panel**: Öffnet sich nativ als Seitenleiste rechts im Browserfenster und bleibt beim Wechsel von Tabs geöffnet.
- **Echtzeit-Token-Streaming**: Antworten werden verzögerungsfrei Token für Token gestreamt (`agent.stream`), inklusive Live-Tool-Aktivitäten (`agent.activity`) und Stop-Funktion (`agent.stop`).
- **Provider- & Modell-Wechsel + API-Key-Verwaltung**: Wähle KI-Provider und Modell direkt im Side Panel (`agent.setSessionModel`) und verwalte API-Keys über die Optionsseite (`options/options.html`).
- **Web-Kontext (Page Q&A)**: Hänge mit einem Klick die URL, den Titel und den Textinhalt des aktiven Tabs an Fragen an.
- **Kontextmenü-Aktionen (Rechtsklick)**:
  - `👻 Ghost: Text / Code erklären`
  - `👻 Ghost: Auswahl zusammenfassen`
  - `👻 Ghost: Als Kanban-Task anlegen (/plan)`
  - `👻 Ghost: Diese Seite analysieren`
- **Sitzungsverwaltung & Löschung**: Wechsel nahtlos zwischen Chat-Sitzungen, starte neue Sessions oder lösche einzelne bzw. alle Sitzungen direkt über den Löschdialog.
- **Auto-Token-Discovery**: Erkennt automatisch das lokale Gateway auf `ws://localhost:3000` und liest den Autorisierungs-Token über `http://localhost:3000/client-token` aus.

---

## 📦 Installation & Setup

1. Stelle sicher, dass die Ghost-Hauptanwendung oder das Gateway läuft:
   ```bash
   flutter run
   ```
2. Öffne in Google Chrome: `chrome://extensions`
3. Aktiviere oben rechts den **Entwicklermodus**.
4. Klicke auf **Entpackte Erweiterung laden** und wähle den Ordner `chrome-extension/` aus dem Ghost-Repository aus.
5. Pinne das Ghost-Icon in der Browser-Symbolleiste an und klicke darauf, um das Side Panel zu öffnen!
