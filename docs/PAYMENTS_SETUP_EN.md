# 💳 Payments, Wallet & Binance Setup — Ghost

Ghost features an integrated payment execution, Web3 blockchain integration, and Binance API trading system. This guide explains how to configure and use these features.

---

## 🔒 Security & Safe Practice First

All credentials (credit cards, EVM private keys, and Binance API keys) are **stored locally in your secure encrypted vault** using AES-256-GCM. They are never transmitted to any third-party servers except the direct destination APIs (Binance, RPC nodes, or block explorers).

> [!WARNING]
> While keys are stored securely, prompt injection attacks can theoretically manipulate an agent. Always test your configuration on **test networks** (such as BSC Testnet, Sepolia, Polygon Amoy) or use **Binance Demo Trading** before configuring mainnet private keys or real assets!

---

## 1. Credit Card & Virtual Budget Setup

Ghost allows agents to make payments on behalf of the user using a configured credit card. To protect your real card, Ghost enforces a **Virtual Budget** system.

### Configuration
1. Open the Ghost UI and navigate to **Settings > Payments**.
2. Enter your card details:
   - **Card Number**: 15 or 16 digits.
   - **Expiry Date**: MM/YY format.
   - **CVV/CVC**: 3 or 4 digits.
   - **Cardholder Name**: Name on the card.
3. Set your **Virtual Budget limits**:
   - **Limit**: The absolute maximum budget allocation.
   - **Balance**: The current available virtual budget balance.

### How Payments Work (The `execute_payment` Tool)
When an agent wants to pay for a service (e.g., purchasing an API key or paying for hosting):
1. The agent executes the `execute_payment` tool, specifying the `amount`, `recipient`, and `purpose`.
2. Ghost checks if a credit card is configured and verifies if the virtual **Balance** is sufficient.
3. If the balance is sufficient, the amount is deducted from the virtual balance, the transaction is marked as `SUCCESS`, and the configuration is saved.
4. If the balance is insufficient, the transaction is recorded as `FAILED`, and a notification is sent to the user via their active communication channels.
5. If **Human-In-The-Loop (HITL)** is enabled, Ghost will pause and request explicit YES/NO confirmation in the chat before executing the payment tool. If **Autonomous Billing** is enabled, it executes in the background.

---

## 2. Personal Web3 Wallet (Reown AppKit)

You can connect your decentralized crypto wallets to view balances and transaction history directly in the app.

### Configuration
1. Obtain a **Project ID** from the [Reown Cloud Console](https://cloud.reown.com/) (formerly WalletConnect).
2. Enter the Project ID in **Settings > Payments > Cryptos** under "Reown Project ID".
3. Click **Initialize AppKit**.
4. Use the **Connect Wallet** button to scan the QR code or select your browser wallet.

### Explorer Integration
To display your transaction history, you can configure a block explorer API key:
- Add your **Etherscan/BscScan/Polygonscan API Key** under **Settings > Payments > Cryptos**.
- Ghost supports Etherscan API V2 to fetch your transaction history on supported networks.

---

## 3. Agent EVM Wallet (Autonomous Blockchain Payments)

You can configure a dedicated private key for the agent's autonomous wallet, allowing the agent to send tokens and execute DeFi swaps on your behalf.

### Supported Networks & native currencies
- **Binance Smart Chain (BSC)**: Chain ID `56` (native token: `BNB`)
- **BSC Testnet**: Chain ID `97` (native token: `tBNB`)
- **Ethereum Mainnet**: Chain ID `1` (native token: `ETH`)
- **Sepolia Testnet**: Chain ID `11155111` (native token: `ETH`)
- **Polygon Mainnet**: Chain ID `137` (native token: `MATIC`)
- **Polygon Amoy Testnet**: Chain ID `80002` (native token: `POL`)

### Available Blockchain Tools

#### `wallet_get_balances`
Retrieves the agent's EVM address, native token balances, and supported ERC-20 tokens (USDT, USDC, LINK, MATIC, BNB, CAKE, etc.) on the current active network.

#### `execute_blockchain_payment`
Transfers native or ERC-20 tokens autonomously to a recipient.
- **Parameters**: `recipient` (EVM address), `amount`, `symbol` (token symbol, e.g. "USDT"), `chainId` (optional), and `purpose`.
- **Validation**: Like credit cards, this tool verifies if the transaction amount is within the virtual budget. It updates the billing configuration and deducts the amount on success.

#### `execute_token_swap`
Performs token swaps (native to ERC-20, ERC-20 to native, or ERC-20 to ERC-20) on DEX routers:
- PancakeSwap V2 (on BSC and BSC Testnet)
- QuickSwap (on Polygon)
- Uniswap (on Ethereum)
- Handles approval transactions automatically behind the scenes.

---

## 4. Binance & Demo Trading

Ghost integrates the Binance API, allowing agents to fetch current price tickers, view balances, and execute buy/sell orders.

### Configuration
1. Generate API keys in your **Binance Account Settings**.
2. Enter them under **Settings > Payments > Cryptos > Binance Spot API** or **Binance Spot Demo API** for risk-free trading.
3. Save the keys to your secure vault.

### Available Binance Tools

#### `binance_get_ticker`
Retrieves ticker price information for a cryptocurrency symbol (e.g. `BTCUSDT`). If no symbol is provided, returns default major USDT pairs.

#### Live Spot Trading Tools:
- `binance_get_balances`: Queries your spot balances for assets with non-zero amounts.
- `binance_create_order`: Places a buy/sell order. Requires `symbol` (e.g. `ETHUSDT`), `side` (`BUY`/`SELL`), `type` (`LIMIT`/`MARKET`), `quantity`, and `price` (required for LIMIT orders).

#### Simulated Demo Trading Tools (Risk-Free):
- `binance_demo_get_balances`: Retrieves simulated assets on the Binance Spot Demo API.
- `binance_demo_create_order`: Places buy/sell orders on the Demo network to test agents.
