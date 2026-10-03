# Ghost AI Assistant — Chrome Extension 👻

Offizielle Google Chrome Erweiterung (Manifest V3) für den persönlichen KI-Assistenten **Ghost**.

Die Erweiterung bringt Ghost direkt in deinen Browser und verbindet sich über das modulare **WebSocket JSON-RPC 2.0 Gateway** (`GatewayServer`) mit deiner lokalen Ghost-Instanz auf Port 3000.

---

## 🚀 Features

### 1. 💬 Interaktives Side Panel (Seitenleiste)
- **Native Chrome Side Panel API**: Bleibt beim Tab-Wechsel rechts geöffnet — genau wie in VS Code!
- **Echtzeit-Streaming**: Antworten werden verzögerungsfrei Token für Token gestreamt (`agent.stream`).
- **Tool-Aktivitäten**: Visualisiert live, woran Ghost gerade arbeitet (z. B. Nachdenken, Workspace-Tools).
- **Sitzungsverwaltung**: Wechsle zwischen Chat-Sitzungen oder starte mit einem Klick eine neue Session.
- **Codeblock-Aktionen**: Jeder generierte Codeblock verfügt über einen 1-Klick-Button zum Kopieren in die Zwischenablage.

### 2. 🌐 Webseiten-Kontext & Recherche (Page Q&A)
- **Aktiven Tab anhängen**: Mit einem Klick auf `🌐 Aktiven Tab anhängen` wird die URL, der Titel und der sichtbare Text der aktuellen Dokumentation oder des Artikels an deinen Prompt übergeben.
- Perfekt zum Verstehen komplexer API-Dokumentationen, RFCs oder GitHub-Repositories.

### 3. ⚡ Kontextmenü-Aktionen (Rechtsklick)
Markiere Text auf einer beliebigen Webseite (GitHub, StackOverflow, Medium, Docs) und wähle per Rechtsklick:
- **👻 Ghost: Text / Code erklären**: Analysiert den markierten Code oder Text verständlich und präzise.
- **👻 Ghost: Auswahl zusammenfassen**: Fasst lange Absätze oder Ticket-Beschreibungen prägnant zusammen.
- **👻 Ghost: Als Kanban-Task anlegen (/plan)**: Übergibt das Problem direkt als Aufgabe an das Ghost-Backend.
- **👻 Ghost: Diese Seite analysieren**: Analysiert die gesamte aktuell geöffnete Seite.

### 4. ⚙️ Einstellungen & Auto-Discovery
- **Auto-Discovery**: Erkennt automatisch das lokale Gateway auf `ws://localhost:3000` und liest bei Bedarf den Autorisierungs-Token über `http://localhost:3000/client-token` aus.
- **Einstellungsseite**: Über das Zahnrad-Symbol oder `chrome://extensions` können Gateway-URL und Token individuell angepasst und mit dem Button *„Verbindung testen“* geprüft werden.

---

## 🛠️ Installation & Testen im Browser

### 1. Erweiterung bauen
Die Erweiterung ist bereits gebaut. Falls du Änderungen machst:
```bash
cd chrome-extension
npm run build
```
*(Für kontinuierlichen Rebuild bei Dateiänderungen: `npm run watch`)*

### 2. Im Browser laden (Unpacked Extension)
1. Öffne Google Chrome (oder Brave / Microsoft Edge / Arc).
2. Navigiere in der Adressleiste zu:
   ```
   chrome://extensions
   ```
3. Aktiviere oben rechts den Schalter **Entwicklermodus** (*Developer mode*).
4. Klicke oben links auf **Entpackte Erweiterung laden** (*Load unpacked*).
5. Wähle den Ordner `chrome-extension` aus:
   ```
   /home/peter/Developer/flutter-dev/ghost/chrome-extension
   ```
6. Die Erweiterung **Ghost AI Assistant** ist sofort einsatzbereit!
7. **Tipp**: Klicke in der Chrome-Symbolleiste auf das Puzzle-Symbol und pinne Ghost an. Ein Klick auf das Ghost-Icon öffnet direkt das Side Panel!

---

## ⚙️ Architektur & Gateway-Verbindung

```
┌─────────────────────────────────┐
│     Google Chrome (Side Panel)  │
│  [sidepanel.html / sidepanel.ts]│
└────────────────┬────────────────┘
                 │ WebSocket JSON-RPC 2.0
                 │ ws://localhost:3000
                 ▼
┌─────────────────────────────────┐
│     Ghost Gateway Server        │
│    (agent.chat, agent.stream,   │
│     agent.activity, sessions)   │
└─────────────────────────────────┘
```
