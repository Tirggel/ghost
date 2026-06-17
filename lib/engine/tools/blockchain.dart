import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:logging/logging.dart';
import 'package:http/http.dart' as http;
import 'package:reown_appkit/reown_appkit.dart';

import '../config/secure_storage.dart';
import '../config/io.dart';
import '../agent/manager.dart';
import 'registry.dart';

final _log = Logger('Ghost.Tools.Blockchain');

class BlockchainTools {
  static void registerAll(
    ToolRegistry registry,
    SecureStorage storage,
    AgentManager agentManager,
  ) {
    registry.register(ExecuteBlockchainPaymentTool(storage, agentManager));
    registry.register(ExecuteTokenSwapTool(storage, agentManager));
    registry.register(WalletGetBalancesTool(storage));
  }
}

class ExecuteBlockchainPaymentTool extends Tool {
  ExecuteBlockchainPaymentTool(this.storage, this.agentManager);

  final SecureStorage storage;
  final AgentManager agentManager;

  @override
  String get name => 'execute_blockchain_payment';

  @override
  String get description =>
      'Executes a real crypto payment (native or ERC-20 token) autonomously in the background on behalf of the agent or user. '
      'Requires a recipient EVM address, an amount, and a token symbol. '
      'If the user has not configured their Agent Private Key, this tool will fail with a configuration prompt.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'recipient': {
            'type': 'string',
            'description': 'The EVM recipient address (e.g. "0x773cC5d6486BDaa4E7217C1aEfBE79520e43A90A"). Must be valid.',
          },
          'amount': {
            'type': 'number',
            'description': 'The amount of tokens to send (e.g. 0.05). Must be positive.',
          },
          'symbol': {
            'type': 'string',
            'description': 'The token symbol (e.g. "BNB", "USDT", "ETH", "USDC"). Defaults to the chain native token.',
          },
          'chainId': {
            'type': 'string',
            'description': 'The chain ID (e.g. "56" for BSC, "1" for Ethereum, "137" for Polygon). Defaults to BSC (56).',
          },
          'purpose': {
            'type': 'string',
            'description': 'The reason or purpose for this blockchain transaction.',
          },
        },
        'required': ['recipient', 'amount', 'purpose'],
      };

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final recipient = input['recipient'] as String;
    final amount = (input['amount'] as num).toDouble();
    final symbol = (input['symbol'] as String?)?.toUpperCase() ?? 'BNB';
    final activeChainId = await storage.get('active_chain_id') ?? '56';
    final chainIdStr = input['chainId'] as String? ?? activeChainId;
    final purpose = input['purpose'] as String;

    _log.info('Executing blockchain payment of $amount $symbol to $recipient on chain $chainIdStr. Purpose: $purpose');

    if (amount <= 0) {
      return const ToolResult.error('Invalid amount: must be greater than zero.');
    }

    if (recipient.length != 42 || !recipient.startsWith('0x')) {
      return const ToolResult.error('Invalid recipient address: must be a 42-character hex address.');
    }

    // 1. Fetch private key from secure storage
    var privateKey = await storage.get('agent_wallet_private_key');
    if (privateKey == null || privateKey.trim().isEmpty) {
      privateKey = await storage.get('agent_wallet_private_key_api_key');
    }
    if (privateKey == null || privateKey.trim().isEmpty) {
      return const ToolResult.error(
        'Transaction failed: No Agent Wallet configured. '
        'Please inform the user to configure their Agent Private Key under Settings > Payments > Cryptos.',
      );
    }

    // 2. Validate user virtual budget
    final billing = agentManager.config.billing;
    final currentBalance = billing.balance;
    if (currentBalance < amount) {
      final isDe = agentManager.config.user.language == 'de';
      final alertMsg = isDe
          ? '⚠️ Autonome Blockchain-Zahlung von $amount $symbol fehlgeschlagen: Kontostand (${currentBalance.toStringAsFixed(2)}) reicht nicht aus.'
          : '⚠️ Autonomous blockchain payment of $amount $symbol failed: Account balance (${currentBalance.toStringAsFixed(2)}) is insufficient.';
      _notifyUser(alertMsg);

      return ToolResult.error(
        'Transaction failed: Insufficient virtual budget. '
        'Available budget: ${currentBalance.toStringAsFixed(2)}. '
        'Requested: $amount.',
      );
    }

    // 3. Setup RPC and web3 client
    String rpcUrl = 'https://bsc-dataseed.bnbchain.org'; // BSC default
    if (chainIdStr == '1') {
      rpcUrl = 'https://ethereum.publicnode.com';
    } else if (chainIdStr == '137') {
      rpcUrl = 'https://polygon-rpc.com';
    } else if (chainIdStr == '97') {
      rpcUrl = 'https://bsc-testnet.publicnode.com';
    } else if (chainIdStr == '11155111') {
      rpcUrl = 'https://ethereum-sepolia.publicnode.com';
    } else if (chainIdStr == '80002') {
      rpcUrl = 'https://polygon-amoy.publicnode.com';
    }

    final client = Web3Client(rpcUrl, http.Client());
    
    try {
      final credentials = EthPrivateKey.fromHex(privateKey.trim());
      final agentAddress = credentials.address;

      final isNative = (chainIdStr == '56' && symbol == 'BNB') ||
          (chainIdStr == '97' && (symbol == 'BNB' || symbol == 'TBNB')) ||
          (chainIdStr == '1' && symbol == 'ETH') ||
          (chainIdStr == '11155111' && symbol == 'ETH') ||
          (chainIdStr == '137' && symbol == 'MATIC') ||
          (chainIdStr == '80002' && (symbol == 'MATIC' || symbol == 'POL'));

      final String txHash;
      final String resolvedSymbol;

      if (isNative) {
        resolvedSymbol = symbol;
        final BigInt amountInWei = BigInt.from((amount * math.pow(10, 18)).round());
        
        txHash = await client.sendTransaction(
          credentials,
          Transaction(
            to: EthereumAddress.fromHex(recipient),
            value: EtherAmount.fromBigInt(EtherUnit.wei, amountInWei),
          ),
          chainId: int.parse(chainIdStr),
        );
      } else {
        // ERC-20 Transfer
        final tokenSpec = await _resolveToken(client, chainIdStr, symbol);
        if (tokenSpec == null) {
          return ToolResult.error('Token "$symbol" is not supported or not a valid contract address on Chain "$chainIdStr".');
        }
        resolvedSymbol = tokenSpec['symbol'] as String;

        final BigInt amountInWei = BigInt.from((amount * math.pow(10, tokenSpec['decimals'])).round());
        
        final abi = ContractAbi.fromJson(_erc20Abi, 'ERC20');
        final contract = DeployedContract(abi, EthereumAddress.fromHex(tokenSpec['address']));
        final function = contract.function('transfer');

        txHash = await client.sendTransaction(
          credentials,
          Transaction.callContract(
            contract: contract,
            function: function,
            parameters: [
              EthereumAddress.fromHex(recipient),
              amountInWei,
            ],
          ),
          chainId: int.parse(chainIdStr),
        );
      }

      // 4. Deduct virtual budget
      final newBalance = currentBalance - amount;
      final updatedBilling = billing.copyWith(balance: newBalance);
      final updatedConfig = agentManager.config.copyWith(billing: updatedBilling);
      
      agentManager.config = updatedConfig;
      if (agentManager.configPath != null) {
        await saveConfig(updatedConfig, agentManager.configPath!);
      }
      agentManager.notifyConfigChanged();

      String explorerUrl = 'https://bscscan.com';
      if (chainIdStr == '1') {
        explorerUrl = 'https://etherscan.io';
      } else if (chainIdStr == '137') {
        explorerUrl = 'https://polygonscan.com';
      } else if (chainIdStr == '97') {
        explorerUrl = 'https://testnet.bscscan.com';
      } else if (chainIdStr == '11155111') {
        explorerUrl = 'https://sepolia.etherscan.io';
      } else if (chainIdStr == '80002') {
        explorerUrl = 'https://amoy.polygonscan.com';
      }
      final txLink = '$explorerUrl/tx/$txHash';

      // 5. Notify user
      final isDe = agentManager.config.user.language == 'de';
      final successMsg = isDe
          ? '✅ Autonome Zahlung von $amount $resolvedSymbol an $recipient erfolgreich ausgeführt. TxHash: [$txHash]($txLink)'
          : '✅ Autonomous payment of $amount $resolvedSymbol to $recipient successfully executed. TxHash: [$txHash]($txLink)';
      _notifyUser(successMsg);

      await _recordManualTransactionIfNoPaidApi(
        storage: storage,
        walletAddress: agentAddress.eip55With0x,
        txHash: txHash,
        value: amount,
        fromAddress: agentAddress.eip55With0x,
        toAddress: recipient,
        symbol: resolvedSymbol,
        chainId: chainIdStr,
      );

      return ToolResult(
        output: 'Transaction successful! TxHash: [$txHash]($txLink). Remaining virtual budget: ${newBalance.toStringAsFixed(2)}.',
        metadata: {'txHash': txHash, 'fromAddress': agentAddress.eip55With0x},
      );
    } catch (e) {
      _log.severe('Autonomous payment failed: $e');
      return ToolResult.error('Blockchain payment execution failed: $e');
    } finally {
      await client.dispose();
    }
  }

  void _notifyUser(String message) {
    if (agentManager.channelManager != null) {
      try {
        agentManager.channelManager.sendNotification(message);
      } catch (e) {
        _log.warning('Could not send payment notification via channel: $e');
      }
    }
  }
}

