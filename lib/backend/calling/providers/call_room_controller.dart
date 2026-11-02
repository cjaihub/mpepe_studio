import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' hide AudioTrack;

import '../../../looks/live/live_looks_controller.dart';
import '../../../looks/models/oneova_look.dart';
import '../../social/models/audio_track.dart';
import 'active_call_controller.dart';
import 'call_media_service.dart';

/// Short sounds anyone in a call can play for everyone (`assets/sounds/call`,
/// synthesised in-house).
enum CallSound {
  applause('Applause', Icons.waving_hand_rounded),
  cheers('Cheers', Icons.celebration_rounded),
  drumroll('Drumroll', Icons.graphic_eq_rounded),
  rimshot('Ba-dum-tss', Icons.sentiment_very_satisfied_rounded),
  airhorn('Airhorn', Icons.campaign_rounded),
  victory('Victory', Icons.emoji_events_rounded),
  ding('Ding', Icons.notifications_active_rounded),
  sadTrombone('Sad trombone', Icons.sentiment_dissatisfied_rounded),
  boing('Boing', Icons.sports_basketball_rounded);

  const CallSound(this.label, this.icon);
  final String label;
  final IconData icon;

  String get asset => switch (this) {
        CallSound.sadTrombone => 'assets/sounds/call/sad_trombone.m4a',
        _ => 'assets/sounds/call/$name.m4a',
      };
}

/// A filter for the outgoing camera, graded on the GPU before encoding, so
/// everyone in the call sees it.
class CallFilter {
  final String id;
  final String label;
  final OneovaLook look;
  const CallFilter(this.id, this.label, this.look);
}

const List<CallFilter> kCallFilters = [
  CallFilter('original', 'Original', OneovaLook(id: 'call_original', name: 'Original')),
  CallFilter(
    'vivid',
    'Vivid',
    OneovaLook(
      id: 'call_vivid',
      name: 'Vivid',
      primary: LookPrimary(contrast: 1.12),
      color: LookColor(vibrance: 0.45, saturation: 1.15),
    ),
  ),
  CallFilter(
    'warm',
    'Warm',
    OneovaLook(id: 'call_warm', name: 'Warm', color: LookColor(temperature: 14.0, vibrance: 0.15)),
  ),
  CallFilter(
    'cool',
    'Cool',
    OneovaLook(id: 'call_cool', name: 'Cool', color: LookColor(temperature: -14.0, tint: -2.0)),
  ),
  CallFilter(
    'cinematic',
    'Cinematic',
    OneovaLook(
      id: 'call_cinematic',
      name: 'Cinematic',
      primary: LookPrimary(contrast: 1.15, shadows: 0.05),
      color: LookColor(vibrance: 0.25),
    ),
  ),
  CallFilter(
    'portrait',
    'Portrait',
    OneovaLook(
      id: 'call_portrait',
      name: 'Portrait',
      primary: LookPrimary(contrast: 1.05, highlights: 0.1, exposure: 0.05),
      color: LookColor(temperature: 6.0, saturation: 1.05),
    ),
  ),
  CallFilter(
    'golden',
    'Golden',
    OneovaLook(
      id: 'call_golden',
      name: 'Golden',
      primary: LookPrimary(exposure: 0.1),
      color: LookColor(temperature: 16.0, tint: 2.0, vibrance: 0.3),
    ),
  ),
  CallFilter(
    'mono',
    'Mono',
    OneovaLook(
      id: 'call_mono',
      name: 'Mono',
      primary: LookPrimary(contrast: 1.18),
      color: LookColor(saturation: 0.0),
    ),
  ),
  CallFilter(
    'film',
    'Film',
    OneovaLook(
      id: 'call_film',
      name: 'Film',
      primary: LookPrimary(contrast: 1.2, shadows: -0.1, blacks: 0.05),
      color: LookColor(temperature: 6.0, tint: -3.0),
      film: LookFilm(grain: 0.18, fade: 0.08),
    ),
  ),
  CallFilter(
    'neon',
    'Neon',
    OneovaLook(
      id: 'call_neon',
      name: 'Neon',
      primary: LookPrimary(contrast: 1.2),
      color: LookColor(tint: 10.0, vibrance: 0.4),
    ),
  ),
];

/// Separate looks pipeline for the call camera, so a call never fights Live
/// over the same processor.
final callLooksControllerProvider =
    NotifierProvider<LiveLooksController, LiveLooksState>(LiveLooksController.new);

