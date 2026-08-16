import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'huddle_auth.dart';
import 'huddle_wire.dart';

typedef HuddleWebSocketFactory = WebSocketChannel Function(Uri uri);

WebSocketChannel _openHuddleWebSocket(Uri uri) =>
    IOWebSocketChannel.connect(uri, pingInterval: const Duration(seconds: 30));

enum HuddleTransportPhase {
  idle,
  connecting,
  awaitingChallenge,
  authenticating,
  connected,
  closing,
  disconnected,
  failed,
}

enum HuddleTransportErrorCode {
  invalidState,
  connectionFailed,
  handshakeTimeout,
  authenticationFailed,
  relayRejected,
  protocolViolation,
  socketClosed,
  sendFailed,
  cancelled,
  disposed,
}

@immutable
final class HuddleTransportError implements Exception {
  final HuddleTransportErrorCode code;
  final String message;
  final String? relayCode;
  final Object? cause;

  const HuddleTransportError({
    required this.code,
    required this.message,
    this.relayCode,
    this.cause,
  });

  @override
  String toString() {
    final suffix = relayCode == null ? '' : ' ($relayCode)';
    return 'HuddleTransportError.${code.name}$suffix: $message';
  }
}

@immutable
final class HuddlePeer {
  final String pubkey;
  final int peerIndex;

  const HuddlePeer({required this.pubkey, required this.peerIndex});
}

enum HuddlePeerEventType { joined, left }

@immutable
final class HuddlePeerEvent {
  final HuddlePeerEventType type;
  final HuddlePeer peer;

  const HuddlePeerEvent({required this.type, required this.peer});
}

@immutable
final class HuddleTransportState {
  final HuddleTransportPhase phase;
  final int? localPeerIndex;
  final UnmodifiableMapView<int, HuddlePeer> peers;
  final HuddleTransportError? error;

  HuddleTransportState({
    required this.phase,
    this.localPeerIndex,
    Map<int, HuddlePeer> peers = const {},
    this.error,
  }) : peers = UnmodifiableMapView(Map<int, HuddlePeer>.from(peers));

  factory HuddleTransportState.idle() =>
      HuddleTransportState(phase: HuddleTransportPhase.idle);
}

/// Dedicated Huddle audio transport.
///
/// This socket intentionally does not reuse [RelaySocket]: the main Nostr
/// connection speaks JSON arrays and ignores binary messages, while Huddle
/// audio uses JSON objects for its handshake/control plane and binary Opus v2
/// frames for media. [connect] completes only after the relay's `joined`
/// response, making authentication and room admission observable to callers.
abstract interface class HuddleTransportClient {
  HuddleTransportState get state;
  Stream<HuddleTransportState> get states;
  Stream<HuddleRemoteAudioFrame> get remoteAudioFrames;
  Stream<HuddlePeerEvent> get peerEvents;
  Stream<HuddleTransportError> get issues;

  Future<void> connect();
  void sendOpusFrame({
    required HuddleAudioHeader header,
    required Uint8List opusPayload,
  });
  Future<void> disconnect();
  Future<void> dispose();
}

final class HuddleTransport implements HuddleTransportClient {
  final HuddleConnectionParameters parameters;
  final Duration connectTimeout;
  final Duration handshakeTimeout;
  final HuddleWebSocketFactory _channelFactory;

  final StreamController<HuddleTransportState> _stateController =
      StreamController.broadcast(sync: true);
  final StreamController<HuddleRemoteAudioFrame> _audioController =
      StreamController.broadcast(sync: true);
  final StreamController<HuddlePeerEvent> _peerController =
      StreamController.broadcast(sync: true);
  final StreamController<HuddleTransportError> _issueController =
      StreamController.broadcast(sync: true);

  HuddleTransportState _state = HuddleTransportState.idle();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Completer<void>? _handshakeCompleter;
  Timer? _handshakeTimer;
  int _generation = 0;
  bool _disposed = false;
  bool _intentionalClose = false;

  HuddleTransport({
    required this.parameters,
    this.connectTimeout = const Duration(seconds: 8),
    this.handshakeTimeout = const Duration(seconds: 5),
    HuddleWebSocketFactory channelFactory = _openHuddleWebSocket,
  }) : _channelFactory = channelFactory;

