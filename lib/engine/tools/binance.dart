import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
// import 'package:logging/logging.dart';

import '../config/secure_storage.dart';
import '../infra/crypto.dart';
import 'registry.dart';

// final _log = Logger('Ghost.Tools.Binance');

class BinanceTools {
  static void registerAll(ToolRegistry registry, SecureStorage storage) {
    registry.register(BinanceGetBalancesTool(storage));
    registry.register(BinanceGetTickerTool());
    registry.register(BinanceCreateOrderTool(storage));
    registry.register(BinanceDemoGetBalancesTool(storage));
    registry.register(BinanceDemoCreateOrderTool(storage));
  }
}

class BinanceGetBalancesTool extends Tool {
  BinanceGetBalancesTool(this.storage);

  final SecureStorage storage;

  @override
  String get name => 'binance_get_balances';

  @override
  String get description =>
      'Retrieves the account asset balances from Binance. '
      'Returns a list of assets with non-zero balances. '
      'Requires Binance credentials to be configured in settings.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {},
      };

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final apiKey = await storage.get('binance_api_key');
    final secretKey = await storage.get('binance_secret_key');

    if (apiKey == null ||
        apiKey.trim().isEmpty ||
        secretKey == null ||
        secretKey.trim().isEmpty) {
      return const ToolResult.error(
        'Binance credentials are not configured. '
        'Please inform the user to configure their Binance API Key and Secret Key under Settings > Payments > Cryptos.',
      );
    }

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final query = 'timestamp=$timestamp';
      final signature = hmacSha256(secretKey, query);
      final signedUrl = 'https://api.binance.com/api/v3/account?$query&signature=$signature';

      final response = await http.get(
        Uri.parse(signedUrl),
        headers: {
          'X-MBX-APIKEY': apiKey,
        },
      );

      if (response.statusCode != 200) {
        return ToolResult.error(
          'Failed to retrieve Binance balances (Status ${response.statusCode}): ${response.body}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final balances = (data['balances'] as List<dynamic>?) ?? [];
      final nonZeroBalances = balances.where((b) {
        final free = double.tryParse(b['free']?.toString() ?? '0') ?? 0.0;
        final locked = double.tryParse(b['locked']?.toString() ?? '0') ?? 0.0;
        return free > 0 || locked > 0;
      }).toList();

      if (nonZeroBalances.isEmpty) {
        return const ToolResult(
          output: 'Your Binance account does not have any assets with a non-zero balance.',
        );
      }

      final buffer = StringBuffer();
      buffer.writeln('Binance Spot Wallet Balances:');
      for (final b in nonZeroBalances) {
        final asset = b['asset'];
        final free = b['free'];
        final locked = b['locked'];
        buffer.writeln('- $asset: Free: $free, Locked: $locked');
      }

      return ToolResult(output: buffer.toString());
    } catch (e) {
      return ToolResult.error('Failed to query Binance balances: $e');
    }
  }
}

class BinanceGetTickerTool extends Tool {
  @override
  String get name => 'binance_get_ticker';

  @override
  String get description =>
      'Retrieves ticker price information for a cryptocurrency symbol from Binance. '
      'If symbol is not provided, returns major USDT pairs (BTCUSDT, ETHUSDT, BNBUSDT, SOLUSDT).';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'symbol': {
            'type': 'string',
            'description': 'The trading pair symbol (e.g. "BTCUSDT", "ETHUSDT"). Case-insensitive.',
          },
        },
      };

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final symbolInput = input['symbol'] as String?;

    try {
      if (symbolInput != null && symbolInput.trim().isNotEmpty) {
        final symbol = symbolInput.trim().toUpperCase();
        final url = 'https://api.binance.com/api/v3/ticker/price?symbol=$symbol';
        final response = await http.get(Uri.parse(url));

        if (response.statusCode != 200) {
          return ToolResult.error(
            'Failed to get price for $symbol (Status ${response.statusCode}): ${response.body}',
          );
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final price = data['price'];
        return ToolResult(output: 'The current price of $symbol is $price USD.');
      } else {
        // Return default list of major pairs
        final majorPairs = ['BTCUSDT', 'ETHUSDT', 'BNBUSDT', 'SOLUSDT'];
        final buffer = StringBuffer();
        buffer.writeln('Current Binance prices for major pairs:');

        for (final pair in majorPairs) {
          final url = 'https://api.binance.com/api/v3/ticker/price?symbol=$pair';
          final response = await http.get(Uri.parse(url));
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final price = double.tryParse(data['price']?.toString() ?? '0') ?? 0.0;
            buffer.writeln('- $pair: \$${price.toStringAsFixed(2)}');
          } else {
            buffer.writeln('- $pair: Price unavailable');
          }
        }
        return ToolResult(output: buffer.toString());
      }
    } catch (e) {
      return ToolResult.error('Failed to retrieve ticker price: $e');
    }
  }
}

