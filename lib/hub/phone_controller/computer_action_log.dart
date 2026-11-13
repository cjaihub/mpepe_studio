import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Who caused a computer action.
enum ActionSource {
  touch('Touch screen'),
  trackpad('Trackpad'),
  media('Media deck'),
  voice('Voice'),
  ai('Ova AI'),
  system('System');

  const ActionSource(this.label);
  final String label;
}

/// One step of computer use: what was done, by whom, where, and the result.
/// Steps are the unit of the training dataset ("observation → action").
@immutable
class ComputerActionStep {
  const ComputerActionStep({
    required this.id,
    required this.at,
    required this.source,
    required this.action,
    this.params = const {},
    this.app,
    this.result = 'ok',
    this.instruction,
    this.count = 1,
  });

  final String id;
  final DateTime at;
  final ActionSource source;

  /// Canonical action name: click, double_click, right_click, move, drag,
  /// scroll, type_text, key_combo, press_key, media_key, volume_set, wake,
  /// unlock, connect, disconnect, user_said, ai_said.
  final String action;
  final Map<String, dynamic> params;

  /// Frontmost app on the computer when the step ran, if known.
  final String? app;
  final String result;

  /// The latest spoken / typed goal the step served (for training).
  final String? instruction;

  /// Coalesced events (pointer moves and scroll ticks are merged).
  final int count;

  ComputerActionStep copyWith({Map<String, dynamic>? params, int? count, String? result}) {
    return ComputerActionStep(
      id: id,
      at: at,
      source: source,
      action: action,
      params: params ?? this.params,
      app: app,
      result: result ?? this.result,
      instruction: instruction,
      count: count ?? this.count,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        't': at.toUtc().toIso8601String(),
        'source': source.name,
        'action': action,
        'params': params,
        if (app != null) 'app': app,
        'result': result,
        if (instruction != null) 'instruction': instruction,
        if (count > 1) 'count': count,
      };

  static ComputerActionStep fromJson(Map<String, dynamic> j) => ComputerActionStep(
        id: j['id'] as String? ?? '',
        at: DateTime.tryParse(j['t'] as String? ?? '')?.toLocal() ?? DateTime.now(),
        source: ActionSource.values.firstWhere(
          (s) => s.name == j['source'],
          orElse: () => ActionSource.system,
        ),
        action: j['action'] as String? ?? '',
        params: Map<String, dynamic>.from(j['params'] as Map? ?? const {}),
        app: j['app'] as String?,
        result: j['result'] as String? ?? 'ok',
        instruction: j['instruction'] as String?,
        count: (j['count'] as num?)?.toInt() ?? 1,
      );

  /// One-line human summary for the logs sidebar.
  String get summary {
    String pct(dynamic v) => v is num ? '${(v * 100).round()}%' : '?';
    switch (action) {
      case 'click':
      case 'double_click':
      case 'right_click':
        final where = params.containsKey('x') ? ' at ${pct(params['x'])}, ${pct(params['y'])}' : '';
        final name = action == 'click'
            ? 'Click'
            : action == 'double_click'
                ? 'Double-click'
                : 'Right-click';
        return '$name$where';
      case 'move':
        final dx = (params['dx'] as num?)?.round() ?? 0;
        final dy = (params['dy'] as num?)?.round() ?? 0;
        return params.containsKey('x')
            ? 'Pointer to ${pct(params['x'])}, ${pct(params['y'])}'
            : 'Moved pointer ($dx, $dy)';
      case 'drag':
        return 'Drag';
      case 'scroll':
        final dy = (params['dy'] as num?)?.round() ?? 0;
        return dy == 0 ? 'Scrolled sideways' : (dy > 0 ? 'Scrolled up' : 'Scrolled down');
      case 'type_text':
        return params['redacted'] == true
            ? 'Typed hidden text'
            : 'Typed “${_clip(params['text'])}”';
      case 'key_combo':
      case 'press_key':
        return 'Key ${params['combo'] ?? params['key']}';
      case 'media_key':
        return 'Media ${params['key']}';
      case 'volume_set':
        return 'Volume ${params['level']}%';
      case 'wake':
        return 'Woke the screen';
      case 'unlock':
        return 'Unlocked the computer';
      case 'connect':
        return 'Connected (${params['mode'] ?? 'link'})';
      case 'disconnect':
        return 'Disconnected';
      case 'user_said':
        return 'You: ${_clip(params['text'], 60)}';
      case 'ai_said':
        return 'Ova: ${_clip(params['text'], 60)}';
      default:
        return action;
    }
  }

  IconData get icon => switch (action) {
        'click' || 'double_click' => Icons.ads_click_rounded,
        'right_click' => Icons.menu_open_rounded,
        'move' => Icons.near_me_outlined,
        'drag' => Icons.open_with_rounded,
        'scroll' => Icons.swap_vert_rounded,
        'type_text' => Icons.keyboard_rounded,
        'key_combo' || 'press_key' => Icons.keyboard_command_key_rounded,
        'media_key' => Icons.play_circle_outline_rounded,
        'volume_set' => Icons.volume_up_rounded,
        'wake' => Icons.wb_sunny_outlined,
        'unlock' => Icons.lock_open_rounded,
        'connect' => Icons.link_rounded,
        'disconnect' => Icons.link_off_rounded,
        'user_said' => Icons.record_voice_over_outlined,
        'ai_said' => Icons.auto_awesome_rounded,
        _ => Icons.bolt_rounded,
      };

  static String _clip(dynamic v, [int n = 40]) {
    final s = (v ?? '').toString().replaceAll('\n', ' ');
    return s.length > n ? '${s.substring(0, n)}…' : s;
  }
}

@immutable
class ComputerActionLogState {
  const ComputerActionLogState({
    this.steps = const [],
    this.sessionId,
    this.deviceId,
    this.syncing = false,
    this.lastSyncedAt,
  });

