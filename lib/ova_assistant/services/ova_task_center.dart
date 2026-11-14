import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ova_abilities.dart';
import 'ova_device_abilities.dart';
import 'ova_device_control.dart';
import 'ova_native_service.dart';

enum OvaTaskStatus { running, done, failed, cancelled }

enum OvaStepStatus { running, done, failed, waiting }

class OvaTaskStep {
  final String label;
  final IconData icon;
  final OvaStepStatus status;
  const OvaTaskStep(this.label, this.icon, this.status);
  OvaTaskStep copyWith({String? label, OvaStepStatus? status}) => OvaTaskStep(label ?? this.label, icon, status ?? this.status);
}

class OvaTask {
  final String id;
  final String title;

  /// 'ova' for assistant turns, 'ai_lab' for AI Lab agent jobs.
  final String source;
  final List<OvaTaskStep> steps;
  final OvaTaskStatus status;
  final String? summary;
  final DateTime startedAt;
  final DateTime? finishedAt;

  const OvaTask({
    required this.id,
    required this.title,
    required this.source,
    this.steps = const [],
    this.status = OvaTaskStatus.running,
    this.summary,
    required this.startedAt,
    this.finishedAt,
  });

  bool get running => status == OvaTaskStatus.running;

  OvaTask copyWith({List<OvaTaskStep>? steps, OvaTaskStatus? status, String? summary, DateTime? finishedAt}) => OvaTask(
        id: id,
        title: title,
        source: source,
        steps: steps ?? this.steps,
        status: status ?? this.status,
        summary: summary ?? this.summary,
        startedAt: startedAt,
        finishedAt: finishedAt ?? this.finishedAt,
      );
}

class OvaTaskState {
  final List<OvaTask> tasks;

  /// The task that just finished; the dock flashes it for a few seconds.
  final OvaTask? justFinished;
  const OvaTaskState({this.tasks = const [], this.justFinished});

  OvaTask? get active {
    for (final t in tasks) {
      if (t.running) return t;
    }
    return null;
  }

  /// Plain spoken words for "what's happening?": running tasks with the step
  /// they're on, then what finished in the last 15 minutes. No AI call needed.
  String progressReport({String? exceptId, int max = 3}) {
    final now = DateTime.now();
    final running = [for (final t in tasks) if (t.running && t.id != exceptId) t];
    final recent = [
      for (final t in tasks)
        if (!t.running && t.id != exceptId && t.finishedAt != null && now.difference(t.finishedAt!).inMinutes < 15) t,
    ];
    if (running.isEmpty && recent.isEmpty) return 'Nothing is running in the background right now.';
    final out = <String>[];
    for (final t in running.take(max)) {
      final step = t.steps.lastWhere((s) => s.status == OvaStepStatus.running, orElse: () => t.steps.isEmpty ? const OvaTaskStep('starting', Icons.circle, OvaStepStatus.running) : t.steps.last);
      final done = t.steps.where((s) => s.status == OvaStepStatus.done).length;
      final mins = now.difference(t.startedAt).inMinutes;
      out.add('${_short(t.title)} is ${_clean(step.label)}${t.steps.length > 1 ? ', step ${done + 1} of ${t.steps.length}' : ''}${mins >= 1 ? ', running $mins minute${mins == 1 ? '' : 's'}' : ''}.');
    }
    if (running.length > max) out.add('And ${running.length - max} more running.');
    for (final t in recent.take(2)) {
      final ok = t.status == OvaTaskStatus.done;
      out.add('${_short(t.title)} ${ok ? 'finished' : 'did not finish'}${(t.summary?.isNotEmpty ?? false) ? ': ${_short(t.summary!, 90)}' : '.'}');
    }
    return out.join(' ');
  }

  /// Compact lines for the AI's context each turn.
  String progressContext({String? exceptId}) {
    final lines = [
      for (final t in tasks.take(6))
        if (t.id != exceptId)
          '- ${_short(t.title)} [${t.status.name}${t.running && t.steps.isNotEmpty ? ': ${_clean(t.steps.last.label)}' : ''}]',
    ];
    return lines.isEmpty ? 'none' : lines.join('\n');
  }

  static String _clean(String label) {
    final l = label.replaceFirst(RegExp(r'^[A-Za-z ]+ · '), '').trim();
    return l.isEmpty ? 'working' : l[0].toLowerCase() + l.substring(1);
  }

  static String _short(String s, [int n = 60]) => s.length > n ? '${s.substring(0, n - 1)}…' : s;
}

final ovaTaskCenterProvider = NotifierProvider<OvaTaskCenter, OvaTaskState>(OvaTaskCenter.new);

/// Live progress for everything Ova (and AI Lab agents) are doing. Survives
/// closing the sheet and changing screens; alerts when a task finishes.
class OvaTaskCenter extends Notifier<OvaTaskState> {
  Timer? _flashTimer;
  StreamSubscription? _authSub;
  StreamSubscription? _labSub;
  final Map<String, String> _labTasks = {}; // interaction doc id -> task id