class ExecuteTokenSwapTool extends Tool {
  ExecuteTokenSwapTool(this.storage, this.agentManager);

  final SecureStorage storage;
  final AgentManager agentManager;

  @override
  String get name => 'execute_token_swap';

  @override
  String get description =>
      'Executes a decentralized swap (DEX trade) autonomously on PancakeSwap or Uniswap. '
      'Allows swapping native token to ERC-20, or ERC-20 to ERC-20. '
      'Requires fromToken, toToken, and amount.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'fromToken': {
            'type': 'string',
            'description': 'The token symbol to swap from (e.g. "BNB", "USDT").',
          },
          'toToken': {
            'type': 'string',
            'description': 'The token symbol to swap to (e.g. "USDT", "BNB").',
          },
          'amount': {
            'type': 'number',
            'description': 'The amount of fromToken to swap.',
          },
          'chainId': {
            'type': 'string',
            'description': 'The chain ID (e.g. "56" for BSC, "137" for Polygon). Defaults to "56" (BSC).',
          },
          'purpose': {
            'type': 'string',
            'description': 'The reason or purpose for this swap transaction.',
          },
        },
        'required': ['fromToken', 'toToken', 'amount', 'purpose'],
      };

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final fromToken = (input['fromToken'] as String).toUpperCase();
    final toToken = (input['toToken'] as String).toUpperCase();
    final amount = (input['amount'] as num).toDouble();
    final activeChainId = await storage.get('active_chain_id') ?? '56';
    final chainIdStr = input['chainId'] as String? ?? activeChainId;
    final purpose = input['purpose'] as String;

    _log.info('Executing token swap of $amount $fromToken to $toToken on chain $chainIdStr. Purpose: $purpose');

    if (amount <= 0) {
      return const ToolResult.error('Invalid swap amount: must be greater than zero.');
    }

    var privateKey = await storage.get('agent_wallet_private_key');
    if (privateKey == null || privateKey.trim().isEmpty) {
      privateKey = await storage.get('agent_wallet_private_key_api_key');
    }
    if (privateKey == null || privateKey.trim().isEmpty) {
      return const ToolResult.error(
        'Transaction failed: No Agent Wallet configured. '
        'Please configure your Agent Private Key under Settings > Payments > Cryptos.',
      );
    }

    String rpcUrl = 'https://bsc-dataseed.bnbchain.org'; // BSC default
    String routerAddress = '0x10ED43C718714eb63d5aA57B78B54704E256024E'; // PancakeSwap V2 BSC
    String wNativeAddress = '0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c'; // WBNB BSC

    if (chainIdStr == '137') {
      rpcUrl = 'https://polygon-rpc.com';
      routerAddress = '0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff'; // QuickSwap Router
      wNativeAddress = '0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270'; // WMATIC
    } else if (chainIdStr == '97') {
      rpcUrl = 'https://bsc-testnet.publicnode.com';
      routerAddress = '0x9Ac64Cc6E4415144C455BD8E4837Fea55603e5c3'; // PancakeSwap V2 Testnet
      wNativeAddress = '0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd'; // WBNB Testnet
    }

    final client = Web3Client(rpcUrl, http.Client());

    try {
      final credentials = EthPrivateKey.fromHex(privateKey.trim());
      final agentAddress = credentials.address;

      final isFromNative = (chainIdStr == '56' && fromToken == 'BNB') ||
          (chainIdStr == '97' && (fromToken == 'BNB' || fromToken == 'TBNB')) ||
          (chainIdStr == '137' && fromToken == 'MATIC');

      final isToNative = (chainIdStr == '56' && toToken == 'BNB') ||
          (chainIdStr == '97' && (toToken == 'BNB' || toToken == 'TBNB')) ||
          (chainIdStr == '137' && toToken == 'MATIC');

      // Resolve token addresses
      final String fromAddress;
      final int fromDecimals;
      final String resolvedFromSymbol;
      if (isFromNative) {
        fromAddress = wNativeAddress;
        fromDecimals = 18;
        resolvedFromSymbol = fromToken;
      } else {
        final spec = await _resolveToken(client, chainIdStr, fromToken);
        if (spec == null) return ToolResult.error('Unsupported token: $fromToken');
        fromAddress = spec['address'] as String;
        fromDecimals = spec['decimals'] as int;
        resolvedFromSymbol = spec['symbol'] as String;
      }

      final String toAddress;
      final String resolvedToSymbol;
      if (isToNative) {
        toAddress = wNativeAddress;
        resolvedToSymbol = toToken;
      } else {
        final spec = await _resolveToken(client, chainIdStr, toToken);
        if (spec == null) return ToolResult.error('Unsupported token: $toToken');
        toAddress = spec['address'] as String;
        resolvedToSymbol = spec['symbol'] as String;
      }

      final BigInt amountInWei = BigInt.from((amount * math.pow(10, fromDecimals)).round());
      final deadline = BigInt.from(DateTime.now().millisecondsSinceEpoch ~/ 1000 + 1200);

      // Simple Router ABI supporting swapExactETHForTokens and swapExactTokensForTokens
      final abi = ContractAbi.fromJson(_routerAbi, 'Router');
      final routerContract = DeployedContract(abi, EthereumAddress.fromHex(routerAddress));

      final String txHash;

      if (isFromNative) {
        // Swap BNB/ETH -> ERC-20
        final function = routerContract.function('swapExactETHForTokens');
        txHash = await client.sendTransaction(
          credentials,
          Transaction.callContract(
            contract: routerContract,
            function: function,
            value: EtherAmount.fromBigInt(EtherUnit.wei, amountInWei),
            parameters: [
              BigInt.from(0), // amountOutMin (0 is fine for simple agent tests)
              [EthereumAddress.fromHex(fromAddress), EthereumAddress.fromHex(toAddress)],
              agentAddress,
              deadline,
            ],
          ),
          chainId: int.parse(chainIdStr),
        );
      } else {
        // First: Approve Router to spend our ERC-20 tokens if needed
        final erc20Abi = ContractAbi.fromJson(_erc20Abi, 'ERC20');
        final tokenContract = DeployedContract(erc20Abi, EthereumAddress.fromHex(fromAddress));
        
        // Broadcast approve call
        final approveFunction = tokenContract.function('approve');
        await client.sendTransaction(
          credentials,
          Transaction.callContract(
            contract: tokenContract,
            function: approveFunction,
            parameters: [
              EthereumAddress.fromHex(routerAddress),
              amountInWei,
            ],
          ),
          chainId: int.parse(chainIdStr),
        );

        // Wait a short moment for approval tx indexing
        await Future.delayed(const Duration(seconds: 4));

        // Swap ERC-20 -> BNB/ETH or ERC-20 -> ERC-20
        if (isToNative) {
          final function = routerContract.function('swapExactTokensForETH');
          txHash = await client.sendTransaction(
            credentials,
            Transaction.callContract(
              contract: routerContract,
              function: function,
              parameters: [
                amountInWei,
                BigInt.from(0), // amountOutMin
                [EthereumAddress.fromHex(fromAddress), EthereumAddress.fromHex(toAddress)],
                agentAddress,
                deadline,
              ],
            ),
            chainId: int.parse(chainIdStr),
          );
        } else {
          final function = routerContract.function('swapExactTokensForTokens');
          txHash = await client.sendTransaction(
            credentials,
            Transaction.callContract(
              contract: routerContract,
              function: function,
              parameters: [
                amountInWei,
                BigInt.from(0), // amountOutMin
                [EthereumAddress.fromHex(fromAddress), EthereumAddress.fromHex(toAddress)],
                agentAddress,
                deadline,
              ],
            ),
            chainId: int.parse(chainIdStr),
          );
        }
      }

      String explorerUrl = 'https://bscscan.com';
      if (chainIdStr == '137') {
        explorerUrl = 'https://polygonscan.com';
      } else if (chainIdStr == '97') {
        explorerUrl = 'https://testnet.bscscan.com';
      }
      final txLink = '$explorerUrl/tx/$txHash';

      // Notify user
      final isDe = agentManager.config.user.language == 'de';
      final successMsg = isDe
          ? '🔄 Autonomer Swap von $amount $resolvedFromSymbol in $resolvedToSymbol erfolgreich initiiert. TxHash: [$txHash]($txLink)'
          : '🔄 Autonomous swap of $amount $resolvedFromSymbol to $resolvedToSymbol successfully initiated. TxHash: [$txHash]($txLink)';
      _notifyUser(successMsg);

      await _recordManualTransactionIfNoPaidApi(
        storage: storage,
        walletAddress: agentAddress.eip55With0x,
        txHash: txHash,
        value: amount,
        fromAddress: agentAddress.eip55With0x,
        toAddress: routerAddress,
        symbol: resolvedFromSymbol,
        chainId: chainIdStr,
      );

      return ToolResult(
        output: 'Token swap transaction successfully broadcasted! TxHash: [$txHash]($txLink)',
        metadata: {'txHash': txHash},
      );
    } catch (e) {
      _log.severe('Token swap failed: $e');
      return ToolResult.error('Blockchain swap execution failed: $e');
    } finally {
      await client.dispose();
    }
  }

  void _notifyUser(String message) {
    if (agentManager.channelManager != null) {
      try {
        agentManager.channelManager.sendNotification(message);
      } catch (e) {
        _log.warning('Could not send swap notification via channel: $e');
      }
    }
  }
}

