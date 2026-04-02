import 'package:flutter_riverpod/flutter_riverpod.dart';

class TokenUsage {
  final int totalInputTokens;
  final int totalOutputTokens;

  TokenUsage({
    this.totalInputTokens = 0,
    this.totalOutputTokens = 0,
  });

  TokenUsage copyWith({
    int? totalInputTokens,
    int? totalOutputTokens,
  }) {
    return TokenUsage(
      totalInputTokens: totalInputTokens ?? this.totalInputTokens,
      totalOutputTokens: totalOutputTokens ?? this.totalOutputTokens,
    );
  }
}

class TokenUsageNotifier extends Notifier<TokenUsage> {
  @override
  TokenUsage build() {
    return TokenUsage();
  }

  void addUsage(int input, int output) {
    state = state.copyWith(
      totalInputTokens: state.totalInputTokens + input,
      totalOutputTokens: state.totalOutputTokens + output,
    );
  }

  void reset() {
    state = TokenUsage();
  }
}

final tokenUsageProvider = NotifierProvider<TokenUsageNotifier, TokenUsage>(() {
  return TokenUsageNotifier();
});
