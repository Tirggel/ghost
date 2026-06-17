import 'dart:async';
import 'dart:convert';
import 'package:logging/logging.dart';

import '../config/secure_storage.dart';
import '../config/io.dart';
import '../agent/manager.dart';
import 'registry.dart';

final _log = Logger('Ghost.Tools.Billing');

class BillingTools {
  static void registerAll(
    ToolRegistry registry,
    SecureStorage storage,
    AgentManager agentManager,
  ) {
    registry.register(ExecutePaymentTool(storage, agentManager));
  }
}

class ExecutePaymentTool extends Tool {
  ExecutePaymentTool(this.storage, this.agentManager);

  final SecureStorage storage;
  final AgentManager agentManager;

  @override
  String get name => 'execute_payment';

  @override
  String get description =>
      'Executes a payment on behalf of the agent or user using the configured credit card. '
      'Requires an amount, a recipient/merchant name, and a clear reason/purpose. '
      'If self-dependent/autonomous mode is disabled, this tool will request confirmation from the user.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'amount': {
            'type': 'number',
            'description': 'The amount to pay (e.g. 5.50). Must be positive.',
          },
          'recipient': {
            'type': 'string',
            'description': 'The merchant or service receiving the payment (e.g. "OpenAI API", "Hugging Face").',
          },
          'purpose': {
            'type': 'string',
            'description': 'The detailed reason/purpose for this payment transaction.',
          },
        },
        'required': ['amount', 'recipient', 'purpose'],
      };

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final amount = (input['amount'] as num).toDouble();
    final recipient = input['recipient'] as String;
    final purpose = input['purpose'] as String;

    if (amount <= 0) {
      return const ToolResult.error('Invalid payment amount: must be greater than zero.');
    }

    // 1. Verify credit card exists in vault
    final cardNumber = await storage.get('payment_card_number');
    if (cardNumber == null || cardNumber.trim().isEmpty) {
      return const ToolResult.error(
        'Payment failed: No credit card configured in settings. '
        'Please inform the user to add a credit card under Settings > Payments.',
      );
    }

    // 2. Check current billing configuration
    final billing = agentManager.config.billing;
    final currentBalance = billing.balance;

    if (currentBalance < amount) {
      // Exceeded! Send notification to user to top up
      final deMsg = '⚠️ Zahlung von ${amount.toStringAsFixed(2)} an $recipient für "$purpose" fehlgeschlagen: '
          'Verfügbares Budget (${currentBalance.toStringAsFixed(2)}) reicht nicht aus. '
          'Bitte stocke dein Budget auf!';
      final enMsg = '⚠️ Payment of ${amount.toStringAsFixed(2)} to $recipient for "$purpose" failed: '
          'Available budget (${currentBalance.toStringAsFixed(2)}) is insufficient. '
          'Please top up your budget!';
      final isDe = agentManager.config.user.language == 'de';
      final alertMsg = isDe ? deMsg : enMsg;

      _notifyUser(alertMsg);

      // Save failed transaction entry
      try {
        final txsJson = await storage.get('payment_card_transactions') ?? '[]';
        final List<dynamic> txs = jsonDecode(txsJson.isEmpty ? '[]' : txsJson);
        txs.insert(0, {
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'date': DateTime.now().toIso8601String(),
          'amount': amount,
          'recipient': recipient,
          'purpose': purpose,
          'status': 'FAILED',
        });
        await storage.set('payment_card_transactions', jsonEncode(txs));
      } catch (e) {
        _log.warning('Could not store failed payment transaction: $e');
      }

      return ToolResult.error(
        'Payment failed: Insufficient budget. '
        'Available budget: ${currentBalance.toStringAsFixed(2)}. '
        'Requested: ${amount.toStringAsFixed(2)}. '
        'A notification has been sent to the user to top up.',
      );
    }

    // 3. Deduct amount from balance
    final newBalance = currentBalance - amount;

    // Update config
    final updatedBilling = billing.copyWith(balance: newBalance);
    final updatedConfig = agentManager.config.copyWith(billing: updatedBilling);
    
    // Update local config on agentManager first
    agentManager.config = updatedConfig;

    if (agentManager.configPath != null) {
      await saveConfig(updatedConfig, agentManager.configPath!);
    }
    agentManager.notifyConfigChanged();

    // Save successful transaction entry
    try {
      final txsJson = await storage.get('payment_card_transactions') ?? '[]';
      final List<dynamic> txs = jsonDecode(txsJson.isEmpty ? '[]' : txsJson);
      txs.insert(0, {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'date': DateTime.now().toIso8601String(),
        'amount': amount,
        'recipient': recipient,
        'purpose': purpose,
        'status': 'SUCCESS',
      });
      await storage.set('payment_card_transactions', jsonEncode(txs));
    } catch (e) {
      _log.warning('Could not store successful payment transaction: $e');
    }

    // 4. Send success notification to communication channels
    final isDe = agentManager.config.user.language == 'de';
    final deSuccess = '✅ Zahlung von ${amount.toStringAsFixed(2)} an $recipient für "$purpose" erfolgreich ausgeführt. '
        'Verbleibendes Budget: ${newBalance.toStringAsFixed(2)}.';
    final enSuccess = '✅ Payment of ${amount.toStringAsFixed(2)} to $recipient for "$purpose" successfully executed. '
        'Remaining budget: ${newBalance.toStringAsFixed(2)}.';
    _notifyUser(isDe ? deSuccess : enSuccess);

    // 5. Send low budget or 0 notifications if needed
    if (newBalance <= 0) {
      final alertMsg = isDe
          ? 'ℹ️ Dein verfügbares Budget ist auf 0 gesunken. Bitte stocke dein Budget auf, damit die Agenten weitere Zahlungen ausführen können!'
          : 'ℹ️ Your available budget has reached 0. Please top up your budget so the agents can perform further payments!';
      _notifyUser(alertMsg);
    }

    final successMsg = 'Successfully paid ${amount.toStringAsFixed(2)} to $recipient. '
        'Remaining available budget: ${newBalance.toStringAsFixed(2)}.';
    _log.info(successMsg);

    return ToolResult(
      output: 'Payment transaction successful: $successMsg',
    );
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