class WalletGetBalancesTool extends Tool {
  WalletGetBalancesTool(this.storage);

  final SecureStorage storage;

  @override
  String get name => 'wallet_get_balances';

  @override
  String get description =>
      'Retrieves the account asset balances of the autonomous agent wallet on the current active chain (or a specified chainId). '
      'Returns the EVM address, native token balance, and supported ERC-20 token balances.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'chainId': {
            'type': 'string',
            'description': 'The chain ID (e.g. "97" for BSC Testnet, "56" for BSC, "137" for Polygon, "1" for Ethereum). Defaults to active chain ID.',
          },
        },
      };

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final activeChainId = await storage.get('active_chain_id') ?? '56';
    final chainIdStr = input['chainId'] as String? ?? activeChainId;

    var privateKey = await storage.get('agent_wallet_private_key');
    if (privateKey == null || privateKey.trim().isEmpty) {
      privateKey = await storage.get('agent_wallet_private_key_api_key');
    }
    if (privateKey == null || privateKey.trim().isEmpty) {
      return const ToolResult.error(
        'Failed to query wallet balances: No Agent Wallet configured. '
        'Please configure your Agent Private Key under Settings > Payments > Cryptos.',
      );
    }

    // Determine RPC URL
    String rpcUrl = 'https://bsc-dataseed.bnbchain.org'; // BSC default
    if (chainIdStr == '1') {
      rpcUrl = 'https://ethereum.publicnode.com';
    } else if (chainIdStr == '137') {
      rpcUrl = 'https://polygon-rpc.com';
    } else if (chainIdStr == '97') {
      rpcUrl = 'https://bsc-testnet.publicnode.com';
    } else if (chainIdStr == '11155111') {
      rpcUrl = 'https://ethereum-sepolia.publicnode.com';
    } else if (chainIdStr == '80002') {
      rpcUrl = 'https://polygon-amoy.publicnode.com';
    }

    final client = Web3Client(rpcUrl, http.Client());

    try {
      final credentials = EthPrivateKey.fromHex(privateKey.trim());
      final agentAddress = credentials.address;

      // 1. Fetch native balance
      final EtherAmount nativeBalance = await client.getBalance(agentAddress);
      final nativeVal = nativeBalance.getValueInUnit(EtherUnit.ether);
      final nativeSymbol = _nativeTokenSymbols[chainIdStr] ?? 'ETH';
      final chainName = _chainNames[chainIdStr] ?? 'Chain ID $chainIdStr';

      final buffer = StringBuffer();
      buffer.writeln('EVM Wallet Address: ${agentAddress.eip55With0x}');
      buffer.writeln('Network: $chainName');
      buffer.writeln('Balances:');
      buffer.writeln('- $nativeSymbol: ${nativeVal.toStringAsFixed(6)}');

      // 2. Fetch supported ERC-20 token balances
      final tokenSpecs = _chainTokenSpecs[chainIdStr] ?? {};
      final erc20AbiObject = ContractAbi.fromJson(_erc20Abi, 'ERC20');

      for (final entry in tokenSpecs.entries) {
        final symbol = entry.key;
        final addressHex = entry.value['address'] as String;
        final decimals = entry.value['decimals'] as int;

        try {
          final contract = DeployedContract(
            erc20AbiObject,
            EthereumAddress.fromHex(addressHex),
          );
          final function = contract.function('balanceOf');
          final response = await client.call(
            contract: contract,
            function: function,
            params: [agentAddress],
          );
          
          if (response.isNotEmpty) {
            final rawBalance = response.first as BigInt;
            final double balance = rawBalance / BigInt.from(10).pow(decimals);
            buffer.writeln('- $symbol: ${balance.toStringAsFixed(4)}');
          } else {
            buffer.writeln('- $symbol: Balance query failed');
          }
        } catch (tokenErr) {
          buffer.writeln('- $symbol: Error querying balance ($tokenErr)');
        }
      }

      return ToolResult(output: buffer.toString());
    } catch (e) {
      _log.severe('Failed to retrieve wallet balances: $e');
      return ToolResult.error('Failed to query wallet balances: $e');
    } finally {
      await client.dispose();
    }
  }
}