  @override
  HuddleTransportState get state => _state;
  @override
  Stream<HuddleTransportState> get states => _stateController.stream;
  @override
  Stream<HuddleRemoteAudioFrame> get remoteAudioFrames =>
      _audioController.stream;
  @override
  Stream<HuddlePeerEvent> get peerEvents => _peerController.stream;

  /// Recoverable packet/control problems that do not tear down a joined room.
  @override
  Stream<HuddleTransportError> get issues => _issueController.stream;

  @override
  Future<void> connect() async {
    if (_disposed) {
      throw const HuddleTransportError(
        code: HuddleTransportErrorCode.disposed,
        message: 'Huddle transport has been disposed.',
      );
    }
    if (_state.phase != HuddleTransportPhase.idle &&
        _state.phase != HuddleTransportPhase.disconnected &&
        _state.phase != HuddleTransportPhase.failed) {
      throw HuddleTransportError(
        code: HuddleTransportErrorCode.invalidState,
        message: 'Cannot connect while transport is ${_state.phase.name}.',
      );
    }

    if (_state.phase == HuddleTransportPhase.failed ||
        _state.phase == HuddleTransportPhase.disconnected) {
      _handshakeTimer?.cancel();
      _handshakeTimer = null;
      final previousSubscription = _subscription;
      _subscription = null;
      await previousSubscription?.cancel();
      final previousChannel = _channel;
      _channel = null;
      await previousChannel?.sink.close();
      _handshakeCompleter = null;
    }

    final generation = ++_generation;
    _intentionalClose = false;
    _emitState(HuddleTransportState(phase: HuddleTransportPhase.connecting));

    try {
      final channel = _channelFactory(parameters.audioWebSocketUri);
      _channel = channel;
      await channel.ready.timeout(connectTimeout);
      if (!_isCurrent(generation)) {
        throw const HuddleTransportError(
          code: HuddleTransportErrorCode.cancelled,
          message: 'Huddle connection was superseded.',
        );
      }

      _handshakeCompleter = Completer<void>();
      _subscription = channel.stream.listen(
        (raw) => _handleRawMessage(raw, generation),
        onError: (Object error, StackTrace stackTrace) =>
            _handleSocketFailure(error, generation),
        onDone: () => _handleSocketClosed(generation),
        cancelOnError: false,
      );
      _emitState(
        HuddleTransportState(phase: HuddleTransportPhase.awaitingChallenge),
      );
      _handshakeTimer = Timer(handshakeTimeout, () {
        _fail(
          const HuddleTransportError(
            code: HuddleTransportErrorCode.handshakeTimeout,
            message: 'Timed out waiting for Huddle room admission.',
          ),
          generation,
        );
      });

      await _handshakeCompleter!.future;
    } on HuddleTransportError {
      rethrow;
    } catch (error) {
      final failure = HuddleTransportError(
        code: HuddleTransportErrorCode.connectionFailed,
        message: 'Unable to connect to the Huddle audio relay.',
        cause: error,
      );
      _fail(failure, generation);
      throw failure;
    }
  }

  @override
  void sendOpusFrame({
    required HuddleAudioHeader header,
    required Uint8List opusPayload,
  }) {
    final channel = _channel;
    if (_disposed ||
        channel == null ||
        _state.phase != HuddleTransportPhase.connected) {
      throw HuddleTransportError(
        code: HuddleTransportErrorCode.invalidState,
        message: 'Cannot send audio while transport is ${_state.phase.name}.',
      );
    }

    try {
      channel.sink.add(HuddleWireV2.encodeClientFrame(header, opusPayload));
    } catch (error) {
      throw HuddleTransportError(
        code: HuddleTransportErrorCode.sendFailed,
        message: 'Unable to send Huddle audio.',
        cause: error,
      );
    }
  }

