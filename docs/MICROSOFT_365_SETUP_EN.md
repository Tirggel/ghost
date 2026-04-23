# Microsoft 365 Setup 🛠️

This guide leads you step-by-step through the configuration in the Microsoft Entra admin center (formerly Azure AD) to use Outlook Mail, Calendar, and OneDrive with Ghost.

## Microsoft Entra Admin Center Workflow

1. **Register an Application**
   - Go to the [Microsoft Entra admin center](https://entra.microsoft.com/).
   - Navigate to **Identity > Applications > App registrations**.
   - Click on **New registration**.
   - **Name**: e.g., `ghost-assistant`.
   - **Supported account types**: Select **Accounts in any organizational directory (Any Microsoft Entra ID tenant - Multitenant) and personal Microsoft accounts (e.g. Skype, Xbox)**.
   - Click **Register**.

2. **Configure Authentication**
   - In your new app registration, go to **Manage > Authentication**.
   - Click **Add a platform** and select **Mobile and desktop applications**.
   - Under **Redirect URIs**, enter: `http://localhost:8080`.
   - Click **Configure**.
   - Under **Advanced settings**, ensure **Allow public client flows** is set to **Yes** (required for desktop apps).
   - Click **Save**.

3. **Enable API Permissions**
   - Go to **Manage > API permissions**.
   - Click **Add a permission** and select **Microsoft Graph**.
   - Select **Delegated permissions**.
   - Search for and check the following permissions:
     - `openid`
     - `profile`
     - `email`
     - `offline_access`
     - `User.Read`
     - `Mail.ReadWrite`
     - `Mail.Send`
     - `Files.ReadWrite.All`
     - `Calendars.ReadWrite`
   - Click **Add permissions**.

4. **Get Client ID**
   - Go to **Overview**.
   - Copy the **Application (client) ID**. This is what you will enter in Ghost.

---
Done! Now enter the **Client ID** in the app under **Settings > Integrations**. Ghost will handle the sign-in flow and secure token storage.
