# 📱 Multi-Channel Support Guide

Ghost supports 13 different communication channels, allowing you to interact with your AI assistant from your favorite messaging apps. This guide explains how to set up each channel.

## 🗝️ General Configuration
All channels are configured via the **Settings → Channels** tab in the Ghost App. Tokens and sensitive keys are stored securely in your local encrypted vault.

**Smart Interface**:
- **Search Filter**: Use the search bar at the top to quickly find specific channels.
- **Auto-Sorting**: Configured and active channels are automatically grouped at the top for easy access.
- **Secure Management**: Sensitive credentials like API keys and tokens are masked by default and securely fetched on-demand.
- **Automated Cleanup**: If you remove a token or disable a channel, Ghost automatically wipes the credentials from the secure vault.
- **Resilient Connections**: Active channels feature automatic connection recovery if the session is interrupted.

---

### 1. Telegram
Ghost uses the [teledart](https://pub.dev/packages/teledart) library to connect to Telegram.
- **Setup**:
  1. Message [@BotFather](https://t.me/botfather) on Telegram.
  2. Use `/newbot` to create a new bot and get your **Bot Token**.
  3. Enter the token in Ghost.
- **Features**: Supports text and **voice messages** (with local STT/TTS).
- **Auto-Restart**: Changing the token automatically restarts the bot with the new credentials.

### 2. Discord
Uses the [nyxx](https://pub.dev/packages/nyxx) library.
- **Setup**:
  1. Go to the [Discord Developer Portal](https://discord.com/developers/applications).
  2. Create a "New Application" and add a "Bot".
  3. Reset/Copy the **Bot Token**.
  4. Enable **Message Content Intent** under the Bot settings.
  5. Invite the bot to your server using the OAuth2 URL Generator (scopes: `bot`, `applications.commands`; permissions: `Send Messages`, `Read Message History`).

### 3. WhatsApp (Meta Cloud API)
Uses the official Meta WhatsApp Business Cloud API.
- **Setup**:
  1. Create a Meta Developer App at [developers.facebook.com](https://developers.facebook.com).
  2. Add "WhatsApp" to your app.
  3. Get your **Phone Number ID** and a **Permanent Access Token**.
  4. Configure the **Webhook**:
     - URL: `https://<your-host>/webhooks/whatsapp`
     - Verify Token: A string you define (default: `ghost_verify`).
  5. Subscribe to `messages` in Webhook fields.

### 4. Slack
Uses Slack's Events API.
- **Setup**:
  1. Create an app at [api.slack.com/apps](https://api.slack.com/apps).
  2. Enable **Event Subscriptions** and set the Request URL to `https://<your-host>/webhooks/slack`.
  3. Subscribe to bot events: `message.im` and `message.channels`.
  4. Install the app to your workspace and copy the **Bot User OAuth Token** (`xoxb-...`).

### 5. Signal
Requires a self-hosted [signal-cli-rest-api](https://github.com/bbernhard/signal-cli-rest-api) instance (e.g., via Docker).
- **Setup**:
  1. Start the Signal REST API container.
  2. Register/Link your phone number via the REST API.
  3. Enter the **Phone Number** and the **API URL** (e.g., `http://localhost:8080`) in Ghost.

### 6. iMessage (BlueBubbles)
Since iMessage requires Apple hardware, Ghost integrates with a [BlueBubbles](https://bluebubbles.app/) server.
- **Setup**:
  1. Install BlueBubbles Server on a Mac.
  2. Note your **Server URL** and **Server Password**.
  3. Ensure the API/WebSocket is accessible by Ghost.

### 7. Google Chat
Connects via Google Cloud Pub/Sub.
- **Setup**:
  1. Create a project in [Google Cloud Console](https://console.cloud.google.com/).
  2. Enable the Google Chat API and create a Chat App.
  3. Configure the app to use **Pub/Sub** as a connection.
  4. Create a Service Account, download the **JSON Key**, and note the **Project ID** and **Subscription ID**.

### 8. Microsoft Teams
Uses the Azure Bot Framework.
- **Setup**:
  1. Register a Bot in [Azure Portal](https://portal.azure.com).
  2. Link it to the "Microsoft Teams" channel.
  3. Set the Messaging Endpoint to `https://<your-host>/webhooks/msteams`.
  4. Copy your **Microsoft App ID** and **App Password**.

### 9. Nextcloud Talk
Connects directly to your Nextcloud instance.
- **Setup**:
  1. Create a user/bot account in Nextcloud.
  2. Generate an **App Password** in Security Settings.
  3. Enter the **Nextcloud URL** and the **Basic Auth credentials** (`username:apppassword`) in Ghost.
  4. (Optional) Provide a specific **Room Token**.

### 10. Matrix
Compatible with any Matrix homeserver (Synapse, etc.).
- **Setup**:
  1. Create a bot account on your homeserver (e.g., matrix.org).
  2. Get an **Access Token** via the Matrix API login.
  3. Enter the **Homeserver URL**, **User ID** (@ghost:...), and **Access Token**.

### 11. Tlon / Urbit
Connects to your Urbit ship.
- **Setup**:
  1. Run an Urbit ship.
  2. Get your session **+code** (via `|code` in dojo).
  3. Enter the **Ship URL**, **Ship Name** (~sampel-palnet), and **+code**.

### 12. Zalo (Vietnam)
Uses the Zalo Official Account (OA) API.
- **Setup**:
  1. Create a Zalo OA at [oa.zalo.me](https://oa.zalo.me).
  2. Create an App at [developers.zalo.me](https://developers.zalo.me).
  3. Generate a **Long-lived Access Token** and note your **OA ID**.
  4. Set the Webhook to `https://<your-host>/webhooks/zalo`.

### 13. WebChat
The internal browser-based chat.
- **Setup**: Automatically enabled when you start the Gateway.
- **Usage**: Use the build-in chat in the Ghost App or the web interface.

---

## 🛡️ DM Policies
For every channel, you can configure the **DM Policy** to control security:
- **Pairing**: New users must enter a pairing code (from settings) before the bot responds.
- **Allowlist**: Only specific user IDs can interact with the bot.
- **Open**: The bot responds to everyone (not recommended for public bots).
- **Disabled**: DMs are completely ignored on this channel.
