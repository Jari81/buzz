import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:buzz/shared/huddle/huddle_auth.dart';
import 'package:buzz/shared/huddle/huddle_transport.dart';
import 'package:buzz/shared/huddle/huddle_wire.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _privateKey =
    '09b3065e3570a3a4054660dccd66e12774a99a904fdb0ca02dbc6c3136249506';
const _parentChannelId = '11111111-2222-4333-8444-555555555555';
const _ephemeralChannelId = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';

void main() {
  test('authenticates with object JSON and admits a v2 room', () async {
    final channel = _ControlledWebSocketChannel();
    final transport = _transport(channel);
    addTearDown(transport.dispose);

    final connect = transport.connect();
    await _waitForPhase(transport, HuddleTransportPhase.awaitingChallenge);
    channel.emitText(jsonEncode({'type': 'challenge', 'challenge': 'abc'}));
    await _waitForPhase(transport, HuddleTransportPhase.authenticating);

    final auth = jsonDecode(channel.sink.sent.single as String);
    expect(auth, isA<Map<String, dynamic>>());
    expect(auth['type'], 'auth');
    expect(auth['parent_channel_id'], _parentChannelId);
    expect(auth['protocol_version'], 2);

    channel.emitText(
      jsonEncode({
        'type': 'joined',
        'pubkey': 'self',
        'peer_index': 3,
        'peers': [
          {'pubkey': 'desktop', 'peer_index': 1},
        ],
      }),
    );
    await connect;

    expect(transport.state.phase, HuddleTransportPhase.connected);
    expect(transport.state.localPeerIndex, 3);
    expect(transport.state.peers.keys, containsAll([1, 3]));
  });

  test(
    'parses inbound relay media and encodes outbound client media',
    () async {
      final channel = _ControlledWebSocketChannel();
      final transport = _transport(channel);
      addTearDown(transport.dispose);
      await _connect(channel, transport);

      final inbound = expectLater(
        transport.remoteAudioFrames,
        emits(
          isA<HuddleRemoteAudioFrame>()
              .having((frame) => frame.peerIndex, 'peer index', 4)
              .having((frame) => frame.header.sequence, 'sequence', 9)
              .having((frame) => frame.opusPayload, 'Opus', [0xaa]),
        ),
      );
      channel.emitBinary(
        Uint8List.fromList([4, 0, 9, 0, 0, 3, 0xc0, 0xd8, 0, 0xaa]),
      );
      await inbound;

      transport.sendOpusFrame(
        header: const HuddleAudioHeader(
          sequence: 10,
          timestamp48k: 1920,
          levelDbov: -40,
          flags: 0,
        ),
        opusPayload: Uint8List.fromList([0xbb]),
      );
      expect(
        channel.sink.sent.last,
        Uint8List.fromList([0, 10, 0, 0, 7, 0x80, 0xd8, 0, 0xbb]),
      );
    },
  );

  test('surfaces malformed media as recoverable issue', () async {
    final channel = _ControlledWebSocketChannel();
    final transport = _transport(channel);
    addTearDown(transport.dispose);
    await _connect(channel, transport);

    final issue = expectLater(
      transport.issues,
      emits(
        isA<HuddleTransportError>().having(
          (error) => error.code,
          'code',
          HuddleTransportErrorCode.protocolViolation,
        ),
      ),
    );
    channel.emitBinary(Uint8List.fromList([1, 2, 3]));
    await issue;

    expect(transport.state.phase, HuddleTransportPhase.connected);
  });

  test('exposes relay rejection code and failed lifecycle state', () async {
    final channel = _ControlledWebSocketChannel();
    final transport = _transport(channel);
    addTearDown(transport.dispose);

    final connect = transport.connect();
    await _waitForPhase(transport, HuddleTransportPhase.awaitingChallenge);
    channel.emitText(jsonEncode({'type': 'challenge', 'challenge': 'abc'}));
    await _waitForPhase(transport, HuddleTransportPhase.authenticating);
    channel.emitText(
      jsonEncode({
        'type': 'error',
        'code': 'upgrade_required',
        'message': 'room is pinned to v1',
      }),
    );

    await expectLater(
      connect,
      throwsA(
        isA<HuddleTransportError>()
            .having(
              (error) => error.code,
              'code',
              HuddleTransportErrorCode.relayRejected,
            )
            .having(
              (error) => error.relayCode,
              'relay code',
              'upgrade_required',
            ),
      ),
    );
    expect(transport.state.phase, HuddleTransportPhase.failed);
  });

  test(
    'intentional disconnect reaches disconnected without an error',
    () async {
      final channel = _ControlledWebSocketChannel();
      final transport = _transport(channel);
      addTearDown(transport.dispose);
      await _connect(channel, transport);

      await transport.disconnect();

      expect(transport.state.phase, HuddleTransportPhase.disconnected);
      expect(transport.state.error, isNull);
    },
  );
}

HuddleTransport _transport(_ControlledWebSocketChannel channel) =>
    HuddleTransport(
      parameters: HuddleConnectionParameters(
        relayWebSocketUrl: 'wss://buzz.example',
        nsec: _privateKey,
        parentChannelId: _parentChannelId,
        ephemeralChannelId: _ephemeralChannelId,
      ),
      channelFactory: (_) => channel,
      connectTimeout: const Duration(seconds: 1),
      handshakeTimeout: const Duration(seconds: 1),
    );

Future<void> _connect(
  _ControlledWebSocketChannel channel,
  HuddleTransport transport,
) async {
  final connect = transport.connect();
  await _waitForPhase(transport, HuddleTransportPhase.awaitingChallenge);
  channel.emitText(jsonEncode({'type': 'challenge', 'challenge': 'abc'}));
  await _waitForPhase(transport, HuddleTransportPhase.authenticating);
  channel.emitText(
    jsonEncode({
      'type': 'joined',
      'pubkey': 'self',
      'peer_index': 3,
      'peers': const [],
    }),
  );
  await connect;
}

Future<void> _waitForPhase(
  HuddleTransport transport,
  HuddleTransportPhase phase,
) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (transport.state.phase == phase) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Transport never reached ${phase.name}; was ${transport.state.phase}.');
}

final class _ControlledWebSocketChannel implements WebSocketChannel {
  final StreamController<dynamic> _streamController = StreamController();
  final _RecordingWebSocketSink _sink = _RecordingWebSocketSink();

  void emitText(String value) => _streamController.add(value);
  void emitBinary(Uint8List value) => _streamController.add(value);

  @override
  Future<void> get ready => Future.value();

  @override
  Stream<dynamic> get stream => _streamController.stream;

  @override
  _RecordingWebSocketSink get sink => _sink;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RecordingWebSocketSink implements WebSocketSink {
  final List<dynamic> sent = [];

  @override
  void add(dynamic event) => sent.add(event);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final event in stream) {
      sent.add(event);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  Future<void> get done => Future.value();
}