// Token specifications dictionaries
final Map<String, Map<String, Map<String, dynamic>>> _chainTokenSpecs = {
  '56': {
    'USDT': {'address': '0x55d398326f99059fF775485246999027B3197955', 'decimals': 18},
    'USDC': {'address': '0x8AC76a51cc950d9822D68b83fE1Ad97B32CD580d', 'decimals': 18},
    'LINK': {'address': '0xF8A3151030485f3850b2ed3fd507e3c8808D53a4', 'decimals': 18},
    'MATIC': {'address': '0xCC427f4fe5873b13027a59A63CEF5fF102B78531', 'decimals': 18},
    'ETH': {'address': '0x2170Ed0880ac9A755fd29B2688956BD959F933F8', 'decimals': 18},
  },
  '137': {
    'USDT': {'address': '0xc2132D05D31c914a87C6611C10748AEb04B58e8F', 'decimals': 6},
    'USDC': {'address': '0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359', 'decimals': 6},
    'LINK': {'address': '0xb0897686c545045aFc77CF20eC7A532E3120E0F1', 'decimals': 18},
    'ETH': {'address': '0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619', 'decimals': 18},
    'BNB': {'address': '0xA649325Aa7C5091d12D4E98aA677c7626e2e5A67', 'decimals': 18},
  },
  '97': {
    'USDT': {'address': '0x337610d27c682E347C9cD60BD4b3b107C9d34dDd', 'decimals': 18},
    'USDC': {'address': '0x64544E66463EC5c8F43f256037C0d71911475A9C', 'decimals': 18},
    'CAKE': {'address': '0x8d008B313C1d6C7fE2982F62d32Da7507cF43551', 'decimals': 18},
  },
  '11155111': {
    'USDT': {'address': '0xaA8E23Fb1079EA71e0a56F48a2aa51851D8433D0', 'decimals': 6},
    'USDC': {'address': '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238', 'decimals': 6},
  },
  '80002': {
    'USDT': {'address': '0x1fdE0e81d154ee464a9c6B90b5220c33aCE4e82f', 'decimals': 6},
    'USDC': {'address': '0x41e945974b7c647a54cd65c92c48b7b137d6e4b4', 'decimals': 6},
  },
};