class BinanceCreateOrderTool extends Tool {
  BinanceCreateOrderTool(this.storage);

  final SecureStorage storage;

  @override
  String get name => 'binance_create_order';

  @override
  String get description =>
      'Creates a buy or sell order on Binance. '
      'Requires a cryptocurrency pair symbol (e.g. "BTCUSDT"), side ("BUY" or "SELL"), '
      'type ("LIMIT" or "MARKET"), and quantity. Price is required for LIMIT orders.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'symbol': {
            'type': 'string',
            'description': 'The trading pair (e.g. "BTCUSDT", "ETHUSDT"). Case-insensitive.',
          },
          'side': {
            'type': 'string',
            'enum': ['BUY', 'SELL'],
            'description': 'Whether you want to buy or sell the asset.',
          },
          'type': {
            'type': 'string',
            'enum': ['LIMIT', 'MARKET'],
            'description': 'The order type: LIMIT or MARKET.',
          },
          'quantity': {
            'type': 'number',
            'description': 'The amount of the base asset to buy/sell.',
          },
          'price': {
            'type': 'number',
            'description': 'Price per unit of the asset (required only for LIMIT orders).',
          },
        },
        'required': ['symbol', 'side', 'type', 'quantity'],
      };

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final symbol = (input['symbol'] as String).trim().toUpperCase();
    final side = (input['side'] as String).trim().toUpperCase();
    final type = (input['type'] as String).trim().toUpperCase();
    final quantity = (input['quantity'] as num).toDouble();
    final price = input['price'] != null ? (input['price'] as num).toDouble() : null;

    if (quantity <= 0) {
      return const ToolResult.error('Order quantity must be greater than zero.');
    }

    if (type == 'LIMIT' && (price == null || price <= 0)) {
      return const ToolResult.error('Price is required and must be greater than zero for LIMIT orders.');
    }

    final apiKey = await storage.get('binance_api_key');
    final secretKey = await storage.get('binance_secret_key');

    if (apiKey == null ||
        apiKey.trim().isEmpty ||
        secretKey == null ||
        secretKey.trim().isEmpty) {
      return const ToolResult.error(
        'Binance credentials are not configured. '
        'Please configure your Binance API Key and Secret Key under Settings > Payments > Cryptos.',
      );
    }

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      final Map<String, String> params = {
        'symbol': symbol,
        'side': side,
        'type': type,
        'quantity': quantity.toString(),
        if (type == 'LIMIT' && price != null) 'price': price.toString(),
        if (type == 'LIMIT') 'timeInForce': 'GTC',
        'timestamp': timestamp.toString(),
      };

      final queryString = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
      final signature = hmacSha256(secretKey, queryString);
      final body = '$queryString&signature=$signature';

      final response = await http.post(
        Uri.parse('https://api.binance.com/api/v3/order'),
        headers: {
          'X-MBX-APIKEY': apiKey,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
      );

      if (response.statusCode != 200) {
        return ToolResult.error(
          'Failed to create Binance order (Status ${response.statusCode}): ${response.body}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final orderId = data['orderId'];
      final status = data['status'];
      final executedQty = data['executedQty'];
      final cumulativeQuoteQty = data['cumulativeQuoteQty'];

      return ToolResult(
        output: 'Binance order successfully created!\n'
            '- Order ID: $orderId\n'
            '- Status: $status\n'
            '- Executed Quantity: $executedQty\n'
            '- Cumulative Quote Cost: $cumulativeQuoteQty USDT',
      );
    } catch (e) {
      return ToolResult.error('Failed to execute Binance order: $e');
    }
  }
}

class BinanceDemoGetBalancesTool extends Tool {
  BinanceDemoGetBalancesTool(this.storage);

  final SecureStorage storage;

  @override
  String get name => 'binance_demo_get_balances';