  @override
  Future<void> disconnect() async {
    if (_disposed ||
        _state.phase == HuddleTransportPhase.idle ||
        _state.phase == HuddleTransportPhase.disconnected) {
      return;
    }

    _generation++;
    _intentionalClose = true;
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    if (_handshakeCompleter case final completer? when !completer.isCompleted) {
      completer.completeError(
        const HuddleTransportError(
          code: HuddleTransportErrorCode.cancelled,
          message: 'Huddle connection was closed.',
        ),
      );
    }
    _emitState(HuddleTransportState(phase: HuddleTransportPhase.closing));

    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    final channel = _channel;
    _channel = null;
    await channel?.sink.close();
    _handshakeCompleter = null;
    _emitState(HuddleTransportState(phase: HuddleTransportPhase.disconnected));
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    await disconnect();
    _disposed = true;
    await _stateController.close();
    await _audioController.close();
    await _peerController.close();
    await _issueController.close();
  }

  void _handleRawMessage(dynamic raw, int generation) {
    if (!_isCurrent(generation)) return;
    if (raw is String) {
      _handleTextMessage(raw, generation);
      return;
    }
    if (raw is List<int>) {
      _handleBinaryMessage(Uint8List.fromList(raw), generation);
      return;
    }
    _handleProtocolProblem('Unsupported Huddle WebSocket message.', generation);
  }

  void _handleTextMessage(String raw, int generation) {
    final Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('expected object');
      message = Map<String, dynamic>.from(decoded);
    } catch (error) {
      _handleProtocolProblem('Malformed Huddle control message.', generation);
      return;
    }