/// Shared music for everyone in the call (`calls/{id}/room/music`).
class CallMusic {
  final String url;
  final String title;
  final String artist;
  final String? coverUrl;
  final int durationMs;
  final bool playing;
  final int positionMs;
  final String byId;
  final String byName;

  /// Local time this state arrived, to work out where playback should be.
  final DateTime receivedAt;

  const CallMusic({
    required this.url,
    required this.title,
    this.artist = '',
    this.coverUrl,
    this.durationMs = 0,
    this.playing = true,
    this.positionMs = 0,
    this.byId = '',
    this.byName = '',
    required this.receivedAt,
  });

  /// Where the song should be right now on every device.
  int get expectedPositionMs =>
      playing ? positionMs + DateTime.now().difference(receivedAt).inMilliseconds : positionMs;

  factory CallMusic.fromMap(Map<String, dynamic> d) => CallMusic(
        url: (d['url'] ?? '') as String,
        title: (d['title'] ?? 'Music') as String,
        artist: (d['artist'] ?? '') as String,
        coverUrl: d['coverUrl'] as String?,
        durationMs: (d['durationMs'] as num?)?.toInt() ?? 0,
        playing: d['playing'] != false,
        positionMs: (d['positionMs'] as num?)?.toInt() ?? 0,
        byId: (d['by'] ?? '') as String,
        byName: (d['byName'] ?? '') as String,
        receivedAt: _anchor(d['updatedAt']),
      );

  /// A fresh change is timed from when it arrived (no clock skew); someone
  /// joining a song already playing is timed from the server write.
  static DateTime _anchor(Object? updatedAt) {
    final now = DateTime.now();
    if (updatedAt is! Timestamp) return now;
    final at = updatedAt.toDate();
    return now.difference(at) > const Duration(seconds: 3) ? at : now;
  }
}

/// A sound someone just played (drives the small "Abdou · Applause" toast).
class CallSoundEvent {
  final String id;
  final CallSound sound;
  final String senderId;
  final String senderName;
  const CallSoundEvent(this.id, this.sound, this.senderId, this.senderName);
}

enum CallLayout { grid, spotlight, split }

class CallRoomState {
  final String? callId;
  final CallMusic? music;
  final double musicVolume;
  final CallSoundEvent? lastSound;
  final String filterId;

  // Personal view settings (this device only).
  final CallLayout layout;
  final String? pinnedUid;
  final bool hideSelfView;
  final bool mirrorSelfView;

  const CallRoomState({
    this.callId,
    this.music,
    this.musicVolume = 50,
    this.lastSound,
    this.filterId = 'original',
    this.layout = CallLayout.grid,
    this.pinnedUid,
    this.hideSelfView = false,
    this.mirrorSelfView = true,
  });

  CallRoomState copyWith({
    String? callId,
    CallMusic? music,
    bool clearMusic = false,
    double? musicVolume,
    CallSoundEvent? lastSound,
    String? filterId,
    CallLayout? layout,
    String? pinnedUid,
    bool clearPin = false,
    bool? hideSelfView,
    bool? mirrorSelfView,
  }) {
    return CallRoomState(
      callId: callId ?? this.callId,
      music: clearMusic ? null : (music ?? this.music),
      musicVolume: musicVolume ?? this.musicVolume,
      lastSound: lastSound ?? this.lastSound,
      filterId: filterId ?? this.filterId,
      layout: layout ?? this.layout,
      pinnedUid: clearPin ? null : (pinnedUid ?? this.pinnedUid),
      hideSelfView: hideSelfView ?? this.hideSelfView,
      mirrorSelfView: mirrorSelfView ?? this.mirrorSelfView,
    );
  }
}

final callRoomControllerProvider =
    NotifierProvider<CallRoomController, CallRoomState>(CallRoomController.new);

