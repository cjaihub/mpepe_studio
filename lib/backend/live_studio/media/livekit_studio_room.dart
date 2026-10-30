// LIVE STUDIO v2 — LiveKit implementation of [StudioRoomPort] (workstream #1).
//
// - joins with a token from `lsToken` (identity = Firebase uid);
// - `adaptiveStream` + `dynacast`, simulcast camera (see publish_profile.dart);
// - data packets decoded by topic with [StudioEvent.decode]; packets from
//   participants are dropped (only the server may send data);
// - active speakers from [ActiveSpeakersChangedEvent];
// - app-level reconnect with backoff + jitter on top of LiveKit's own;
// - audio-only fallback ([AudioOnlyFallback]) and QoS every 10 s.

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc show Helper;
import 'package:livekit_client/livekit_client.dart';

import '../contracts/studio_contracts.dart';
import '../contracts/studio_ports.dart';
import '../security/studio_e2ee_session.dart';
import '../security/studio_security_models.dart';
import 'audio_only_fallback.dart';
import 'game_stream.dart';
import 'livekit_video_handle.dart';
import 'publish_profile.dart';
import 'qos_sampler.dart';
import 'reconnect_policy.dart';
import 'studio_media_api.dart';
import 'studio_packet_decoder.dart';

/// Maps LiveKit's connection quality to the port's.
StudioLinkQuality studioLinkQualityOf(ConnectionQuality q) => switch (q) {
      ConnectionQuality.excellent => StudioLinkQuality.excellent,
      ConnectionQuality.good => StudioLinkQuality.good,
      ConnectionQuality.poor => StudioLinkQuality.poor,
      ConnectionQuality.lost => StudioLinkQuality.lost,
      ConnectionQuality.unknown => StudioLinkQuality.good,
    };

/// Microphone sound presets. They use the platform's real-time voice
/// processing (WebRTC): noise suppression, voice isolation, gain and filters.
enum StudioVoicePreset {
  natural('Natural', 'Balanced cleanup for talking'),
  clear('Clear voice', 'Extra noise and rumble removal for busy places'),
  studio('Studio', 'Steady level and isolated voice, like a podcast mic'),
  music('Music', 'No processing: best for singing and instruments (use headphones)');

  const StudioVoicePreset(this.label, this.description);
  final String label;
  final String description;

  AudioCaptureOptions get captureOptions => switch (this) {
        StudioVoicePreset.natural => const AudioCaptureOptions(),
        StudioVoicePreset.clear => const AudioCaptureOptions(highPassFilter: true, typingNoiseDetection: true),
        StudioVoicePreset.studio =>
          const AudioCaptureOptions(highPassFilter: true, autoGainControl: false, voiceIsolation: true),
        StudioVoicePreset.music => const AudioCaptureOptions(
            noiseSuppression: false,
            autoGainControl: false,
            highPassFilter: false,
            voiceIsolation: false,
            typingNoiseDetection: false,
          ),
      };
}

class LiveKitStudioRoom implements StudioRoomPort, StudioGameStreamPort {
  LiveKitStudioRoom({
    required this.streamId,
    required StudioMediaApi api,
    StudioMetricsSink? metrics,
    StudioReconnectBackoff? backoff,
    DateTime Function()? clock,
    Future<StudioJoinCredentials> Function()? credentials,
  })  : _media = api,
        _backoff = backoff ?? StudioReconnectBackoff(),
        _clock = clock ?? DateTime.now,
        _tokenSource = credentials {
    _qos = StudioQosSampler(sink: metrics ?? _NoopSink(), streamId: streamId, clock: _clock)
      ..audioOnlyTime = () => _fallback.audioOnlyTime(_clock());
  }

  final String streamId;
  final StudioMediaApi _media;
  final StudioReconnectBackoff _backoff;
  final DateTime Function() _clock;
  Future<StudioJoinCredentials> Function()? _tokenSource;

  late final StudioQosSampler _qos;
  final AudioOnlyFallback _fallback = AudioOnlyFallback();

  Room? _room;
  EventsListener<RoomEvent>? _listener;
  final Map<String, EventsListener<TrackEvent>> _trackListeners = {};

  final _events = StreamController<StudioEvent>.broadcast();
  final _speakersCtl = StreamController<List<String>>.broadcast();
  final _qualityCtl = StreamController<StudioLinkQuality>.broadcast();
  final _mediaChanged = StreamController<void>.broadcast();
  final _securityCtl = StreamController<StudioSecurityPacket>.broadcast();

