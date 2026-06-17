# 💳 Zahlungs-, Wallet- & Binance-Einrichtung — Ghost

Ghost verfügt über ein integriertes System zur Zahlungsausführung, Web3-Blockchain-Integration und zum Binance-API-Handel. In dieser Anleitung wird erklärt, wie Sie diese Funktionen konfigurieren und verwenden.

---

## 🔒 Sicherheit & Sicherheitsrichtlinien zuerst

Alle Anmeldeinformationen (Kreditkarten, EVM-Private-Keys und Binance-API-Schlüssel) werden **lokal in Ihrem sicheren, verschlüsselten Tresor (Vault)** mit AES-256-GCM gespeichert. Sie werden niemals an Server von Drittanbietern übertragen, außer an die direkten Ziel-APIs (Binance, RPC-Knoten oder Block-Explorer).

> [!WARNING]
> Obwohl die Schlüssel sicher gespeichert sind, können Prompt-Injection-Angriffe theoretisch einen Agenten manipulieren. Testen Sie Ihre Konfiguration daher immer auf **Testnetzwerken** (wie BSC Testnet, Sepolia, Polygon Amoy) oder verwenden Sie das **Binance Demo-Trading**, bevor Sie Mainnet-Private-Keys oder echte Vermögenswerte konfigurieren!

---

## 1. Kreditkarten- & virtuelles Budget-Setup

Ghost ermöglicht es Agenten, Zahlungen im Namen des Benutzers mit einer konfigurierten Kreditkarte durchzuführen. Zum Schutz Ihrer echten Karte erzwingt Ghost ein **virtuelles Budgetsystem**.

### Konfiguration
1. Öffnen Sie die Ghost-Benutzeroberfläche und navigieren Sie zu **Einstellungen > Zahlungen**.
2. Geben Sie Ihre Kreditkartendaten ein:
   - **Kartennummer**: 15 oder 16 Ziffern.
   - **Ablaufdatum**: Format MM/YY.
   - **CVV/CVC**: 3 oder 4 Ziffern.
   - **Karteninhaber**: Name auf der Karte.
3. Stellen Sie Ihre **virtuellen Budgetgrenzen** ein:
   - **Limit**: Das absolute maximale Budget.
   - **Guthaben (Balance)**: Das aktuell verfügbare virtuelle Budget.

### Funktionsweise von Zahlungen (Das Tool `execute_payment`)
Wenn ein Agent für einen Dienst bezahlen möchte (z. B. Kauf eines API-Schlüssels oder Hosting-Zahlung):
1. Der Agent führt das Tool `execute_payment` aus und gibt `amount` (Betrag), `recipient` (Empfänger) und `purpose` (Zweck) an.
2. Ghost prüft, ob eine Kreditkarte konfiguriert ist, und verifiziert, ob das virtuelle **Guthaben** ausreicht.
3. Wenn das Guthaben ausreicht, wird der Betrag vom virtuellen Guthaben abgezogen, die Transaktion als `SUCCESS` (Erfolgreich) verbucht und die Konfiguration gespeichert.
4. Ist das Guthaben unzureichend, wird die Transaktion als `FAILED` (Fehlgeschlagen) erfasst und der Nutzer über seine aktiven Kommunikationskanäle benachrichtigt.
5. Wenn **Human-In-The-Loop (HITL)** aktiviert ist, pausiert Ghost und bittet im Chat um eine explizite JA/NEIN-Bestätigung, bevor das Zahlungstool ausgeführt wird. Ist die **autonome Abrechnung** aktiviert, wird die Zahlung direkt im Hintergrund ausgeführt.

---

## 2. Persönliches Web3-Wallet (Reown AppKit)

Sie können Ihre dezentralen Krypto-Wallets verbinden, um Guthaben und Transaktionsdaten direkt in der App anzuzeigen.

