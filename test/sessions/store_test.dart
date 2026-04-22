import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:hive_ce/hive.dart';
import 'package:ghost/engine/sessions/store.dart';
import 'package:ghost/engine/models/message.dart';

void main() {
  late Directory tempDir;
  late SessionStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ghost_store_');
    Hive.init(tempDir.path);
    store = SessionStore(encryptionKey: Uint8List(32));
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('SessionStore', () {
    test('Append and load messages', () async {
      const sessionId = 'test-session';
      final msg1 =
          Message(role: 'user', content: 'hello', timestamp: DateTime.now());
      final msg2 =
          Message(role: 'assistant', content: 'hi', timestamp: DateTime.now());

      await store.appendMessage(sessionId, msg1);
      await store.appendMessage(sessionId, msg2);

      final loaded = await store.loadTranscript(sessionId);
      expect(loaded.length, equals(2));
      expect(loaded[0].content, equals('hello'));
      expect(loaded[1].content, equals('hi'));
    });

    test('List session IDs', () async {
      await store.appendMessage(
          's1', Message(role: 'u', content: 'x', timestamp: DateTime.now()));
      await store.appendMessage(
          's2', Message(role: 'u', content: 'y', timestamp: DateTime.now()));

      final ids = await store.listSessionIds();
      expect(ids, containsAll(['s1', 's2']));
    });

    test('Delete transcript', () async {
      await store.appendMessage(
          's1', Message(role: 'u', content: 'x', timestamp: DateTime.now()));
      expect(await store.exists('s1'), isTrue);

      await store.deleteTranscript('s1');
      expect(await store.exists('s1'), isFalse);
    });
  });
}
