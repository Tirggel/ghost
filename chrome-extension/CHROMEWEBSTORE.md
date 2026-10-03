# Chrome Web Store Listing — Ghost AI Assistant

> Last Updated: 2026-10-02

## Store Listing

**Extension Name** [REQUIRED]
Ghost AI Assistant

**Short Description** [REQUIRED]
Persönlicher KI-Assistent im Browser: Side Panel Chat, Web-Kontext, Rechtsklick-Aktionen und Live-Streaming über Ghost Gateway.

**Detailed Description** [REQUIRED]
Verbinde deinen persönlichen KI-Assistenten Ghost direkt mit Google Chrome.

Ghost AI Assistant erweitert deinen Browser um eine intelligente Seitenleiste, die dir bei Recherchen, Code-Analysen, Zusammenfassungen von Artikeln und der Erstellung von Aufgaben zur Seite steht.

Hauptfunktionen:
- Interaktiver Side Panel Chat: Ein permanentes Seitenleisten-Chatfenster mit verzögerungsfreiem Token-Streaming und Anzeige von Tool-Aktivitäten.
- Webseiten-Kontext & Recherche: Hänge die aktuelle Seite (URL, Titel und Textinhalte) mit einem Klick an deine Fragen an, um präzise Antworten zu Dokumentationen oder Artikeln zu erhalten.
- Schnelle Kontextmenü-Aktionen: Markiere Text auf beliebigen Webseiten (z. B. GitHub, StackOverflow, Blogs) und lasse ihn per Rechtsklick erklären, zusammenfassen oder in einen Kanban-Task verwandeln.
- Aufgabenverwaltung mit /plan: Starte strukturierte Analysen oder plane Aufgaben direkt aus dem Browser in dein Ghost-Backend.
- Nahtlose Anbindung: Verbindet sich direkt über das sichere WebSocket-Gateway mit deiner lokalen oder entfernten Ghost-Instanz.

So startest du:
1. Starte deine Ghost-Anwendung auf deinem Rechner (Standard-Gateway auf Port 3000).
2. Klicke auf das Ghost-Symbol in der Chrome-Symbolleiste, um das Side Panel zu öffnen.
3. Chatte sofort los oder markiere Text auf einer beliebigen Webseite für Kontext-Aktionen.

Datenschutz:
Deine Anfragen verbleiben bei deiner eigenen Ghost-Instanz. Es werden keine Browserverläufe oder Daten an Drittanbieter-Server gesendet.

Support:
Besuche https://github.com/Tirggel/ghost für Dokumentation, Updates und Feedback.

**Category** [REQUIRED]
Developer Tools

**Single Purpose** [REQUIRED]
Bietet einen KI-Seitenleisten-Chat und Kontextmenü-Aktionen zur Analyse und Zusammenfassung von Webinhalten über das Ghost Gateway.

**Primary Language** [REQUIRED]
German

## Graphics & Assets

| Asset | Dimensions | Status | Filename |
|---|---|---|---|
| Store Icon [REQUIRED] | 128×128 PNG | ✅ Ready | `icons/icon-128.png` |
| Screenshot 1 [REQUIRED] | 1280×800 or 640×400 | ⬜ Not created | |
| Screenshot 2 [RECOMMENDED] | 1280×800 or 640×400 | ⬜ Not created | |
| Small Promo Tile [RECOMMENDED] | 440×280 | ⬜ Not created | |

## Permissions Justification

| Permission | Type | Justification |
|---|---|---|
| `sidePanel` | permissions | Wird benötigt, um die intuitive Chat-Seitenleiste direkt im Browser neben Webinhalten anzuzeigen. |
| `contextMenus` | permissions | Ermöglicht Rechtsklick-Aktionen auf markierten Text ("Code erklären", "Zusammenfassen", "Task erstellen"). |
| `storage` | permissions | Speichert Konfigurationen wie die Gateway-URL und temporäre Übergabewerte zwischen Kontextmenü und Seitenleiste. |
| `tabs` | permissions | Ermöglicht das Auslesen von URL und Seitentitel des aktiven Tabs, wenn der Nutzer die Seite als Kontext an die Frage anhängt. |
| `scripting` | permissions | Extrahiert auf Nutzerwunsch Textauszüge des aktuellen Tabs zur Beantwortung von Fragen zur aktuellen Seite. |
| `http://localhost:3000/*` | host_permissions | Ermöglicht die HTTP- und WebSocket-Kommunikation mit dem lokalen Ghost Gateway Server. |
| `http://127.0.0.1:3000/*` | host_permissions | Ermöglicht die HTTP- und WebSocket-Kommunikation mit dem lokalen Ghost Gateway Server über Loopback-IP. |

## Privacy & Data Use

### Data Collection
- Keine Erfassung von Nutzerdaten durch den Entwickler.
- Sämtliche Kommunikationsdaten fließen ausschließlich zwischen dem lokalen Browser und dem konfigurierten Ghost-Gateway des Nutzers.

### Data Security
- Kommunikation erfolgt lokal über WebSocket JSON-RPC 2.0 (bzw. verschlüsseltes WSS im Remote-Betrieb).

## Version History

| Version | Date | Changes |
|---|---|---|
| 0.1.0 | 2026-10-02 | Initial release: Side Panel Chat, WebSocket JSON-RPC Client, Kontextmenüs, Tab-Kontext-Injektion. |