### Konfiguration
1. Besorgen Sie sich eine **Projekt-ID** aus der [Reown Cloud-Konsole](https://cloud.reown.com/) (ehemals WalletConnect).
2. Tragen Sie die Projekt-ID in den **Einstellungen > Zahlungen > Kryptos** unter "Reown Projekt-ID" ein.
3. Klicken Sie auf **AppKit initialisieren**.
4. Nutzen Sie den Button **Wallet verbinden**, um den QR-Code zu scannen oder Ihr Browser-Wallet auszuwählen.

### Explorer-Integration
Um Ihren Transaktionsverlauf anzuzeigen, können Sie einen Block-Explorer-API-Schlüssel einrichten:
- Fügen Sie Ihren **Etherscan/BscScan/Polygonscan API-Schlüssel** unter **Einstellungen > Zahlungen > Kryptos** hinzu.
- Ghost unterstützt Etherscan API V2, um Ihre Transaktionshistorie auf unterstützten Netzwerken abzurufen.

---

## 3. Agenten-EVM-Wallet (Autonome Blockchain-Zahlungen)

Sie können einen dedizierten Private Key für das autonome Wallet des Agenten konfigurieren, sodass dieser Token senden und DeFi-Swaps in Ihrem Namen ausführen kann.

### Unterstützte Netzwerke & native Währungen
- **Binance Smart Chain (BSC)**: Chain-ID `56` (natives Token: `BNB`)
- **BSC Testnet**: Chain-ID `97` (natives Token: `tBNB`)
- **Ethereum Mainnet**: Chain-ID `1` (natives Token: `ETH`)
- **Sepolia Testnet**: Chain-ID `11155111` (natives Token: `ETH`)
- **Polygon Mainnet**: Chain-ID `137` (natives Token: `MATIC`)
- **Polygon Amoy Testnet**: Chain-ID `80002` (natives Token: `POL`)

### Verfügbare Blockchain-Tools

#### `wallet_get_balances`
Ruft die EVM-Adresse des Agenten, das native Token-Guthaben und unterstützte ERC-20-Token-Guthaben (USDT, USDC, LINK, MATIC, BNB, CAKE usw.) im aktuell aktiven Netzwerk ab.

#### `execute_blockchain_payment`
Überweist autonome native oder ERC-20-Token an einen Empfänger.
- **Parameter**: `recipient` (EVM-Empfängeradresse), `amount` (Betrag), `symbol` (Token-Symbol, z.B. "USDT"), `chainId` (optional) und `purpose` (Zweck).
- **Validierung**: Ähnlich wie bei Kreditkarten prüft dieses Tool, ob der Transaktionsbetrag innerhalb des virtuellen Budgets liegt. Es aktualisiert die Abrechnungskonfiguration und zieht den Betrag bei Erfolg ab.

#### `execute_token_swap`
Führt Token-Swaps (nativ zu ERC-20, ERC-20 zu nativ oder ERC-20 zu ERC-20) auf DEX-Routern aus:
- PancakeSwap V2 (auf BSC und BSC Testnet)
- QuickSwap (auf Polygon)
- Uniswap (auf Ethereum)
- Genehmigungstransaktionen (Approvals) werden im Hintergrund automatisch abgewickelt.

---

## 4. Binance & Demo-Trading

Ghost integriert die Binance-API, sodass Agenten aktuelle Preisticker abrufen, Guthaben einsehen und Kauf-/Verkaufsaufträge ausführen können.

### Konfiguration
1. Erstellen Sie API-Schlüssel in Ihren **Binance-Kontoeinstellungen**.
2. Tragen Sie diese unter **Einstellungen > Zahlungen > Kryptos > Binance Spot API** oder **Binance Spot Demo API** (für risikofreies Trading) ein.
3. Speichern Sie die Schlüssel in Ihrem sicheren Tresor.

### Verfügbare Binance-Tools

#### `binance_get_ticker`
Ruft Kursinformationen für ein Kryptowährungssymbol (z. B. `BTCUSDT`) ab. Wenn kein Symbol angegeben ist, werden standardmäßig die wichtigsten USDT-Paare zurückgegeben.

#### Live-Spot-Trading-Tools:
- `binance_get_balances`: Fragt Ihr Spot-Guthaben für Vermögenswerte mit einem Betrag größer als Null ab.
- `binance_create_order`: Plaziert eine Kauf- oder Verkaufsorder. Erfordert `symbol` (z. B. `ETHUSDT`), `side` (`BUY`/`SELL`), `type` (`LIMIT`/`MARKET`), `quantity` (Menge) und `price` (Preis, nur für LIMIT-Orders erforderlich).

#### Simulierte Demo-Trading-Tools (Risikofrei):
- `binance_demo_get_balances`: Ruft das simulierte Guthaben über die Binance Spot Demo API ab.
- `binance_demo_create_order`: Plaziert Kauf- oder Verkaufsorders im Demo-Netzwerk, um Agenten zu testen.