const Map<String, String> _nativeTokenSymbols = {
  '56': 'BNB',
  '97': 'tBNB',
  '1': 'ETH',
  '11155111': 'ETH',
  '137': 'MATIC',
  '80002': 'POL',
};

const Map<String, String> _chainNames = {
  '56': 'Binance Smart Chain (Mainnet)',
  '97': 'BSC Testnet',
  '1': 'Ethereum Mainnet',
  '11155111': 'Sepolia Testnet',
  '137': 'Polygon Mainnet',
  '80002': 'Polygon Amoy Testnet',
};

Map<String, dynamic>? _getTokenSpec(String chainId, String symbol) {
  final cleanSymbol = symbol.toUpperCase();
  return _chainTokenSpecs[chainId]?[cleanSymbol];
}

Future<Map<String, dynamic>?> _resolveToken(
  Web3Client client,
  String chainId,
  String input,
) async {
  final cleanInput = input.trim();

  // Check if it's a hex address (42 chars, starting with 0x)
  if (cleanInput.length == 42 && cleanInput.startsWith('0x')) {
    try {
      final address = EthereumAddress.fromHex(cleanInput);
      final abi = ContractAbi.fromJson(_erc20Abi, 'ERC20');
      final contract = DeployedContract(abi, address);

      int decimals = 18;
      try {
        final decimalsFn = contract.function('decimals');
        final response = await client.call(
          contract: contract,
          function: decimalsFn,
          params: [],
        );
        if (response.isNotEmpty) {
          decimals = (response.first as BigInt).toInt();
        }
      } catch (_) {
        // Fallback
      }

      String symbol = 'ERC20';
      try {
        final symbolFn = contract.function('symbol');
        final response = await client.call(
          contract: contract,
          function: symbolFn,
          params: [],
        );
        if (response.isNotEmpty) {
          symbol = response.first.toString();
        }
      } catch (_) {
        // Fallback
      }

      return {
        'address': cleanInput,
        'decimals': decimals,
        'symbol': symbol,
      };
    } catch (_) {
      return null;
    }
  }

  // Otherwise, lookup from predefined specs
  final spec = _getTokenSpec(chainId, cleanInput);
  if (spec != null) {
    return {
      'address': spec['address'],
      'decimals': spec['decimals'],
      'symbol': cleanInput.toUpperCase(),
    };
  }

  return null;
}

