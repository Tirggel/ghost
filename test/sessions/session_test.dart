import 'package:test/test.dart';
import 'package:ghost/engine/sessions/session.dart';
import 'package:ghost/engine/models/message.dart';

void main() {
  group('Session', () {
    test('Creation and message addition', () {
      final session = Session(
        id: 'sess-1',
        agentId: 'agent-1',
        channelType: 'webchat',
        peerId: 'user-1',
      );

      expect(session.history, isEmpty);

      session.addMessage(Message(
        role: 'user',
        content: 'hello',
        timestamp: DateTime.now(),
      ));

      expect(session.history.length, equals(1));
    });

    test('Session key generation', () {
      final dmSession = Session(
        id: '1',
        agentId: 'a',
        channelType: 'telegram',
        peerId: 'u1',
      );
      expect(dmSession.sessionKey, equals('telegram:u1'));

      final groupSession = Session(
        id: '2',
        agentId: 'a',
        channelType: 'telegram',
        peerId: 'u1',
        groupId: 'g1',
      );
      expect(groupSession.sessionKey, equals('telegram:g1'));
    });

    test('JSON round-trip', () {
      final session = Session(
        id: 's1',
        agentId: 'a1',
        channelType: 'c1',
        peerId: 'p1',
      );
      session.addMessage(
          Message(role: 'u', content: 'hi', timestamp: DateTime.now()));

      final json = session.toJson();
      final restored = Session.fromJson(json);

      expect(restored.id, equals('s1'));
      expect(restored.history.length, equals(1));
      expect(restored.history.first.content, equals('hi'));
    });
  });
}
