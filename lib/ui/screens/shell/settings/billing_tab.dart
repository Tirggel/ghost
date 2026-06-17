import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'dart:math' as math;
import 'package:qr_flutter_wc/qr_flutter_wc.dart';
import 'package:http/http.dart' as http;

import '../../../../core/constants.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../../providers/shell_provider.dart';
import '../../../../engine/infra/crypto.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/app_dialogs.dart';
import '../../../widgets/app_snackbar.dart';

class BillingTab extends ConsumerStatefulWidget {
  const BillingTab({super.key, this.onBack, this.onNext, this.topPadding});
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final double? topPadding;

  @override
  ConsumerState<BillingTab> createState() => _BillingTabState();
}

class _BillingTabState extends ConsumerState<BillingTab> with SettingsSaveMixin {
  // Tab index state
  int _currentSubTabIndex = 0;

  // Credit Card Controllers & State
  final _cardNumController = TextEditingController();
  final _cardExpController = TextEditingController();
  final _cardCvvController = TextEditingController();
  final _cardHolderController = TextEditingController();

  final _limitController = TextEditingController();
  final _balanceController = TextEditingController();

  bool _autonomous = false;
  bool _isEditing = false;
  bool _isInit = false;

  String? _cardNumberLast4;
  String? _cardHolderName;
  bool _isLoadingCardDetails = false;

  // Crypto / Reown AppKit State
  final _reownProjectIdController = TextEditingController();
  bool _isLoadingReownConfig = false;
  String? _appKitInitError;
  ReownAppKitModal? _appKitModal;
  bool _isAppKitModalInitializing = false;
  bool _isAppKitConnected = false;
  String? _connectedAddress;
  String? _connectedChainName;
  String? _connectedProvider;

  // ERC-20 Token Balance State
  Timer? _balanceTimer;
  Map<String, double> _tokenBalances = {};
  bool _isFetchingBalances = false;

  // Agent Autonomous Wallet State
  final _agentPrivateKeyController = TextEditingController();
  bool _isLoadingAgentWallet = false;
  String? _agentAddress;
  double _agentBalance = 0.0;
  bool _isFetchingAgentBalance = false;
  Timer? _agentBalanceTimer;
  String _agentActiveChainId = '56';
  bool _showPersonalWallet = false;
  bool _showAgentWallet = false;
  bool _hasSavedPersonalWalletVisibility = false;
  bool _hasSavedAgentWalletVisibility = false;
  
  // Binance State
  final _binanceApiKeyController = TextEditingController();
  final _binanceSecretKeyController = TextEditingController();
  bool _isLoadingBinance = false;
  bool _hasBinanceConfigured = false;
  bool _showBinance = false;
  bool _hasSavedBinanceVisibility = false;

  // Binance Demo State
  final _binanceDemoApiKeyController = TextEditingController();
  final _binanceDemoSecretKeyController = TextEditingController();
  bool _isLoadingBinanceDemo = false;
  bool _hasBinanceDemoConfigured = false;
  bool _showBinanceDemo = false;
  bool _hasSavedBinanceDemoVisibility = false;

  // Block Explorer API Key input controller
  final _explorerApiKeyInputController = TextEditingController();

  // History Expansion States
  bool _showPersonalTxHistory = false;
  bool _showAgentTxHistory = false;
  bool _showBinanceOrders = false;
  bool _showBinanceDemoOrders = false;

  // History Data & Fetch States
  List<Map<String, dynamic>> _personalTransactions = [];
  bool _isFetchingPersonalTransactions = false;
  String? _personalTransactionsError;

  List<Map<String, dynamic>> _agentTransactions = [];
  bool _isFetchingAgentTransactions = false;
  String? _agentTransactionsError;

  List<Map<String, dynamic>> _binanceOrders = [];
  bool _isFetchingBinanceOrders = false;
  String? _binanceOrdersError;

  List<Map<String, dynamic>> _binanceDemoOrders = [];
  bool _isFetchingBinanceDemoOrders = false;
  String? _binanceDemoOrdersError;

  bool _showCardTxHistory = false;
  List<Map<String, dynamic>> _cardTransactions = [];
  bool _isFetchingCardTransactions = false;