/// Everything "fun" layered on a call: sound pad, shared music and camera
/// filters. Sounds and music are synced through Firestore and played on
/// every device locally (flutter_webrtc cannot mix them into the mic track).
class CallRoomController extends Notifier<CallRoomState> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _eventsSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _musicSub;
  final Set<String> _seenEvents = {};
  bool _eventsPrimed = false;
  final List<Player> _sfxPlayers = [];
  int _nextSfx = 0;
  Player? _musicPlayer;
  String? _loadedMusicUrl;
  DateTime _lastSoundSent = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lookTrackId;

  String get _me => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  CallRoomState build() {
    ref.listen<ActiveCallState>(activeCallControllerProvider, (_, next) => _onCall(next));
    ref.listen<CallMediaState>(callMediaServiceProvider, (_, next) => _syncLookTrack(next));
    ref.onDispose(_leave);
    // Created mid-call (first watch): pick up the call already in progress.
    Future.microtask(() => _onCall(ref.read(activeCallControllerProvider)));
    return const CallRoomState();
  }

  DocumentReference<Map<String, dynamic>> _musicRef(String callId) =>
      _db.collection('calls').doc(callId).collection('room').doc('music');

  CollectionReference<Map<String, dynamic>> _events(String callId) =>
      _db.collection('calls').doc(callId).collection('events');

  // ───────────────────────── Call lifecycle ─────────────────────────

  void _onCall(ActiveCallState s) {
    final inCall = s.call != null &&
        (s.phase == CallPhase.connecting || s.phase == CallPhase.connected || s.phase == CallPhase.reconnecting);
    final id = inCall ? s.call!.id : null;
    if (id == state.callId) return;
    _leave();
    if (id == null) {
      state = CallRoomState(
        layout: state.layout,
        hideSelfView: state.hideSelfView,
        mirrorSelfView: state.mirrorSelfView,
        musicVolume: state.musicVolume,
        filterId: state.filterId,
      );
      return;
    }
    state = state.copyWith(callId: id, clearMusic: true, clearPin: true);
    _eventsPrimed = false;
    _eventsSub = _events(id).orderBy('at', descending: true).limit(10).snapshots().listen(
          _onEvents,
          onError: (Object e) => debugPrint('[CallRoom] events: $e'),
        );
    _musicSub = _musicRef(id).snapshots().listen(
          _onMusic,
          onError: (Object e) => debugPrint('[CallRoom] music: $e'),
        );
  }

  void _leave() {
    _eventsSub?.cancel();
    _eventsSub = null;
    _musicSub?.cancel();
    _musicSub = null;
    _seenEvents.clear();
    _loadedMusicUrl = null;
    final music = _musicPlayer;
    _musicPlayer = null;
    if (music != null) unawaited(music.dispose().catchError((_) {}));
    for (final p in _sfxPlayers) {
      unawaited(p.dispose().catchError((_) {}));
    }
    _sfxPlayers.clear();
  }

  // ───────────────────────── Sound pad ─────────────────────────

  /// Plays [sound] for everyone in the call. Returns false when throttled.
  Future<bool> sendSound(CallSound sound) async {
    final callId = state.callId;
    if (callId == null) return false;
    final now = DateTime.now();
    if (now.difference(_lastSoundSent) < const Duration(milliseconds: 1200)) return false;
    _lastSoundSent = now;
    final call = ref.read(activeCallControllerProvider);
    final myName = call.participants[_me]?.name ?? '';
    await _events(callId).add({
      'type': 'sfx',
      'sound': sound.name,
      'senderId': _me,
      'senderName': myName,
      'at': FieldValue.serverTimestamp(),
    });
    return true;
  }

  void _onEvents(QuerySnapshot<Map<String, dynamic>> snap) {
    // Snapshots up to the first one from the server are history from before
    // we joined; don't replay them.
    if (!_eventsPrimed) {
      _seenEvents.addAll(snap.docs.map((d) => d.id));
      if (!snap.metadata.isFromCache) _eventsPrimed = true;
      return;
    }
    for (final change in snap.docChanges) {
      if (change.type != DocumentChangeType.added) continue;
      final id = change.doc.id;
      if (!_seenEvents.add(id)) continue;
      final d = change.doc.data();
      if (d == null || d['type'] != 'sfx') continue;
      final at = d['at'];
      if (at is Timestamp && DateTime.now().difference(at.toDate()) > const Duration(seconds: 30)) continue;
      final sound = CallSound.values.where((s) => s.name == d['sound']).firstOrNull;
      if (sound == null) continue;
      _playSound(sound);
      state = state.copyWith(
        lastSound: CallSoundEvent(id, sound, (d['senderId'] ?? '') as String, (d['senderName'] ?? '') as String),
      );
    }
  }

  void _playSound(CallSound sound) {
    try {
      // Two players so a quick second sound doesn't cut the first one off.
      while (_sfxPlayers.length < 2) {
        _sfxPlayers.add(Player());
      }
      final player = _sfxPlayers[_nextSfx % _sfxPlayers.length];
      _nextSfx++;
      unawaited(player.setVolume(90));
      unawaited(player.open(Media('asset:///${sound.asset}'), play: true));
    } catch (e) {
      debugPrint('[CallRoom] sound failed: $e');
    }
  }

  // ───────────────────────── Shared music ─────────────────────────

  Future<void> playTrack(AudioTrack track) async {
    final callId = state.callId;
    if (callId == null || track.contentUrl.isEmpty) return;
    final call = ref.read(activeCallControllerProvider);
    await _musicRef(callId).set({
      'url': track.contentUrl,
      'title': track.title,
      'artist': track.ownerName,
      'coverUrl': track.coverImageUrl.isEmpty ? null : track.coverImageUrl,
      'durationMs': track.durationMs,
      'trackId': track.id,
      'playing': true,
      'positionMs': 0,
      'by': _me,
      'byName': call.participants[_me]?.name ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> togglePlay() async {
    final callId = state.callId;
    final music = state.music;
    if (callId == null || music == null) return;
    final pos = _musicPlayer?.state.position.inMilliseconds ?? music.expectedPositionMs;
    await _musicRef(callId).set({
      'playing': !music.playing,
      'positionMs': pos,
      'by': _me,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> stopMusic() async {
    final callId = state.callId;
    if (callId == null) return;
    await _musicRef(callId).delete();
  }

  /// Volume on this device only (0–100).
  void setMusicVolume(double v) {
    state = state.copyWith(musicVolume: v);
    unawaited(_musicPlayer?.setVolume(v).catchError((_) {}));
  }

  Future<void> _onMusic(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final d = doc.data();
    if (d == null || (d['url'] ?? '') == '') {
      state = state.copyWith(clearMusic: true);
      _loadedMusicUrl = null;
      await _musicPlayer?.stop();
      return;
    }
    final music = CallMusic.fromMap(d);
    final prev = state.music;
    // Our own write comes back once more when the server confirms it.
    if (prev != null &&
        prev.url == music.url &&
        prev.playing == music.playing &&
        prev.positionMs == music.positionMs &&
        _musicPlayer != null) {
      return;
    }
    state = state.copyWith(music: music);
    try {
      final player = _musicPlayer ??= Player();
      await player.setVolume(state.musicVolume);
      if (_loadedMusicUrl != music.url) {
        _loadedMusicUrl = music.url;
        await player.open(Media(music.url), play: false);
        // Seeking before the stream is loaded is ignored.
        await player.stream.duration
            .firstWhere((d) => d > Duration.zero)
            .timeout(const Duration(seconds: 12), onTimeout: () => Duration.zero);
      }
      await player.seek(Duration(milliseconds: music.expectedPositionMs));
      if (music.playing) {
        await player.play();
      } else {
        await player.pause();
      }
    } catch (e) {
      debugPrint('[CallRoom] music playback failed: $e');
    }
  }

  // ───────────────────────── Filters ─────────────────────────

  Future<void> setFilter(String id) async {
    final filter = kCallFilters.firstWhere((f) => f.id == id, orElse: () => kCallFilters.first);
    state = state.copyWith(filterId: filter.id);
    await _syncLookTrack(ref.read(callMediaServiceProvider));
    await ref.read(callLooksControllerProvider.notifier).applyLook(
          filter.look,
          crossFade: const Duration(milliseconds: 250),
        );
  }

  /// Keeps the GPU processor on the current camera track (it changes when an
  /// audio call turns its camera on for the first time).
  Future<void> _syncLookTrack(CallMediaState media) async {
    final looks = ref.read(callLooksControllerProvider.notifier);
    final tracks = media.localStream?.getVideoTracks() ?? const [];
    final trackId = tracks.isEmpty ? null : tracks.first.id;
    final wanted = state.filterId != 'original' ? trackId : null;
    if (wanted == _lookTrackId) return;
    _lookTrackId = wanted;
    if (wanted == null) {
      await looks.detachCameraTrack();
      return;
    }
    if (kIsWeb) return;
    await looks.attachCameraTrack(wanted);
  }

  // ───────────────────────── Layout ─────────────────────────

  void setLayout(CallLayout layout) => state = state.copyWith(layout: layout);

  void pin(String? uid) =>
      state = uid == null || uid == state.pinnedUid ? state.copyWith(clearPin: true) : state.copyWith(pinnedUid: uid);

  void setHideSelfView(bool v) => state = state.copyWith(hideSelfView: v);

  void setMirrorSelfView(bool v) => state = state.copyWith(mirrorSelfView: v);
}