const String _erc20Abi = '''
[
  {
    "constant": true,
    "inputs": [],
    "name": "decimals",
    "outputs": [
      {
        "name": "",
        "type": "uint8"
      }
    ],
    "payable": false,
    "stateMutability": "view",
    "type": "function"
  },
  {
    "constant": true,
    "inputs": [],
    "name": "symbol",
    "outputs": [
      {
        "name": "",
        "type": "string"
      }
    ],
    "payable": false,
    "stateMutability": "view",
    "type": "function"
  },
  {
    "constant": true,
    "inputs": [
      {
        "name": "_owner",
        "type": "address"
      }
    ],
    "name": "balanceOf",
    "outputs": [
      {
        "name": "balance",
        "type": "uint256"
      }
    ],
    "payable": false,
    "stateMutability": "view",
    "type": "function"
  },
  {
    "constant": false,
    "inputs": [
      {
        "name": "_spender",
        "type": "address"
      },
      {
        "name": "_value",
        "type": "uint256"
      }
    ],
    "name": "approve",
    "outputs": [
      {
        "name": "success",
        "type": "bool"
      }
    ],
    "payable": false,
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "constant": false,
    "inputs": [
      {
        "name": "_to",
        "type": "address"
      },
      {
        "name": "_value",
        "type": "uint256"
      }
    ],
    "name": "transfer",
    "outputs": [
      {
        "name": "success",
        "type": "bool"
      }
    ],
    "payable": false,
    "stateMutability": "nonpayable",
    "type": "function"
  }
]
''';

