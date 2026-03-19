# Google Workspace Einrichtung 🛠️

Diese Anleitung führt dich Schritt für Schritt durch die Konfiguration in der Google Cloud Console, um Gmail, Kalender und Drive mit Ghost zu nutzen.

## Google Cloud Console Ablauf

1. **Projekt erstellen**
   - Gehe zur [Google Cloud Console](https://console.cloud.google.com/).
   - Klicke auf **Projekt auswählen** und dann auf **Neues Projekt**.
   - Projektname: z.B. `ghost`.
   - Klicke auf **Erstellen** und danach auf **Projekt auswählen**.

2. **OAuth-Plattform konfigurieren**
   - Gib im Suchfeld "clients" ein und klicke auf den Button **"Clients Produktseite Google Auth Platform"**.
   - Klicke auf **Erste Schritte**.
   - **App-Informationen**: Anwendungsname z.B. `ghost-bot-login`.
   - **Nutzersupport-Email**: Wähle deine E-Mail-Adresse aus.
   - Klicke auf **Weiter**.
   - **Zielgruppe**: Wähle die Option **Extern**.
   - Klicke auf **Weiter**.
   - **Kontaktdaten**: Gib deine E-Mail-Adresse ein (z.B. `peter.rubin.bot@gmail.com`).
   - Klicke auf **Weiter**.
   - Setze den Haken bei "Ich akzeptiere die Richtlinie zu Nutzerdaten für Google API-Dienste".
   - Klicke auf **Fortfahren** und dann auf **Erstellen**.

3. **OAuth-Clients (Anmeldedaten) erstellen**
   
   **Client für Web:**
   - Klicke auf **OAuth-Client erstellen**.
   - Anwendungstyp: **Webanwendung**.
   - Name: `ghost-web`.
   - **Autorisierte JavaScript-Quellen**: Klicke auf "URI hinzufügen" und gib `http://localhost` ein.
   - Klicke auf **Erstellen** und lade die JSON-Datei herunter.

   **Client für Desktop:**
   - Suche erneut nach "clients" und gehe zur Produktseite.
   - Klicke auf **Client erstellen**.
   - Anwendungstyp: **Desktopanwendung**.
   - Name: `ghost-desktop`.
   - Klicke auf **Erstellen** und lade die JSON-Datei herunter.

4. **APIs aktivieren**
   - Suche nach "Google Workspace" oder gehe zu "APIs & Services".
   - Aktiviere folgende APIs nacheinander:
     - `Gmail API`
     - `Google Chat API`
     - `Google Drive API`
     - `Google Calendar API`

5. **Testnutzer hinzufügen**
   - Suche nach "Zielgruppe" und gehe zur Produktseite.
   - Klicke unter **Testnutzer** auf **Add users**.
   - Gib deine E-Mail-Adresse ein und klicke auf **Speichern**.

6. **Bereiche (Scopes) konfigurieren**
   - Suche nach "Datenzugriff" und klicke auf **"Bereiche hinzufügen oder entfernen"**.
   - Scrolle nach unten zu "Bereiche manuell hinzufügen" und füge folgende URIs hinzu:
     - `https://mail.google.com/`
     - `https://www.googleapis.com/auth/gmail.modify`
     - `https://www.googleapis.com/auth/drive.file`
     - `https://www.googleapis.com/auth/calendar`

   > [!IMPORTANT]
   > Folgende Bereiche erfordern Google Workspace Business (kostenpflichtig):
   > - `https://www.googleapis.com/auth/chat.bot`
   > - `https://www.googleapis.com/auth/chat.app.spaces.create`
   > - `https://www.googleapis.com/auth/chat.import`

   - Klicke auf **Zum Tabelle hinzufügen** und dann auf **Aktualisieren**.

---
Fertig! Trage nun die Client-IDs und das Secret in der App unter **Einstellungen > Integrationen** ein.