  /// Media E2EE for the current connection (null = not encrypted).
  StudioE2eeSession? _e2ee;

  List<String> _speakers = const [];
  StudioLinkQuality _quality = StudioLinkQuality.lost;
  StudioRole _role = StudioRole.viewer;
  Object? _fatalError;

  bool _closed = false;
  bool _connecting = false;
  bool _connectedOnce = false;
  int _attempt = 0;
  Timer? _retryTimer;
  Timer? _tickTimer;
  Timer? _qosTimer;

  bool _wantMic = false;
  bool _wantCam = false;
  bool _cameraSuspended = false;
  LocalVideoTrack? _screenTrack;

  final Map<String, LiveKitVideoHandle> _cams = {};
  LiveKitVideoHandle? _screen;

  /// Hook called when a local camera track is published (e.g. for TrackLookProcessor).
  void Function(String trackId)? onCameraTrackPublished;

  /// Hook called when a local camera track is unpublished or stopped.
  void Function(String trackId)? onCameraTrackUnpublished;

  /// Current microphone preset (see [setVoicePreset]).
  StudioVoicePreset voicePreset = StudioVoicePreset.natural;

  /// Switches the mic's sound processing; republishes the mic if it is live.
  Future<void> setVoicePreset(StudioVoicePreset preset) async {
    voicePreset = preset;
    final lp = _room?.localParticipant;
    if (lp == null || !canPublish || !_wantMic) return;
    final pub = lp.getTrackPublicationBySource(TrackSource.microphone);
    if (pub != null) await lp.removePublishedTrack(pub.sid);
    await lp.setMicrophoneEnabled(true, audioCaptureOptions: preset.captureOptions);
    _changed();
  }

  /// The host's first join publishes mic / camera per these (setup wizard).
  bool hostStartsWithMic = true;
  bool hostStartsWithCamera = true;

  // ─── Extra API (beyond the port) ───────────────────────────────────────────

  /// Server messages on topic `security` (advisories for managers, key updates).
  Stream<StudioSecurityPacket> get securityPackets => _securityCtl.stream;

  /// True when stage media of this connection is end-to-end encrypted.
  bool get e2eeActive => _e2ee?.active ?? false;

  /// Role the current token was minted for.
  StudioRole get role => _role;

  /// Set when joining is impossible (ended, blocked, kicked); no more retries.
  Object? get fatalError => _fatalError;

  bool get isConnected => _room?.connectionState == ConnectionState.connected;

  /// Fires when any publication appears, disappears, mutes or (un)subscribes:
  /// the stage should re-query [cameraOf] / [tableScreen].
  Stream<void> get mediaChanged => _mediaChanged.stream;

  /// Whether the server currently lets this client publish.
  bool get canPublish => _room?.localParticipant?.permissions.canPublish ?? false;

  /// Identities (uids) currently in the room, including this client.
  Set<String> get connectedIdentities {
    final room = _room;
    if (room == null) return const {};
    return {
      ...room.remoteParticipants.keys,
      if (room.localParticipant != null) room.localParticipant!.identity,
    };
  }

  /// Uses [first] for the first join (e.g. the token lsStart returned), then
  /// lsToken for every reconnect.
  void useInitialCredentials(StudioJoinCredentials first) {
    var used = false;
    final previous = _tokenSource;
    _tokenSource = () async {
      if (!used) {
        used = true;
        return first;
      }
      return previous != null ? previous() : _media.token(streamId);
    };
  }

