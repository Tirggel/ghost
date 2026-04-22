# 📱 Leitfaden zur Multi-Channel-Unterstützung

Ghost unterstützt 13 verschiedene Kommunikationskanäle, so dass Sie von Ihren bevorzugten Messaging-Apps aus mit Ihrem KI-Assistenten interagieren können. In diesem Leitfaden wird die Einrichtung der einzelnen Kanäle erläutert.

## 🗝️ Allgemeine Konfiguration
Alle Kanäle werden über die Registerkarte **Einstellungen → Kanäle** in der Ghost App konfiguriert. Token und empfindliche Schlüssel werden sicher in Ihrem lokalen verschlüsselten Tresor gespeichert.

**Intelligente Benutzeroberfläche**:
- **Suchfilter**: Verwenden Sie die Suchleiste oben, um bestimmte Kanäle schnell zu finden.
- **Automatische Sortierung**: Konfigurierte und aktive Kanäle werden automatisch oben gruppiert, um den Zugriff zu erleichtern.
- **Sichere Verwaltung**: Sensible Zugangsdaten wie API-Schlüssel und Token werden standardmäßig maskiert und bei Bedarf sicher abgerufen.
- **Automatisierte Bereinigung**: Wenn Sie ein Token entfernen oder einen Kanal deaktivieren, löscht Ghost die Zugangsdaten automatisch aus dem sicheren Tresor.
- **Resiliente Verbindungen**: Aktive Kanäle verfügen über eine automatische Verbindungswiederherstellung, falls die Sitzung unterbrochen wird.

---

