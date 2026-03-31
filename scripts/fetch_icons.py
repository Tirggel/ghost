import urllib.request
import os

os.makedirs('app/assets/icons/channels', exist_ok=True)

icons = {
    'whatsapp': 'whatsapp.com',
    'telegram': 'telegram.org',
    'discord': 'discord.com',
    'slack': 'slack.com',
    'signal': 'signal.org',
    'imessage': 'apple.com',
    'msteams': 'microsoft.com/en-us/microsoft-teams/group-chat-software',
    'nextcloud': 'nextcloud.com',
    'matrix': 'matrix.org',
    'nostr': 'nostr.com',
    'tlon': 'tlon.io',
    'zalo': 'zalo.me',
    'webchat': 'openclaw.ai',
    'google': 'google.com'
}

for name, domain in icons.items():
    url = f"https://www.google.com/s2/favicons?domain={domain}&sz=128"
    path = f"app/assets/icons/channels/{name}.png"
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req) as response, open(path, 'wb') as out_file:
            out_file.write(response.read())
        print(f"Downloaded {name}.png")
    except Exception as e:
        print(f"Failed to download {name}.png: {e}")