  /// Newest first, capped in memory.
  final List<ComputerActionStep> steps;
  final String? sessionId;
  final String? deviceId;
  final bool syncing;
  final DateTime? lastSyncedAt;

  ComputerActionLogState copyWith({
    List<ComputerActionStep>? steps,
    String? sessionId,
    String? deviceId,
    bool? syncing,
    DateTime? lastSyncedAt,
  }) =>
      ComputerActionLogState(
        steps: steps ?? this.steps,
        sessionId: sessionId ?? this.sessionId,
        deviceId: deviceId ?? this.deviceId,
        syncing: syncing ?? this.syncing,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      );
}

/// Records every computer action from the phone (touch, trackpad, media,
/// voice and Ova AI), shows them in the logs sidebar, and stores them
/// end-to-end encrypted (AES-256-GCM, key only on this phone) in
/// `users/{uid}/computer_log_chunks` so they can be exported as a
/// computer-use training dataset. Secrets are never recorded.
class ComputerActionLog extends Notifier<ComputerActionLogState> {
  static const int _memoryCap = 600;
  static const Duration _coalesceWindow = Duration(milliseconds: 700);
  static const Duration _flushEvery = Duration(seconds: 8);
  static const _secretKeys = {'password', 'passkey', 'secret', 'token', 'pin'};

  final List<ComputerActionStep> _pending = [];
  Timer? _flushTimer;
  String? _instruction;
  String? _app;
  int _chunk = 0;
  final _rand = Random();

  @override
  ComputerActionLogState build() {
    ref.onDispose(() {
      _flushTimer?.cancel();
      unawaited(flush());
    });
    return const ComputerActionLogState();
  }

  /// Starts a new log session for [deviceId] (one controller visit).
  void beginSession(String deviceId) {
    if (state.deviceId == deviceId && state.sessionId != null) return;
    final id = '${DateTime.now().millisecondsSinceEpoch}_${_rand.nextInt(1 << 20)}';
    _chunk = 0;
    state = state.copyWith(sessionId: id, deviceId: deviceId);
  }

  void setFrontApp(String? app) => _app = app;

  /// The current goal, used to label following steps for training.
  void setInstruction(String? text) {
    final t = text?.trim();
    if (t == null || t.isEmpty) return;
    _instruction = t.length > 280 ? t.substring(0, 280) : t;
  }

  void record(
    ActionSource source,
    String action, {
    Map<String, dynamic> params = const {},
    String result = 'ok',
    bool secret = false,
  }) {
    final clean = <String, dynamic>{};
    params.forEach((k, v) {
      if (_secretKeys.contains(k)) return;
      clean[k] = v is double ? (v * 1000).roundToDouble() / 1000 : v;
    });
    if (secret && clean.containsKey('text')) {
      clean
        ..remove('text')
        ..['redacted'] = true;
    }

    final now = DateTime.now();
    final steps = state.steps;
    // Merge high-rate pointer/scroll events into one step.
    if ((action == 'move' || action == 'scroll') &&
        steps.isNotEmpty &&
        steps.first.action == action &&
        steps.first.source == source &&
        !clean.containsKey('x') &&
        now.difference(steps.first.at) < _coalesceWindow) {
      final head = steps.first;
      final merged = Map<String, dynamic>.from(head.params);
      for (final k in ['dx', 'dy']) {
        final a = (merged[k] as num?)?.toDouble() ?? 0;
        final b = (clean[k] as num?)?.toDouble() ?? 0;
        merged[k] = ((a + b) * 10).roundToDouble() / 10;
      }
      final updated = head.copyWith(params: merged, count: head.count + 1);
      state = state.copyWith(steps: [updated, ...steps.skip(1)]);
      if (_pending.isNotEmpty && _pending.last.id == head.id) {
        _pending[_pending.length - 1] = updated;
      }
      return;
    }

    if (action == 'user_said') setInstruction(clean['text'] as String?);
    final step = ComputerActionStep(
      id: '${now.microsecondsSinceEpoch}',
      at: now,
      source: source,
      action: action,
      params: clean,
      app: _app,
      result: result,
      instruction: _instruction,
    );
    final next = [step, ...steps];
    state = state.copyWith(
      steps: next.length > _memoryCap ? next.sublist(0, _memoryCap) : next,
    );
    _pending.add(step);
    _flushTimer ??= Timer(_flushEvery, () {
      _flushTimer = null;
      unawaited(flush());
    });
  }

