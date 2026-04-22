import 'package:test/test.dart';
import 'package:ghost/engine/models/provider.dart';

void main() {
  group('AIResponse Models', () {
    test('ToolCall JSON logic', () {
      final json = {
        'id': 'call_123',
        'name': 'test_tool',
        'arguments': {'arg': 'val'}
      };

      final call = ToolCall.fromJson(json);
      expect(call.id, equals('call_123'));
      expect(call.name, equals('test_tool'));
      expect(call.arguments['arg'], equals('val'));

      expect(call.toJson(), equals(json));
    });

    test('AIResponse properties', () {
      const response = AIResponse(
        content: 'hello',
        usage: TokenUsage(inputTokens: 10, outputTokens: 20),
      );

      expect(response.content, equals('hello'));
      expect(response.usage?.totalTokens, equals(30));
      expect(response.hasToolCalls, isFalse);
    });
  });
}