  @override
  String get description =>
      'Retrieves the demo account asset balances from Binance Spot Demo API. '
      'Returns a list of assets with non-zero balances. '
      'Requires Binance Demo credentials to be configured in settings.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {},
      };

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final apiKey = await storage.get('binance_demo_api_key');
    final secretKey = await storage.get('binance_demo_secret_key');

    if (apiKey == null ||
        apiKey.trim().isEmpty ||
        secretKey == null ||
        secretKey.trim().isEmpty) {
      return const ToolResult.error(
        'Binance Demo credentials are not configured. '
        'Please inform the user to configure their Binance Demo API Key and Secret Key under Settings > Payments > Cryptos.',
      );
    }

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final query = 'timestamp=$timestamp';
      final signature = hmacSha256(secretKey, query);
      final signedUrl = 'https://demo-api.binance.com/api/v3/account?$query&signature=$signature';

      final response = await http.get(
        Uri.parse(signedUrl),
        headers: {
          'X-MBX-APIKEY': apiKey,
        },
      );

      if (response.statusCode != 200) {
        return ToolResult.error(
          'Failed to retrieve Binance Demo balances (Status ${response.statusCode}): ${response.body}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final balances = (data['balances'] as List<dynamic>?) ?? [];
      final nonZeroBalances = balances.where((b) {
        final free = double.tryParse(b['free']?.toString() ?? '0') ?? 0.0;
        final locked = double.tryParse(b['locked']?.toString() ?? '0') ?? 0.0;
        return free > 0 || locked > 0;
      }).toList();

      if (nonZeroBalances.isEmpty) {
        return const ToolResult(
          output: 'Your Binance Demo account does not have any assets with a non-zero balance.',
        );
      }

      final buffer = StringBuffer();
      buffer.writeln('Binance Spot Demo Wallet Balances:');
      for (final b in nonZeroBalances) {
        final asset = b['asset'];
        final free = b['free'];
        final locked = b['locked'];
        buffer.writeln('- $asset: Free: $free, Locked: $locked');
      }

      return ToolResult(output: buffer.toString());
    } catch (e) {
      return ToolResult.error('Failed to query Binance Demo balances: $e');
    }
  }
}

class BinanceDemoCreateOrderTool extends Tool {
  BinanceDemoCreateOrderTool(this.storage);

  final SecureStorage storage;

  @override
  String get name => 'binance_demo_create_order';

  @override
  String get description =>
      'Creates a buy or sell order on Binance Spot Demo API (Demo-Trading). '
      'Requires a cryptocurrency pair symbol (e.g. "BTCUSDT"), side ("BUY" or "SELL"), '
      'type ("LIMIT" or "MARKET"), and quantity. Price is required for LIMIT orders.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'symbol': {
            'type': 'string',
            'description': 'The trading pair (e.g. "BTCUSDT", "ETHUSDT"). Case-insensitive.',
          },
          'side': {
            'type': 'string',
            'enum': ['BUY', 'SELL'],
            'description': 'Whether you want to buy or sell the asset.',
          },
          'type': {
            'type': 'string',
            'enum': ['LIMIT', 'MARKET'],
            'description': 'The order type: LIMIT or MARKET.',
          },
          'quantity': {
            'type': 'number',
            'description': 'The amount of the base asset to buy/sell.',
          },
          'price': {
            'type': 'number',
            'description': 'Price per unit of the asset (required only for LIMIT orders).',
          },
        },
        'required': ['symbol', 'side', 'type', 'quantity'],
      };

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final symbol = (input['symbol'] as String).trim().toUpperCase();
    final side = (input['side'] as String).trim().toUpperCase();
    final type = (input['type'] as String).trim().toUpperCase();
    final quantity = (input['quantity'] as num).toDouble();
    final price = input['price'] != null ? (input['price'] as num).toDouble() : null;

    if (quantity <= 0) {
      return const ToolResult.error('Order quantity must be greater than zero.');
    }

    if (type == 'LIMIT' && (price == null || price <= 0)) {
      return const ToolResult.error('Price is required and must be greater than zero for LIMIT orders.');
    }

    final apiKey = await storage.get('binance_demo_api_key');
    final secretKey = await storage.get('binance_demo_secret_key');

    if (apiKey == null ||
        apiKey.trim().isEmpty ||
        secretKey == null ||
        secretKey.trim().isEmpty) {
      return const ToolResult.error(
        'Binance Demo credentials are not configured. '
        'Please configure your Binance Demo API Key and Secret Key under Settings > Payments > Cryptos.',
      );
    }

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      final Map<String, String> params = {
        'symbol': symbol,
        'side': side,
        'type': type,
        'quantity': quantity.toString(),
        if (type == 'LIMIT' && price != null) 'price': price.toString(),
        if (type == 'LIMIT') 'timeInForce': 'GTC',
        'timestamp': timestamp.toString(),
      };

      final queryString = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
      final signature = hmacSha256(secretKey, queryString);
      final body = '$queryString&signature=$signature';

      final response = await http.post(
        Uri.parse('https://demo-api.binance.com/api/v3/order'),
        headers: {
          'X-MBX-APIKEY': apiKey,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
      );

      if (response.statusCode != 200) {
        return ToolResult.error(
          'Failed to create Binance Demo order (Status ${response.statusCode}): ${response.body}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final orderId = data['orderId'];
      final status = data['status'];
      final executedQty = data['executedQty'];
      final cumulativeQuoteQty = data['cumulativeQuoteQty'];

      return ToolResult(
        output: 'Binance Demo order successfully created!\n'
            '- Order ID: $orderId\n'
            '- Status: $status\n'
            '- Executed Quantity: $executedQty\n'
            '- Cumulative Quote Cost: $cumulativeQuoteQty USDT',
      );
    } catch (e) {
      return ToolResult.error('Failed to execute Binance Demo order: $e');
    }
  }
}
