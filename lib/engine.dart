// Ghost — Library barrel export.
//
// 👻 Ghost — Personal AI Assistant
// A complete Dart clone of OpenClaw.

// Config
export 'engine/config/config.dart';
export 'engine/config/io.dart';
export 'engine/config/schema.dart';
export 'engine/config/secure_storage.dart';

// Infra
export 'engine/infra/crypto.dart';
export 'engine/infra/env.dart';
export 'engine/infra/errors.dart';
export 'engine/infra/logger.dart';

// Gateway
export 'engine/gateway/auth.dart';
export 'engine/gateway/protocol.dart';
export 'engine/gateway/router.dart';
export 'engine/gateway/server.dart';

// Channels
export 'engine/channels/channel.dart';
export 'engine/channels/envelope.dart';
export 'engine/channels/manager.dart';
export 'engine/channels/telegram.dart';

// Models
export 'engine/models/message.dart';
export 'engine/models/provider.dart';

// Agent
export 'engine/agent/agent.dart';
export 'engine/agent/manager.dart'; // Wait, double engine? No, agent/manager.dart.
export 'engine/agent/providers/anthropic.dart';
export 'engine/agent/providers/openai.dart';
export 'engine/agent/providers/factory.dart';

// Sessions
export 'engine/sessions/manager.dart';
export 'engine/sessions/session.dart';
export 'engine/sessions/store.dart';

// Tools
export 'engine/tools/registry.dart';
export 'engine/tools/fs.dart';
export 'engine/tools/exec.dart';
export 'engine/tools/search.dart';
export 'engine/tools/sessions.dart';
export 'engine/tools/github.dart';
export 'engine/tools/google_workspace.dart';
export 'engine/tools/microsoft_graph.dart';
export 'engine/tools/browser.dart';
export 'engine/tools/memory.dart';
export 'engine/tools/skills.dart';
export 'engine/tools/agents.dart';

// Routers
export 'engine/gateway/agent_router.dart';
export 'engine/gateway/config_router.dart';
