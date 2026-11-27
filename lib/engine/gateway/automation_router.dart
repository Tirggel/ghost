// Ghost — Automations RPC Router (Pure Dart, no Flutter/dart:ui imports).

import 'package:logging/logging.dart';

import '../automations/automation_manager.dart';
import '../automations/automation_models.dart';
import '../automations/cron_utils.dart';
import '../gateway/server.dart';
import '../infra/errors.dart';

final _log = Logger('Ghost.AutomationRouter');

/// Routes `automations.*` JSON-RPC 2.0 requests from the Gateway.
class AutomationRouter {
  AutomationRouter({
    required this.gateway,
    required this.automationManager,
  });

  final GatewayServer gateway;
  final AutomationManager automationManager;

  Map<String, dynamic> _serializeAutomation(
    Automation a, {
    String locale = 'en',
  }) {
    final nextRun = a.enabled ? CronUtils.computeNextRun(a.schedule) : null;
    return {
      ...a.toJson(),
      'humanSchedule': CronUtils.formatHumanReadable(a.schedule, locale: locale),
      'cronExpressions': a.schedule.toCronExpressions(),
      if (nextRun != null) 'nextRunAt': nextRun.toIso8601String(),
      'isRunning': automationManager.isRunning(a.id),
    };
  }

  void register() {
    gateway.rpcRegistry.register('automations.list', (params, context) async {
      final locale = params?['locale'] as String? ?? 'en';
      final list = automationManager.automations
          .map((a) => _serializeAutomation(a, locale: locale))
          .toList();
      return {'status': 'ok', 'automations': list};
    });

    gateway.rpcRegistry.register('automations.get', (params, context) async {
      final id = params?['id'] as String?;
      if (id == null || id.isEmpty) {
        throw ProtocolError('Missing required parameter: id');
      }
      final locale = params?['locale'] as String? ?? 'en';
      final runsLimit = (params?['runsLimit'] as num?)?.toInt() ?? 50;

      final automation = automationManager.getAutomation(id);
      if (automation == null) {
        throw ProtocolError('Automation not found: $id');
      }

      final runs = await automationManager.getRuns(id, limit: runsLimit);
      final nextRuns = automation.enabled
          ? CronUtils.computeNextRuns(automation.schedule, count: 3)
              .map((dt) => dt.toIso8601String())
              .toList()
          : const <String>[];

      return {
        'status': 'ok',
        'automation': _serializeAutomation(automation, locale: locale),
        'runs': runs.map((r) => r.toJson()).toList(),
        'nextRuns': nextRuns,
      };
    });

    gateway.rpcRegistry.register('automations.create', (params, context) async {
      final title = params?['title'] as String?;
      if (title == null || title.trim().isEmpty) {
        throw ProtocolError('Missing required parameter: title');
      }
      final instructions = params?['instructions'] as String? ?? '';
      final rawSchedule = params?['schedule'];
      final schedule = rawSchedule is Map
          ? AutomationSchedule.fromJson(Map<String, dynamic>.from(rawSchedule))
          : const AutomationSchedule();
      final agentId =
          params?['agentId'] as String? ?? Automation.autoAgentId;
      final agentName = params?['agentName'] as String?;
      final providerOverride = params?['providerOverride'] as String?;
      final modelOverride = params?['modelOverride'] as String?;
      final enabled = params?['enabled'] as bool? ?? true;
      final locale = params?['locale'] as String? ?? 'en';

      try {
        final created = await automationManager.createAutomation(
          title: title,
          instructions: instructions,
          schedule: schedule,
          agentId: agentId,
          agentName: agentName,
          providerOverride: providerOverride,
          modelOverride: modelOverride,
          enabled: enabled,
        );
        return {
          'status': 'ok',
          'automation': _serializeAutomation(created, locale: locale),
        };
      } on ArgumentError catch (e) {
        throw ProtocolError(e.message.toString());
      }
    });

    gateway.rpcRegistry.register('automations.update', (params, context) async {
      final id = params?['id'] as String?;
      if (id == null || id.isEmpty) {
        throw ProtocolError('Missing required parameter: id');
      }
      final locale = params?['locale'] as String? ?? 'en';
      final rawSchedule = params?['schedule'];
      final schedule = rawSchedule is Map
          ? AutomationSchedule.fromJson(Map<String, dynamic>.from(rawSchedule))
          : null;

      try {
        final updated = await automationManager.updateAutomation(
          id,
          title: params?['title'] as String?,
          instructions: params?['instructions'] as String?,
          schedule: schedule,
          enabled: params?['enabled'] as bool?,
          agentId: params?['agentId'] as String?,
          agentName: params?['agentName'] as String?,
          providerOverride: params?['providerOverride'] as String?,
          clearProviderOverride: params?['clearProviderOverride'] == true,
          modelOverride: params?['modelOverride'] as String?,
          clearModelOverride: params?['clearModelOverride'] == true,
        );
        return {
          'status': 'ok',
          'automation': _serializeAutomation(updated, locale: locale),
        };
      } on ArgumentError catch (e) {
        throw ProtocolError(e.message.toString());
      } on StateError catch (e) {
        throw ProtocolError(e.message);
      }
    });

    gateway.rpcRegistry.register('automations.toggle', (params, context) async {
      final id = params?['id'] as String?;
      final enabled = params?['enabled'] as bool?;
      if (id == null || enabled == null) {
        throw ProtocolError('Missing required parameters: id, enabled');
      }
      final locale = params?['locale'] as String? ?? 'en';
      try {
        final updated = await automationManager.toggleAutomation(id, enabled);
        return {
          'status': 'ok',
          'automation': _serializeAutomation(updated, locale: locale),
        };
      } on StateError catch (e) {
        throw ProtocolError(e.message);
      }
    });

    gateway.rpcRegistry.register('automations.delete', (params, context) async {
      final id = params?['id'] as String?;
      if (id == null || id.isEmpty) {
        throw ProtocolError('Missing required parameter: id');
      }
      await automationManager.deleteAutomation(id);
      return {'status': 'ok', 'id': id};
    });

    gateway.rpcRegistry.register('automations.runNow', (params, context) async {
      final id = params?['id'] as String?;
      if (id == null || id.isEmpty) {
        throw ProtocolError('Missing required parameter: id');
      }
      try {
        final run = await automationManager.triggerRunNow(id);
        return {
          'status': 'started',
          'run': run.toJson(),
          'runId': run.id,
          'sessionId': run.sessionId,
        };
      } on StateError catch (e) {
        throw ProtocolError(e.message);
      }
    });

    gateway.rpcRegistry.register('automations.runs', (params, context) async {
      final automationId = params?['automationId'] as String?;
      if (automationId == null || automationId.isEmpty) {
        throw ProtocolError('Missing required parameter: automationId');
      }
      final limit = (params?['limit'] as num?)?.toInt() ?? 50;
      final runs = await automationManager.getRuns(automationId, limit: limit);
      return {
        'status': 'ok',
        'runs': runs.map((r) => r.toJson()).toList(),
      };
    });

    gateway.rpcRegistry.register(
      'automations.previewSchedule',
      (params, context) async {
        final locale = params?['locale'] as String? ?? 'en';
        final rawSchedule = params?['schedule'];
        if (rawSchedule is! Map) {
          throw ProtocolError('Missing required parameter: schedule');
        }
        final schedule =
            AutomationSchedule.fromJson(Map<String, dynamic>.from(rawSchedule));
        final error = CronUtils.validateSchedule(schedule);
        if (error != null) {
          return {
            'status': 'ok',
            'valid': false,
            'error': error,
            'cronExpressions': schedule.toCronExpressions(),
            'humanSchedule':
                CronUtils.formatHumanReadable(schedule, locale: locale),
            'nextRuns': const <String>[],
          };
        }

        final nextRuns = CronUtils.computeNextRuns(schedule, count: 3)
            .map((dt) => dt.toIso8601String())
            .toList();
        return {
          'status': 'ok',
          'valid': true,
          'cronExpressions': schedule.toCronExpressions(),
          'humanSchedule':
              CronUtils.formatHumanReadable(schedule, locale: locale),
          'nextRuns': nextRuns,
        };
      },
    );

    gateway.rpcRegistry.register(
      'automations.previewRouting',
      (params, context) async {
        final title = params?['title'] as String? ?? '';
        final instructions = params?['instructions'] as String? ?? '';
        final decision = await automationManager.previewRouting(
          title: title,
          instructions: instructions,
        );
        return {
          'status': 'ok',
          'decision': decision,
        };
      },
    );

    gateway.rpcRegistry.register(
      'automations.generateFromPrompt',
      (params, context) async {
        final prompt = params?['prompt'] as String?;
        if (prompt == null || prompt.trim().isEmpty) {
          throw ProtocolError('Missing required parameter: prompt');
        }
        final locale = params?['locale'] as String? ?? 'en';
        try {
          final draft = await automationManager.generateFromPrompt(
            prompt,
            locale: locale,
          );
          return {'status': 'ok', 'draft': draft};
        } catch (e) {
          throw ProtocolError('Failed to generate automation: $e');
        }
      },
    );

    _log.info('Automation RPC routes registered');
  }
}
