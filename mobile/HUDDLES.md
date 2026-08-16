# Mobile Huddles MVP

This foreground-only product slice preserves the existing Desktop/relay
contract. Android and iOS clients can start a human Huddle, open a recent
Desktop-started Huddle card, join with the microphone on, hear multiple remote
participants, send microphone audio, mute, leave, or (as creator) end the room.

The parent channel carries creator-signed kind `48100` start and `48103` end
events. The private `stream` backing channel uses kind `9007`, `ttl=3600`, and
is hidden from the ordinary channel list only after a matching start event
links it from an accessible parent. The top-right hang-up follows Desktop's
rule: it counts non-`bot` backing-channel members before disconnecting, submits
kind `9022` when another human remains, and otherwise publishes kind `48103`
and archives with kind `9002`. A failed count safely assumes another human is
present so a transient relay error cannot end the Huddle. Creator-only explicit
“End for everyone” remains a separate action. On relaunch, parent event history
reconstructs the visible card without silently reopening a microphone.

## Control plane

1. Connect to `WS /huddle/{ephemeral_channel_id}/audio`.
2. Receive `{"type":"challenge","challenge":"..."}`.
3. Sign NIP-42 kind `22242` with `relay=<base relay WebSocket URL>` and the
   challenge. The `relay` tag is **not** the Huddle endpoint URL.
4. Send an object envelope containing `type=auth`, the signed event,
   `parent_channel_id`, and `protocol_version=2`.
5. Treat the connection as usable only after a `joined` response. `error`,
   unexpected close, handshake timeout, and protocol failures are explicit
   states. An established session retries only its media socket with bounded
   backoff (`0, 100, 250, 500, 1000, 2000, 2000 ms`) and keeps native media
   alive while reconnecting.

The main Nostr socket is intentionally not shared: it accepts Nostr JSON arrays
and drops binary frames, while Huddle control messages are JSON objects.

## Media plane: protocol v2

Audio is 48 kHz, mono Opus in 20 ms (960-sample) frames.

Client to relay:

```text
8-byte header | Opus payload
```

Relay to client:

```text
peer_index u8 | 8-byte header | Opus payload
```

The header is network byte order: sequence `u16`, 48 kHz timestamp `u32`,
level dBov `i8` in `-127...0`, and flags `u8` where bit 0 marks DTX. Unknown
flag bits are ignored. Frames are capped at 4096 bytes before the relay peer
prefix.

## Native boundary

`buzz/huddle_media` owns microphone permission and the foreground voice audio
session. Each platform probes its native Opus encoder and decoder before
advertising support. On Android, `AudioRecord` captures 48 kHz mono PCM,
`MediaCodec` encodes and decodes Opus, and one `AudioTrack` per remote
participant lets the Android communication mixer combine decoded PCM. On iOS,
`AVAudioEngine` owns voice-processed capture and per-peer mixed playout while
`AVAudioConverter` performs native Opus encoding and decoding. Both paths use a
three-packet startup jitter buffer with a ten-packet per-peer bound.

Acoustic echo cancellation is enabled through Android's voice communication
effects and iOS Voice Processing I/O. Audio focus/session interruptions surface
explicitly; media resumes only when the platform permits it. The Flutter
speaker control directly switches between the built-in speaker and the normal
communication route. Built-in output starts on the earpiece/receiver, while an
already-selected external Bluetooth or wired communication route remains under
the operating system's routing policy until the user explicitly enables the
built-in speaker.

Only compressed `localOpusFrame` and `playRemoteOpusFrame` messages cross the
Flutter bridge; PCM remains inside the native realtime path. Capture starts
unmuted. Debuggable builds also emit aggregate pre-encode RMS/peak dBov
histograms plus the active recording route and exposed voice-processing state.
They never retain or persist PCM, Opus packets, or speech content. Native
capture and compressed ingress queues are bounded so a foreground session
cannot accumulate unbounded latency.

This is deliberately not Desktop parity. The app must remain in the foreground;
pausing/detaching leaves the room. Mobile agent controls, mobile-originated
STT/TTS, recordings, reactions, background ringing/calling, and advanced device
controls remain outside this slice. Agent-authenticated Opus published by a
Desktop Huddle uses the same remote playback path as any other participant.

Physical iOS acceptance must separately verify permission, receiver/speaker and
connected-headset routing, interruption recovery, and two-way audio with a
Desktop participant. Static codec and Flutter tests do not prove those device
behaviors.
