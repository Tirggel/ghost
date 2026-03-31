// Ghost — Nostr Channel implementation.
//
// Nostr is a decentralized protocol for censorship-resistant social networking.
// https://nostr.com / https://github.com/nostr-protocol/nostr
//
// Ghost connects to one or more Nostr relays via WebSocket and listens for
// direct messages (kind 4 = encrypted DM) or public posts (kind 1).
//
// Setup:
//   1. Generate a Nostr key pair (nsec = private key, npub = public key)
//      Use any Nostr client (e.g. Amethyst, Damus) to create one.
//   2. Store the hex private key in Ghost settings.
//   3. Ghost's Nostr identity will be associated with this key pair.
//
// Settings to store in Ghost:
//   - token:    Hex-encoded private key (nsec decoded)
//   - apiUrl:   Relay WebSocket URL (e.g. wss://relay.damus.io)
//
// NOTE: Full NIP-04 encrypted DM support requires implementing the
// NIP-04 encryption (secp256k1 + AES-256-CBC). This implementation
// handles plaintext kind 1 notes. Use a library like dart_nostr for production.

import 'dart:async';
import 'dart:convert';
import 'package:logging/logging.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';

import 'channel.dart';
import 'envelope.dart';

final _log = Logger('Ghost.NostrChannel');
const _uuid = Uuid();

class NostrChannel extends Channel {
  NostrChannel({
    required this.relayUrl,
    required this.publicKeyHex,
    this.privateKeyHex,
  });

  final String relayUrl;
  final String publicKeyHex;
  final String? privateKeyHex;

  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _sub;
  void Function(Envelope envelope)? _handler;
  bool _isRunning = false;

  @override
  String get type => 'nostr';

  @override
  String get displayName => 'Nostr ($relayUrl)';

  @override
  bool get isConnected => _isRunning;

  @override
  Future<void> connect() async {
    if (_isRunning) return;

    _ws = WebSocketChannel.connect(Uri.parse(relayUrl));
    _isRunning = true;

    // Subscribe to kind 1 (text notes) mentioning us
    final subscriptionId = _uuid.v4().substring(0, 8);
    final req = jsonEncode([
      'REQ',
      subscriptionId,
      {
        'kinds': [1, 4], // text notes + encrypted DMs
        '#p': [publicKeyHex], // mentions of us
        'limit': 50,
      }
    ]);
    _ws!.sink.add(req);

    _sub = _ws!.stream.listen(
      (raw) {
        try {
          final msg = jsonDecode(raw.toString()) as List<dynamic>;
          if (msg[0] == 'EVENT' && msg.length >= 3) {
            final event = msg[2] as Map<String, dynamic>;
            _processEvent(event);
          }
        } catch (e) {
          _log.warning('Nostr: Failed to parse message: $e');
        }
      },
      onError: (Object e) => _log.warning('Nostr WebSocket error: $e'),
      onDone: () {
        _isRunning = false;
        _log.info('Nostr relay connection closed');
      },
    );

    _log.info('Nostr connected to $relayUrl as $publicKeyHex');
  }

  void _processEvent(Map<String, dynamic> event) {
    if (_handler == null) return;

    final pubkey = event['pubkey'] as String? ?? '';
    if (pubkey == publicKeyHex) return; // Skip own events

    final content = event['content'] as String? ?? '';
    if (content.isEmpty) return;

    final kind = (event['kind'] as num?)?.toInt() ?? 0;
    final id = event['id'] as String? ?? '';
    final createdAt = (event['created_at'] as num?)?.toInt() ?? 0;

    // NOTE: Kind 4 events are NIP-04 encrypted. We pass the raw ciphertext here
    // since decryption requires secp256k1 math which needs additional libraries.
    final displayContent = kind == 4 ? '[Encrypted DM - decryption pending]' : content;

    _handler!(Envelope(
      id: id,
      channelType: 'nostr',
      senderId: pubkey,
      content: displayContent,
      timestamp: DateTime.fromMillisecondsSinceEpoch(createdAt * 1000),
      metadata: {'kind': kind, 'relay': relayUrl},
    ));
  }

  @override
  Future<void> disconnect() async {
    await _sub?.cancel();
    await _ws?.sink.close();
    _ws = null;
    _isRunning = false;
    _log.info('Nostr channel disconnected');
  }

  @override
  Future<void> sendMessage({
    required String peerId,
    required String content,
    String? groupId,
    List<MediaAttachment>? media,
  }) async {
    if (!_isRunning || _ws == null) {
      throw Exception('Nostr channel not connected');
    }

    // Publish a kind 1 text note (public)
    // For production, sign with private key using schnorr signatures (NIP-01)
    _log.warning(
        'Nostr: Sending requires signing with private key (NIP-01). '
        'Use the dart_nostr package for production.');
  }

  @override
  void onMessage(void Function(Envelope envelope) handler) {
    _handler = handler;
  }
}