const String _routerAbi = '''
[
  {
    "inputs": [
      {
        "internalType": "uint256",
        "name": "amountOutMin",
        "type": "uint256"
      },
      {
        "internalType": "address[]",
        "name": "path",
        "type": "address[]"
      },
      {
        "internalType": "address",
        "name": "to",
        "type": "address"
      },
      {
        "internalType": "uint256",
        "name": "deadline",
        "type": "uint256"
      }
    ],
    "name": "swapExactETHForTokens",
    "outputs": [
      {
        "internalType": "uint256[]",
        "name": "amounts",
        "type": "uint256[]"
      }
    ],
    "stateMutability": "payable",
    "type": "function"
  },
  {
    "inputs": [
      {
        "internalType": "uint256",
        "name": "amountIn",
        "type": "uint256"
      },
      {
        "internalType": "uint256",
        "name": "amountOutMin",
        "type": "uint256"
      },
      {
        "internalType": "address[]",
        "name": "path",
        "type": "address[]"
      },
      {
        "internalType": "address",
        "name": "to",
        "type": "address"
      },
      {
        "internalType": "uint256",
        "name": "deadline",
        "type": "uint256"
      }
    ],
    "name": "swapExactTokensForETH",
    "outputs": [
      {
        "internalType": "uint256[]",
        "name": "amounts",
        "type": "uint256[]"
      }
    ],
    "stateMutability": "nonpayable",
    "type": "function"
  },
  {
    "inputs": [
      {
        "internalType": "uint256",
        "name": "amountIn",
        "type": "uint256"
      },
      {
        "internalType": "uint256",
        "name": "amountOutMin",
        "type": "uint256"
      },
      {
        "internalType": "address[]",
        "name": "path",
        "type": "address[]"
      },
      {
        "internalType": "address",
        "name": "to",
        "type": "address"
      },
      {
        "internalType": "uint256",
        "name": "deadline",
        "type": "uint256"
      }
    ],
    "name": "swapExactTokensForTokens",
    "outputs": [
      {
        "internalType": "uint256[]",
        "name": "amounts",
        "type": "uint256[]"
      }
    ],
    "stateMutability": "nonpayable",
    "type": "function"
  }
]
''';