  String _getAgentActiveCurrency() {
    if (_agentActiveChainId == '97') return 'tBNB';
    if (_agentActiveChainId == '1' || _agentActiveChainId == '11155111') return 'ETH';
    if (_agentActiveChainId == '137' || _agentActiveChainId == '80002') return 'POL';
    return 'BNB';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final config = ref.read(configProvider);
      _limitController.text = config.billing.limit.toStringAsFixed(2);
      _balanceController.text = config.billing.balance.toStringAsFixed(2);
      _autonomous = config.billing.autonomous;
      _loadCardDetails();
      _loadReownConfig();
      _loadAgentWalletConfig();
      _loadWalletVisibilitySettings();
      _loadBinanceConfig();
      _loadBinanceDemoConfig();

      // Listeners to flag editing changes
      _limitController.addListener(_onTextChanged);
      _balanceController.addListener(_onTextChanged);
      _isInit = true;
    }
  }

  void _onTextChanged() {
    if (!_isEditing) {
      setState(() => _isEditing = true);
    }
  }

  @override
  void dispose() {
    _cardNumController.dispose();
    _cardExpController.dispose();
    _cardCvvController.dispose();
    _cardHolderController.dispose();
    _limitController.dispose();
    _balanceController.dispose();
    _reownProjectIdController.dispose();
    _agentPrivateKeyController.dispose();
    _binanceApiKeyController.dispose();
    _binanceSecretKeyController.dispose();
    _binanceDemoApiKeyController.dispose();
    _binanceDemoSecretKeyController.dispose();
    _explorerApiKeyInputController.dispose();
    _balanceTimer?.cancel();
    _agentBalanceTimer?.cancel();
    if (_appKitModal != null) {
      try {
        _appKitModal!.removeListener(_onAppKitModalUpdate);
        _appKitModal!.dispose();
      } catch (_) {}
    }
    super.dispose();
  }

  // Load and save Credit Card Details
  Future<void> _loadCardDetails() async {
    final config = ref.read(configProvider);
    if (config.vaultKeys.contains('payment_card_number')) {
      setState(() => _isLoadingCardDetails = true);
      try {
        final card = await ref.read(configProvider.notifier).getKey('payment_card_number');
        final holder = await ref.read(configProvider.notifier).getKey('payment_card_holder');
        if (card != null && card.length >= 4) {
          setState(() {
            _cardNumberLast4 = card.substring(card.length - 4);
            _cardHolderName = holder;
          });
        }
      } catch (_) {
        // Suppress
      } finally {
        setState(() => _isLoadingCardDetails = false);
      }
      _fetchCardTransactions();
    } else {
      setState(() {
        _cardNumberLast4 = null;
        _cardHolderName = null;
        _cardTransactions = [];
        _showCardTxHistory = false;
      });
    }
  }

  Future<void> _saveCard() async {
    final numStr = _cardNumController.text.replaceAll(' ', '');
    final expStr = _cardExpController.text;
    final cvvStr = _cardCvvController.text;
    final holderStr = _cardHolderController.text.trim();

    if (numStr.length < 15 || numStr.length > 16) {
      AppSnackBar.showError(context, 'Invalid card number.');
      return;
    }
    if (expStr.length != 5 || !expStr.contains('/')) {
      AppSnackBar.showError(context, 'Invalid expiry date. Use MM/YY format.');
      return;
    }
    if (cvvStr.length < 3 || cvvStr.length > 4) {
      AppSnackBar.showError(context, 'Invalid CVV/CVC.');
      return;
    }
    if (holderStr.isEmpty) {
      AppSnackBar.showError(context, 'Cardholder name is required.');
      return;
    }

    await handleSave(() async {
      final notifier = ref.read(configProvider.notifier);
      await notifier.setKey('payment_card_number', numStr);
      await notifier.setKey('payment_card_expiry', expStr);
      await notifier.setKey('payment_card_cvv', cvvStr);
      await notifier.setKey('payment_card_holder', holderStr);
      await _loadCardDetails();
    }, successMessage: 'settings.billing.card_saved'.tr());
  }

  Future<void> _fetchCardTransactions() async {
    if (!mounted) return;
    setState(() {
      _isFetchingCardTransactions = true;
    });
    try {
      final txsJson = await ref.read(configProvider.notifier).getKey('payment_card_transactions');
      if (txsJson != null && txsJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(txsJson);
        if (mounted) {
          setState(() {
            _cardTransactions = decoded.map((t) => Map<String, dynamic>.from(t)).toList();
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _cardTransactions = [];
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading card transactions: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingCardTransactions = false;
        });
      }
    }
  }

  Future<void> _removeCard() async {
    final confirmed = await AppAlertDialog.showConfirmation(
      context: context,
      title: 'settings.billing.card_removed'.tr(),
      content: 'settings.billing.desc'.tr(),
      confirmLabel: 'common.delete'.tr(),
      isDestructive: true,
    );
    if (confirmed == true) {
      await handleSave(() async {
        final notifier = ref.read(configProvider.notifier);
        await notifier.setKey('payment_card_number', '');
        await notifier.setKey('payment_card_expiry', '');
        await notifier.setKey('payment_card_cvv', '');
        await notifier.setKey('payment_card_holder', '');
        await notifier.setKey('payment_card_transactions', '');
        setState(() {
          _cardNumberLast4 = null;
          _cardHolderName = null;
          _cardNumController.clear();
          _cardExpController.clear();
          _cardCvvController.clear();
          _cardHolderController.clear();
          _cardTransactions = [];
          _showCardTxHistory = false;
        });
      }, successMessage: 'settings.billing.card_removed'.tr());
    }
  }

  // Load and save Reown configuration
  Future<void> _loadReownConfig() async {
    final config = ref.read(configProvider);
    final hasReownKey = config.vaultKeys.contains('reown_project_id') ||
        config.vaultKeys.contains('reown_project_id_api_key');
    if (hasReownKey) {
      setState(() => _isLoadingReownConfig = true);
      try {
        final pid = await ref.read(configProvider.notifier).getKey('reown_project_id');
        if (pid != null && pid.isNotEmpty) {
          setState(() {
            _reownProjectIdController.text = pid;
          });
          _initAppKit(pid);
        }
      } catch (_) {
        // Suppress
      } finally {
        setState(() => _isLoadingReownConfig = false);
      }
    }
  }

  Future<void> _saveReownProjectId() async {
    final pid = _reownProjectIdController.text.trim();
    if (pid.isEmpty) {
      AppSnackBar.showError(context, 'settings.billing.reown_id_required'.tr());
      return;
    }

    await handleSave(() async {
      final notifier = ref.read(configProvider.notifier);
      await notifier.setKey('reown_project_id', pid);
      await _initAppKit(pid);
    }, successMessage: 'settings.billing.settings_saved'.tr());
  }

  // Load and save Agent Wallet configurations
  Future<void> _loadAgentWalletConfig() async {
    try {
      final savedChainId = await ref.read(configProvider.notifier).getKey('active_chain_id');
      if (savedChainId != null && savedChainId.isNotEmpty && mounted) {
        setState(() {
          _agentActiveChainId = savedChainId;
        });
      }
    } catch (e) {
      debugPrint('Error loading active_chain_id: $e');
    }

    final config = ref.read(configProvider);
    final hasAgentWalletKey = config.vaultKeys.contains('agent_wallet_private_key') ||
        config.vaultKeys.contains('agent_wallet_private_key_api_key');
    if (hasAgentWalletKey) {
      if (mounted) {
        setState(() => _isLoadingAgentWallet = true);
      }
      try {
        var privateKey = await ref.read(configProvider.notifier).getKey('agent_wallet_private_key');
        if (privateKey == null || privateKey.trim().isEmpty) {
          privateKey = await ref.read(configProvider.notifier).getKey('agent_wallet_private_key_api_key');
        }
        if (privateKey != null && privateKey.trim().isNotEmpty && mounted) {
          _agentPrivateKeyController.text = privateKey;
          _deriveAgentAddressAndFetchBalance(privateKey);
        }
      } catch (e) {
        debugPrint('Error loading agent wallet key: $e');
      } finally {
        if (mounted) {
          setState(() => _isLoadingAgentWallet = false);
        }
      }
    }
  }

  Future<void> _loadWalletVisibilitySettings() async {
    try {
      final showPersonalVal = await ref.read(configProvider.notifier).getKey('show_personal_wallet');
      final showAgentVal = await ref.read(configProvider.notifier).getKey('show_agent_wallet');
      final showBinanceVal = await ref.read(configProvider.notifier).getKey('show_binance');
      final showBinanceDemoVal = await ref.read(configProvider.notifier).getKey('show_binance_demo');
      if (mounted) {
        setState(() {
          _hasSavedPersonalWalletVisibility = showPersonalVal != null;
          _hasSavedAgentWalletVisibility = showAgentVal != null;
          _hasSavedBinanceVisibility = showBinanceVal != null;
          _hasSavedBinanceDemoVisibility = showBinanceDemoVal != null;

          if (_hasSavedPersonalWalletVisibility) {
            _showPersonalWallet = showPersonalVal == 'true';
          } else {
            _showPersonalWallet = _isAppKitConnected;
          }

          if (_hasSavedAgentWalletVisibility) {
            _showAgentWallet = showAgentVal == 'true';
          } else {
            final config = ref.read(configProvider);
            final hasAgentKey = config.vaultKeys.contains('agent_wallet_private_key') ||
                config.vaultKeys.contains('agent_wallet_private_key_api_key');
            _showAgentWallet = hasAgentKey;
          }

          if (_hasSavedBinanceVisibility) {
            _showBinance = showBinanceVal == 'true';
          } else {
            final config = ref.read(configProvider);
            final hasBinance = config.vaultKeys.contains('binance_api_key') &&
                config.vaultKeys.contains('binance_secret_key');
            _showBinance = hasBinance;
          }

          if (_hasSavedBinanceDemoVisibility) {
            _showBinanceDemo = showBinanceDemoVal == 'true';
          } else {
            final config = ref.read(configProvider);
            final hasBinanceDemo = config.vaultKeys.contains('binance_demo_api_key') &&
                config.vaultKeys.contains('binance_demo_secret_key');
            _showBinanceDemo = hasBinanceDemo;
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading wallet visibility settings: $e');
    }
  }


  Future<void> _saveWalletVisibilitySetting(String key, bool value) async {
    try {
      await ref.read(configProvider.notifier).setKey(key, value.toString());
      if (mounted) {
        setState(() {
          if (key == 'show_personal_wallet') {
            _showPersonalWallet = value;
            _hasSavedPersonalWalletVisibility = true;
          } else if (key == 'show_agent_wallet') {
            _showAgentWallet = value;
            _hasSavedAgentWalletVisibility = true;
          } else if (key == 'show_binance') {
            _showBinance = value;
            _hasSavedBinanceVisibility = true;
          } else if (key == 'show_binance_demo') {
            _showBinanceDemo = value;
            _hasSavedBinanceDemoVisibility = true;
          }
        });
      }
    } catch (e) {
      debugPrint('Error saving wallet visibility setting: $e');
    }
  }

  Future<void> _loadBinanceConfig() async {
    final config = ref.read(configProvider);
    final hasBinanceApiKey = config.vaultKeys.contains('binance_api_key');
    final hasBinanceSecretKey = config.vaultKeys.contains('binance_secret_key');

    if (hasBinanceApiKey || hasBinanceSecretKey) {
      if (mounted) {
        setState(() => _isLoadingBinance = true);
      }
      try {
        final apiKey = await ref.read(configProvider.notifier).getKey('binance_api_key');
        final secretKey = await ref.read(configProvider.notifier).getKey('binance_secret_key');
        if (mounted) {
          if (apiKey != null && apiKey.isNotEmpty) {
            _binanceApiKeyController.text = apiKey;
          }
          if (secretKey != null && secretKey.isNotEmpty) {
            _binanceSecretKeyController.text = secretKey;
          }
          _hasBinanceConfigured = (apiKey != null && apiKey.isNotEmpty) &&
                                  (secretKey != null && secretKey.isNotEmpty);
          if (_hasBinanceConfigured) {
            _fetchBinanceOrders();
          }
        }
      } catch (e) {
        debugPrint('Error loading Binance config: $e');
      } finally {
        if (mounted) {
          setState(() => _isLoadingBinance = false);
        }
      }
    }
  }

  Future<void> _saveBinanceConfig() async {
    final apiKey = _binanceApiKeyController.text.trim();
    final secretKey = _binanceSecretKeyController.text.trim();

    if (apiKey.isEmpty || secretKey.isEmpty) {
      AppSnackBar.showError(context, 'settings.billing.binance_error_empty'.tr());
      return;
    }

    await handleSave(() async {
      final notifier = ref.read(configProvider.notifier);
      await notifier.setKey('binance_api_key', apiKey);
      await notifier.setKey('binance_secret_key', secretKey);
      setState(() {
        _hasBinanceConfigured = true;
        if (!_hasSavedBinanceVisibility) {
          _showBinance = true;
        }
      });
      _fetchBinanceOrders();
    }, successMessage: 'settings.billing.binance_saved'.tr());
  }

  Future<void> _removeBinanceConfig() async {
    final confirmed = await AppAlertDialog.showConfirmation(
      context: context,
      title: 'settings.billing.binance_remove_title'.tr(),
      content: 'settings.billing.binance_remove_content'.tr(),
      confirmLabel: 'common.delete'.tr(),
      isDestructive: true,
    );

    if (confirmed == true) {
      await handleSave(() async {
        final notifier = ref.read(configProvider.notifier);
        await notifier.setKey('binance_api_key', '');
        await notifier.setKey('binance_secret_key', '');
        _binanceApiKeyController.clear();
        _binanceSecretKeyController.clear();
        setState(() {
          _hasBinanceConfigured = false;
          if (!_hasSavedBinanceVisibility) {
            _showBinance = false;
          }
        });
      }, successMessage: 'settings.billing.binance_removed'.tr());
    }
  }

  Future<void> _loadBinanceDemoConfig() async {
    final config = ref.read(configProvider);
    final hasBinanceDemoApiKey = config.vaultKeys.contains('binance_demo_api_key');
    final hasBinanceDemoSecretKey = config.vaultKeys.contains('binance_demo_secret_key');

    if (hasBinanceDemoApiKey || hasBinanceDemoSecretKey) {
      if (mounted) {
        setState(() => _isLoadingBinanceDemo = true);
      }
      try {
        final apiKey = await ref.read(configProvider.notifier).getKey('binance_demo_api_key');
        final secretKey = await ref.read(configProvider.notifier).getKey('binance_demo_secret_key');
        if (mounted) {
          if (apiKey != null && apiKey.isNotEmpty) {
            _binanceDemoApiKeyController.text = apiKey;
          }
          if (secretKey != null && secretKey.isNotEmpty) {
            _binanceDemoSecretKeyController.text = secretKey;
          }
          _hasBinanceDemoConfigured = (apiKey != null && apiKey.isNotEmpty) &&
                                  (secretKey != null && secretKey.isNotEmpty);
          if (_hasBinanceDemoConfigured) {
            _fetchBinanceDemoOrders();
          }
        }
      } catch (e) {
        debugPrint('Error loading Binance Demo config: $e');
      } finally {
        if (mounted) {
          setState(() => _isLoadingBinanceDemo = false);
        }
      }
    }
  }

  Future<void> _saveBinanceDemoConfig() async {
    final apiKey = _binanceDemoApiKeyController.text.trim();
    final secretKey = _binanceDemoSecretKeyController.text.trim();

    if (apiKey.isEmpty || secretKey.isEmpty) {
      AppSnackBar.showError(context, 'settings.billing.binance_error_empty'.tr());
      return;
    }

    await handleSave(() async {
      final notifier = ref.read(configProvider.notifier);
      await notifier.setKey('binance_demo_api_key', apiKey);
      await notifier.setKey('binance_demo_secret_key', secretKey);
      setState(() {
        _hasBinanceDemoConfigured = true;
        if (!_hasSavedBinanceDemoVisibility) {
          _showBinanceDemo = true;
        }
      });
      _fetchBinanceDemoOrders();
    }, successMessage: 'settings.billing.binance_demo_saved'.tr());
  }

  Future<void> _removeBinanceDemoConfig() async {
    final confirmed = await AppAlertDialog.showConfirmation(
      context: context,
      title: 'settings.billing.binance_demo_remove_title'.tr(),
      content: 'settings.billing.binance_demo_remove_content'.tr(),
      confirmLabel: 'common.delete'.tr(),
      isDestructive: true,
    );

    if (confirmed == true) {
      await handleSave(() async {
        final notifier = ref.read(configProvider.notifier);
        await notifier.setKey('binance_demo_api_key', '');
        await notifier.setKey('binance_demo_secret_key', '');
        _binanceDemoApiKeyController.clear();
        _binanceDemoSecretKeyController.clear();
        setState(() {
          _hasBinanceDemoConfigured = false;
          if (!_hasSavedBinanceDemoVisibility) {
            _showBinanceDemo = false;
          }
        });
      }, successMessage: 'settings.billing.binance_demo_removed'.tr());
    }
  }

  String _cleanChainId(String chainId) {
    if (chainId.contains(':')) {
      return chainId.split(':').last;
    }
    return chainId;
  }

  List<Map<String, dynamic>> _getMockBinanceOrders({required bool isDemo}) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return [
      {
        'symbol': 'BTCUSDT',
        'orderId': 2008103 + (isDemo ? 1000 : 0),
        'price': '64850.00',
        'origQty': '0.01500',
        'executedQty': '0.01500',
        'cummulativeQuoteQty': '972.75',
        'status': 'FILLED',
        'type': 'MARKET',
        'side': 'BUY',
        'time': timestamp - 3600000 * 2, // 2 hours ago
      },
      {
        'symbol': 'BNBUSDT',
        'orderId': 2008104 + (isDemo ? 1000 : 0),
        'price': '585.50',
        'origQty': '1.20000',
        'executedQty': '0.00000',
        'cummulativeQuoteQty': '0.00',
        'status': 'NEW',
        'type': 'LIMIT',
        'side': 'BUY',
        'time': timestamp - 3600000 * 5, // 5 hours ago
      },
      {
        'symbol': 'ETHUSDT',
        'orderId': 2008105 + (isDemo ? 1000 : 0),
        'price': '3420.00',
        'origQty': '0.50000',
        'executedQty': '0.50000',
        'cummulativeQuoteQty': '1710.00',
        'status': 'FILLED',
        'type': 'LIMIT',
        'side': 'SELL',
        'time': timestamp - 3600000 * 24 * 1, // 1 day ago
      },
      {
        'symbol': 'BTCUSDT',
        'orderId': 2008106 + (isDemo ? 1000 : 0),
        'price': '66100.00',
        'origQty': '0.02000',
        'executedQty': '0.00000',
        'cummulativeQuoteQty': '0.00',
        'status': 'CANCELED',
        'type': 'LIMIT',
        'side': 'SELL',
        'time': timestamp - 3600000 * 24 * 3, // 3 days ago
      },
    ];
  }

  List<Map<String, dynamic>> _getMockEvmTransactions({required String address}) {
    final now = DateTime.now();
    return [
      {
        'hash': '0xa28dfb8893ec5c8f43f256037c0d71911475a9c086dff115e51111ea3a620023a',
        'date': now.subtract(const Duration(minutes: 45)),
        'from': address,
        'to': '0x773cC5d6486BDaa4E7217C1aEfBE79520e43A90A',
        'value': 0.125,
        'isError': false,
        'isSend': true,
        'tokenSymbol': 'BNB',
      },
      {
        'hash': '0x4f12d8a4e58b1cd32da7507cf4355156bc21e7890a5e0829caced8ffdd4de3c',
        'date': now.subtract(const Duration(hours: 4)),
        'from': '0x8AC76a51cc950d9822D68b83fE1Ad97B32CD580d',
        'to': address,
        'value': 25.0,
        'isError': false,
        'isSend': false,
        'tokenSymbol': 'USDT',
      },
      {
        'hash': '0x15f10b8ef421c99d1db9a6444d3adf1270ae13d989dac2f0debff460ac112a83',
        'date': now.subtract(const Duration(days: 1, hours: 2)),
        'from': address,
        'to': '0x10ED43C718714eb63d5aA57B78B54704E256024E',
        'value': 0.05,
        'isError': false,
        'isSend': true,
        'tokenSymbol': 'BNB',
      },
      {
        'hash': '0xc2132d05d31c914a87c6611c10748aeb04b58e8fc7ebd1ea3a620022d129a086',
        'date': now.subtract(const Duration(days: 3)),
        'from': address,
        'to': '0x337610d27c682E347C9cD60BD4b3b107C9d34dDd',
        'value': 0.005,
        'isError': true,
        'isSend': true,
        'tokenSymbol': 'BNB',
      },
    ];
  }

  Future<List<Map<String, dynamic>>> _fetchEvmTransactionsFromExplorer(
    String address,
    String chainId, {
    int retryCount = 0,
  }) async {
    // Etherscan API V2 uses a unified endpoint with the chainid parameter for all networks.
    final String host = 'https://api.etherscan.io/v2/api';
    final String apiKeyName = 'etherscan_api_key';
    
    if (chainId != '56' && chainId != '97' && chainId != '1' && chainId != '11155111' && chainId != '137' && chainId != '80002') {
      throw Exception('Unsupported network chain ID: $chainId');
    }

    // Try to load key from secure storage
    final String? apiKey = await ref.read(configProvider.notifier).getKey(apiKeyName);

    final apiKeyParam = (apiKey != null && apiKey.isNotEmpty) ? '&apikey=$apiKey' : '';
    final url = '$host?chainid=$chainId&module=account&action=txlist&address=$address&startblock=0&endblock=99999999&page=1&offset=15&sort=desc$apiKeyParam';
    
    debugPrint('Querying explorer URL: ${url.replaceAll(apiKey ?? '', '***')}');
    final response = await http.get(Uri.parse(url));

    if (response.statusCode != 200) {
      throw Exception('HTTP error status ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final status = data['status']?.toString();
    final message = data['message']?.toString();
    final result = data['result'];

    if (status == '1' && result is List) {
      final List<dynamic> list = result;
      return list.map((tx) {
        final valueInWei = BigInt.tryParse(tx['value']?.toString() ?? '0') ?? BigInt.zero;
        final value = valueInWei / BigInt.from(10).pow(18);
        
        String nativeSymbol = 'ETH';
        if (chainId == '56' || chainId == '97') {
          nativeSymbol = 'BNB';
        } else if (chainId == '137' || chainId == '80002') {
          nativeSymbol = 'POL';
        }

        return {
          'hash': tx['hash']?.toString() ?? '',
          'date': DateTime.fromMillisecondsSinceEpoch(
            (int.tryParse(tx['timeStamp']?.toString() ?? '0') ?? 0) * 1000,
          ),
          'from': tx['from']?.toString() ?? '',
          'to': tx['to']?.toString() ?? '',
          'value': value,
          'isError': tx['isError']?.toString() == '1',
          'isSend': tx['from']?.toString().toLowerCase() == address.toLowerCase(),
          'tokenSymbol': nativeSymbol,
        };
      }).toList();
    } else if (status == '0' && (message == 'No transactions found' || (result is List && result.isEmpty))) {
      return <Map<String, dynamic>>[];
    } else {
      final isRateLimit = (message == 'NOTOK' && result?.toString().toLowerCase().contains('rate limit') == true);
      if (isRateLimit && retryCount < 2) {
        debugPrint('Rate limited by block explorer API. Retrying in 3.5 seconds... (Attempt ${retryCount + 1})');
        await Future.delayed(const Duration(milliseconds: 3500));
        return _fetchEvmTransactionsFromExplorer(address, chainId, retryCount: retryCount + 1);
      }

      final resultStr = result?.toString() ?? '';
      if (resultStr.contains('deprecated V1 endpoint') || resultStr.contains('Free API access is not supported')) {
        if (chainId == '56' || chainId == '97') {
          if (apiKey != null && apiKey.isNotEmpty) {
            throw Exception('Für die BNB Smart Chain und das Binance Testnet ist ein kostenpflichtiges Etherscan API V2-Abonnement (z. B. der günstige Lite-Tarif) erforderlich. Der konfigurierte API-Key "$apiKeyName" wird vom Explorer abgelehnt.');
          } else {
            throw Exception('Für die BNB Smart Chain und das Binance Testnet ist ein kostenpflichtiges Etherscan API V2-Abonnement (z. B. der günstige Lite-Tarif) erforderlich. Bitte geben Sie Ihren API-Key für "$apiKeyName" ein.');
          }
        }
        if (apiKey != null && apiKey.isNotEmpty) {
          throw Exception('Der konfigurierte API-Key "$apiKeyName" wird vom Explorer für dieses Netzwerk abgelehnt oder erfordert ein Upgrade.');
        } else {
          throw Exception('API Key für Block-Explorer erforderlich. Bitte geben Sie Ihren Key für "$apiKeyName" ein.');
        }
      }

      String errorMsg = message ?? 'API error response';
      if (resultStr.isNotEmpty) {
        errorMsg = '$errorMsg: $resultStr';
      }
      throw Exception(errorMsg);
    }
  }

  String? _getExplorerApiKeyNameForChain(String chainId) {
    if (chainId == '56' || chainId == '97' || chainId == '1' || chainId == '11155111' || chainId == '137' || chainId == '80002') {
      return 'etherscan_api_key';
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> _loadManualTransactions(String address) async {
    try {
      final key = 'manual_txs_${address.toLowerCase()}';
      final jsonStr = await ref.read(configProvider.notifier).getKey(key);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        return decoded.map((tx) {
          return {
            'hash': tx['hash']?.toString() ?? '',
            'date': DateTime.tryParse(tx['date']?.toString() ?? '') ?? DateTime.now(),
            'from': tx['from']?.toString() ?? '',
            'to': tx['to']?.toString() ?? '',
            'value': double.tryParse(tx['value']?.toString() ?? '0.0') ?? 0.0,
            'isError': tx['isError'] == true,
            'isSend': tx['isSend'] == true,
            'tokenSymbol': tx['tokenSymbol']?.toString() ?? 'ETH',
          };
        }).toList();
      }
    } catch (e) {
      debugPrint('Error loading manual transactions: $e');
    }
    return <Map<String, dynamic>>[];
  }

  Future<void> _saveManualTransaction(String address, Map<String, dynamic> tx) async {
    try {
      final key = 'manual_txs_${address.toLowerCase()}';
      final existing = await _loadManualTransactions(address);
      existing.insert(0, tx);
      final serialized = existing.map((t) => {
        'hash': t['hash'],
        'date': (t['date'] as DateTime).toIso8601String(),
        'from': t['from'],
        'to': t['to'],
        'value': t['value'],
        'isError': t['isError'],
        'isSend': t['isSend'],
        'tokenSymbol': t['tokenSymbol'],
      }).toList();
      await ref.read(configProvider.notifier).setKey(key, jsonEncode(serialized));
    } catch (e) {
      debugPrint('Error saving manual transaction: $e');
    }
  }

  void _showAddManualTransactionDialog(String address, String chainId, {required bool isAgent}) {
    final nativeSymbol = (chainId == '56' || chainId == '97')
        ? 'BNB'
        : (chainId == '137' || chainId == '80002')
            ? 'POL'
            : 'ETH';

    bool isSend = true;
    final amountController = TextEditingController();
    final addressController = TextEditingController();
    final hashController = TextEditingController();
    final symbolController = TextEditingController(text: nativeSymbol);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.background,
              shape: const RoundedRectangleBorder(
                side: BorderSide(color: AppColors.border),
                borderRadius: BorderRadius.zero,
              ),
              title: Text(
                'settings.billing.add_manual_tx_title'.tr().toUpperCase(),
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppFormLabel('settings.billing.tx_type'.tr()),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setDialogState(() => isSend = true),
                            child: Container(
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: isSend ? AppColors.primary : AppColors.border,
                                ),
                                color: isSend
                                    ? AppColors.primary.withValues(alpha: 0.1)
                                    : AppColors.surface,
                              ),
                              child: const Text(
                                'SEND',
                                style: TextStyle(
                                  color: AppColors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () => setDialogState(() => isSend = false),
                            child: Container(
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: !isSend ? AppColors.primary : AppColors.border,
                                ),
                                color: !isSend
                                    ? AppColors.primary.withValues(alpha: 0.1)
                                    : AppColors.surface,
                              ),
                              child: const Text(
                                'RECEIVE',
                                style: TextStyle(
                                  color: AppColors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    AppFormLabel(
                      isSend ? 'settings.billing.tx_recipient'.tr() : 'settings.billing.tx_sender'.tr(),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: addressController,
                      style: const TextStyle(color: AppColors.white, fontSize: 13),
                      decoration: AppInputDecoration.compact(
                        hint: '0x...',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppFormLabel('settings.billing.tx_amount'.tr()),
                              const SizedBox(height: 6),
                              TextField(
                                controller: amountController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: const TextStyle(color: AppColors.white, fontSize: 13),
                                decoration: AppInputDecoration.compact(
                                  hint: '0.0',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const AppFormLabel('Asset'),
                              const SizedBox(height: 6),
                              TextField(
                                controller: symbolController,
                                style: const TextStyle(color: AppColors.white, fontSize: 13),
                                decoration: AppInputDecoration.compact(
                                  hint: nativeSymbol,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    AppFormLabel('settings.billing.tx_hash_label'.tr()),
                    const SizedBox(height: 6),
                    TextField(
                      controller: hashController,
                      style: const TextStyle(color: AppColors.white, fontSize: 13),
                      decoration: AppInputDecoration.compact(
                        hint: '0x...',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'settings.billing.tx_cancel'.tr().toUpperCase(),
                    style: const TextStyle(color: AppColors.textDim, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final val = double.tryParse(amountController.text.trim()) ?? 0.0;
                    final targetAddr = addressController.text.trim();
                    if (targetAddr.isEmpty || val <= 0) {
                      return;
                    }

                    final symbol = symbolController.text.trim().toUpperCase();
                    final fromAddress = isSend ? address : targetAddr;
                    final toAddress = isSend ? targetAddr : address;
                    final enteredHash = hashController.text.trim();
                    
                    final finalHash = enteredHash.isNotEmpty
                        ? enteredHash
                        : '0x${List.generate(32, (i) => math.Random().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';

                    final tx = {
                      'hash': finalHash,
                      'date': DateTime.now(),
                      'from': fromAddress,
                      'to': toAddress,
                      'value': val,
                      'isError': false,
                      'isSend': isSend,
                      'tokenSymbol': symbol.isNotEmpty ? symbol : nativeSymbol,
                    };

                    await _saveManualTransaction(address, tx);
                    
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }

                    if (isAgent) {
                      _fetchAgentWalletTransactions();
                    } else {
                      _fetchPersonalWalletTransactions();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.white,
                    foregroundColor: AppColors.black,
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  ),
                  child: Text(
                    'settings.billing.tx_save'.tr().toUpperCase(),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAddManualTransactionRow(String address, String chainId, {required bool isAgent}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          height: 32,
          child: ElevatedButton.icon(
            onPressed: () => _showAddManualTransactionDialog(address, chainId, isAgent: isAgent),
            icon: const Icon(Icons.add_rounded, size: 14),
            label: Text(
              'settings.billing.add_manual_tx'.tr().toUpperCase(),
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.background,
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.border),
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _deduplicateTransactions(List<Map<String, dynamic>> txs) {
    final seen = <String>{};
    final List<Map<String, dynamic>> result = [];
    for (final tx in txs) {
      final hash = tx['hash']?.toString().toLowerCase() ?? '';
      if (hash.isEmpty) {
        result.add(tx);
      } else if (seen.add(hash)) {
        result.add(tx);
      }
    }
    return result;
  }

  Future<void> _fetchPersonalWalletTransactions() async {
    if (_connectedAddress == null) return;
    
    setState(() {
      _isFetchingPersonalTransactions = true;
      _personalTransactionsError = null;
    });

    try {
      final chainId = _cleanChainId(_appKitModal?.selectedChain?.chainId ?? '56');
      final txs = await _fetchEvmTransactionsFromExplorer(_connectedAddress!, chainId);
      final manualTxs = await _loadManualTransactions(_connectedAddress!);
      if (mounted) {
        setState(() {
          _personalTransactions = _deduplicateTransactions([...manualTxs, ...txs]);
          _isFetchingPersonalTransactions = false;
        });
      }
    } catch (e) {
      debugPrint('Personal transactions fetch failed, using mock fallback: $e');
      final manualTxs = await _loadManualTransactions(_connectedAddress!);
      final chainId = _cleanChainId(_appKitModal?.selectedChain?.chainId ?? '56');
      final useMock = (chainId != '56' && chainId != '97');
      if (mounted) {
        setState(() {
          _personalTransactions = _deduplicateTransactions([
            ...manualTxs,
            if (useMock) ..._getMockEvmTransactions(address: _connectedAddress!),
          ]);
          _isFetchingPersonalTransactions = false;
          _personalTransactionsError = e.toString();
        });
      }
    }
  }

  Future<void> _fetchAgentWalletTransactions() async {
    if (_agentAddress == null) return;

    setState(() {
      _isFetchingAgentTransactions = true;
      _agentTransactionsError = null;
    });

    try {
      final txs = await _fetchEvmTransactionsFromExplorer(_agentAddress!, _agentActiveChainId);
      final manualTxs = await _loadManualTransactions(_agentAddress!);
      if (mounted) {
        setState(() {
          _agentTransactions = _deduplicateTransactions([...manualTxs, ...txs]);
          _isFetchingAgentTransactions = false;
        });
      }
    } catch (e) {
      debugPrint('Agent transactions fetch failed, using mock fallback: $e');
      final manualTxs = await _loadManualTransactions(_agentAddress!);
      final useMock = (_agentActiveChainId != '56' && _agentActiveChainId != '97');
      if (mounted) {
        setState(() {
          _agentTransactions = _deduplicateTransactions([
            ...manualTxs,
            if (useMock) ..._getMockEvmTransactions(address: _agentAddress!),
          ]);
          _isFetchingAgentTransactions = false;
          _agentTransactionsError = e.toString();
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchBinanceOrdersFromApi(String apiKey, String secretKey, {required bool isDemo}) async {
    final baseUrl = isDemo ? 'https://demo-api.binance.com' : 'https://api.binance.com';
    
    // Default list of symbols to always check
    final Set<String> symbols = {
      'BNBUSDT', 'BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'JTOUSDT',
      'USDTUSD', 'BNBUSD', 'BTCUSD', 'ETHUSD', 'SOLUSD',
    };

    // Try to get account assets to dynamically discover symbols from assets with balances
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final accountQuery = 'timestamp=$timestamp';
      final signature = hmacSha256(secretKey, accountQuery);
      final accountUrl = '$baseUrl/api/v3/account?$accountQuery&signature=$signature';
      
      final response = await http.get(
        Uri.parse(accountUrl),
        headers: {
          'X-MBX-APIKEY': apiKey,
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Binance API authentication failed: Status ${response.statusCode} - ${response.body}');
      }

      final data = jsonDecode(response.body);
      final balances = data['balances'] as List<dynamic>? ?? [];
      for (final b in balances) {
        final asset = b['asset'] as String? ?? '';
        if (asset.isEmpty) continue;
        final free = double.tryParse(b['free']?.toString() ?? '0') ?? 0.0;
        final locked = double.tryParse(b['locked']?.toString() ?? '0') ?? 0.0;
        if (free > 0 || locked > 0) {
          if (asset != 'USDT' && asset != 'USD') {
            symbols.add('${asset}USDT');
            symbols.add('${asset}USD');
            symbols.add('${asset}BTC');
          }
        }
      }
    } catch (e) {
      debugPrint('Binance account balance discovery failed: $e');
      // Re-throw if this is a general credential or auth failure
      if (e.toString().contains('authentication failed') || e.toString().contains('API query failed')) {
        rethrow;
      }
    }

    final List<Map<String, dynamic>> allOrders = [];
    final requests = symbols.map((symbol) async {
      try {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final query = 'symbol=$symbol&timestamp=$timestamp';
        final signature = hmacSha256(secretKey, query);
        final url = '$baseUrl/api/v3/allOrders?$query&signature=$signature';
        
        final response = await http.get(
          Uri.parse(url),
          headers: {
            'X-MBX-APIKEY': apiKey,
          },
        );
        if (response.statusCode == 200) {
          final List<dynamic> orders = jsonDecode(response.body);
          return orders.cast<Map<String, dynamic>>();
        } else {
          return <Map<String, dynamic>>[];
        }
      } catch (e) {
        return <Map<String, dynamic>>[];
      }
    });

    final results = await Future.wait(requests);
    for (final list in results) {
      allOrders.addAll(list);
    }

    allOrders.sort((a, b) {
      final tA = a['time'] as int? ?? 0;
      final tB = b['time'] as int? ?? 0;
      return tB.compareTo(tA);
    });

    return allOrders;
  }

  Future<void> _fetchBinanceOrders() async {
    if (!_hasBinanceConfigured) {
      setState(() {
        _binanceOrders = _getMockBinanceOrders(isDemo: false);
        _isFetchingBinanceOrders = false;
        _binanceOrdersError = null;
      });
      return;
    }

    setState(() {
      _isFetchingBinanceOrders = true;
      _binanceOrdersError = null;
    });

    try {
      final apiKey = _binanceApiKeyController.text.trim();
      final secretKey = _binanceSecretKeyController.text.trim();
      final orders = await _fetchBinanceOrdersFromApi(apiKey, secretKey, isDemo: false);
      if (mounted) {
        setState(() {
          _binanceOrders = orders;
          _isFetchingBinanceOrders = false;
        });
      }
    } catch (e) {
      debugPrint('Binance orders query failed, falling back to mock: $e');
      if (mounted) {
        setState(() {
          _binanceOrders = _getMockBinanceOrders(isDemo: false);
          _isFetchingBinanceOrders = false;
          _binanceOrdersError = e.toString();
        });
      }
    }
  }

  Future<void> _fetchBinanceDemoOrders() async {
    if (!_hasBinanceDemoConfigured) {
      setState(() {
        _binanceDemoOrders = _getMockBinanceOrders(isDemo: true);
        _isFetchingBinanceDemoOrders = false;
        _binanceDemoOrdersError = null;
      });
      return;
    }

    setState(() {
      _isFetchingBinanceDemoOrders = true;
      _binanceDemoOrdersError = null;
    });

    try {
      final apiKey = _binanceDemoApiKeyController.text.trim();
      final secretKey = _binanceDemoSecretKeyController.text.trim();
      final orders = await _fetchBinanceOrdersFromApi(apiKey, secretKey, isDemo: true);
      if (mounted) {
        setState(() {
          _binanceDemoOrders = orders;
          _isFetchingBinanceDemoOrders = false;
        });
      }
    } catch (e) {
      debugPrint('Binance Demo orders query failed, falling back to mock: $e');
      if (mounted) {
        setState(() {
          _binanceDemoOrders = _getMockBinanceOrders(isDemo: true);
          _isFetchingBinanceDemoOrders = false;
          _binanceDemoOrdersError = e.toString();
        });
      }
    }
  }




  void _deriveAgentAddressAndFetchBalance(String privateKey) {
    try {
      // Remove '0x' prefix if present
      String cleanKey = privateKey.trim();
      if (cleanKey.startsWith('0x')) {
        cleanKey = cleanKey.substring(2);
      }
      final credentials = EthPrivateKey.fromHex(cleanKey);
      _agentAddress = credentials.address.eip55With0x;
      _startAgentBalanceTimer();
    } catch (e) {
      debugPrint('Error deriving agent address: $e');
      _agentAddress = null;
    }
  }

  void _startAgentBalanceTimer() {
    _fetchAgentBalance();
  }

  void _stopAgentBalanceTimer() {
    if (mounted) {
      setState(() {
        _agentAddress = null;
        _agentBalance = 0.0;
      });
    }
  }

  Future<void> _fetchAgentBalance() async {
    if (_agentAddress == null) return;
    _fetchAgentWalletTransactions();
    if (_isFetchingAgentBalance) return;
    if (mounted) {
      setState(() => _isFetchingAgentBalance = true);
    }

    try {
      String rpcUrl = 'https://bsc-dataseed.bnbchain.org'; // Stable BSC default
      if (_agentActiveChainId == '1') {
        rpcUrl = 'https://ethereum.publicnode.com';
      } else if (_agentActiveChainId == '137') {
        rpcUrl = 'https://polygon-rpc.com';
      } else if (_agentActiveChainId == '56') {
        rpcUrl = 'https://bsc-dataseed.bnbchain.org';
      } else if (_agentActiveChainId == '97') {
        rpcUrl = 'https://bsc-testnet.publicnode.com';
      } else if (_agentActiveChainId == '11155111') {
        rpcUrl = 'https://ethereum-sepolia.publicnode.com';
      } else if (_agentActiveChainId == '80002') {
        rpcUrl = 'https://polygon-amoy.publicnode.com';
      }
      
      final client = Web3Client(rpcUrl, http.Client());
      final address = EthereumAddress.fromHex(_agentAddress!);
      final balance = await client.getBalance(address);
      if (mounted) {
        setState(() {
          _agentBalance = balance.getValueInUnit(EtherUnit.ether).toDouble();
        });
      }
      await client.dispose();
    } catch (e) {
      debugPrint('Error fetching agent balance: $e');
    } finally {
      if (mounted) {
        setState(() => _isFetchingAgentBalance = false);
      }
    }
  }

  Future<void> _saveAgentPrivateKey() async {
    String pk = _agentPrivateKeyController.text.trim();
    if (pk.isEmpty) return;

    if (pk.startsWith('0x')) {
      pk = pk.substring(2);
    }

    final hexRegex = RegExp(r'^[0-9a-fA-F]{64}$');
    if (!hexRegex.hasMatch(pk)) {
      AppSnackBar.showError(context, 'settings.billing.agent_wallet_invalid_key'.tr());
      return;
    }

    await handleSave(() async {
      final notifier = ref.read(configProvider.notifier);
      await notifier.setKey('agent_wallet_private_key', pk);
      if (mounted) {
        _deriveAgentAddressAndFetchBalance(pk);
        if (!_hasSavedAgentWalletVisibility) {
          setState(() {
            _showAgentWallet = true;
          });
        }
      }
    }, successMessage: 'settings.billing.agent_wallet_saved'.tr());
  }

  Future<void> _removeAgentWallet() async {
    final confirmed = await AppAlertDialog.showConfirmation(
      context: context,
      title: 'settings.billing.agent_wallet_remove_button'.tr(),
      content: 'Are you sure you want to remove the agent autonomous wallet private key from the secure vault?',
      confirmLabel: 'common.delete'.tr(),
      isDestructive: true,
    );

    if (confirmed == true) {
      await handleSave(() async {
        final notifier = ref.read(configProvider.notifier);
        await notifier.setKey('agent_wallet_private_key', '');
        _agentPrivateKeyController.clear();
        _stopAgentBalanceTimer();
        setState(() {
          _agentAddress = null;
          _agentBalance = 0.0;
          if (!_hasSavedAgentWalletVisibility) {
            _showAgentWallet = false;
          }
        });
      }, successMessage: 'settings.billing.agent_wallet_removed'.tr());
    }
  }

  Future<void> _initAppKit(String pid) async {
    try {
      if (WebViewPlatform.instance == null) {
        WebViewPlatform.instance = FakeWebViewPlatform();
      }
    } catch (e) {
      debugPrint('WebViewPlatform stub initialization error: $e');
    }

    if (_appKitModal != null) {
      try {
        _appKitModal!.removeListener(_onAppKitModalUpdate);
        _appKitModal!.dispose();
      } catch (_) {}
      _appKitModal = null;
    }

    setState(() {
      _isAppKitModalInitializing = true;
      _appKitInitError = null;
      _isAppKitConnected = false;
      _connectedAddress = null;
      _connectedChainName = null;
      _connectedProvider = null;
    });

    try {
      final modal = ReownAppKitModal(
        context: context,
        projectId: pid,
        metadata: const PairingMetadata(
          name: 'Ghost Personal AI Assistant',
          description: 'Secure personal AI coworker payment client',
          url: 'https://ghost.ai',
          icons: ['https://ghost.ai/assets/icons/logo/ghost.png'],
          redirect: Redirect(
            native: 'ghostapp://',
            universal: 'https://ghost.ai/app',
          ),
        ),
        optionalNamespaces: {
          'eip155': RequiredNamespace.fromJson({
            'chains': ReownAppKitModalNetworks.getAllSupportedNetworks(
              namespace: 'eip155',
            ).map((chain) => chain.chainId).toList(),
            'methods': NetworkUtils.defaultNetworkMethods['eip155']!.toList(),
            'events': NetworkUtils.defaultNetworkEvents['eip155']!.toList(),
          }),
        },
        featuresConfig: FeaturesConfig(
          socials: [
            AppKitSocialOption.Email,
            AppKitSocialOption.Google,
            AppKitSocialOption.Apple,
            AppKitSocialOption.X,
            AppKitSocialOption.GitHub,
            AppKitSocialOption.Discord,
          ],
          showMainWallets: true,
        ),
      );

      await modal.init();
      modal.addListener(_onAppKitModalUpdate);

      setState(() {
        _appKitModal = modal;
        _onAppKitModalUpdate();
      });
    } catch (e) {
      debugPrint('Reown AppKit Init Error: $e');
      setState(() {
        _appKitInitError = e.toString();
      });
      if (mounted) {
        AppSnackBar.showError(context, 'Reown Init Error: $e');
      }
    } finally {
      setState(() {
        _isAppKitModalInitializing = false;
      });
    }
  }

  void _onAppKitModalUpdate() {
    if (_appKitModal == null) return;
    final isConnectedNow = _appKitModal!.isConnected;
    final addressNow = _appKitModal!.session?.getAddress('eip155');
    final chainNow = _appKitModal!.selectedChain;

    setState(() {
      _isAppKitConnected = isConnectedNow;
      if (!_hasSavedPersonalWalletVisibility) {
        _showPersonalWallet = isConnectedNow;
      }
      if (isConnectedNow) {
        _connectedAddress = addressNow;
        _connectedChainName = chainNow?.name;
        _connectedProvider = _appKitModal!.session?.peer?.metadata.name ?? 'Universal Wallet';
      } else {
        _connectedAddress = null;
        _connectedChainName = null;
        _connectedProvider = null;
      }
    });

    if (isConnectedNow && chainNow != null) {
      final numericChainId = chainNow.chainId.contains(':') ? chainNow.chainId.split(':').last : chainNow.chainId;
      ref.read(configProvider.notifier).setKey('active_chain_id', numericChainId).catchError((e) {
        debugPrint('Error saving active_chain_id: $e');
      });
    }

    if (isConnectedNow && _connectedAddress != null) {
      _fetchPersonalWalletTransactions();
      if (_balanceTimer == null) {
        _startBalanceTimer();
      } else {
        _fetchTokenBalances();
      }
    } else {
      _stopBalanceTimer();
    }
  }

  void _startBalanceTimer() {
    _balanceTimer?.cancel();
    _balanceTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _fetchTokenBalances();
    });
    _fetchTokenBalances();
  }

  void _stopBalanceTimer() {
    _balanceTimer?.cancel();
    _balanceTimer = null;
    if (mounted) {
      setState(() {
        _tokenBalances.clear();
      });
    }
  }

  Future<void> _fetchTokenBalances() async {
    if (_appKitModal == null || !_appKitModal!.isConnected || _connectedAddress == null) return;
    if (_isFetchingBalances) return;
    _isFetchingBalances = true;

    try {
      final chain = _appKitModal!.selectedChain;
      if (chain == null) return;

      final numericChainId = chain.chainId.contains(':') ? chain.chainId.split(':').last : chain.chainId;
      final caipChainId = chain.chainId.contains(':') ? chain.chainId : 'eip155:${chain.chainId}';
      
      final tokens = _getTokensForChain(numericChainId);
      if (tokens.isEmpty) {
        if (mounted) {
          setState(() {
            _tokenBalances.clear();
          });
        }
        _isFetchingBalances = false;
        return;
      }

      final Map<String, double> newBalances = {};
      final abi = ContractAbi.fromJson(_erc20Abi, 'ERC20');
      final ownerAddr = EthereumAddress.fromHex(_connectedAddress!);

      for (final spec in tokens) {
        try {
          final contract = DeployedContract(abi, EthereumAddress.fromHex(spec.address));
          final result = await _appKitModal!.requestReadContract(
            topic: _appKitModal!.session!.topic!,
            chainId: caipChainId,
            deployedContract: contract,
            functionName: 'balanceOf',
            parameters: [ownerAddr],
          );

          if (result.isNotEmpty && result.first is BigInt) {
            final rawBalance = result.first as BigInt;
            final double divisor = spec.decimals == 6 ? 1000000.0 : 1000000000000000000.0;
            newBalances[spec.symbol] = rawBalance.toDouble() / divisor;
          } else {
            newBalances[spec.symbol] = 0.0;
          }
        } catch (e) {
          debugPrint('Error fetching balance for ${spec.symbol}: $e');
          newBalances[spec.symbol] = 0.0;
        }
      }

      if (mounted) {
        setState(() {
          _tokenBalances = newBalances;
        });
      }
    } catch (e) {
      debugPrint('Error fetching token balances: $e');
    } finally {
      _isFetchingBalances = false;
    }
  }

  String _shortenAddress(String? address) {
    if (address == null || address.isEmpty) return '';
    String checksummed = address;
    try {
      checksummed = EthereumAddress.fromHex(address).eip55With0x;
    } catch (_) {}
    if (checksummed.length <= 12) return checksummed;
    return '${checksummed.substring(0, 6)}••••${checksummed.substring(checksummed.length - 4)}';
  }

  // Save Settings
  Future<void> _saveBillingSettings({bool silent = false}) async {
    final limitVal = double.tryParse(_limitController.text) ?? 0.0;
    final balanceVal = double.tryParse(_balanceController.text) ?? 0.0;

    await handleSave(() async {
      final updatedBilling = ref.read(configProvider).billing.copyWith(
        limit: limitVal,
        balance: balanceVal,
        autonomous: _autonomous,
      );
      await ref.read(configProvider.notifier).updateBilling(updatedBilling.toJson());
      if (mounted) {
        setState(() => _isEditing = false);
      }
    },
    successMessage: 'settings.billing.settings_saved'.tr(),
    silent: silent,
    );
  }

  // Top Up Actions
  Future<void> _showTopUpDialog() async {
    final amountStr = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.borderRadiusDefault),
            side: const BorderSide(color: AppColors.border),
          ),
          title: Text('settings.billing.topup_dialog_title'.tr()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'settings.billing.topup_amount'.tr(),
                style: const TextStyle(color: AppColors.textDim, fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                ],
                style: const TextStyle(color: AppColors.white, fontSize: 13),
                decoration: AppInputDecoration.compact(
                  hint: '0.00',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [10, 20, 50, 100].map((preset) {
                  return InkWell(
                    onTap: () {
                      controller.text = preset.toStringAsFixed(2);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '+$preset',
                        style: const TextStyle(color: AppColors.textMain, fontSize: 12),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'common.cancel'.tr(),
                style: const TextStyle(color: AppColors.textDim),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: Text(
                'settings.billing.topup_label'.tr(),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (amountStr != null && amountStr.isNotEmpty) {
      final amount = double.tryParse(amountStr) ?? 0.0;
      if (amount <= 0) {
        if (mounted) {
          AppSnackBar.showError(context, 'settings.billing.topup_failed'.tr());
        }
        return;
      }

      await handleSave(() async {
        final currentBilling = ref.read(configProvider).billing;
        final newBalance = currentBilling.balance + amount;
        final updatedBilling = currentBilling.copyWith(balance: newBalance);
        
        await ref.read(configProvider.notifier).updateBilling(updatedBilling.toJson());

        try {
          final txsJson = await ref.read(configProvider.notifier).getKey('payment_card_transactions') ?? '[]';
          final List<dynamic> txs = jsonDecode(txsJson.isEmpty ? '[]' : txsJson);
          txs.insert(0, {
            'id': DateTime.now().millisecondsSinceEpoch.toString(),
            'date': DateTime.now().toIso8601String(),
            'amount': amount,
            'recipient': 'Top Up',
            'purpose': 'Budget Top Up',
            'status': 'SUCCESS',
          });
          await ref.read(configProvider.notifier).setKey('payment_card_transactions', jsonEncode(txs));
        } catch (e) {
          debugPrint('Error saving top up transaction: $e');
        }
        
        if (mounted) {
          _balanceController.text = newBalance.toStringAsFixed(2);
        }
        await _fetchCardTransactions();
      }, successMessage: 'settings.billing.topup_success'.tr(namedArgs: {'amount': amount.toStringAsFixed(2)}));
    }
  }

  Future<void> _showCryptoTopUpDialog() async {
    final amountStr = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.borderRadiusDefault),
            side: const BorderSide(color: AppColors.border),
          ),
          title: Text('settings.billing.topup_crypto_title'.tr()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'settings.billing.topup_amount'.tr(),
                style: const TextStyle(color: AppColors.textDim, fontSize: 13),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                ],
                style: const TextStyle(color: AppColors.white, fontSize: 13),
                decoration: AppInputDecoration.compact(
                  hint: '0.00',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [10, 20, 50, 100].map((preset) {
                  return InkWell(
                    onTap: () {
                      controller.text = preset.toStringAsFixed(2);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '+$preset',
                        style: const TextStyle(color: AppColors.textMain, fontSize: 12),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'common.cancel'.tr(),
                style: const TextStyle(color: AppColors.textDim),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: Text(
                'settings.billing.topup_label'.tr(),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (amountStr != null && amountStr.isNotEmpty) {
      final amount = double.tryParse(amountStr) ?? 0.0;
      if (amount <= 0) {
        if (mounted) {
          AppSnackBar.showError(context, 'settings.billing.topup_failed'.tr());
        }
        return;
      }

      // Show confirmation dialog before simulated Web3 transaction
      final confirmed = await AppAlertDialog.showConfirmation(
        context: context,
        title: 'settings.billing.topup_crypto_title'.tr(),
        content: 'settings.billing.topup_crypto_confirm'.tr(namedArgs: {'amount': amount.toStringAsFixed(2)}),
        confirmLabel: 'settings.billing.topup_label'.tr(),
      );

      if (confirmed == true) {
        await handleSave(() async {
          // Simulate blockchain transaction delay
          await Future<void>.delayed(const Duration(seconds: 2));

          final currentBilling = ref.read(configProvider).billing;
          final newBalance = currentBilling.balance + amount;
          final updatedBilling = currentBilling.copyWith(balance: newBalance);
          
          await ref.read(configProvider.notifier).updateBilling(updatedBilling.toJson());
          
          if (mounted) {
            _balanceController.text = newBalance.toStringAsFixed(2);
          }
        }, successMessage: 'settings.billing.topup_success'.tr(namedArgs: {'amount': amount.toStringAsFixed(2)}));
      }
    }
  }

  // Credit Card Tab UI Creators
  Widget _buildCreditCard() {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [
            AppColors.surfaceLight,
            AppColors.surface.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'GHOST SECURE CARD',
                style: TextStyle(
                  color: AppColors.textDim,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              Icon(
                Icons.credit_card_rounded,
                color: AppColors.primary.withValues(alpha: 0.8),
                size: 32,
              ),
            ],
          ),
          const Spacer(),
          Text(
            '•••• •••• •••• $_cardNumberLast4',
            style: const TextStyle(
              color: AppColors.textMain,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 2.0,
            ),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CARDHOLDER',
                    style: TextStyle(
                      color: AppColors.textDim,
                      fontSize: 9,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _cardHolderName?.toUpperCase() ?? 'GHOST USER',
                    style: const TextStyle(
                      color: AppColors.textMain,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.error),
                onPressed: _removeCard,
                tooltip: 'settings.billing.card_removed'.tr(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCreditCardForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        color: AppColors.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Number
          const AppFormLabel('settings.billing.card_number'),
          const SizedBox(height: 6),
          TextField(
            controller: _cardNumController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              CardNumberFormatter(),
            ],
            style: const TextStyle(color: AppColors.white, fontSize: 13),
            decoration: AppInputDecoration.compact(
              hint: '•••• •••• •••• ••••',
            ),
          ),
          const SizedBox(height: 12),

          // Expiry & CVV Row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppFormLabel('settings.billing.card_expiry'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _cardExpController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        CardExpiryFormatter(),
                      ],
                      style: const TextStyle(color: AppColors.white, fontSize: 13),
                      decoration: AppInputDecoration.compact(
                        hint: 'MM/YY',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppFormLabel('settings.billing.card_cvv'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _cardCvvController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      obscureText: true,
                      style: const TextStyle(color: AppColors.white, fontSize: 13),
                      decoration: AppInputDecoration.compact(
                        hint: '•••',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Cardholder Name
          const AppFormLabel('settings.billing.card_holder'),
          const SizedBox(height: 6),
          TextField(
            controller: _cardHolderController,
            style: const TextStyle(color: AppColors.white, fontSize: 13),
            decoration: AppInputDecoration.compact(
              hint: 'John Doe',
            ),
          ),
          const SizedBox(height: 16),

          // Save Card Action Button
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppSaveButton(
                onPressed: _saveCard,
                label: 'settings.billing.save_settings',
                icon: Icons.credit_card_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Crypto Tab UI Creators
  Widget _buildCryptoWalletCard() {
    return Container(
      height: 180,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [
            AppColors.surfaceLight,
            AppColors.surface.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'GHOST WEB3 WALLET',
                style: TextStyle(
                  color: AppColors.textDim,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              Icon(
                Icons.account_balance_wallet_rounded,
                color: AppColors.primary.withValues(alpha: 0.8),
                size: 32,
              ),
            ],
          ),
          const Spacer(),
          Text(
            _shortenAddress(_connectedAddress),
            style: const TextStyle(
              color: AppColors.textMain,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 2.0,
            ),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${'settings.billing.wallet_provider'.tr().toUpperCase()} / ${'settings.billing.wallet_chain'.tr().toUpperCase()}',
                      style: const TextStyle(
                        color: AppColors.textDim,
                        fontSize: 9,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_connectedProvider?.toUpperCase() ?? 'UNKNOWN'} • ${_connectedChainName?.toUpperCase() ?? 'EVM CHAIN'}',
                            style: const TextStyle(
                              color: AppColors.textMain,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              if (_appKitModal != null) {
                                _appKitModal!.openModalView(ReownAppKitModalSelectNetworkPage());
                              }
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.swap_horiz_rounded,
                                    color: AppColors.primary,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'settings.billing.change_network'.tr().toUpperCase(),
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout_rounded, color: AppColors.error),
                onPressed: () async {
                  if (_appKitModal != null) {
                    await _appKitModal!.disconnect();
                  }
                },
                tooltip: 'settings.billing.disconnect_wallet'.tr(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCryptoWalletActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _showSendCryptoDialog,
            icon: const Icon(Icons.arrow_upward_rounded),
            label: Text('settings.billing.send'.tr().toUpperCase()),
            style: OutlinedButton.styleFrom(
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _showReceiveCryptoDialog,
            icon: const Icon(Icons.arrow_downward_rounded),
            label: Text('settings.billing.receive'.tr().toUpperCase()),
            style: OutlinedButton.styleFrom(
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showReceiveCryptoDialog() async {
    if (_connectedAddress == null) return;
    
    String checksummedAddress = _connectedAddress!;
    try {
      checksummedAddress = EthereumAddress.fromHex(_connectedAddress!).eip55With0x;
    } catch (_) {}

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.borderRadiusDefault),
            side: const BorderSide(color: AppColors.border),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Title
                    Text(
                      'settings.billing.receive_crypto_title'.tr(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.white,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // QR Code
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SizedBox(
                        width: 200,
                        height: 200,
                        child: QrImageView(
                          data: checksummedAddress,
                          version: QrVersions.auto,
                          backgroundColor: Colors.white,
                          errorCorrectionLevel: QrErrorCorrectLevel.M,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.circle,
                            color: Colors.black,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.circle,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Address
                    SelectableText(
                      checksummedAddress,
                      style: const TextStyle(
                        color: AppColors.textMain,
                        fontSize: 12,
                        fontFamily: 'Courier',
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    // Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(
                            'common.close'.tr(),
                            style: const TextStyle(color: AppColors.textDim),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: checksummedAddress));
                            AppSnackBar.showSuccess(context, 'settings.billing.address_copied'.tr());
                            Navigator.pop(ctx);
                          },
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: Text('common.copy'.tr().toUpperCase()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.white,
                            foregroundColor: AppColors.black,
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showSendCryptoDialog() async {
    if (_appKitModal == null || !_appKitModal!.isConnected || _connectedAddress == null) return;

    final chain = _appKitModal!.selectedChain;
    if (chain == null) return;

    final numericChainId = chain.chainId.contains(':') ? chain.chainId.split(':').last : chain.chainId;
    final caipChainId = chain.chainId.contains(':') ? chain.chainId : 'eip155:${chain.chainId}';

    // Fetch latest balance for native token
    double nativeAmount = 0.0;
    final balanceStr = _appKitModal!.balanceNotifier.value;
    if (balanceStr.isNotEmpty) {
      final parts = balanceStr.trim().split(' ');
      if (parts.isNotEmpty) {
        nativeAmount = double.tryParse(parts[0]) ?? 0.0;
      }
    }

    final nativeSymbol = chain.currency;
    final nativeName = chain.name;

    final List<Map<String, dynamic>> tokensList = [
      {
        'symbol': nativeSymbol,
        'name': nativeName,
        'balance': nativeAmount,
        'isNative': true,
        'decimals': 18,
      }
    ];

    final tokenSpecs = _getTokensForChain(numericChainId);
    for (final spec in tokenSpecs) {
      final double amount = _tokenBalances[spec.symbol] ?? 0.0;
      if (amount > 0.0) {
        tokensList.add({
          'symbol': spec.symbol,
          'name': spec.name,
          'balance': amount,
          'isNative': false,
          'decimals': spec.decimals,
          'address': spec.address,
        });
      }
    }

    // Local controllers/variables for dialog state
    final recipientController = TextEditingController();
    final amountController = TextEditingController();
    Map<String, dynamic> selectedToken = tokensList.first;
    String? validationError;
    bool isSending = false;

    await showDialog(
      context: context,
      barrierDismissible: false, // Prevents closing while sending
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AppAlertDialog(
              title: Text('settings.billing.send_crypto_title'.tr()),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Token Selector
                    const AppFormLabel('settings.billing.send_token_label'),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        color: AppColors.surface,
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<Map<String, dynamic>>(
                          value: selectedToken,
                          dropdownColor: AppColors.surface,
                          isExpanded: true,
                          icon: const Icon(Icons.arrow_drop_down, color: AppColors.textMain),
                          items: tokensList.map((token) {
                            final double bal = token['balance'] as double;
                            return DropdownMenuItem<Map<String, dynamic>>(
                              value: token,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${token['name']} (${token['symbol']})',
                                    style: const TextStyle(color: AppColors.white, fontSize: 13),
                                  ),
                                  Text(
                                    '${bal.toStringAsFixed(4)} ${token['symbol']}',
                                    style: const TextStyle(color: AppColors.textDim, fontSize: 12),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: isSending
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setStateDialog(() {
                                      selectedToken = value;
                                      validationError = null;
                                    });
                                  }
                                },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Recipient Address
                    const AppFormLabel('settings.billing.send_recipient_label'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: recipientController,
                      enabled: !isSending,
                      style: const TextStyle(color: AppColors.white, fontSize: 13),
                      decoration: AppInputDecoration.compact(
                        hint: '0x...',
                      ),
                      onChanged: (_) {
                        if (validationError != null) {
                          setStateDialog(() => validationError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // Amount
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const AppFormLabel('settings.billing.send_amount_label'),
                        InkWell(
                          onTap: isSending
                              ? null
                              : () {
                                  amountController.text = (selectedToken['balance'] as double).toString();
                                  setStateDialog(() => validationError = null);
                                },
                          child: Text(
                            'Max: ${(selectedToken['balance'] as double).toStringAsFixed(4)}',
                            style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: amountController,
                      enabled: !isSending,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                      ],
                      style: const TextStyle(color: AppColors.white, fontSize: 13),
                      decoration: AppInputDecoration.compact(
                        hint: '0.00',
                      ),
                      onChanged: (_) {
                        if (validationError != null) {
                          setStateDialog(() => validationError = null);
                        }
                      },
                    ),
                    
                    if (validationError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        validationError!,
                        style: const TextStyle(color: AppColors.error, fontSize: 12),
                      ),
                    ],

                    if (isSending) ...[
                      const SizedBox(height: 20),
                      const Center(
                        child: Column(
                          children: [
                            CircularProgressIndicator(strokeWidth: 2),
                            SizedBox(height: 12),
                            Text(
                              'Confirm transaction in your wallet...',
                              style: TextStyle(color: AppColors.textDim, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSending ? null : () => Navigator.pop(dialogCtx),
                  child: Text(
                    'common.cancel'.tr(),
                    style: const TextStyle(color: AppColors.textDim),
                  ),
                ),
                TextButton(
                  onPressed: isSending
                      ? null
                      : () async {
                          final recipient = recipientController.text.trim();
                          final amountText = amountController.text.trim();
                          final double? amount = double.tryParse(amountText);

                          // Validators
                          if (recipient.length != 42 || !recipient.startsWith('0x')) {
                            setStateDialog(() => validationError = 'settings.billing.invalid_address'.tr());
                            return;
                          }
                          try {
                            EthereumAddress.fromHex(recipient);
                          } catch (_) {
                            setStateDialog(() => validationError = 'settings.billing.invalid_address'.tr());
                            return;
                          }

                          if (amount == null || amount <= 0 || amount > selectedToken['balance']) {
                            setStateDialog(() => validationError = 'settings.billing.invalid_amount'.tr());
                            return;
                          }

                          // Confirm Dialog
                          final confirmed = await AppAlertDialog.showConfirmation(
                            context: context,
                            title: 'settings.billing.send_confirm_title'.tr(),
                            content: 'settings.billing.send_confirm_desc'.tr(namedArgs: {
                              'amount': amount.toString(),
                              'symbol': selectedToken['symbol'],
                              'recipient': _shortenAddress(recipient),
                            }),
                            confirmLabel: 'settings.billing.send'.tr(),
                          );

                          if (confirmed != true) return;

                          setStateDialog(() {
                            isSending = true;
                            validationError = null;
                          });

                          try {
                            final String txHash;
                            final decimals = selectedToken['decimals'] as int;
                            final BigInt amountInWei = BigInt.from((amount * math.pow(10, decimals)).round());

                            if (selectedToken['isNative'] == true) {
                              // Native Token Transfer (e.g. BNB/ETH)
                              final trx = Transaction(
                                from: EthereumAddress.fromHex(_connectedAddress!),
                                to: EthereumAddress.fromHex(recipient),
                                value: EtherAmount.fromBigInt(EtherUnit.wei, amountInWei),
                              );

                              final result = await _appKitModal!.request(
                                topic: _appKitModal!.session?.topic,
                                chainId: caipChainId,
                                request: SessionRequestParams(
                                  method: 'eth_sendTransaction',
                                  params: [trx.toJson()],
                                ),
                              );
                              txHash = result.toString();
                            } else {
                              // ERC-20 Token Transfer
                              final abi = ContractAbi.fromJson(_erc20Abi, 'ERC20');
                              final contract = DeployedContract(abi, EthereumAddress.fromHex(selectedToken['address']));
                              final result = await _appKitModal!.requestWriteContract(
                                topic: _appKitModal!.session?.topic,
                                chainId: caipChainId,
                                deployedContract: contract,
                                functionName: 'transfer',
                                transaction: Transaction(
                                  from: EthereumAddress.fromHex(_connectedAddress!),
                                ),
                                parameters: [
                                  EthereumAddress.fromHex(recipient),
                                  amountInWei,
                                ],
                              );
                              txHash = result.toString();
                            }

                            if (mounted) {
                              Navigator.pop(dialogCtx); // Close the dialog
                              AppSnackBar.showSuccess(
                                context,
                                'settings.billing.send_success'.tr(namedArgs: {'hash': txHash}),
                              );
                            }

                            // Trigger a balance refresh
                            Future.delayed(const Duration(seconds: 2), () {
                              _fetchTokenBalances();
                            });
                          } catch (e) {
                            if (mounted) {
                              setStateDialog(() {
                                isSending = false;
                                validationError = 'settings.billing.send_failed'.tr(namedArgs: {'error': e.toString()});
                              });
                            }
                          }
                        },
                  child: Text(
                    'settings.billing.send'.tr(),
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildConnectWalletView() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        color: AppColors.surface,
      ),
      child: Column(
        children: [
          const Icon(
            Icons.account_balance_wallet_outlined,
            size: 48,
            color: AppColors.textDim,
          ),
          const SizedBox(height: 16),
          Text(
            'settings.billing.wallet_not_connected'.tr(),
            style: const TextStyle(
              color: AppColors.textMain,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Connect your external wallet via WalletConnect or use email and social logins to securely connect to Web3.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textDim,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  if (_appKitModal != null) {
                    _appKitModal!.openModalView();
                  }
                },
                icon: const Icon(Icons.link_rounded),
                label: Text('settings.billing.connect_wallet'.tr().toUpperCase()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.white,
                  foregroundColor: AppColors.black,
                  minimumSize: const Size(180, 48),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  if (_appKitModal != null) {
                    _appKitModal!.openModalView(ReownAppKitModalQRCodePage());
                  }
                },
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: Text('settings.billing.scan_qr_code'.tr().toUpperCase()),
                style: OutlinedButton.styleFrom(
                  backgroundColor: AppColors.background,
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary, width: 1.2),
                  minimumSize: const Size(180, 48),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAgentWalletSection({required bool showDivider}) {
    final hasKey = _agentAddress != null;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showDivider)
          const Divider(color: AppColors.border, height: 32)
        else
          const SizedBox(height: 16),
        Text(
          'settings.billing.agent_wallet_title'.tr().toUpperCase(),
          style: const TextStyle(
            color: AppColors.textDim,
            fontSize: AppConstants.fontSizeLabelTiny,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),
        if (_isLoadingAgentWallet)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (hasKey) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              color: AppColors.surface,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'settings.billing.agent_wallet_address_label'.tr().toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.textDim,
                              fontSize: 9,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _agentAddress ?? '',
                                  style: const TextStyle(
                                    color: AppColors.white,
                                    fontSize: 13,
                                    fontFamily: 'monospace',
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, size: 16, color: AppColors.textDim),
                                onPressed: () {
                                  if (_agentAddress != null) {
                                    Clipboard.setData(ClipboardData(text: _agentAddress!));
                                    AppSnackBar.showSuccess(context, 'settings.billing.address_copied'.tr());
                                  }
                                },
                                tooltip: 'settings.billing.copy_address_tooltip'.tr(),
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(4),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: _removeAgentWallet,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: AppColors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                      ),
                      child: Text(
                        'settings.billing.agent_wallet_remove_button'.tr().toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: AppColors.border, height: 1),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'settings.billing.wallet_chain'.tr().toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.textDim,
                              fontSize: 9,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _agentActiveChainId,
                              dropdownColor: AppColors.surface,
                              icon: const Icon(Icons.arrow_drop_down, color: AppColors.textDim),
                              items: const [
                                DropdownMenuItem(
                                  value: '56',
                                  child: Text('BNB Smart Chain (BNB)', style: TextStyle(color: AppColors.white, fontSize: 13)),
                                ),
                                DropdownMenuItem(
                                  value: '97',
                                  child: Text('BSC Testnet (tBNB)', style: TextStyle(color: AppColors.white, fontSize: 13)),
                                ),
                                DropdownMenuItem(
                                  value: '1',
                                  child: Text('Ethereum Mainnet (ETH)', style: TextStyle(color: AppColors.white, fontSize: 13)),
                                ),
                                DropdownMenuItem(
                                  value: '11155111',
                                  child: Text('Ethereum Sepolia (ETH)', style: TextStyle(color: AppColors.white, fontSize: 13)),
                                ),
                                DropdownMenuItem(
                                  value: '137',
                                  child: Text('Polygon Mainnet (POL)', style: TextStyle(color: AppColors.white, fontSize: 13)),
                                ),
                                DropdownMenuItem(
                                  value: '80002',
                                  child: Text('Polygon Amoy (POL)', style: TextStyle(color: AppColors.white, fontSize: 13)),
                                ),
                              ],
                              onChanged: (value) async {
                                if (value != null) {
                                  setState(() {
                                    _agentActiveChainId = value;
                                    _agentBalance = 0.0;
                                  });
                                  await ref.read(configProvider.notifier).setKey('active_chain_id', value);
                                  _fetchAgentBalance();
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'settings.billing.agent_wallet_balance_label'.tr().toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.textDim,
                            fontSize: 9,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (_isFetchingAgentBalance) ...[
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 1.5),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              '${_agentBalance.toStringAsFixed(4)} ${_getAgentActiveCurrency()}',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: _isFetchingAgentBalance
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: AppColors.textDim,
                              ),
                            )
                          : const Icon(Icons.refresh, color: AppColors.textDim, size: 20),
                      onPressed: _isFetchingAgentBalance
                          ? null
                          : () {
                              _fetchAgentBalance();
                            },
                      tooltip: 'common.refresh'.tr(),
                    ),
                  ],
                ),
              ],
            ),
          ),

        ] else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              color: AppColors.surface,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppFormLabel('settings.billing.agent_wallet_private_key_label'),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _agentPrivateKeyController,
                        obscureText: true,
                        style: const TextStyle(color: AppColors.white, fontSize: 13),
                        decoration: AppInputDecoration.compact(
                          hint: 'settings.billing.agent_wallet_private_key_hint'.tr(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _saveAgentPrivateKey,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.white,
                        foregroundColor: AppColors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                      ),
                      child: Text(
                        'settings.billing.agent_wallet_save_button'.tr().toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildBinanceSection({required bool showDivider}) {
    final hasKey = _hasBinanceConfigured;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showDivider)
          const Divider(color: AppColors.border, height: 32)
        else
          const SizedBox(height: 16),
        Text(
          'settings.billing.binance_section'.tr().toUpperCase(),
          style: const TextStyle(
            color: AppColors.textDim,
            fontSize: AppConstants.fontSizeLabelTiny,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),
        if (_isLoadingBinance)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (hasKey) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              color: AppColors.surface,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'settings.billing.binance_status_label'.tr().toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.textDim,
                              fontSize: 9,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.check_circle_outline, color: AppColors.success, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'settings.billing.binance_connected'.tr(),
                                style: const TextStyle(
                                  color: AppColors.success,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _removeBinanceConfig,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: AppColors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                      ),
                      child: Text(
                        'settings.billing.agent_wallet_remove_button'.tr().toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10),
                      ),
                    ),
                  ],
                ),
                if (_binanceApiKeyController.text.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(color: AppColors.border, height: 1),
                  const SizedBox(height: 16),
                  Text(
                    'settings.billing.binance_api_key_label'.tr().toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.textDim,
                      fontSize: 9,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _binanceApiKeyController.text.length > 8
                        ? '${_binanceApiKeyController.text.substring(0, 4)}••••••••${_binanceApiKeyController.text.substring(_binanceApiKeyController.text.length - 4)}'
                        : '••••••••',
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              color: AppColors.surface,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppFormLabel('settings.billing.binance_api_key_label'),
                const SizedBox(height: 6),
                TextField(
                  controller: _binanceApiKeyController,
                  style: const TextStyle(color: AppColors.white, fontSize: 13),
                  decoration: AppInputDecoration.compact(
                    hint: 'settings.billing.binance_api_key_hint'.tr(),
                  ),
                ),
                const SizedBox(height: 16),
                const AppFormLabel('settings.billing.binance_secret_key_label'),
                const SizedBox(height: 6),
                TextField(
                  controller: _binanceSecretKeyController,
                  obscureText: true,
                  style: const TextStyle(color: AppColors.white, fontSize: 13),
                  decoration: AppInputDecoration.compact(
                    hint: 'settings.billing.binance_secret_key_hint'.tr(),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: _saveBinanceConfig,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.white,
                      foregroundColor: AppColors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                    ),
                    child: Text(
                      'settings.billing.agent_wallet_save_button'.tr().toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBinanceDemoSection({required bool showDivider}) {
    final hasKey = _hasBinanceDemoConfigured;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showDivider)
          const Divider(color: AppColors.border, height: 32)
        else
          const SizedBox(height: 16),
        Text(
          'settings.billing.binance_demo_section'.tr().toUpperCase(),
          style: const TextStyle(
            color: AppColors.textDim,
            fontSize: AppConstants.fontSizeLabelTiny,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),
        if (_isLoadingBinanceDemo)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (hasKey) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              color: AppColors.surface,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'settings.billing.binance_demo_status_label'.tr().toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.textDim,
                              fontSize: 9,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.check_circle_outline, color: AppColors.success, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'settings.billing.binance_demo_connected'.tr(),
                                style: const TextStyle(
                                  color: AppColors.success,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _removeBinanceDemoConfig,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        foregroundColor: AppColors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                      ),
                      child: Text(
                        'settings.billing.agent_wallet_remove_button'.tr().toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10),
                      ),
                    ),
                  ],
                ),
                if (_binanceDemoApiKeyController.text.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(color: AppColors.border, height: 1),
                  const SizedBox(height: 16),
                  Text(
                    'settings.billing.binance_demo_api_key_label'.tr().toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.textDim,
                      fontSize: 9,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _binanceDemoApiKeyController.text.length > 8
                        ? '${_binanceDemoApiKeyController.text.substring(0, 4)}••••••••${_binanceDemoApiKeyController.text.substring(_binanceDemoApiKeyController.text.length - 4)}'
                        : '••••••••',
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              color: AppColors.surface,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppFormLabel('settings.billing.binance_demo_api_key_label'),
                const SizedBox(height: 6),
                TextField(
                  controller: _binanceDemoApiKeyController,
                  style: const TextStyle(color: AppColors.white, fontSize: 13),
                  decoration: AppInputDecoration.compact(
                    hint: 'settings.billing.binance_demo_api_key_hint'.tr(),
                  ),
                ),
                const SizedBox(height: 16),
                const AppFormLabel('settings.billing.binance_demo_secret_key_label'),
                const SizedBox(height: 6),
                TextField(
                  controller: _binanceDemoSecretKeyController,
                  obscureText: true,
                  style: const TextStyle(color: AppColors.white, fontSize: 13),
                  decoration: AppInputDecoration.compact(
                    hint: 'settings.billing.binance_demo_secret_key_hint'.tr(),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: _saveBinanceDemoConfig,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.white,
                      foregroundColor: AppColors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                    ),
                    child: Text(
                      'settings.billing.agent_wallet_save_button'.tr().toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWalletAssetsSection() {
    if (_appKitModal == null) return const SizedBox.shrink();

    return ValueListenableBuilder<String>(
      valueListenable: _appKitModal!.balanceNotifier,
      builder: (context, balanceStr, child) {
        double nativeAmount = 0.0;
        String nativeSymbol = 'ETH';
        String nativeName = 'Ethereum';

        final chain = _appKitModal!.selectedChain;
        if (chain != null) {
          nativeSymbol = chain.currency;
          nativeName = chain.name;
        }

        if (balanceStr.isNotEmpty) {
          final parts = balanceStr.trim().split(' ');
          if (parts.isNotEmpty) {
            nativeAmount = double.tryParse(parts[0]) ?? 0.0;
          }
        }

        double nativePriceUsd = 3450.00;
        Color nativeColor = AppColors.primary;
        IconData nativeIcon = Icons.generating_tokens_rounded;

        if (nativeSymbol == 'BNB') {
          nativePriceUsd = 580.00;
          nativeColor = const Color(0xFFF3BA2F);
          nativeIcon = Icons.stars_rounded;
        } else if (nativeSymbol == 'ETH') {
          nativePriceUsd = 3450.00;
          nativeColor = const Color(0xFF627EEA);
          nativeIcon = Icons.generating_tokens_rounded;
        } else if (nativeSymbol == 'MATIC' || nativeSymbol == 'POL') {
          nativePriceUsd = 0.45;
          nativeColor = const Color(0xFF8247E5);
          nativeIcon = Icons.hexagon_rounded;
        } else if (nativeSymbol == 'AVAX') {
          nativePriceUsd = 25.00;
        } else if (nativeSymbol == 'DAI' || nativeSymbol == 'xDAI' || nativeSymbol == 'USDC' || nativeSymbol == 'USDT') {
          nativePriceUsd = 1.00;
        }

        final double nativeTotal = nativeAmount * nativePriceUsd;

        final List<Map<String, dynamic>> assets = [
          {
            'name': nativeName,
            'symbol': nativeSymbol,
            'amount': nativeAmount,
            'price': nativePriceUsd,
            'total': nativeTotal,
            'icon': nativeIcon,
            'color': nativeColor,
            'isNative': true,
          },
        ];

        if (chain != null) {
          final numericChainId = chain.chainId.contains(':') ? chain.chainId.split(':').last : chain.chainId;
          final tokenSpecs = _getTokensForChain(numericChainId);
          for (final spec in tokenSpecs) {
            final double amount = _tokenBalances[spec.symbol] ?? 0.0;
            final double total = amount * spec.priceUsd;
            assets.add({
              'name': spec.name,
              'symbol': spec.symbol,
              'amount': amount,
              'price': spec.priceUsd,
              'total': total,
              'icon': spec.icon,
              'color': spec.color,
              'isNative': false,
            });
          }
        }

        // Filter to display either native token OR assets with a non-zero balance
        final List<Map<String, dynamic>> filteredAssets = assets
            .where((asset) => (asset['isNative'] == true) || (asset['amount'] as double) > 0.0)
            .toList();

        double grandTotal = 0.0;
        for (final asset in filteredAssets) {
          grandTotal += asset['total'] as double;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'settings.billing.wallet_assets'.tr().toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: AppConstants.fontSizeLabelTiny,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
                Text(
                  'Total: \$${grandTotal.toStringAsFixed(2)} USD',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                color: AppColors.surface,
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: AppColors.border)),
                      color: AppColors.background,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            'settings.billing.asset_header_name'.tr().toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.textDim,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'settings.billing.asset_header_amount'.tr().toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.textDim,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'settings.billing.asset_header_price'.tr().toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.textDim,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'settings.billing.asset_header_total'.tr().toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.textDim,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (filteredAssets.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      alignment: Alignment.center,
                      child: Text(
                        'common.no_results'.tr(),
                        style: const TextStyle(color: AppColors.textDim, fontSize: 13),
                      ),
                    )
                  else
                    ...filteredAssets.map((asset) {
                      final isLast = filteredAssets.last == asset;
                      final double amount = asset['amount'] as double;
                      final double price = asset['price'] as double;
                      final double total = asset['total'] as double;

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          border: isLast ? null : const Border(bottom: BorderSide(color: AppColors.border)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Row(
                                children: [
                                  Icon(
                                    asset['icon'] as IconData,
                                    color: asset['color'] as Color,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          asset['name'] as String,
                                          style: const TextStyle(
                                            color: AppColors.textMain,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          asset['symbol'] as String,
                                          style: const TextStyle(
                                            color: AppColors.textDim,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                amount.toStringAsFixed(4),
                                style: const TextStyle(
                                  color: AppColors.textMain,
                                  fontFamily: 'Courier',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '\$${price.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: AppColors.textDim,
                                  fontFamily: 'Courier',
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '\$${total.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: AppColors.white,
                                  fontFamily: 'Courier',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildErrorBanner(
    String message, {
    String? explorerApiKeyName,
    VoidCallback? onSaved,
  }) {
    final bool isMissingKey = message.contains('Block-Explorer') || message.contains('API Key');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (isMissingKey && explorerApiKeyName != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 32,
                    child: TextField(
                      controller: _explorerApiKeyInputController,
                      style: const TextStyle(color: AppColors.white, fontSize: 12),
                      decoration: AppInputDecoration.compact(
                        hint: 'settings.billing.explorer_api_key_hint'.tr(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 32,
                  child: ElevatedButton(
                    onPressed: () async {
                      final key = _explorerApiKeyInputController.text.trim();
                      if (key.isNotEmpty) {
                        await ref.read(configProvider.notifier).setKey(explorerApiKeyName, key);
                        _explorerApiKeyInputController.clear();
                        if (onSaved != null) {
                          onSaved();
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.white,
                      foregroundColor: AppColors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                    ),
                    child: Text(
                      'settings.billing.explorer_api_key_save'.tr().toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryHeader({
    required String title,
    required bool isExpanded,
    required bool isLoading,
    required bool hasConfig,
    required VoidCallback onToggle,
    required VoidCallback onRefresh,
  }) {
    return InkWell(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          color: AppColors.background,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  Icons.history_rounded,
                  color: isExpanded ? AppColors.primary : AppColors.textDim,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: isExpanded ? AppColors.white : AppColors.textDim,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                // Status tag
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: hasConfig
                        ? AppColors.success.withValues(alpha: 0.15)
                        : AppColors.textDim.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    hasConfig
                        ? 'settings.billing.connected_to_api'.tr().toUpperCase()
                        : 'settings.billing.offline_demo_mode'.tr().toUpperCase(),
                    style: TextStyle(
                      color: hasConfig ? AppColors.success : AppColors.textDim,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                if (isLoading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  )
                else
                  GestureDetector(
                    onTap: () {
                      onRefresh();
                    },
                    child: const MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Padding(
                        padding: EdgeInsets.all(4.0),
                        child: Icon(Icons.refresh, size: 16, color: AppColors.textDim),
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Icon(
                  isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: AppColors.textDim,
                  size: 20,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionList(List<Map<String, dynamic>> txs, {required String chainId}) {
    if (txs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          color: AppColors.surface,
        ),
        child: Text(
          'settings.billing.no_transactions'.tr(),
          style: const TextStyle(color: AppColors.textDim, fontSize: 12),
        ),
      );
    }

    String explorerBase = 'https://bscscan.com';
    if (chainId == '1') explorerBase = 'https://etherscan.io';
    else if (chainId == '137') explorerBase = 'https://polygonscan.com';
    else if (chainId == '97') explorerBase = 'https://testnet.bscscan.com';
    else if (chainId == '11155111') explorerBase = 'https://sepolia.etherscan.io';
    else if (chainId == '80002') explorerBase = 'https://amoy.polygonscan.com';

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        color: AppColors.surface,
      ),
      child: Column(
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
              color: AppColors.background,
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'settings.billing.type'.tr().toUpperCase(),
                    style: const TextStyle(color: AppColors.textDim, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'settings.billing.date'.tr().toUpperCase(),
                    style: const TextStyle(color: AppColors.textDim, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'settings.billing.amount'.tr().toUpperCase(),
                    style: const TextStyle(color: AppColors.textDim, fontSize: 9, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'settings.billing.status'.tr().toUpperCase(),
                    style: const TextStyle(color: AppColors.textDim, fontSize: 9, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(width: 32), // Spacer for explorer icon
              ],
            ),
          ),
          // Scrollable Rows
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 250),
            child: SingleChildScrollView(
              child: Column(
                children: txs.map((tx) {
                  final isLast = txs.last == tx;
                  final isSend = tx['isSend'] == true;
                  final isError = tx['isError'] == true;
                  final hash = tx['hash'] as String;
                  final shortHash = hash.length > 10 ? '${hash.substring(0, 6)}...${hash.substring(hash.length - 4)}' : hash;
                  final date = tx['date'] as DateTime;
                  final formattedDate = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                  final value = tx['value'] as double;
                  final symbol = tx['tokenSymbol'] as String;

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: isLast ? null : const Border(bottom: BorderSide(color: AppColors.border)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Row(
                            children: [
                              Icon(
                                isSend ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                                color: isSend ? AppColors.error : AppColors.success,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isSend ? 'SEND' : 'RECEIVE',
                                      style: const TextStyle(color: AppColors.textMain, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      shortHash,
                                      style: const TextStyle(color: AppColors.textDim, fontSize: 9, fontFamily: 'monospace'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            formattedDate,
                            style: const TextStyle(color: AppColors.textDim, fontSize: 11),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            '${value.toStringAsFixed(4)} $symbol',
                            style: const TextStyle(color: AppColors.white, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            isError ? 'FAILED' : 'SUCCESS',
                            style: TextStyle(
                              color: isError ? AppColors.error : AppColors.success,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.open_in_new_rounded, size: 14, color: AppColors.primary),
                          onPressed: () {
                            if (hash.isNotEmpty) {
                              launchUrl(
                                Uri.parse('$explorerBase/tx/$hash'),
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          tooltip: 'settings.billing.view_on_explorer'.tr(),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardTransactionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHistoryHeader(
          title: 'settings.billing.card_transactions_title'.tr(),
          isExpanded: _showCardTxHistory,
          isLoading: _isFetchingCardTransactions,
          hasConfig: true,
          onToggle: () {
            setState(() {
              _showCardTxHistory = !_showCardTxHistory;
            });
            if (_showCardTxHistory && _cardTransactions.isEmpty) {
              _fetchCardTransactions();
            }
          },
          onRefresh: _fetchCardTransactions,
        ),
        if (_showCardTxHistory) ...[
          const SizedBox(height: 8),
          _buildCardTransactionList(_cardTransactions),
        ],
      ],
    );
  }

  Widget _buildCardTransactionList(List<Map<String, dynamic>> txs) {
    if (txs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          color: AppColors.surface,
        ),
        child: Text(
          'settings.billing.card_no_transactions'.tr(),
          style: const TextStyle(color: AppColors.textDim, fontSize: 12),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        color: AppColors.surface,
      ),
      child: Column(
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
              color: AppColors.background,
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'settings.billing.card_merchant'.tr().toUpperCase(),
                    style: const TextStyle(color: AppColors.textDim, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'settings.billing.date'.tr().toUpperCase(),
                    style: const TextStyle(color: AppColors.textDim, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Text(
                    'settings.billing.card_purpose'.tr().toUpperCase(),
                    style: const TextStyle(color: AppColors.textDim, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'settings.billing.card_amount'.tr().toUpperCase(),
                    style: const TextStyle(color: AppColors.textDim, fontSize: 9, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'settings.billing.status'.tr().toUpperCase(),
                    style: const TextStyle(color: AppColors.textDim, fontSize: 9, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
          // Scrollable Rows
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 250),
            child: SingleChildScrollView(
              child: Column(
                children: txs.map((tx) {
                  final isLast = txs.last == tx;
                  final recipient = tx['recipient'] as String? ?? '';
                  final purpose = tx['purpose'] as String? ?? '';
                  final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
                  final status = tx['status'] as String? ?? 'SUCCESS';
                  
                  DateTime date;
                  try {
                    date = DateTime.parse(tx['date'] as String);
                  } catch (_) {
                    date = DateTime.now();
                  }
                  final formattedDate = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

                  final isSuccess = status == 'SUCCESS';

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: isLast ? null : const Border(bottom: BorderSide(color: AppColors.border)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            recipient == 'Top Up' ? 'settings.billing.topup_label'.tr() : recipient,
                            style: const TextStyle(color: AppColors.textMain, fontSize: 12, fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            formattedDate,
                            style: const TextStyle(color: AppColors.textDim, fontSize: 11),
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: Text(
                            purpose,
                            style: const TextStyle(color: AppColors.textDim, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            '\$${amount.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: recipient == 'Top Up' ? AppColors.success : AppColors.textMain,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Container(
                            alignment: Alignment.centerRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isSuccess
                                    ? AppColors.success.withValues(alpha: 0.15)
                                    : AppColors.error.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  color: isSuccess ? AppColors.success : AppColors.error,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderList(List<Map<String, dynamic>> orders) {
    if (orders.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          color: AppColors.surface,
        ),
        child: Text(
          'settings.billing.no_orders'.tr(),
          style: const TextStyle(color: AppColors.textDim, fontSize: 12),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        color: AppColors.surface,
      ),
      child: Column(
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
              color: AppColors.background,
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'settings.billing.pair'.tr().toUpperCase(),
                    style: const TextStyle(color: AppColors.textDim, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'settings.billing.date'.tr().toUpperCase(),
                    style: const TextStyle(color: AppColors.textDim, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'settings.billing.side'.tr().toUpperCase(),
                    style: const TextStyle(color: AppColors.textDim, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'settings.billing.type'.tr().toUpperCase(),
                    style: const TextStyle(color: AppColors.textDim, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'settings.billing.amount'.tr().toUpperCase(),
                    style: const TextStyle(color: AppColors.textDim, fontSize: 9, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'settings.billing.price'.tr().toUpperCase(),
                    style: const TextStyle(color: AppColors.textDim, fontSize: 9, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'settings.billing.status'.tr().toUpperCase(),
                    style: const TextStyle(color: AppColors.textDim, fontSize: 9, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
          // Scrollable Rows
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 250),
            child: SingleChildScrollView(
              child: Column(
                children: orders.map((order) {
                  final isLast = orders.last == order;
                  final symbol = order['symbol'] as String? ?? 'UNKNOWN';
                  final side = order['side'] as String? ?? 'BUY';
                  final type = order['type'] as String? ?? 'LIMIT';
                  final price = double.tryParse(order['price']?.toString() ?? '0') ?? 0.0;
                  final origQty = double.tryParse(order['origQty']?.toString() ?? '0') ?? 0.0;
                  final executedQty = double.tryParse(order['executedQty']?.toString() ?? '0') ?? 0.0;
                  final cumQuoteQty = double.tryParse((order['cumulativeQuoteQty'] ?? order['cummulativeQuoteQty'])?.toString() ?? '0') ?? 0.0;
                  final status = order['status'] as String? ?? 'NEW';

                  final int timeMs = order['time'] as int? ?? 0;
                  final date = DateTime.fromMillisecondsSinceEpoch(timeMs);
                  final formattedDate = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

                  final isBuy = side.toUpperCase() == 'BUY';
                  Color statusColor = AppColors.textDim;
                  if (status == 'FILLED') statusColor = AppColors.success;
                  else if (status == 'NEW') statusColor = const Color(0xFFF3BA2F); // yellow
                  else if (status == 'CANCELED' || status == 'REJECTED') statusColor = AppColors.error;

                  double displayPrice = price;
                  if (displayPrice == 0.0 && executedQty > 0.0) {
                    displayPrice = cumQuoteQty / executedQty;
                  }

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: isLast ? null : const Border(bottom: BorderSide(color: AppColors.border)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                symbol,
                                style: const TextStyle(color: AppColors.textMain, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'ID: ${order['orderId']}',
                                style: const TextStyle(color: AppColors.textDim, fontSize: 9, fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            formattedDate,
                            style: const TextStyle(color: AppColors.textDim, fontSize: 11),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            side,
                            style: TextStyle(
                              color: isBuy ? AppColors.success : AppColors.error,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            type,
                            style: const TextStyle(color: AppColors.textDim, fontSize: 11),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            origQty.toStringAsFixed(4),
                            style: const TextStyle(color: AppColors.white, fontSize: 11, fontFamily: 'monospace'),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            displayPrice > 0 ? '\$${displayPrice.toStringAsFixed(2)}' : 'MARKET',
                            style: const TextStyle(color: AppColors.white, fontSize: 11, fontFamily: 'monospace'),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            status,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalTransactionsSection() {
    if (!_isAppKitConnected || _connectedAddress == null) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _buildHistoryHeader(
          title: 'settings.billing.transactions'.tr(),
          isExpanded: _showPersonalTxHistory,
          isLoading: _isFetchingPersonalTransactions,
          hasConfig: true,
          onToggle: () {
            setState(() {
              _showPersonalTxHistory = !_showPersonalTxHistory;
            });
            if (_showPersonalTxHistory && _personalTransactions.isEmpty) {
              _fetchPersonalWalletTransactions();
            }
          },
          onRefresh: _fetchPersonalWalletTransactions,
        ),
        if (_showPersonalTxHistory) ...[
          const SizedBox(height: 8),
          if (_personalTransactionsError != null) ...[
            _buildErrorBanner(
              _personalTransactionsError!,
              explorerApiKeyName: _getExplorerApiKeyNameForChain(
                _cleanChainId(_appKitModal?.selectedChain?.chainId ?? '56'),
              ),
              onSaved: _fetchPersonalWalletTransactions,
            ),
            const SizedBox(height: 8),
          ],
          _buildAddManualTransactionRow(
            _connectedAddress!,
            _cleanChainId(_appKitModal?.selectedChain?.chainId ?? '56'),
            isAgent: false,
          ),
          const SizedBox(height: 8),
          _buildTransactionList(
            _personalTransactions,
            chainId: _cleanChainId(_appKitModal?.selectedChain?.chainId ?? '56'),
          ),
        ],
      ],
    );
  }

  Widget _buildAgentTransactionsSection() {
    if (_agentAddress == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _buildHistoryHeader(
          title: 'settings.billing.transactions'.tr(),
          isExpanded: _showAgentTxHistory,
          isLoading: _isFetchingAgentTransactions,
          hasConfig: true,
          onToggle: () {
            setState(() {
              _showAgentTxHistory = !_showAgentTxHistory;
            });
            if (_showAgentTxHistory && _agentTransactions.isEmpty) {
              _fetchAgentWalletTransactions();
            }
          },
          onRefresh: _fetchAgentWalletTransactions,
        ),
        if (_showAgentTxHistory) ...[
          const SizedBox(height: 8),
          if (_agentTransactionsError != null) ...[
            _buildErrorBanner(
              _agentTransactionsError!,
              explorerApiKeyName: _getExplorerApiKeyNameForChain(_agentActiveChainId),
              onSaved: _fetchAgentWalletTransactions,
            ),
            const SizedBox(height: 8),
          ],
          _buildAddManualTransactionRow(
            _agentAddress!,
            _agentActiveChainId,
            isAgent: true,
          ),
          const SizedBox(height: 8),
          _buildTransactionList(_agentTransactions, chainId: _agentActiveChainId),
        ],
      ],
    );
  }

  Widget _buildBinanceOrdersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _buildHistoryHeader(
          title: 'settings.billing.orders'.tr(),
          isExpanded: _showBinanceOrders,
          isLoading: _isFetchingBinanceOrders,
          hasConfig: _hasBinanceConfigured,
          onToggle: () {
            setState(() {
              _showBinanceOrders = !_showBinanceOrders;
            });
            if (_showBinanceOrders && _binanceOrders.isEmpty) {
              _fetchBinanceOrders();
            }
          },
          onRefresh: _fetchBinanceOrders,
        ),
        if (_showBinanceOrders) ...[
          const SizedBox(height: 8),
          if (_binanceOrdersError != null) ...[
            _buildErrorBanner(_binanceOrdersError!),
            if (_binanceOrders.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildOrderList(_binanceOrders),
            ],
          ] else ...[
            _buildOrderList(_binanceOrders),
          ],
        ],
      ],
    );
  }

  Widget _buildBinanceDemoOrdersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _buildHistoryHeader(
          title: 'settings.billing.orders'.tr(),
          isExpanded: _showBinanceDemoOrders,
          isLoading: _isFetchingBinanceDemoOrders,
          hasConfig: _hasBinanceDemoConfigured,
          onToggle: () {
            setState(() {
              _showBinanceDemoOrders = !_showBinanceDemoOrders;
            });
            if (_showBinanceDemoOrders && _binanceDemoOrders.isEmpty) {
              _fetchBinanceDemoOrders();
            }
          },
          onRefresh: _fetchBinanceDemoOrders,
        ),
        if (_showBinanceDemoOrders) ...[
          const SizedBox(height: 8),
          if (_binanceDemoOrdersError != null) ...[
            _buildErrorBanner(_binanceDemoOrdersError!),
            if (_binanceDemoOrders.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildOrderList(_binanceDemoOrders),
            ],
          ] else ...[
            _buildOrderList(_binanceDemoOrders),
          ],
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(configProvider, (prev, next) {
      if (!_isInit) return;
      if (!isSaveLoading && next.billing != ref.read(configProvider).billing) {
        setState(() {
          _limitController.text = next.billing.limit.toStringAsFixed(2);
          _balanceController.text = next.billing.balance.toStringAsFixed(2);
          _autonomous = next.billing.autonomous;
        });
        _fetchCardTransactions();
      }

      // Auto-load Reown Project ID once it is fetched from the gateway vault
      final hasReownKey = next.vaultKeys.contains('reown_project_id') ||
          next.vaultKeys.contains('reown_project_id_api_key');
      if (hasReownKey &&
          _reownProjectIdController.text.isEmpty &&
          !_isLoadingReownConfig &&
          _appKitModal == null) {
        _loadReownConfig();
      }
    });

    ref.listen(shellProvider.select((s) => s.settingsTabIndex), (prev, next) {
      if (prev == 7 && next != 7 && _isEditing && !isSaveLoading) {
        _saveBillingSettings(silent: true);
      }
    });

    final isCardSet = _cardNumberLast4 != null;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && _isEditing && !isSaveLoading) {
          _saveBillingSettings(silent: true);
        }
      },
      child: AppSettingsPage(
        onBack: widget.onBack,
        onNext: widget.onNext,
        onSave: _isEditing ? _saveBillingSettings : null,
        isSaveLoading: isSaveLoading,
        topPadding: widget.topPadding,
        subTabLabels: const [
          'settings.billing.tab_credit_card',
          'settings.billing.tab_crypto',
        ],
        currentSubTabIndex: _currentSubTabIndex,
        onSubTabChanged: (index) {
          setState(() {
            _currentSubTabIndex = index;
          });
        },
        children: [
          const AppSectionHeader('settings.billing.section', large: true),
          Text(
            'settings.billing.desc'.tr(),
            style: const TextStyle(
              fontSize: AppConstants.fontSizeBody,
              color: AppColors.textDim,
            ),
          ),
          const SizedBox(height: AppConstants.settingsSectionSpacing),

          // Conditional rendering of tabs
          if (_currentSubTabIndex == 0) ...[
            // 1. Credit Card details section
            Text(
              'settings.billing.card_section'.tr().toUpperCase(),
              style: const TextStyle(
                color: AppColors.textDim,
                fontSize: AppConstants.fontSizeLabelTiny,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: AppConstants.settingsHeaderSpacing),

            if (_isLoadingCardDetails)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (isCardSet) ...[
              _buildCreditCard(),
              const SizedBox(height: 16),
              _buildCardTransactionsSection(),
            ]
            else
              _buildCreditCardForm(),
          ] else ...[
            // 1. Crypto Wallet section
            Text(
              'settings.billing.tab_crypto'.tr().toUpperCase(),
              style: const TextStyle(
                color: AppColors.textDim,
                fontSize: AppConstants.fontSizeLabelTiny,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: AppConstants.settingsHeaderSpacing),

            // Visibility Toggles
            AppSwitchListTile(
              title: Text(
                'settings.billing.show_personal_wallet_label'.tr(),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              value: _showPersonalWallet,
              onChanged: (val) {
                _saveWalletVisibilitySetting('show_personal_wallet', val);
              },
            ),
            AppSwitchListTile(
              title: Text(
                'settings.billing.show_agent_wallet_label'.tr(),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              value: _showAgentWallet,
              onChanged: (val) {
                _saveWalletVisibilitySetting('show_agent_wallet', val);
              },
            ),
            const SizedBox(height: 8),
            AppSwitchListTile(
              title: Text(
                'settings.billing.show_binance_label'.tr(),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              value: _showBinance,
              onChanged: (val) {
                _saveWalletVisibilitySetting('show_binance', val);
              },
            ),
            const SizedBox(height: 8),
            AppSwitchListTile(
              title: Text(
                'settings.billing.show_binance_demo_label'.tr(),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              value: _showBinanceDemo,
              onChanged: (val) {
                _saveWalletVisibilitySetting('show_binance_demo', val);
              },
            ),
            const SizedBox(height: 16),

            if (_showPersonalWallet) ...[
              // Reown Project ID configuration Input (only shown when not connected)
              if (!_isAppKitConnected) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    color: AppColors.surface,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AppFormLabel('settings.billing.reown_project_id_label'),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _reownProjectIdController,
                              style: const TextStyle(color: AppColors.white, fontSize: 13),
                              decoration: AppInputDecoration.compact(
                                hint: 'settings.billing.reown_project_id_hint'.tr(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: _saveReownProjectId,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.white,
                              foregroundColor: AppColors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                            ),
                            child: Text(
                              'settings.billing.save_project_id'.tr().toUpperCase(),
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              if (_isLoadingReownConfig || _isAppKitModalInitializing)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_appKitInitError != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.error, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          'Reown Initialization Failed'.toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _appKitInitError!,
                          style: const TextStyle(color: AppColors.textDim, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => _initAppKit(_reownProjectIdController.text.trim()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.white,
                            foregroundColor: AppColors.black,
                            minimumSize: const Size(120, 40),
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                          ),
                          child: const Text('RETRY'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_appKitModal == null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        Text(
                          'settings.billing.reown_id_required'.tr(),
                          style: const TextStyle(color: AppColors.textDim, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        InkWell(
                          onTap: () => launchUrl(
                            Uri.parse('https://cloud.reown.com/'),
                            mode: LaunchMode.externalApplication,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.border),
                              color: AppColors.surface,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.open_in_new_rounded,
                                  size: 16,
                                  color: AppColors.white,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Create Reown Project ID'.toUpperCase(),
                                  style: const TextStyle(
                                    color: AppColors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_isAppKitConnected) ...[
                _buildCryptoWalletCard(),
                const SizedBox(height: 16),
                _buildCryptoWalletActions(),
                const SizedBox(height: 24),
                _buildWalletAssetsSection(),
                _buildPersonalTransactionsSection(),

              ] else
                _buildConnectWalletView(),
            ],

            if (_showAgentWallet) ...[
              _buildAgentWalletSection(showDivider: _showPersonalWallet),
              _buildAgentTransactionsSection(),
            ],
            if (_showBinance) ...[
              _buildBinanceSection(showDivider: _showPersonalWallet || _showAgentWallet),
              _buildBinanceOrdersSection(),
            ],
            if (_showBinanceDemo) ...[
              _buildBinanceDemoSection(showDivider: _showPersonalWallet || _showAgentWallet || _showBinance),
              _buildBinanceDemoOrdersSection(),
            ],
          ],

          const SizedBox(height: AppConstants.settingsSectionSpacing),

          // 2. Budget limits section
          Text(
            'settings.billing.budget_section'.tr().toUpperCase(),
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: AppConstants.fontSizeLabelTiny,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppConstants.settingsHeaderSpacing),

          // Limits TextFields
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppFormLabel('settings.billing.limit_label'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _limitController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                      ],
                      style: const TextStyle(color: AppColors.white, fontSize: 13),
                      decoration: AppInputDecoration.compact(
                        hint: 'settings.billing.limit_hint'.tr(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AppFormLabel('settings.billing.balance_label'),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _balanceController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                            ],
                            style: const TextStyle(color: AppColors.white, fontSize: 13),
                            decoration: AppInputDecoration.compact(
                              hint: 'settings.billing.balance_hint'.tr(),
                            ),
                          ),
                        ),
                        // Show active Top Up trigger depending on connected payment option
                        if ((_currentSubTabIndex == 0 && isCardSet) || (_currentSubTabIndex == 1 && _isAppKitConnected)) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
                            onPressed: _currentSubTabIndex == 0 ? _showTopUpDialog : _showCryptoTopUpDialog,
                            tooltip: 'settings.billing.topup_label'.tr(),
                            style: IconButton.styleFrom(
                              minimumSize: const Size(40, 40),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: AppConstants.settingsSectionSpacing),

          // 3. Autonomous Actions switch
          AppSwitchListTile(
            title: Text(
              'settings.billing.autonomous_label'.tr(),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              'settings.billing.autonomous_desc'.tr(),
              style: const TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
            value: _autonomous,
            onChanged: (val) {
              setState(() {
                _autonomous = val;
                _isEditing = true;
              });
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final trimmed = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (trimmed.length > 16) {
      return oldValue;
    }
    final buffer = StringBuffer();
    for (int i = 0; i < trimmed.length; i++) {
      if (i > 0 && i % 4 == 0) {
        buffer.write(' ');
      }
      buffer.write(trimmed[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class CardExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final trimmed = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (trimmed.length > 4) {
      return oldValue;
    }
    final buffer = StringBuffer();
    for (int i = 0; i < trimmed.length; i++) {
      if (i == 2) {
        buffer.write('/');
      }
      buffer.write(trimmed[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class FakeWebViewPlatform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return FakeWebViewController(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return FakeWebViewWidget(params);
  }

  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) {
    return FakeWebViewCookieManager(params);
  }
}

class FakeWebViewController extends PlatformWebViewController {
  FakeWebViewController(PlatformWebViewControllerCreationParams params)
      : super.implementation(params);
}

class FakeWebViewWidget extends PlatformWebViewWidget {
  FakeWebViewWidget(PlatformWebViewWidgetCreationParams params)
      : super.implementation(params);

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class FakeWebViewCookieManager extends PlatformWebViewCookieManager {
  FakeWebViewCookieManager(PlatformWebViewCookieManagerCreationParams params)
      : super.implementation(params);
}

class ERC20TokenSpec {
  final String symbol;
  final String name;
  final String address;
  final int decimals;
  final double priceUsd;
  final IconData icon;
  final Color color;

  const ERC20TokenSpec({
    required this.symbol,
    required this.name,
    required this.address,
    required this.decimals,
    required this.priceUsd,
    required this.icon,
    required this.color,
  });
}

const String _erc20Abi = '''
[
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
  }
]
''';

List<ERC20TokenSpec> _getTokensForChain(String chainId) {
  if (chainId == '1') {
    return const [
      ERC20TokenSpec(
        symbol: 'BNB',
        name: 'Binance Coin',
        address: '0xB8c77482e45F1F44dE1745F52C74426C631bDD52',
        decimals: 18,
        priceUsd: 580.00,
        icon: Icons.stars_rounded,
        color: Color(0xFFF3BA2F),
      ),
      ERC20TokenSpec(
        symbol: 'USDT',
        name: 'Tether USD',
        address: '0xdAC17F958D2ee523a2206206994597C13D831ec7',
        decimals: 6,
        priceUsd: 1.00,
        icon: Icons.monetization_on_rounded,
        color: Color(0xFF26A17B),
      ),
      ERC20TokenSpec(
        symbol: 'USDC',
        name: 'USD Coin',
        address: '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',
        decimals: 6,
        priceUsd: 1.00,
        icon: Icons.monetization_on_rounded,
        color: Color(0xFF2775CA),
      ),
      ERC20TokenSpec(
        symbol: 'LINK',
        name: 'Chainlink',
        address: '0x514910771AF9Ca656af840dff83E8264ECF986CA',
        decimals: 18,
        priceUsd: 16.00,
        icon: Icons.link_rounded,
        color: Color(0xFF375BD2),
      ),
      ERC20TokenSpec(
        symbol: 'MATIC',
        name: 'Polygon',
        address: '0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0',
        decimals: 18,
        priceUsd: 0.45,
        icon: Icons.hexagon_rounded,
        color: Color(0xFF8247E5),
      ),
    ];
  } else if (chainId == '56') {
    return const [
      ERC20TokenSpec(
        symbol: 'ETH',
        name: 'Ethereum',
        address: '0x2170Ed0880ac9A755fd29B2688956BD959F933F8',
        decimals: 18,
        priceUsd: 3450.00,
        icon: Icons.generating_tokens_rounded,
        color: Color(0xFF627EEA),
      ),
      ERC20TokenSpec(
        symbol: 'USDT',
        name: 'Tether USD',
        address: '0x55d398326f99059fF775485246999027B3197955',
        decimals: 18,
        priceUsd: 1.00,
        icon: Icons.monetization_on_rounded,
        color: Color(0xFF26A17B),
      ),
      ERC20TokenSpec(
        symbol: 'USDC',
        name: 'USD Coin',
        address: '0x8AC76a51cc950d9822D68b83fE1Ad97B32CD580d',
        decimals: 18,
        priceUsd: 1.00,
        icon: Icons.monetization_on_rounded,
        color: Color(0xFF2775CA),
      ),
      ERC20TokenSpec(
        symbol: 'LINK',
        name: 'Chainlink',
        address: '0xF8A3151030485f3850b2ed3fd507e3c8808D53a4',
        decimals: 18,
        priceUsd: 16.00,
        icon: Icons.link_rounded,
        color: Color(0xFF375BD2),
      ),
      ERC20TokenSpec(
        symbol: 'MATIC',
        name: 'Polygon',
        address: '0xCC427f4fe5873b13027a59A63CEF5fF102B78531',
        decimals: 18,
        priceUsd: 0.45,
        icon: Icons.hexagon_rounded,
        color: Color(0xFF8247E5),
      ),
    ];
  } else if (chainId == '137') {
    return const [
      ERC20TokenSpec(
        symbol: 'ETH',
        name: 'Ethereum',
        address: '0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619',
        decimals: 18,
        priceUsd: 3450.00,
        icon: Icons.generating_tokens_rounded,
        color: Color(0xFF627EEA),
      ),
      ERC20TokenSpec(
        symbol: 'BNB',
        name: 'Binance Coin',
        address: '0xA649325Aa7C5091d12D4E98aA677c7626e2e5A67',
        decimals: 18,
        priceUsd: 580.00,
        icon: Icons.stars_rounded,
        color: Color(0xFFF3BA2F),
      ),
      ERC20TokenSpec(
        symbol: 'USDT',
        name: 'Tether USD',
        address: '0xc2132D05D31c914a87C6611C10748AEb04B58e8F',
        decimals: 6,
        priceUsd: 1.00,
        icon: Icons.monetization_on_rounded,
        color: Color(0xFF26A17B),
      ),
      ERC20TokenSpec(
        symbol: 'USDC',
        name: 'USD Coin',
        address: '0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359',
        decimals: 6,
        priceUsd: 1.00,
        icon: Icons.monetization_on_rounded,
        color: Color(0xFF2775CA),
      ),
      ERC20TokenSpec(
        symbol: 'LINK',
        name: 'Chainlink',
        address: '0xb0897686c545045aFc77CF20eC7A532E3120E0F1',
        decimals: 18,
        priceUsd: 16.00,
        icon: Icons.link_rounded,
        color: Color(0xFF375BD2),
      ),
    ];
  } else if (chainId == '97') {
    return const [
      ERC20TokenSpec(
        symbol: 'USDT',
        name: 'Tether USD',
        address: '0x337610d27c682E347C9cD60BD4b3b107C9d34dDd',
        decimals: 18,
        priceUsd: 1.00,
        icon: Icons.monetization_on_rounded,
        color: Color(0xFF26A17B),
      ),
      ERC20TokenSpec(
        symbol: 'USDC',
        name: 'USD Coin',
        address: '0x64544E66463EC5c8F43f256037C0d71911475A9C',
        decimals: 18,
        priceUsd: 1.00,
        icon: Icons.monetization_on_rounded,
        color: Color(0xFF2775CA),
      ),
    ];
  } else if (chainId == '11155111') {
    return const [
      ERC20TokenSpec(
        symbol: 'USDT',
        name: 'Tether USD',
        address: '0xaA8E23Fb1079EA71e0a56F48a2aa51851D8433D0',
        decimals: 6,
        priceUsd: 1.00,
        icon: Icons.monetization_on_rounded,
        color: Color(0xFF26A17B),
      ),
      ERC20TokenSpec(
        symbol: 'USDC',
        name: 'USD Coin',
        address: '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238',
        decimals: 6,
        priceUsd: 1.00,
        icon: Icons.monetization_on_rounded,
        color: Color(0xFF2775CA),
      ),
    ];
  } else if (chainId == '80002') {
    return const [
      ERC20TokenSpec(
        symbol: 'USDT',
        name: 'Tether USD',
        address: '0x1fdE0e81d154ee464a9c6B90b5220c33aCE4e82f',
        decimals: 6,
        priceUsd: 1.00,
        icon: Icons.monetization_on_rounded,
        color: Color(0xFF26A17B),
      ),
      ERC20TokenSpec(
        symbol: 'USDC',
        name: 'USD Coin',
        address: '0x41e945974b7c647a54cd65c92c48b7b137d6e4b4',
        decimals: 6,
        priceUsd: 1.00,
        icon: Icons.monetization_on_rounded,
        color: Color(0xFF2775CA),
      ),
    ];
  }
  return const [];
}


