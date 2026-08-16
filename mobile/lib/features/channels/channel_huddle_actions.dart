part of 'channel_management_provider.dart';

/// Canonical Huddle lifecycle operations built on the shared channel actions.
extension HuddleChannelActions on ChannelActions {
  /// Creates the private, one-hour stream used only by Huddle media.
  Future<String> createHuddleBackingChannel() async {
    final channelId = _newUuidV4();
    await _signedEventRelay.submit(
      kind: 9007,
      content: '',
      tags: buildCreateChannelTags(
        channelId: channelId,
        name: 'huddle-${channelId.substring(0, 8)}',
        channelType: 'stream',
        visibility: 'private',
        ttlSeconds: 3600,
      ),
    );
    // The accepted kind:9007 write has already committed creator membership
    // on the relay. Avoid refreshing the global channel list here: the backing
    // channel is intentionally hidden, and racing its membership fan-out can
    // temporarily make the parent channel appear read-only.
    return channelId;
  }

  /// Publishes the canonical creator-signed Huddle start event in its parent.
  Future<NostrEvent> announceHuddleStarted({
    required String parentChannelId,
    required String ephemeralChannelId,
  }) async {
    NostrEvent? signed;
    await _signedEventRelay.submit(
      kind: EventKind.huddleStarted,
      content: jsonEncode({'ephemeral_channel_id': ephemeralChannelId}),
      tags: [
        ['h', parentChannelId],
      ],
      onSigned: (event) => signed = event,
    );
    return signed ??
        (throw StateError('Huddle start event was not signed locally'));
  }

  /// Publishes the canonical creator-signed Huddle end event in its parent.
  Future<void> announceHuddleEnded({
    required String parentChannelId,
    required String ephemeralChannelId,
  }) async {
    await _signedEventRelay.submit(
      kind: EventKind.huddleEnded,
      content: jsonEncode({'ephemeral_channel_id': ephemeralChannelId}),
      tags: [
        ['h', parentChannelId],
      ],
    );
  }
}