  void clearView() => state = state.copyWith(steps: const []);

  // ─── Encrypted storage ────────────────────────────────────────────────────

  static final _aes = AesGcm.with256bits();
  static const _storage = FlutterSecureStorage();
  SecretKey? _key;

  Future<SecretKey> _keyFor(String uid) async {
    final cached = _key;
    if (cached != null) return cached;
    final name = 'oneova_computer_log_key_$uid';
    String? b64;
    try {
      b64 = await _storage.read(key: name);
    } catch (_) {}
    if (b64 == null) {
      final k = await _aes.newSecretKey();
      b64 = base64Encode(await k.extractBytes());
      try {
        await _storage.write(key: name, value: b64);
      } catch (_) {}
      _key = k;
      return k;
    }
    return _key = SecretKey(base64Decode(b64));
  }

  /// Uploads pending steps as one encrypted chunk (batched to keep Firestore
  /// writes low).
  Future<void> flush() async {
    if (_pending.isEmpty) return;
    String? uid;
    try {
      uid = FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return; // Firebase not initialised (tests / early start).
    }
    final session = state.sessionId;
    if (uid == null || session == null) return;
    final batch = List<ComputerActionStep>.from(_pending);
    _pending.clear();
    try {
      state = state.copyWith(syncing: true);
      final key = await _keyFor(uid);
      final plain = utf8.encode(jsonEncode(batch.map((s) => s.toJson()).toList()));
      final box = await _aes.encrypt(plain, secretKey: key);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('computer_log_chunks')
          .doc('${session}_${_chunk++}')
          .set({
        'session_id': session,
        'device_id': state.deviceId,
        'started_at': Timestamp.fromDate(batch.first.at),
        'count': batch.length,
        'v': 1,
        'alg': 'AES-256-GCM',
        'nonce': base64Encode(box.nonce),
        'mac': base64Encode(box.mac.bytes),
        'cipher': base64Encode(box.cipherText),
        'created_at': FieldValue.serverTimestamp(),
      });
      state = state.copyWith(syncing: false, lastSyncedAt: DateTime.now());
    } catch (e) {
      debugPrint('[ComputerActionLog] flush notice: $e');
      _pending.insertAll(0, batch); // retry with the next flush
      state = state.copyWith(syncing: false);
    }
  }

  /// Loads and decrypts recent history (newest first) for the logs view.
  Future<List<ComputerActionStep>> loadHistory({int chunks = 40}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const [];
    final key = await _keyFor(uid);
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('computer_log_chunks')
        .orderBy('started_at', descending: true)
        .limit(chunks)
        .get();
    final out = <ComputerActionStep>[];
    for (final doc in snap.docs) {
      try {
        final d = doc.data();
        final box = SecretBox(
          base64Decode(d['cipher'] as String),
          nonce: base64Decode(d['nonce'] as String),
          mac: Mac(base64Decode(d['mac'] as String)),
        );
        final clear = await _aes.decrypt(box, secretKey: key);
        final list = jsonDecode(utf8.decode(clear)) as List;
        out.addAll(list.map((e) => ComputerActionStep.fromJson(Map<String, dynamic>.from(e as Map))));
      } catch (_) {
        // Chunk from another phone's key, or corrupted: skip.
      }
    }
    out.sort((a, b) => b.at.compareTo(a.at));
    return out;
  }

  /// Exports steps as a JSONL computer-use dataset (one episode per line:
  /// goal + ordered actions) and opens the share sheet.
  Future<void> exportDataset(List<ComputerActionStep> steps) async {
    final bySession = <String, List<ComputerActionStep>>{};
    final ordered = [...steps]..sort((a, b) => a.at.compareTo(b.at));
    for (final s in ordered) {
      final goal = s.instruction ?? '(no instruction)';
      bySession.putIfAbsent(goal, () => []).add(s);
    }
    final lines = <String>[];
    bySession.forEach((goal, list) {
      lines.add(jsonEncode({
        'schema': 'oneova.computer_use.v1',
        'goal': goal,
        'steps': [
          for (var i = 0; i < list.length; i++) {'i': i, ...list[i].toJson()},
        ],
      }));
    });
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/oneova_computer_use_${DateTime.now().millisecondsSinceEpoch}.jsonl');
    await file.writeAsString(lines.join('\n'));
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/jsonl')],
        subject: 'Oneova computer-use dataset',
      ),
    );
  }
}

final computerActionLogProvider =
    NotifierProvider<ComputerActionLog, ComputerActionLogState>(ComputerActionLog.new);