### 1. Telegram
Ghost verwendet die [teledart](https://pub.dev/packages/teledart)-Bibliothek für die Verbindung zu Telegram.
- **Einrichtung**:
  1. Senden Sie eine Nachricht an [@BotFather](https://t.me/botfather) auf Telegram.
  2. Verwenden Sie `/newbot`, um einen neuen Bot zu erstellen und Ihren **Bot Token** zu erhalten.
  3. Geben Sie den Token in Ghost ein.
- **Funktionen**: Unterstützt Text- und **Sprachnachrichten** (mit lokalem STT/TTS).
- **Auto-Neustart**: Das Ändern des Tokens startet den Bot automatisch mit den neuen Zugangsdaten neu.

### 2. Discord
Verwendet die [nyxx](https://pub.dev/packages/nyxx)-Bibliothek.
- **Einrichtung**:
  1. Gehen Sie zum [Discord Developer Portal](https://discord.com/developers/applications).
  2. Erstellen Sie eine "New Application" und fügen Sie einen "Bot" hinzu.
  3. Setzen Sie den **Bot Token** zurück/kopieren Sie ihn.
  4. Aktivieren Sie den **Message Content Intent** in den Bot-Einstellungen.
  5. Laden Sie den Bot mit dem OAuth2 URL Generator auf Ihren Server ein (Scopes: `bot`, `applications.commands`; Berechtigungen: `Send Messages`, `Read Message History`).

### 3. WhatsApp (Meta Cloud API)
Verwendet die offizielle Meta WhatsApp Business Cloud API.
- **Einrichtung**:
  1. Erstellen Sie eine Meta Developer App unter [developers.facebook.com](https://developers.facebook.com).
  2. Fügen Sie "WhatsApp" zu Ihrer App hinzu.
  3. Rufen Sie Ihre **Phone Number ID** und einen **Permanent Access Token** ab.
  4. Konfigurieren Sie den **Webhook**:
     - URL: `https://<ihr-host>/webhooks/whatsapp`
     - Verify Token: Eine von Ihnen definierte Zeichenfolge (Standard: `ghost_verify`).
  5. Abonnieren Sie `messages` in den Webhook-Feldern.

### 4. Slack
Verwendet die Slack-Events-API.
- **Einrichtung**:
  1. Erstellen Sie eine App unter [api.slack.com/apps](https://api.slack.com/apps).
  2. Aktivieren Sie **Event Subscriptions** und setzen Sie die Request URL auf `https://<ihr-host>/webhooks/slack`.
  3. Abonnieren Sie Bot-Ereignisse: `message.im` und `message.channels`.
  4. Installieren Sie die App in Ihrem Workspace und kopieren Sie den **Bot User OAuth Token** (`xoxb-...`).

### 5. Signal
Erfordert eine selbst gehostete [signal-cli-rest-api](https://github.com/bbernhard/signal-cli-rest-api)-Instanz (z. B. über Docker).
- **Einrichtung**:
  1. Starten Sie den Signal-REST-API-Container.
  2. Registrieren/Verknüpfen Sie Ihre Telefonnummer über die REST-API.
  3. Geben Sie die **Telefonnummer** und die **API-URL** (z. B. `http://localhost:8080`) in Ghost ein.

### 6. iMessage (BlueBubbles)
Da iMessage Apple-Hardware erfordert, integriert sich Ghost in einen [BlueBubbles](https://bluebubbles.app/)-Server.
- **Einrichtung**:
  1. Installieren Sie den BlueBubbles Server auf einem Mac.
  2. Notieren Sie sich Ihre **Server-URL** und das **Server-Passwort**.
  3. Stellen Sie sicher, dass die API/WebSocket für Ghost zugänglich ist.

### 7. Google Chat
Verbindung über Google Cloud Pub/Sub.
- **Einrichtung**:
  1. Erstellen Sie ein Projekt in der [Google Cloud Console](https://console.cloud.google.com/).
  2. Aktivieren Sie die Google Chat API und erstellen Sie eine Chat App.
  3. Konfigurieren Sie die App so, dass sie **Pub/Sub** als Verbindung verwendet.
  4. Erstellen Sie ein Servicekonto, laden Sie den **JSON-Schlüssel** herunter und notieren Sie sich die **Projekt-ID** sowie die **Abonnement-ID**.

### 8. Microsoft Teams
Verwendet das Azure Bot Framework.
- **Einrichtung**:
  1. Registrieren Sie einen Bot im [Azure Portal](https://portal.azure.com).
  2. Verknüpfen Sie ihn mit dem "Microsoft Teams"-Kanal.
  3. Setzen Sie den Messaging-Endpunkt auf `https://<ihr-host>/webhooks/msteams`.
  4. Kopieren Sie Ihre **Microsoft App ID** und Ihr **App Password**.

### 9. Nextcloud Talk
Verbindet sich direkt mit Ihrer Nextcloud-Instanz.
- **Einrichtung**:
  1. Erstellen Sie ein Benutzer-/Bot-Konto in Nextcloud.
  2. Erzeugen Sie ein **App-Passwort** in den Sicherheitseinstellungen.
  3. Geben Sie die **Nextcloud-URL** und die **Basic-Auth-Zugangsdaten** (`benutzername:apppasswort`) in Ghost ein.
  4. (Optional) Geben Sie ein spezifisches **Raum-Token** an.

### 10. Matrix
Kompatibel mit jedem Matrix-Homeserver (Synapse usw.).
- **Einrichtung**:
  1. Erstellen Sie ein Bot-Konto auf Ihrem Homeserver (z. B. matrix.org).
  2. Rufen Sie ein **Access Token** über den Matrix API Login ab.
  3. Geben Sie die **Homeserver-URL**, die **User-ID** (@ghost:...) und das **Access Token** ein.

### 11. Tlon / Urbit
Verbindet sich mit Ihrem Urbit-Ship.
- **Einrichtung**:
  1. Betreiben Sie ein Urbit-Ship.
  2. Rufen Sie Ihren Session-**+code** ab (über `|code` im Dojo).
  3. Geben Sie die **Ship-URL**, den **Ship-Namen** (~sampel-palnet) und den **+code** ein.

### 12. Zalo (Vietnam)
Verwendet die Zalo Official Account (OA) API.
- **Einrichtung**:
  1. Erstellen Sie einen Zalo OA unter [oa.zalo.me](https://oa.zalo.me).
  2. Erstellen Sie eine App unter [developers.zalo.me](https://developers.zalo.me).
  3. Generieren Sie ein **langlebiges Access Token** und notieren Sie sich Ihre **OA-ID**.
  4. Setzen Sie den Webhook auf `https://<ihr-host>/webhooks/zalo`.

### 13. WebChat
Der interne browserbasierte Chat.
- **Einrichtung**: Automatisch aktiviert, wenn Sie das Gateway starten.
- **Nutzung**: Verwenden Sie den integrierten Chat in der Ghost App oder das Webinterface.

---

## 🛡️ DM-Richtlinien
Für jeden Kanal können Sie die **DM-Richtlinie** konfigurieren, um die Sicherheit zu steuern:
- **Pairing**: Neue Benutzer müssen einen Pairing-Code (aus den Einstellungen) eingeben, bevor der Bot antwortet.
- **Allowlist**: Nur bestimmte User-IDs können mit dem Bot interagieren.
- **Open**: Der Bot antwortet jedem (nicht empfohlen für öffentliche Bots).
- **Disabled**: DMs werden auf diesem Kanal komplett ignoriert.