Future<void> _recordManualTransactionIfNoPaidApi({
  required SecureStorage storage,
  required String walletAddress,
  required String txHash,
  required double value,
  required String fromAddress,
  required String toAddress,
  required String symbol,
  required String chainId,
}) async {
  try {
    final apiKey = await storage.get('etherscan_api_key');
    bool hasPaidApi = false;
    if (apiKey != null && apiKey.isNotEmpty) {
      try {
        final checkUrl = 'https://api.etherscan.io/v2/api?chainid=$chainId&module=account&action=txlist&address=$walletAddress&page=1&offset=1&apikey=$apiKey';
        final res = await http.get(Uri.parse(checkUrl)).timeout(const Duration(seconds: 3));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final status = data['status']?.toString();
          final message = data['message']?.toString();
          if (status == '1' || (status == '0' && message == 'No transactions found')) {
            hasPaidApi = true;
          }
        }
      } catch (_) {}
    }

    if (!hasPaidApi) {
      final key = 'manual_txs_${walletAddress.toLowerCase()}';
      final jsonStr = await storage.get(key);
      List<dynamic> txList = [];
      if (jsonStr != null && jsonStr.isNotEmpty) {
        try {
          txList = jsonDecode(jsonStr);
        } catch (_) {}
      }

      final newTx = {
        'hash': txHash,
        'date': DateTime.now().toIso8601String(),
        'from': fromAddress,
        'to': toAddress,
        'value': value,
        'isError': false,
        'isSend': walletAddress.toLowerCase() == fromAddress.toLowerCase(),
        'tokenSymbol': symbol,
      };

      txList.insert(0, newTx);
      await storage.set(key, jsonEncode(txList));
    }
  } catch (e) {
    Logger('Ghost.Tools.Blockchain').warning('Failed to record manual transaction in tool: $e');
  }
}
