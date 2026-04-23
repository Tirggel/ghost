# Microsoft 365 Einrichtung 🛠️

Diese Anleitung führt Sie Schritt für Schritt durch die Konfiguration im Microsoft Entra Admin Center (ehemals Azure AD), um Outlook Mail, Kalender und OneDrive mit Ghost zu nutzen.

## Microsoft Entra Admin Center Workflow

1. **Anwendung registrieren**
   - Rufen Sie das [Microsoft Entra admin center](https://entra.microsoft.com/) auf.
   - Navigieren Sie zu **Identity > Applications > App registrations**.
   - Klicken Sie auf **New registration**.
   - **Name**: z.B. `ghost-assistent`.
   - **Supported account types**: Wählen Sie **Accounts in any organizational directory (Any Microsoft Entra ID tenant - Multitenant) and personal Microsoft accounts (e.g. Skype, Xbox)**.
   - Klicken Sie auf **Register**.

2. **Authentifizierung konfigurieren**
   - Navigieren Sie in Ihrer neuen App-Registrierung zu **Manage > Authentication**.
   - Klicken Sie auf **Add a platform** und wählen Sie **Mobile and desktop applications**.
   - Geben Sie unter **Redirect URIs** Folgendes ein: `http://localhost:8080`.
   - Klicken Sie auf **Configure**.
   - Stellen Sie unter **Advanced settings** sicher, dass **Allow public client flows** auf **Yes** gesetzt ist (erforderlich für Desktop-Apps).
   - Klicken Sie auf **Save**.

3. **API-Berechtigungen aktivieren**
   - Navigieren Sie zu **Manage > API permissions**.
   - Klicken Sie auf **Add a permission** und wählen Sie **Microsoft Graph**.
   - Wählen Sie **Delegated permissions**.
   - Suchen und aktivieren Sie die folgenden Berechtigungen:
     - `openid`
     - `profile`
     - `email`
     - `offline_access`
     - `User.Read`
     - `Mail.ReadWrite`
     - `Mail.Send`
     - `Files.ReadWrite.All`
     - `Calendars.ReadWrite`
   - Klicken Sie auf **Add permissions**.

4. **Client-ID kopieren**
   - Gehen Sie auf **Overview**.
   - Kopieren Sie die **Application (client) ID**. Dies ist die ID, die Sie in Ghost eingeben müssen.

---
Fertig! Geben Sie nun die **Client-ID** in der App unter **Einstellungen > Integrationen** ein. Ghost kümmert sich um den Anmeldevorgang und die sichere Speicherung der Token.