  @override
  OvaTaskState build() {
    if (Firebase.apps.isNotEmpty) {
      try {
        _authSub = FirebaseAuth.instance.authStateChanges().listen(_watchAiLab);
      } catch (_) {}
    }
    ref.onDispose(() {
      _flashTimer?.cancel();
      _authSub?.cancel();
      _labSub?.cancel();
    });
    return const OvaTaskState();
  }

  String start(String title, {String source = 'ova'}) {
    final id = '${DateTime.now().microsecondsSinceEpoch}';
    final t = OvaTask(id: id, title: title, source: source, startedAt: DateTime.now());
    state = OvaTaskState(tasks: [t, ...state.tasks].take(12).toList(), justFinished: state.justFinished);
    return id;
  }

  int addStep(String taskId, String label, IconData icon, {OvaStepStatus status = OvaStepStatus.running}) {
    var index = -1;
    _update(taskId, (t) {
      index = t.steps.length;
      return t.copyWith(steps: [...t.steps, OvaTaskStep(label, icon, status)]);
    });
    _mirrorToScreen(label);
    return index;
  }

  void updateStep(String taskId, int index, OvaStepStatus status, {String? label}) {
    _update(taskId, (t) {
      if (index < 0 || index >= t.steps.length) return t;
      final steps = [...t.steps];
      steps[index] = steps[index].copyWith(status: status, label: label);
      return t.copyWith(steps: steps);
    });
  }

  void finish(String taskId, {required bool ok, String? summary, bool cancelled = false}) {
    OvaTask? done;
    _update(taskId, (t) {
      done = t.copyWith(
        status: cancelled ? OvaTaskStatus.cancelled : (ok ? OvaTaskStatus.done : OvaTaskStatus.failed),
        summary: summary,
        finishedAt: DateTime.now(),
      );
      return done!;
    });
    final d = done;
    if (d == null || cancelled) return;
    state = OvaTaskState(tasks: state.tasks, justFinished: d);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(seconds: 6), () => state = OvaTaskState(tasks: state.tasks));
    _alert(d);
  }

  void _update(String id, OvaTask Function(OvaTask) f) {
    state = OvaTaskState(
      tasks: [for (final t in state.tasks) t.id == id ? f(t) : t],
      justFinished: state.justFinished,
    );
  }

  /// When Ova is working inside another app, show the step there too.
  void _mirrorToScreen(String label) {
    final life = WidgetsBinding.instance.lifecycleState;
    if (life == AppLifecycleState.resumed) return;
    if (!ref.read(ovaAbilitiesProvider).screenControl) return;
    ref.read(ovaDeviceControlProvider).showBubble('Ova · $label').catchError((_) {});
  }

  Future<void> _alert(OvaTask t) async {
    if (!ref.read(ovaAbilitiesProvider).finishAlerts) return;
    final life = WidgetsBinding.instance.lifecycleState;
    if (life == AppLifecycleState.resumed) return; // the dock shows it in-app
    final ok = t.status == OvaTaskStatus.done;
    final body = (t.summary?.trim().isNotEmpty ?? false) ? t.summary!.trim() : t.title;
    if (ref.read(ovaAbilitiesProvider).screenControl) {
      ref.read(ovaDeviceControlProvider).showBubble('${ok ? '✓' : '✕'} $body').catchError((_) {});
    }
    await OvaDeviceAbilities(OvaNativeService()).notifyNow(null, ok ? 'Ova finished' : 'Ova could not finish', body);
  }

  // ── AI Lab agent jobs (users/{uid}/ai_interactions) ─────────────────────

  void _watchAiLab(User? user) {
    _labSub?.cancel();
    _labTasks.clear();
    if (user == null || user.isAnonymous) return;
    _labSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('ai_interactions')
        .orderBy('timestamp', descending: true)
        .limit(5)
        .snapshots()
        .listen((snap) {
      for (final ch in snap.docChanges) {
        final d = ch.doc.data();
        if (d == null || d['kind'] == 'ova_assistant') continue;
        final status = d['status'];
        final query = (d['query'] ?? 'AI task').toString();
        final existing = _labTasks[ch.doc.id];
        if (status == 'processing' && existing == null && !ch.doc.metadata.isFromCache) {
          final id = start(query.length > 60 ? '${query.substring(0, 60)}…' : query, source: 'ai_lab');
          addStep(id, 'AI Lab agent working', Icons.psychology_rounded);
          _labTasks[ch.doc.id] = id;
        } else if (existing != null && (status == 'completed' || status == 'error')) {
          updateStep(existing, 0, status == 'completed' ? OvaStepStatus.done : OvaStepStatus.failed);
          final resp = (d['response'] ?? '').toString();
          finish(existing, ok: status == 'completed', summary: resp.length > 140 ? '${resp.substring(0, 140)}…' : resp);
          _labTasks.remove(ch.doc.id);
        }
      }
    }, onError: (_) {});
  }
}
