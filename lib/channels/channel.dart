// Ghost — Channel base interface.

import 'envelope.dart';

/// Abstract base class for messaging channels.
///
/// Each channel (Telegram, Discord, etc.) implements this interface
/// to provide a unified API for the Gateway.
abstract class Channel {
  /// Channel type identifier (e.g., "telegram", "discord").
  String get type;

  /// Display name for this channel.
  String get displayName;

  /// Whether this channel is currently connected and running.
  bool get isConnected;

  /// Connect and start listening for messages.
  Future<void> connect();

  /// Disconnect and stop listening.
  Future<void> disconnect();

  /// Send a message via this channel.
  Future<void> sendMessage({
    required String peerId,
    required String content,
    String? groupId,
    List<MediaAttachment>? media,
  });

  /// Register a callback for incoming messages.
  void onMessage(void Function(Envelope envelope) handler);

  /// Get the connection status info.
  Map<String, dynamic> getStatus() => {
        'type': type,
        'displayName': displayName,
        'isConnected': isConnected,
      };
}