  /// Joins the room. Never throws: failures schedule a retry, or set
  /// [fatalError] when retrying cannot help.
  Future<void> connect() async {
    if (_closed || _connecting) return;
    _connecting = true;
    _retryTimer?.cancel();
    _qos.markJoinStart();
    try {
      final creds = await (_tokenSource ?? () => _media.token(streamId))();
      if (_closed) return;
      _role = creds.role;
      _qos.role = _role.wire;
      await _teardownRoom();
      var room = Room(roomOptions: _roomOptions(await _prepareE2ee(creds.e2ee)));
      _room = room;
      _bindRoom(room);
      try {
        await room.connect(creds.url, creds.token);
      } on LiveKitE2EEException {
        // This platform has no frame encryption: join without it (chat and
        // state still work; encrypted stage video will not decode here).
        await _teardownRoom();
        _e2ee = null;
        room = Room(roomOptions: _roomOptions(null));
        _room = room;
        _bindRoom(room);
        await room.connect(creds.url, creds.token);
      }
      await _e2ee?.reapply();
      if (_closed) {
        await room.disconnect();
        return;
      }
      if (_connectedOnce) _qos.onReconnect();
      // The host goes live on camera + mic as soon as the room is joined
      // (guests opt in through the device check / goOnStage instead).
      if (!_connectedOnce && _role == StudioRole.host) {
        _wantMic = hostStartsWithMic;
        _wantCam = hostStartsWithCamera;
      }
      _connectedOnce = true;
      _attempt = 0;
      _fatalError = null;
      _setQuality(StudioLinkQuality.good);
      _startTimers();
      _syncHandles();
      await _restoreLocalMedia();
    } catch (e) {
      if (isFatalJoinError(e)) {
        _fatalError = e;
        _setQuality(StudioLinkQuality.lost);
      } else {
        _scheduleRetry();
      }
    } finally {
      _connecting = false;
    }
  }

  /// Re-joins with a fresh token (e.g. after a role change).
  Future<void> rejoin() async {
    _attempt = 0;
    await connect();
  }

  /// Key provider + session for [key]; null when the server sent no key or the
  /// platform cannot create a frame-crypto key provider.
  Future<E2EEOptions?> _prepareE2ee(StudioMediaKey? key) async {
    _e2ee = null;
    if (key == null) return null;
    try {
      final provider = await BaseKeyProvider.create();
      final session = StudioE2eeSession(
        fetchKey: () => _media.mediaKey(streamId),
        installKey: (k) => provider.setRawKey(k.bytes, keyIndex: k.keyIndex),
        useIndex: (i) async => _room?.e2eeManager?.setKeyIndex(i),
      );
      await session.start(key);
      _e2ee = session;
      return E2EEOptions(keyProvider: provider);
    } catch (_) {
      return null;
    }
  }

  RoomOptions _roomOptions(E2EEOptions? e2ee) {
    final profile = StudioPublishProfile.standard;
    return RoomOptions(
      // Media-only frame encryption. Not `encryption:`, which also encrypts
      // data packets: ours are server-sent and must stay readable.
      // ignore: deprecated_member_use
      e2eeOptions: e2ee,
      adaptiveStream: true,
      dynacast: true,
      defaultCameraCaptureOptions: profile.cameraOptions,
      defaultVideoPublishOptions: profile.publishOptions,
      defaultAudioPublishOptions: const AudioPublishOptions(name: StudioTrackNames.microphone, dtx: true),
      defaultScreenShareCaptureOptions: kTableScreenCaptureOptions,
    );
  }

  void _onSecurityPacket(List<int> data) {
    final p = StudioSecurityPacket.decodeBytes(data);
    if (p == null) return;
    if (p is KeyUpdatePacket) unawaited(_e2ee?.onKeyUpdate(p.keyIndex));
    if (!_securityCtl.isClosed) _securityCtl.add(p);
  }