    switch (message['type']) {
      case 'challenge':
        _handleChallenge(message, generation);
      case 'joined':
        _handleJoined(message, generation);
      case 'left':
        _handleLeft(message, generation);
      case 'error':
        _handleRelayError(message, generation);
      default:
        _handleProtocolProblem('Unknown Huddle control message.', generation);
    }
  }

  void _handleChallenge(Map<String, dynamic> message, int generation) {
    if (_state.phase != HuddleTransportPhase.awaitingChallenge) {
      _handleProtocolProblem('Unexpected Huddle auth challenge.', generation);
      return;
    }
    final challenge = message['challenge'];
    if (challenge is! String || challenge.isEmpty) {
      _fail(
        const HuddleTransportError(
          code: HuddleTransportErrorCode.protocolViolation,
          message: 'Huddle auth challenge was missing.',
        ),
        generation,
      );
      return;
    }

    try {
      final auth = HuddleAuthV2.buildMessage(
        parameters: parameters,
        challenge: challenge,
      );
      _channel?.sink.add(jsonEncode(auth));
      _emitState(
        HuddleTransportState(phase: HuddleTransportPhase.authenticating),
      );
    } catch (error) {
      _fail(
        HuddleTransportError(
          code: HuddleTransportErrorCode.authenticationFailed,
          message: 'Unable to sign Huddle authentication.',
          cause: error,
        ),
        generation,
      );
    }
  }

  void _handleJoined(Map<String, dynamic> message, int generation) {
    if (_state.phase != HuddleTransportPhase.authenticating &&
        _state.phase != HuddleTransportPhase.connected) {
      _handleProtocolProblem('Unexpected Huddle joined message.', generation);
      return;
    }

    final pubkey = message['pubkey'];
    final peerIndex = message['peer_index'];
    if (pubkey is! String ||
        pubkey.isEmpty ||
        peerIndex is! int ||
        peerIndex < 0 ||
        peerIndex > 255) {
      _handleProtocolProblem('Malformed Huddle joined message.', generation);
      return;
    }

    final peers = Map<int, HuddlePeer>.from(_state.peers);
    final snapshot = message['peers'];
    if (snapshot is List) {
      peers.clear();
      for (final candidate in snapshot) {
        if (candidate is! Map) continue;
        final candidatePubkey = candidate['pubkey'];
        final candidateIndex = candidate['peer_index'];
        if (candidatePubkey is String &&
            candidatePubkey.isNotEmpty &&
            candidateIndex is int &&
            candidateIndex >= 0 &&
            candidateIndex <= 255) {
          peers[candidateIndex] = HuddlePeer(
            pubkey: candidatePubkey,
            peerIndex: candidateIndex,
          );
        }
      }
    }
    final peer = HuddlePeer(pubkey: pubkey, peerIndex: peerIndex);
    peers[peerIndex] = peer;

    final initialAdmission =
        _state.phase == HuddleTransportPhase.authenticating;
    _emitState(
      HuddleTransportState(
        phase: HuddleTransportPhase.connected,
        localPeerIndex: initialAdmission ? peerIndex : _state.localPeerIndex,
        peers: peers,
      ),
    );
    if (!initialAdmission) {
      _peerController.add(
        HuddlePeerEvent(type: HuddlePeerEventType.joined, peer: peer),
      );
    }
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    if (_handshakeCompleter case final completer? when !completer.isCompleted) {
      completer.complete();
    }
  }

  void _handleLeft(Map<String, dynamic> message, int generation) {
    if (_state.phase != HuddleTransportPhase.connected) {
      _handleProtocolProblem('Unexpected Huddle left message.', generation);
      return;
    }
    final pubkey = message['pubkey'];
    final peerIndex = message['peer_index'];
    if (pubkey is! String ||
        peerIndex is! int ||
        peerIndex < 0 ||
        peerIndex > 255) {
      _handleProtocolProblem('Malformed Huddle left message.', generation);
      return;
    }

    final peers = Map<int, HuddlePeer>.from(_state.peers);
    final removed =
        peers.remove(peerIndex) ??
        HuddlePeer(pubkey: pubkey, peerIndex: peerIndex);
    _emitState(
      HuddleTransportState(
        phase: HuddleTransportPhase.connected,
        localPeerIndex: _state.localPeerIndex,
        peers: peers,
      ),
    );
    _peerController.add(
      HuddlePeerEvent(type: HuddlePeerEventType.left, peer: removed),
    );
  }

  void _handleRelayError(Map<String, dynamic> message, int generation) {
    final relayCode = message['code'] is String
        ? message['code'] as String
        : null;
    final relayMessage = message['message'] is String
        ? message['message'] as String
        : 'Huddle audio relay rejected the connection.';
    _fail(
      HuddleTransportError(
        code: HuddleTransportErrorCode.relayRejected,
        message: relayMessage,
        relayCode: relayCode,
      ),
      generation,
    );
  }

  void _handleBinaryMessage(Uint8List bytes, int generation) {
    if (_state.phase != HuddleTransportPhase.connected) {
      _handleProtocolProblem(
        'Received Huddle audio before room admission.',
        generation,
      );
      return;
    }
    try {
      _audioController.add(HuddleWireV2.decodeRelayFrame(bytes));
    } on HuddleWireException catch (error) {
      _issueController.add(
        HuddleTransportError(
          code: HuddleTransportErrorCode.protocolViolation,
          message: error.message,
          cause: error,
        ),
      );
    }
  }

  void _handleProtocolProblem(String message, int generation) {
    final error = HuddleTransportError(
      code: HuddleTransportErrorCode.protocolViolation,
      message: message,
    );
    if (_state.phase == HuddleTransportPhase.connected) {
      _issueController.add(error);
    } else {
      _fail(error, generation);
    }
  }

  void _handleSocketFailure(Object error, int generation) {
    if (_intentionalClose || !_isCurrent(generation)) return;
    _fail(
      HuddleTransportError(
        code: HuddleTransportErrorCode.connectionFailed,
        message: 'Huddle audio socket failed.',
        cause: error,
      ),
      generation,
    );
  }

  void _handleSocketClosed(int generation) {
    if (_intentionalClose || !_isCurrent(generation)) return;
    _fail(
      const HuddleTransportError(
        code: HuddleTransportErrorCode.socketClosed,
        message: 'Huddle audio socket closed unexpectedly.',
      ),
      generation,
    );
  }

  void _fail(HuddleTransportError error, int generation) {
    if (!_isCurrent(generation) ||
        _state.phase == HuddleTransportPhase.failed) {
      return;
    }
    _handshakeTimer?.cancel();
    _handshakeTimer = null;
    _emitState(
      HuddleTransportState(
        phase: HuddleTransportPhase.failed,
        localPeerIndex: _state.localPeerIndex,
        peers: _state.peers,
        error: error,
      ),
    );
    if (_handshakeCompleter case final completer? when !completer.isCompleted) {
      completer.completeError(error);
    }
    _subscription?.cancel();
    _subscription = null;
    final channel = _channel;
    _channel = null;
    unawaited(channel?.sink.close() ?? Future<void>.value());
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _emitState(HuddleTransportState next) {
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }
}
