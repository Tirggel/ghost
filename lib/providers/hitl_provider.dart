import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks Human-In-The-Loop state per session.
enum HitlStatus {
  /// No pending HITL request.
  none,
  /// HITL is pending — YES/NO buttons are showing.
  pending,
  /// User clicked NEIN — action is permanently blocked for this turn.
  declined,
}

class HitlNotifier extends Notifier<Map<String, HitlStatus>> {
  @override
  Map<String, HitlStatus> build() => {};

  HitlStatus getStatus(String sessionId) =>
      state[sessionId] ?? HitlStatus.none;

  void setPending(String sessionId) {
    state = {...state, sessionId: HitlStatus.pending};
  }

  void setDeclined(String sessionId) {
    state = {...state, sessionId: HitlStatus.declined};
  }

  void reset(String sessionId) {
    state = {...state, sessionId: HitlStatus.none};
  }
}

final hitlProvider =
    NotifierProvider<HitlNotifier, Map<String, HitlStatus>>(() {
  return HitlNotifier();
});

/// Helper: returns true if this text looks like a confirmation message.
bool isHitlConfirmation(String text) {
  final confirmPattern = RegExp(
    r'\b(ja|yes|ok|okay|yep|sure|bestätige|bestätig|erlaubt|gerne|klar|natürlich|do it|go ahead|proceed|confirm|allow|weiter|mach es|mach das)\b',
    caseSensitive: false,
  );
  return confirmPattern.hasMatch(text.trim());
}