  void _scheduleRetry() {
    if (_closed || _fatalError != null) return;
    _setQuality(StudioLinkQuality.lost);
    final delay = _backoff.delayFor(_attempt++);
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () => unawaited(connect()));
  }

  void _startTimers() {
    _tickTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (_fallback.evaluate(_clock())) unawaited(_applyAudioOnly());
    });
    _qosTimer ??= Timer.periodic(StudioQosSampler.interval, (_) => _qos.flush());
  }

  // ─── Room events ───────────────────────────────────────────────────────────

  void _bindRoom(Room room) {
    final l = room.createListener();
    _listener = l;
    l
      ..on<DataReceivedEvent>((e) {
        if (e.topic == StudioSecurityWire.topic) {
          if (e.participant == null) _onSecurityPacket(e.data);
          return;
        }
        final ev = decodeStudioPacket(e.data, topic: e.topic, fromParticipant: e.participant != null);
        if (ev != null && !_events.isClosed) _events.add(ev);
      })
      ..on<ActiveSpeakersChangedEvent>((e) {
        _speakers = [for (final p in e.speakers) p.identity];
        if (!_speakersCtl.isClosed) _speakersCtl.add(_speakers);
        _changed();
      })
      ..on<ParticipantConnectionQualityUpdatedEvent>((e) {
        if (e.participant is LocalParticipant) _setQuality(studioLinkQualityOf(e.connectionQuality));
      })
      // In-place promotion/demotion (lsRespondRequest / lsModerate) updates our
      // permission and the server-set `role` attribute without a new token.
      ..on<ParticipantAttributesChanged>((e) {
        if (e.participant is LocalParticipant) _adoptServerRole(e.attributes['role']);
      })
      ..on<ParticipantPermissionsUpdatedEvent>((e) {
        if (e.participant is! LocalParticipant) return;
        _adoptServerRole(e.participant.attributes['role']);
        if (!e.permissions.canPublish && _role.canPublish) _adoptServerRole(StudioRole.viewer.wire);
      })
      // New local tracks start at key index 0: switch them to the current one.
      ..on<LocalTrackPublishedEvent>((_) => unawaited(_e2ee?.reapply()))
      ..on<RoomReconnectingEvent>((_) => _setQuality(StudioLinkQuality.lost))
      ..on<RoomReconnectedEvent>((_) {
        _qos.onReconnect();
        _setQuality(StudioLinkQuality.good);
        _syncHandles();
      })
      ..on<RoomDisconnectedEvent>((e) => _onDisconnected(e.reason))
      ..on<TrackSubscribedEvent>((e) {
        final t = e.track;
        if (t is RemoteVideoTrack) {
          _watchReceiver(e.publication.sid, t);
          if (_fallback.audioOnly) unawaited(e.publication.unsubscribe());
        } else if (t is RemoteAudioTrack) {
          _watchReceiver(e.publication.sid, t);
        }
        _syncHandles();
      })
      ..on<TrackUnsubscribedEvent>((e) {
        _unwatch(e.publication.sid);
        _syncHandles();
      })
      ..on<LocalTrackPublishedEvent>((e) {
        final t = e.publication.track;
        if (t is LocalVideoTrack) _watchSender(e.publication.sid, t);
        _syncHandles();
      })
      ..on<LocalTrackUnpublishedEvent>((e) {
        _unwatch(e.publication.sid);
        _syncHandles();
      })
      ..on<TrackPublishedEvent>((_) => _syncHandles())
      ..on<TrackUnpublishedEvent>((_) => _syncHandles())
      ..on<TrackMutedEvent>((_) => _syncHandles())
      ..on<TrackUnmutedEvent>((_) => _syncHandles())
      ..on<TrackStreamStateUpdatedEvent>((_) => _syncHandles())
      ..on<ParticipantConnectedEvent>((_) => _syncHandles())
      ..on<ParticipantDisconnectedEvent>((_) => _syncHandles())
      ..on<ParticipantPermissionsUpdatedEvent>((_) => _changed());
  }

  void _onDisconnected(DisconnectReason? reason) {
    if (_closed) return;
    _setQuality(StudioLinkQuality.lost);
    switch (reason) {
      case DisconnectReason.clientInitiated:
        return;
      case DisconnectReason.roomDeleted:
      case DisconnectReason.participantRemoved:
      case DisconnectReason.duplicateIdentity:
        _fatalError = StateError('Disconnected by the server: ${reason!.name}');
        _changed();
        return;
      default:
        _scheduleRetry();
    }
  }

  void _watchReceiver(String sid, Track track) {
    _unwatch(sid);
    final l = track.createListener();
    _trackListeners[sid] = l;
    l
      ..on<VideoReceiverStatsEvent>((e) {
        final s = e.stats;
        if ((s.framesDecoded ?? 0) > 0) _qos.markFirstFrame();
        _qos.onReceiverStats(sid,
            packetsLost: s.packetsLost,
            packetsReceived: s.packetsReceived,
            jitterSeconds: s.jitter,
            frameHeight: s.frameHeight);
      })
      ..on<AudioReceiverStatsEvent>((e) {
        final s = e.stats;
        _qos.onReceiverStats(sid,
            packetsLost: s.packetsLost, packetsReceived: s.packetsReceived, jitterSeconds: s.jitter);
      });
  }

  void _watchSender(String sid, LocalVideoTrack track) {
    _unwatch(sid);
    final l = track.createListener();
    _trackListeners[sid] = l;
    l.on<VideoSenderStatsEvent>((e) {
      for (final s in e.stats.values) {
        _qos.onSenderStats(roundTripTimeSeconds: s.roundTripTime, jitterSeconds: s.jitter);
      }
    });
  }

  void _unwatch(String sid) {
    unawaited(_trackListeners.remove(sid)?.dispose());
    _qos.forgetTrack(sid);
  }

  // ─── Quality / audio-only ──────────────────────────────────────────────────

  void _setQuality(StudioLinkQuality q) {
    final flipped = _fallback.onQuality(q, _clock());
    if (q != _quality) {
      _quality = q;
      if (!_qualityCtl.isClosed) _qualityCtl.add(q);
    }
    if (flipped) unawaited(_applyAudioOnly());
  }

  Future<void> _applyAudioOnly() async {
    final on = _fallback.audioOnly;
    final room = _room;
    if (room != null) {
      // Viewer side: stop / resume receiving video.
      for (final p in room.remoteParticipants.values) {
        for (final pub in p.videoTrackPublications) {
          try {
            on ? await pub.unsubscribe() : await pub.subscribe();
          } catch (_) {}
        }
      }
      // Publisher side: stop / resume sending camera video.
      final lp = room.localParticipant;
      if (lp != null && _wantCam) {
        try {
          if (on && lp.isCameraEnabled()) {
            _cameraSuspended = true;
            await lp.setCameraEnabled(false);
          } else if (!on && _cameraSuspended) {
            _cameraSuspended = false;
            await lp.setCameraEnabled(true);
          }
        } catch (_) {}
      }
    }
    for (final h in [..._cams.values, ?_screen]) {
      h.setSuppressed(on && !h.isLocal);
    }
    _changed();
  }

  // ─── Handles ───────────────────────────────────────────────────────────────

  Participant? _participant(String uid) {
    final room = _room;
    if (room == null) return null;
    final lp = room.localParticipant;
    if (lp != null && lp.identity == uid) return lp;
    return room.remoteParticipants[uid];
  }

  Iterable<Participant> get _allParticipants sync* {
    final room = _room;
    if (room == null) return;
    final lp = room.localParticipant;
    if (lp != null) yield lp;
    yield* room.remoteParticipants.values;
  }

  TrackPublication? _cameraPub(String uid) => _participant(uid)?.getTrackPublicationBySource(TrackSource.camera);

  ({String uid, TrackPublication pub})? _screenPub() {
    for (final p in _allParticipants) {
      for (final pub in p.videoTrackPublications) {
        if (pub.name == StudioTrackNames.tableScreen || pub.source == TrackSource.screenShareVideo) {
          return (uid: p.identity, pub: pub);
        }
      }
    }
    return null;
  }

  void _syncHandles() {
    _cams.forEach((uid, h) {
      final pub = _cameraPub(uid);
      if (!identical(pub, h.publication)) {
        h.bind(pub);
      } else {
        h.refresh();
      }
    });
    final s = _screen;
    if (s != null) {
      final cur = _screenPub();
      if (cur == null || cur.uid != s.uid) {
        s.bind(null);
        _screen = null;
      } else if (!identical(cur.pub, s.publication)) {
        s.bind(cur.pub);
      } else {
        s.refresh();
      }
    }
    _changed();
  }

  void _changed() {
    if (!_mediaChanged.isClosed) _mediaChanged.add(null);
  }

  /// Adopts a role pushed by the server without a new token (the `role`
  /// participant attribute, or lost publish permission). Losing publish stops
  /// local media; gaining it lets the next toggle publish and sync.
  void _adoptServerRole(String? wire) {
    if (wire == null || wire.isEmpty) return;
    final next = StudioRole.fromWire(wire);
    if (next == _role) return;
    final lostPublish = _role.canPublish && !next.canPublish;
    _role = next;
    _qos.role = next.wire;
    if (lostPublish) {
      _wantMic = false;
      _wantCam = false;
      unawaited(stopTableScreenShare().catchError((_) {}));
    }
    _changed();
  }

  // ─── StudioRoomPort ────────────────────────────────────────────────────────

  @override
  Stream<StudioEvent> get events => _events.stream;

  @override
  Stream<List<String>> get activeSpeakers => _speakersCtl.stream;

  @override
  List<String> get currentSpeakers => _speakers;

  @override
  Stream<StudioLinkQuality> get quality => _qualityCtl.stream;

  StudioLinkQuality get currentQuality => _quality;

  @override
  bool get audioOnly => _fallback.audioOnly;

  @override
  StudioVideoHandle? cameraOf(String uid) {
    final pub = _cameraPub(uid);
    if (pub == null) return null;
    final h = _cams.putIfAbsent(uid, () => LiveKitVideoHandle(uid));
    if (!identical(pub, h.publication)) h.bind(pub);
    h.setSuppressed(_fallback.audioOnly && !h.isLocal);
    return h;
  }

  @override
  StudioVideoHandle? tableScreen() {
    final cur = _screenPub();
    if (cur == null) return null;
    var h = _screen;
    if (h == null || h.uid != cur.uid) {
      h?.bind(null);
      h = LiveKitVideoHandle(cur.uid, isTableScreen: true);
      _screen = h;
    }
    if (!identical(cur.pub, h.publication)) h.bind(cur.pub);
    h.setSuppressed(_fallback.audioOnly && !h.isLocal);
    return h;
  }

  @override
  bool isSpeaking(String uid) => _participant(uid)?.isSpeaking ?? false;

  @override
  bool isMicMuted(String uid) {
    final p = _participant(uid);
    return p == null || !p.isMicrophoneEnabled();
  }

  // ─── Local publishing ──────────────────────────────────────────────────────

  @override
  Future<void> setMicEnabled(bool on) async {
    _wantMic = on;
    final lp = _room?.localParticipant;
    if (lp != null && canPublish) {
      await lp.setMicrophoneEnabled(on, audioCaptureOptions: voicePreset.captureOptions);
    }
    _syncOwnMedia();
  }

  @override
  Future<void> setCameraEnabled(bool on) async {
    _wantCam = on;
    _cameraSuspended = false;
    final lp = _room?.localParticipant;
    if (lp != null && canPublish) {
      if (on && _fallback.audioOnly) {
        _cameraSuspended = true; // resumes when the link recovers
      } else if (on && lp.getTrackPublicationBySource(TrackSource.camera) == null) {
        await _publishCamera(lp);
      } else {
        if (!on) {
          final pub = lp.getTrackPublicationBySource(TrackSource.camera);
          if (pub?.track != null) {
            final tid = pub!.track!.mediaStreamTrack.id;
            if (tid != null) onCameraTrackUnpublished?.call(tid);
          }
        }
        await lp.setCameraEnabled(on);
      }
    }
    _syncOwnMedia();
  }

  /// Opens the camera with the role's profile. The host tries 1080p and
  /// falls back to 720p when the device delivers fewer lines.
  Future<void> _publishCamera(LocalParticipant lp) async {
    var profile = StudioPublishProfile.forRole(_role, supports1080: _role == StudioRole.host);
    var track = await LocalVideoTrack.createCameraTrack(profile.cameraOptions);
    if (identical(profile, StudioPublishProfile.hostHd)) {
      final s = track.mediaStreamTrack.getSettings();
      final w = s['width'], h = s['height'];
      if (w is num && h is num && (w < h ? w : h) < 1000) {
        await track.stop();
        profile = StudioPublishProfile.standard;
        track = await LocalVideoTrack.createCameraTrack(profile.cameraOptions);
      }
    }
    await lp.publishVideoTrack(track, publishOptions: profile.publishOptions);
    final tid = track.mediaStreamTrack.id;
    if (tid != null) onCameraTrackPublished?.call(tid);
  }

  Future<void> _restoreLocalMedia() async {
    if (!canPublish) return;
    final lp = _room?.localParticipant;
    if (lp == null) return;
    // Independent steps: a refused mic must not stop the camera (and vice versa).
    if (_wantMic) {
      try {
        await lp.setMicrophoneEnabled(true, audioCaptureOptions: voicePreset.captureOptions);
      } catch (e) {
        _wantMic = false;
        debugPrint('[LiveKitStudioRoom] mic publish failed: $e');
      }
    }
    if (_wantCam && !_fallback.audioOnly && lp.getTrackPublicationBySource(TrackSource.camera) == null) {
      try {
        await _publishCamera(lp);
      } catch (e) {
        _wantCam = false;
        debugPrint('[LiveKitStudioRoom] camera publish failed: $e');
      }
    }
    _syncOwnMedia();
    _changed();
  }

  void _syncOwnMedia() {
    if (!_role.canPublish) return;
    unawaited(_media.setOwnMedia(streamId, micOn: _wantMic, camOn: _wantCam).then((_) {}, onError: (_) {}));
  }

  @override
  Future<void> startTableScreenShare() =>
      _startScreenShare(kTableScreenCaptureOptions, kTableScreenPublishOptions);

  /// Game Live: whole-screen capture at up to 1080p/30 with a high bitrate
  /// ([kGameScreenCaptureOptions]). The capture service keeps mic (and camera)
  /// alive while the host is in the game app; the mic is (re)published here so
  /// viewers keep hearing the host.
  @override
  Future<void> startGameStream() async {
    final lp = _room?.localParticipant;
    if (lp == null || !canPublish) return;
    await _startScreenShare(kGameScreenCaptureOptions, kGameScreenPublishOptions);
    if (!lp.isMicrophoneEnabled()) {
      try {
        await setMicEnabled(true);
      } catch (e) {
        debugPrint('[LiveKitStudioRoom] game stream mic: $e');
      }
    }
  }

  Future<void> _startScreenShare(ScreenShareCaptureOptions capture, VideoPublishOptions publish) async {
    final lp = _room?.localParticipant;
    if (lp == null || !canPublish || _screenTrack != null) return;
    // Android 14+: consent first, then a mediaProjection foreground service,
    // then capture (LiveScreenCaptureService.kt). Without the service the OS
    // throws a SecurityException inside the plugin and the app crashes.
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (android) {
      final granted = await webrtc.Helper.requestCapturePermission();
      if (!granted) throw StateError('Screen sharing was not allowed.');
      await _screenCaptureService.invokeMethod<bool>('start');
    }
    try {
      final track = await LocalVideoTrack.createScreenShareTrack(capture);
      _screenTrack = track;
      await lp.publishVideoTrack(track, publishOptions: publish);
    } catch (e) {
      _screenTrack = null;
      if (android) await _stopScreenCaptureService();
      rethrow;
    }
  }

  static const MethodChannel _screenCaptureService = MethodChannel('com.oneova.app/live_screen_capture');

  Future<void> _stopScreenCaptureService() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _screenCaptureService.invokeMethod<bool>('stop');
    } catch (e) {
      debugPrint('[LiveKitStudioRoom] stop screen service: $e');
    }
  }

  @override
  Future<void> stopTableScreenShare() async {
    final track = _screenTrack;
    _screenTrack = null;
    final lp = _room?.localParticipant;
    if (lp != null) {
      for (final pub in [...lp.videoTrackPublications]) {
        if (pub.name == StudioTrackNames.tableScreen) await lp.removePublishedTrack(pub.sid);
      }
    }
    await track?.stop();
    await _stopScreenCaptureService();
  }

  // ─── Teardown ──────────────────────────────────────────────────────────────

  Future<void> _teardownRoom() async {
    for (final l in _trackListeners.values) {
      await l.dispose();
    }
    _trackListeners.clear();
    await _listener?.dispose();
    _listener = null;
    final room = _room;
    _room = null;
    if (room != null) {
      try {
        await room.disconnect();
      } catch (_) {}
      await room.dispose();
    }
  }

  @override
  Future<void> disconnect() async {
    if (_closed) return;
    _closed = true;
    _retryTimer?.cancel();
    _tickTimer?.cancel();
    _qosTimer?.cancel();
    _qos.flush();
    final wasSharing = _screenTrack != null;
    await _screenTrack?.stop();
    _screenTrack = null;
    if (wasSharing) await _stopScreenCaptureService();
    final camPub = _room?.localParticipant?.getTrackPublicationBySource(TrackSource.camera);
    if (camPub?.track != null) {
      final tid = camPub!.track!.mediaStreamTrack.id;
      if (tid != null) onCameraTrackUnpublished?.call(tid);
    }
    await _teardownRoom();
    for (final h in _cams.values) {
      h.dispose();
    }
    _cams.clear();
    _screen?.dispose();
    _screen = null;
    await _events.close();
    await _speakersCtl.close();
    await _qualityCtl.close();
    await _mediaChanged.close();
    await _securityCtl.close();
  }
}

class _NoopSink implements StudioMetricsSink {
  @override
  void metric(String name, double value, Map<String, String> attributes) {}
}
