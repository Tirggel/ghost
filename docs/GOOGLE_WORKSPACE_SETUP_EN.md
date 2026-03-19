# Google Workspace Setup 🛠️

This guide leads you step-by-step through the configuration in the Google Cloud Console to use Gmail, Calendar, and Drive with Ghost.

## Google Cloud Console Workflow

1. **Create a Project**
   - Go to the [Google Cloud Console](https://console.cloud.google.com/).
   - Click on **Select a project** and then on **New Project**.
   - Project Name: e.g., `ghost`.
   - Click **Create** and then **Select project**.

2. **Configure OAuth Platform**
   - Type "clients" in the search field and click the **"Clients Product Page Google Auth Platform"** button.
   - Click on **Get Started**.
   - **App Information**: App name e.g., `ghost-bot-login`.
   - **User support email**: Select your email address.
   - Click **Next**.
   - **Audience**: Select **External**.
   - Click **Next**.
   - **Contact Information**: Enter your email address (e.g., `peter.rubin.bot@gmail.com`).
   - Click **Next**.
   - Check the box "I accept the User Data Policy for Google API Services".
   - Click **Continue** and then **Create**.

3. **Create OAuth Clients (Credentials)**
   
   **Client for Web:**
   - Click **Create OAuth Client**.
   - Application Type: **Web Application**.
   - Name: `ghost-web`.
   - **Authorized JavaScript origins**: Click "Add URI" and enter `http://localhost`.
   - Click **Create** and download the JSON file.

   **Client for Desktop:**
   - Search for "clients" again and go to the product page.
   - Click **Create Client**.
   - Application Type: **Desktop Application**.
   - Name: `ghost-desktop`.
   - Click **Create** and download the JSON file.

4. **Enable APIs**
   - Search for "Google Workspace" or go to "APIs & Services".
   - Enable the following APIs one by one:
     - `Gmail API`
     - `Google Chat API`
     - `Google Drive API`
     - `Google Calendar API`

5. **Add Test Users**
   - Search for "Audience" and go to the product page.
   - Under **Test Users**, click **Add users**.
   - Enter your email address and click **Save**.

6. **Configure Scopes**
   - Search for "Data Access" and click **"Add or remove scopes"**.
   - Scroll down to "Manually add scopes" and add the following URIs:
     - `https://mail.google.com/`
     - `https://www.googleapis.com/auth/gmail.modify`
     - `https://www.googleapis.com/auth/drive.file`
     - `https://www.googleapis.com/auth/calendar`

   > [!IMPORTANT]
   > The following scopes require Google Workspace Business (paid):
   > - `https://www.googleapis.com/auth/chat.bot`
   > - `https://www.googleapis.com/auth/chat.app.spaces.create`
   > - `https://www.googleapis.com/auth/chat.import`

   - Click **Add to table** and then **Update**.

---
Done! Now enter the Client IDs and Secret in the app under **Settings > Integrations**.
