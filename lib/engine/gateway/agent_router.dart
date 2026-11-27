// Ghost — Agent RPC Router.

import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';

import '../infra/errors.dart';
import '../gateway/server.dart';
import '../agent/manager.dart';
import '../agent/ontology/ontology_store_service.dart';

import '../models/message.dart';
import '../sessions/manager.dart';
import '../sessions/session.dart';
import '../tasks/task.dart';
import '../tasks/task_orchestrator.dart';


final _log = Logger('Ghost.AgentRouter');

/// Routes RPC requests from the Gateway to the Agent runtime.
class AgentRouter {
  AgentRouter({
    required this.agentManager,
    required this.gateway,
    required this.sessionManager,
    this.orchestrator,
  });

  final AgentManager agentManager;
  final GatewayServer gateway;
  final SessionManager sessionManager;
  final TaskOrchestrator? orchestrator;

  /// Register all agent-related RPC methods to the gateway's registry.
  void register() {
    // 1. Send a message to the agent
      gateway.rpcRegistry.register('agent.chat', (params, context) async {
        final content = params?['content'] as String?;
        if (content == null) {
          throw ProtocolError('Missing required parameter: content');
        }
        final rawAttachments = params?['attachments'] as List<dynamic>?;
        final attachments = rawAttachments
                ?.map((a) =>
                    MessageAttachment.fromJson(a as Map<String, dynamic>))
                .toList() ??
            [];

        final channelType = params?['channelType'] as String? ?? 'gateway';
        final String peerId =
            (params?['peerId'] as String?) ?? (context.clientId ?? 'unknown');
        final groupId = params?['groupId'] as String?;
        final model = params?['model'] as String?;
        final provider = params?['provider'] as String?;
        final targetAgentId = params?['agentId'] as String?;
        final workspaceDir = params?['workspaceDir'] as String?;

        // Resolve session
        final reqSessionId = params?['sessionId'] as String?;
        late Session session;

        if (reqSessionId != null) {
          session = sessionManager.getSession(reqSessionId) ??
              sessionManager.createSession(
                id: reqSessionId,
                channelType: channelType,
                peerId: peerId,
                groupId: groupId,
              );
        } else {
          session = await sessionManager.resolveSession(
            channelType: channelType,
            peerId: peerId,
            groupId: groupId,
          );
        }

        // Update session agentId if a specific agent was targeted
        if (targetAgentId != null) {
          session.agentId = targetAgentId;
        }
        if (model != null) {
          session.model = model;
        }
        if (provider != null) {
          session.provider = provider;
        }

        // Add user message to history (skip internal HITL sentinel — agent handles it)
        if (content.trim() != '__HITL_DECLINED__') {
          await sessionManager.addMessage(
            sessionId: session.id,
            role: 'user',
            content: content,
            attachments: attachments,
            metadata: {
              'channelType': channelType,
              'senderId': peerId,
              'groupId': ?groupId,
              'model': ?model,
              'provider': ?provider,
              'agentId': ?targetAgentId,
            },
          );
          gateway.broadcast('agent.session_updated', {
            'sessionId': session.id,
            if (session.title != null) 'title': session.title,
          });
        }


        // Trigger agent processing in the background
        unawaited(_processInAgent(session.id, content, targetAgentId,
            attachments: attachments, workspaceDir: workspaceDir));

        return {
          'sessionId': session.id,
          'status': 'processing',
        };
      });

    // 1b. Edit a previous user message, truncate subsequent history, and re-run
    gateway.rpcRegistry.register('agent.editMessage', (params, context) async {
      final sessionId = params?['sessionId'] as String?;
      final content = params?['content'] as String?;
      if (sessionId == null || content == null) {
        throw ProtocolError('Missing required parameter: sessionId or content');
      }

      final userMessageIndex = (params?['userMessageIndex'] as num?)?.toInt() ?? -1;
      final rawAttachments = params?['attachments'] as List<dynamic>?;
      final attachments = rawAttachments
              ?.map((a) => MessageAttachment.fromJson(a as Map<String, dynamic>))
              .toList() ??
          [];

      final channelType = params?['channelType'] as String? ?? 'gateway';
      final String peerId =
          (params?['peerId'] as String?) ?? (context.clientId ?? 'unknown');
      final groupId = params?['groupId'] as String?;
      final model = params?['model'] as String?;
      final provider = params?['provider'] as String?;
      final targetAgentId = params?['agentId'] as String?;
      final workspaceDir = params?['workspaceDir'] as String?;

      // Stop any active generation for this session before truncating
      agentManager.stop(sessionId);

      final session = sessionManager.getSession(sessionId) ??
          sessionManager.createSession(
            id: sessionId,
            channelType: channelType,
            peerId: peerId,
            groupId: groupId,
          );

      if (targetAgentId != null) {
        session.agentId = targetAgentId;
      }
      if (model != null) {
        session.model = model;
      }
      if (provider != null) {
        session.provider = provider;
      }

      // Truncate history from the edited user message onwards
      await sessionManager.truncateFromUserMessage(session.id, userMessageIndex);

      // Add the edited user message (preserve session metadata in case index 0 was replaced)
      await sessionManager.addMessage(
        sessionId: session.id,
        role: 'user',
        content: content,
        attachments: attachments,
        metadata: {
          'channelType': session.channelType,
          'senderId': session.peerId,
          'groupId': ?session.groupId,
          'model': ?session.model,
          'provider': ?session.provider,
          'agentId': session.agentId,
          'title': ?session.title,
          'edited': true,
        },
      );

      // Notify connected clients that session history was updated
      gateway.broadcast('agent.session_updated', {
        'sessionId': session.id,
        if (session.title != null) 'title': session.title,
        'edited': true,
      });

      // Trigger agent processing in the background
      unawaited(_processInAgent(session.id, content, targetAgentId,
          attachments: attachments, workspaceDir: workspaceDir));

      return {
        'sessionId': session.id,
        'status': 'processing',
      };
    });

    // 2. Query session history
    gateway.rpcRegistry.register('agent.history', (params, context) async {
      final sessionId = params?['sessionId'] as String?;
      if (sessionId == null) {
        throw ProtocolError('Missing required parameter: sessionId');
      }
      final maxMessages = params?['maxMessages'] as int? ?? 50;

      final history =
          await sessionManager.getHistory(sessionId, maxMessages: maxMessages);
      return {
        'sessionId': sessionId,
        'messages': history.map((m) => m.toJson()).toList(),
      };
    });

    // 3. List active sessions
    gateway.rpcRegistry.register('agent.sessions', (params, context) async {
      return {'sessions': sessionManager.listSessions()};
    });

    // 4. Delete a session (single, batch, or all)
    gateway.rpcRegistry.register('agent.deleteSession',
        (params, context) async {
      final all = params?['all'] as bool? ?? false;
      final sessionId = params?['sessionId'] as String?;
      final sessionIds = (params?['sessionIds'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList();

      if (all) {
        for (final s in sessionManager.listSessions()) {
          final id = s['id'] as String?;
          if (id != null) agentManager.stop(id);
        }
        await sessionManager.deleteAllSessions();
        gateway.broadcast('agent.sessions_cleared', {});
        return {'status': 'ok', 'all': true};
      } else if (sessionIds != null && sessionIds.isNotEmpty) {
        for (final id in sessionIds) {
          agentManager.stop(id);
        }
        await sessionManager.deleteSessions(sessionIds);
        for (final id in sessionIds) {
          gateway.broadcast('agent.session_deleted', {'sessionId': id});
        }
        return {'status': 'ok', 'count': sessionIds.length};
      } else if (sessionId != null) {
        agentManager.stop(sessionId);
        await sessionManager.deleteSession(sessionId);
        gateway.broadcast('agent.session_deleted', {'sessionId': sessionId});
        return {'status': 'ok', 'sessionId': sessionId};
      } else {
        throw ProtocolError(
            'Missing required parameter: sessionId, sessionIds, or all: true');
      }
    });

    gateway.rpcRegistry.register('agent.deleteAllSessions',
        (params, context) async {
      await sessionManager.deleteAllSessions();
      gateway.broadcast('agent.sessions_cleared', {});
      return {'status': 'ok', 'all': true};
    });

    // 5. Set model for a specific session
    gateway.rpcRegistry.register('agent.setSessionModel',
        (params, context) async {
      final sessionId = params?['sessionId'] as String?;
      final model = params?['model'] as String?;
      final provider = params?['provider'] as String?;
      if (sessionId == null || model == null) {
        throw ProtocolError('Missing required parameter: sessionId or model');
      }
      final session = sessionManager.getSession(sessionId);
      if (session != null) {
        session.model = model;
        session.provider = provider;
        await sessionManager.addMessage(
          sessionId: sessionId,
          role: 'system',
          content: 'session_config_update',
          metadata: {
            'model': model,
            'provider': ?provider,
          },
        );
      }
      return {'status': 'ok', 'sessionId': sessionId, 'model': model};
    });

    // 5b. Set title for a specific session
    gateway.rpcRegistry.register('agent.setSessionTitle',
        (params, context) async {
      final sessionId = params?['sessionId'] as String?;
      final title = params?['title'] as String?;
      if (sessionId == null || title == null) {
        throw ProtocolError('Missing required parameter: sessionId or title');
      }
      final session = sessionManager.getSession(sessionId);
      if (session != null) {
        session.title = title;
        await sessionManager.addMessage(
          sessionId: sessionId,
          role: 'system',
          content: 'session_rename',
          metadata: {'title': title},
        );
        // Broadcast update
        gateway.broadcast('agent.session_updated', {
          'sessionId': sessionId,
          'title': title,
        });
      }
      return {'status': 'ok', 'sessionId': sessionId, 'title': title};
    });

    // 5c. Listen for renames in the manager and broadcast
    agentManager.onSessionRenamed = (sessionId, title) {
      gateway.broadcast('agent.session_updated', {
        'sessionId': sessionId,
        'title': title,
      });
    };

    // 6. Stop/Interrupt processing for a session
    gateway.rpcRegistry.register('agent.stop', (params, context) async {
      final sessionId = params?['sessionId'] as String?;
      if (sessionId == null) {
        throw ProtocolError('Missing required parameter: sessionId');
      }
      agentManager.stop(sessionId);
      return {'status': 'ok', 'sessionId': sessionId};
    });

    // 7. Memory backup and restore
    gateway.rpcRegistry.register('memory.backup', (params, context) async {
      return {'status': 'ok', 'data': await agentManager.memoryEngine.backup()};
    });

    gateway.rpcRegistry.register('memory.restore', (params, context) async {
      final data = params?['data'] as String?;
      if (data == null) throw ProtocolError('Missing required parameter: data');
      await agentManager.memoryEngine.restore(data);
      return {'status': 'ok'};
    });

    gateway.rpcRegistry.register('memory.rag.backup', (params, context) async {
      return {'status': 'ok', 'data': await agentManager.ragMemoryEngine.backup()};
    });

    gateway.rpcRegistry.register('memory.rag.restore', (params, context) async {
      final data = params?['data'] as String?;
      if (data == null) throw ProtocolError('Missing required parameter: data');
      await agentManager.ragMemoryEngine.restore(data);
      return {'status': 'ok'};
    });

    gateway.rpcRegistry.register('memory.ontology.backup', (params, context) async {
      return {
        'status': 'ok',
        'data': await agentManager.ontologyStoreService.exportJson(),
      };
    });

    gateway.rpcRegistry.register('memory.ontology.restore', (params, context) async {
      final data = params?['data'] as String?;
      if (data == null) throw ProtocolError('Missing required parameter: data');
      await agentManager.ontologyStoreService.importJson(data);
      gateway.broadcast('ontology.changed', {});
      return {'status': 'ok'};
    });

    gateway.rpcRegistry.register('memory.ontology.stats', (params, context) async {
      return {
        'status': 'ok',
        'stats': agentManager.ontologyStoreService.getStats().toJson(),
      };
    });

    gateway.rpcRegistry.register('memory.ontology.list', (params, context) async {
      final category = (params?['category'] as String?)?.trim().toLowerCase() ?? 'all';
      final query = (params?['query'] as String?)?.trim() ?? '';
      final limit = (params?['limit'] as num?)?.toInt() ?? 200;
      final offset = (params?['offset'] as num?)?.toInt() ?? 0;

      final ontology = agentManager.ontologyStoreService;
      final factCategory = category == 'rules' ? 'all' : category;
      final factsRes = ontology.listFacts(
        category: factCategory,
        query: query,
        limit: limit,
        offset: offset,
      );
      final nodes = ontology.listNodes(
        category: factCategory,
        query: query,
      );

      final queryLower = query.toLowerCase();
      final allRelations = ontology.getAllRelationDefs();
      final relations = queryLower.isEmpty
          ? allRelations
          : allRelations
              .where(
                (r) =>
                    r.predicate.toLowerCase().contains(queryLower) ||
                    r.domainType.toLowerCase().contains(queryLower) ||
                    r.rangeType.toLowerCase().contains(queryLower),
              )
              .toList();

      return {
        'status': 'ok',
        'stats': ontology.getStats().toJson(),
        'facts': factsRes.facts.map((f) => f.toJson()).toList(),
        'totalFacts': factsRes.totalCount,
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'relations': relations.map((r) => r.toJson()).toList(),
      };
    });

    gateway.rpcRegistry.register('memory.ontology.assert', (params, context) async {
      final subject = (params?['subject'] as String?)?.trim() ?? '';
      final predicate = (params?['predicate'] as String?)?.trim() ?? '';
      final object = (params?['object'] as String?)?.trim() ?? '';
      if (subject.isEmpty || predicate.isEmpty || object.isEmpty) {
        throw ProtocolError(
          'Missing required parameters: subject, predicate, and object must be non-empty',
        );
      }

      final subjectType = (params?['subjectType'] as String?)?.trim() ?? 'Entity';
      final objectType = (params?['objectType'] as String?)?.trim() ?? 'Entity';
      final explicitSubjectKey = (params?['subjectKey'] as String?)?.trim();
      final confidence = (params?['confidence'] as num?)?.toDouble() ?? 1.0;

      final lowerSubj = subject.toLowerCase();
      final isPrimaryUser = explicitSubjectKey == OntologyStoreService.primaryUserKey ||
          lowerSubj == 'user:primary' ||
          lowerSubj == 'user' ||
          lowerSubj == 'ich' ||
          lowerSubj == 'me';
      final configuredUserName = agentManager.config.user.name.trim();
      final effectiveSubjectLabel = isPrimaryUser
          ? (configuredUserName.isNotEmpty ? configuredUserName : 'User')
          : subject;

      final ontology = agentManager.ontologyStoreService;
      final result = await ontology.assertFact(
        subjectLabel: effectiveSubjectLabel,
        subjectType: isPrimaryUser ? 'Person' : subjectType,
        subjectKey: isPrimaryUser ? OntologyStoreService.primaryUserKey : explicitSubjectKey,
        predicate: predicate,
        objectLabel: object,
        objectType: objectType,
        confidence: confidence,
      );

      gateway.broadcast('ontology.changed', {});
      return {
        'status': 'ok',
        'result': result.toJson(),
        'stats': ontology.getStats().toJson(),
      };
    });

    gateway.rpcRegistry.register('memory.ontology.deleteEdge', (params, context) async {
      final edgeId = (params?['edgeId'] as num?)?.toInt();
      if (edgeId == null || edgeId <= 0) {
        throw ProtocolError('Missing or invalid required parameter: edgeId');
      }
      final ontology = agentManager.ontologyStoreService;
      final deleted = await ontology.deleteEdge(edgeId);
      if (deleted) {
        gateway.broadcast('ontology.changed', {});
      }
      return {
        'status': 'ok',
        'deleted': deleted,
        'stats': ontology.getStats().toJson(),
      };
    });

    gateway.rpcRegistry.register('memory.ontology.deleteNode', (params, context) async {
      final canonicalKey = (params?['canonicalKey'] as String?)?.trim() ?? '';
      if (canonicalKey.isEmpty) {
        throw ProtocolError('Missing required parameter: canonicalKey');
      }
      final ontology = agentManager.ontologyStoreService;
      final deleted = await ontology.deleteNode(canonicalKey);
      if (deleted) {
        gateway.broadcast('ontology.changed', {});
      }
      return {
        'status': 'ok',
        'deleted': deleted,
        'stats': ontology.getStats().toJson(),
      };
    });

    gateway.rpcRegistry.register('memory.ontology.query', (params, context) async {
      final entity = (params?['entity'] as String?)?.trim() ?? '';
      if (entity.isEmpty) {
        throw ProtocolError('Missing required parameter: entity');
      }
      final maxDepth = (params?['maxDepth'] as num?)?.toInt() ?? 2;
      final maxResults = (params?['maxResults'] as num?)?.toInt() ?? 30;
      final includeIncoming = params?['includeIncoming'] as bool? ?? true;

      final result = await agentManager.ontologyStoreService.queryFactsForEntity(
        entity,
        maxDepth: maxDepth,
        maxResults: maxResults,
        includeIncoming: includeIncoming,
      );

      return {
        'status': 'ok',
        'result': result.toJson(),
        'promptPreview': result.toCompactPromptString(),
      };
    });
  }

  Future<void> _processInAgent(
      String sessionId, String content, String? agentId,
      {List<MessageAttachment> attachments = const [],
      String? workspaceDir}) async {
    // --- /goal and /plan Kanban tracking + ontology routing ---
    final trimmed = content.trim();
    final isGoal = trimmed.startsWith('/goal');
    final isPlan = trimmed.startsWith('/plan');
    final taskManager = agentManager.taskManager;
    KanbanTask? kanbanTask;
    AgentRoutingDecision? routingDecision;

    final session = sessionManager.getSession(sessionId);
    final explicitAgentId = (agentId != null && agentId.isNotEmpty && agentId != KanbanTask.autoAgentId)
        ? agentId
        : (session != null &&
                session.agentId.isNotEmpty &&
                session.agentId != 'default' &&
                session.agentId != 'default-agent' &&
                session.agentId != KanbanTask.autoAgentId
            ? session.agentId
            : null);

    String effectiveAgentId = explicitAgentId ?? 'default-agent';
    String resolveDisplayName(String id) {
      if (id == 'default-agent') {
        final name = agentManager.config.identity.name.trim();
        return name.isNotEmpty ? name : 'Ghost';
      }
      return agentManager.config.customAgents
              .where((a) => a.id == id)
              .firstOrNull
              ?.name ??
          id;
    }

    if ((isGoal || isPlan) && taskManager != null) {
      final rawCommandText = trimmed.substring(5).trim();
      final prefix = isGoal ? '🎯' : '📋';
      final shortTitle = rawCommandText.length > 60
          ? '$prefix ${rawCommandText.substring(0, 60)}...'
          : '$prefix $rawCommandText';

      final initialAgentId =
          explicitAgentId ?? (orchestrator != null ? KanbanTask.autoAgentId : 'default-agent');
      final initialAgentName = explicitAgentId != null
          ? resolveDisplayName(explicitAgentId)
          : (orchestrator != null ? 'Auto (Ontologie)' : resolveDisplayName('default-agent'));

      kanbanTask = await taskManager.createTask(
        title: shortTitle,
        description: trimmed,
        status: TaskStatus.inProgress,
        assignedAgentId: initialAgentId,
        assignedAgentName: initialAgentName,
        sessionId: sessionId,
      );

      if (explicitAgentId == null && orchestrator != null) {
        routingDecision = await orchestrator!.routeTask(kanbanTask.id, force: true);
        kanbanTask = taskManager.getTask(kanbanTask.id) ?? kanbanTask;
        if (routingDecision != null) {
          effectiveAgentId = routingDecision.selectedAgentId;
        }
      }

      gateway.broadcast('kanban.changed');
      _log.info('/${isGoal ? "goal" : "plan"} task created: ${kanbanTask.id} -> $effectiveAgentId');
    } else if ((isGoal || isPlan) && explicitAgentId == null && orchestrator != null) {
      final synthetic = KanbanTask(
        title: trimmed.substring(5).trim(),
        description: trimmed,
      );
      routingDecision = await orchestrator!.evaluateAgentRouting(synthetic);
      effectiveAgentId = routingDecision.selectedAgentId;
    }

    try {
      final agent = agentManager.getAgent(effectiveAgentId);
      final effectiveAgentName = agent.id == 'default-agent'
          ? resolveDisplayName('default-agent')
          : '${resolveDisplayName(agent.id)} Agent';

      if (session != null) {
        session.agentId = agent.id;
        session.agentName = effectiveAgentName;
      }

      if (routingDecision != null && (isGoal || isPlan)) {
        await sessionManager.addMessage(
          sessionId: sessionId,
          role: 'system',
          content: 'session_agent_routed',
          metadata: {
            'agentId': agent.id,
            'agentName': effectiveAgentName,
            'routingReason': routingDecision.reason,
          },
        );
        gateway.broadcast('agent.session_updated', {
          'sessionId': sessionId,
          'agentId': agent.id,
          'agentName': effectiveAgentName,
          'routingReason': routingDecision.reason,
          if (session?.title != null) 'title': session!.title,
        });
      }

      if (workspaceDir != null &&
          workspaceDir.trim().isNotEmpty &&
          Directory(workspaceDir.trim()).existsSync()) {
        agent.workspaceDir = workspaceDir.trim();
        _log.info('Dynamic workspace applied for agent ${agent.id}: ${agent.workspaceDir}');
      }

      final expectedRunId = agent.currentRunId(sessionId) + 1;
      await agent.processMessage(
        sessionId: sessionId,
        content: content,
        attachments: attachments,
        model: session?.model,
        providerHint: session?.provider,
        onPartialResponse: (chunk) {
          // Stream partial response to all authenticated gateway clients
          gateway.broadcast('agent.stream', {
            'sessionId': sessionId,
            'chunk': chunk,
          });
        },
        onActivityUpdate: (activity) {
          gateway.broadcast('agent.activity', {
            'sessionId': sessionId,
            'activity': activity,
          });
        },
      );

      // If this turn was stopped or superseded (e.g. by editMessage or deleteSession), do not broadcast completion
      if (agent.currentRunId(sessionId) != expectedRunId) {
        return;
      }

      // Notify completion
      if (session != null && session.history.isNotEmpty) {
        final lastMsg = session.history.last;
        // Don't broadcast sentinel messages or non-assistant messages
        if (lastMsg.content.trim() == '__HITL_DECLINED__' ||
            lastMsg.role != 'assistant') {
          return;
        }
        gateway.broadcast('agent.response', {
          'sessionId': sessionId,
          'message': lastMsg.toJson(),
        });
      }

      // Auto-rename in background AFTER response is delivered so chat is never blocked
      if (session != null && session.title == null && session.history.length <= 2) {
        unawaited(agentManager.autoRenameSession(session, agent));
      }

      // --- /goal abgeschlossen → Task auf "done" ---
      if (isGoal && kanbanTask != null && taskManager != null) {
        await taskManager.moveTask(kanbanTask.id, TaskStatus.done);
        final session = sessionManager.getSession(sessionId);
        String summary = '';
        if (session != null && session.history.isNotEmpty) {
          summary = session.history.last.content;
          if (summary.length > 500) summary = '${summary.substring(0, 500)}...';
        }
        await taskManager.addComment(
          kanbanTask.id,
          authorId: agent.id,
          authorName: resolveDisplayName(agent.id),
          content: 'Ziel erreicht ✅\n\nZusammenfassung:\n$summary',
        );
        gateway.broadcast('kanban.changed');
        _log.info('/goal task ${kanbanTask.id} marked as done.');
      }

      // --- /plan abgeschlossen → Task auf "review" (wartet auf User-Feedback) ---
      if (isPlan && kanbanTask != null && taskManager != null) {
        await taskManager.moveTask(kanbanTask.id, TaskStatus.review);
        final session = sessionManager.getSession(sessionId);
        String summary = '';
        if (session != null && session.history.isNotEmpty) {
          summary = session.history.last.content;
          if (summary.length > 500) summary = '${summary.substring(0, 500)}...';
        }
        await taskManager.addComment(
          kanbanTask.id,
          authorId: agent.id,
          authorName: resolveDisplayName(agent.id),
          content: 'Plan ausgearbeitet 📋 (Bereit zum Review)\n\nZusammenfassung:\n$summary',
        );
        gateway.broadcast('kanban.changed');
        _log.info('/plan task ${kanbanTask.id} marked as review.');
      }
    } catch (e) {
      _log.severe('Agent routing error: $e');
      gateway.broadcast('agent.error', {
        'sessionId': sessionId,
        'error': e.toString(),
      });

      // --- /goal oder /plan Fehler → Task auf "review" ---
      if ((isGoal || isPlan) && kanbanTask != null && taskManager != null) {
        await taskManager.moveTask(kanbanTask.id, TaskStatus.review);
        await taskManager.addComment(
          kanbanTask.id,
          authorId: 'system',
          authorName: 'Ghost System',
          content: 'Fehler bei der Ausführung: $e',
        );
        gateway.broadcast('kanban.changed');
        _log.info('/${isGoal ? "goal" : "plan"} task ${kanbanTask.id} moved to review due to error.');
      }
    }
  }
}
