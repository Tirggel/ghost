import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:hive_ce/hive.dart';
import 'package:ghost/engine/sessions/store.dart';
import 'package:ghost/engine/sessions/manager.dart';
import 'package:ghost/engine/models/message.dart';

void main() {
  late Directory tempDir;
  late SessionStore store;
  late SessionManager manager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ghost_repro_');
    Hive.init(tempDir.path);
    store = SessionStore(encryptionKey: Uint8List(32));
    manager = SessionManager(store: store);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('Session is restored correctly when metadata is present', () async {
    const sessionId = 'test-session-id';
    const channelType = 'telegram';
    const senderId = '12345';

    // Simulate what ChannelManager now does: include metadata
    final msg = Message(
      role: 'user',
      content: 'Hello',
      timestamp: DateTime.now(),
      metadata: {
        'channelType': channelType,
        'senderId': senderId,
      },
    );

    await store.appendMessage(sessionId, msg);

    // Verify session is restored by loadAll()
    await manager.loadAll();

    final sessions = manager.listSessions();
    expect(sessions, isNotEmpty,
        reason: 'Session should be restored from disk');
    expect(sessions.first['channelType'], equals(channelType));
    expect(sessions.first['peerId'], equals(senderId));
    expect(sessions.first['id'], equals(sessionId));
  });

  test('Session restoration fails if metadata is missing (as before)',
      () async {
    const sessionId = 'old-session-id';

    // Simulate the old behavior: missing metadata
    final msg = Message(
      role: 'user',
      content: 'Hello',
      timestamp: DateTime.now(),
      metadata: {}, // Missing channelType, senderId
    );

    await store.appendMessage(sessionId, msg);

    // loadAll() tries to load it but defaults to 'gateway' and 'unknown' if missing
    await manager.loadAll();

    final sessions = manager.listSessions();
    expect(sessions, isNotEmpty);
    expect(sessions.first['channelType'], equals('gateway'));
    expect(sessions.first['peerId'], equals('unknown'));
  });
}
