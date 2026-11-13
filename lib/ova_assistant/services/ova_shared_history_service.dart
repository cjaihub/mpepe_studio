import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Workspaces available in the Ova Main Interface drawer & composer.
enum OvaWorkspaceId {
  personal,
  work,
  research;

  String get label => switch (this) {
        OvaWorkspaceId.personal => 'Personal',
        OvaWorkspaceId.work => 'Work projects',
        OvaWorkspaceId.research => 'Research',
      };

  String get shortLabel => switch (this) {
        OvaWorkspaceId.personal => 'Personal',
        OvaWorkspaceId.work => 'Work',
        OvaWorkspaceId.research => 'Research',
      };

  String get subtitle => switch (this) {
        OvaWorkspaceId.personal => 'Daily tasks, captions & personal planning',
        OvaWorkspaceId.work => 'Studio productions, channels & team workflows',
        OvaWorkspaceId.research => 'Script breakdowns, trends & deep analysis',
      };

  IconData get icon => switch (this) {
        OvaWorkspaceId.personal => Icons.work_outline_rounded,
        OvaWorkspaceId.work => Icons.groups_outlined,
        OvaWorkspaceId.research => Icons.science_outlined,
      };

  static OvaWorkspaceId fromString(String? raw) => switch (raw) {
        'work' => OvaWorkspaceId.work,
        'research' => OvaWorkspaceId.research,
        _ => OvaWorkspaceId.personal,
      };
}

/// Identifies which Ova surface produced an interaction, while sharing the
/// unified History & Activity store across both interfaces.
enum OvaOriginSource {
  main,
  overlay,
  voice;

  String get firestoreKind => switch (this) {
        OvaOriginSource.main => 'ova_main',
        OvaOriginSource.overlay => 'ova_assistant',
        OvaOriginSource.voice => 'ova_voice',
      };

  String get badgeLabel => switch (this) {
        OvaOriginSource.main => 'Main',
        OvaOriginSource.overlay => 'Overlay',
        OvaOriginSource.voice => 'Voice',
      };

  IconData get icon => switch (this) {
        OvaOriginSource.main => Icons.auto_awesome_rounded,
        OvaOriginSource.overlay => Icons.layers_outlined,
        OvaOriginSource.voice => Icons.graphic_eq_rounded,
      };

  static OvaOriginSource fromKind(String? raw) => switch (raw) {
        'ova_assistant' || 'ova_overlay' || 'device_control' => OvaOriginSource.overlay,
        'ova_voice' => OvaOriginSource.voice,
        _ => OvaOriginSource.main,
      };
}

/// A single user->Ova turn synced across Ova Main Interface and Overlay Assistant.
class OvaSharedTurn {
  final String id;
  final String threadId;
  final String? threadTitle;
  final String query;
  final String response;
  final OvaOriginSource source;
  final OvaWorkspaceId workspace;
  final DateTime timestamp;
  final String status;

  const OvaSharedTurn({
    required this.id,
    required this.threadId,
    this.threadTitle,
    required this.query,
    required this.response,
    required this.source,
    this.workspace = OvaWorkspaceId.personal,
    required this.timestamp,
    this.status = 'completed',
  });

  factory OvaSharedTurn.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final query = (d['query'] ?? '').toString().trim();
    final response = (d['response'] ?? '').toString().trim();
    final ts = (d['timestamp'] as Timestamp?)?.toDate() ??
        (d['completedAt'] as Timestamp?)?.toDate() ??
        DateTime.now();
    return OvaSharedTurn(
      id: doc.id,
      threadId: (d['threadId'] as String?)?.trim().isNotEmpty == true
          ? (d['threadId'] as String).trim()
          : doc.id,
      threadTitle: d['threadTitle'] as String?,
      query: query,
      response: response,
      source: OvaOriginSource.fromKind(d['kind'] as String?),
      workspace: OvaWorkspaceId.fromString(d['workspace'] as String?),
      timestamp: ts,
      status: (d['status'] ?? 'completed').toString(),
    );
  }
}

/// Grouped conversation thread built from shared turns.
class OvaSharedThread {
  final String id;
  final String title;
  final String preview;
  final OvaOriginSource source;
  final OvaWorkspaceId workspace;
  final List<OvaSharedTurn> turns;
  final DateTime updatedAt;

  const OvaSharedThread({
    required this.id,
    required this.title,
    required this.preview,
    required this.source,
    required this.workspace,
    required this.turns,
    required this.updatedAt,
  });
}

/// Saved item in the Ova Library (prompts, script breakdowns, agent outputs).
class OvaLibraryEntry {
  final String id;
  final String title;
  final String content;
  final String category; // 'Prompt', 'Script', 'Output', 'Agent'
  final OvaWorkspaceId workspace;
  final DateTime createdAt;

  const OvaLibraryEntry({
    required this.id,
    required this.title,
    required this.content,
    this.category = 'Output',
    this.workspace = OvaWorkspaceId.personal,
    required this.createdAt,
  });

  factory OvaLibraryEntry.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return OvaLibraryEntry(
      id: doc.id,
      title: (d['title'] ?? 'Saved item').toString(),
      content: (d['content'] ?? '').toString(),
      category: (d['category'] ?? 'Output').toString(),
      workspace: OvaWorkspaceId.fromString(d['workspace'] as String?),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class OvaSharedHistoryState {
  final List<OvaSharedTurn> turns;
  final List<OvaLibraryEntry> library;
  final bool loading;

  const OvaSharedHistoryState({
    this.turns = const [],
    this.library = const [],
    this.loading = false,
  });

  /// Groups turns by [threadId] in reverse chronological order.
  List<OvaSharedThread> get threads {
    final grouped = <String, List<OvaSharedTurn>>{};
    for (final t in turns) {
      if (t.query.isEmpty && t.response.isEmpty) continue;
      grouped.putIfAbsent(t.threadId, () => []).add(t);
    }

    final out = <OvaSharedThread>[];
    grouped.forEach((threadId, list) {
      list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      final first = list.first;
      final last = list.last;
      final rawTitle = (first.threadTitle?.trim().isNotEmpty == true)
          ? first.threadTitle!.trim()
          : first.query;
      final title = rawTitle.length > 56 ? '${rawTitle.substring(0, 56)}…' : rawTitle;
      final rawPreview = last.response.isNotEmpty ? last.response : last.query;
      final cleanPreview = rawPreview.replaceAll(RegExp(r'[#*_`\n]+'), ' ').trim();
      final preview = cleanPreview.length > 90 ? '${cleanPreview.substring(0, 90)}…' : cleanPreview;
      out.add(
        OvaSharedThread(
          id: threadId,
          title: title.isEmpty ? 'Ova conversation' : title,
          preview: preview,
          source: last.source,
          workspace: last.workspace,
          turns: list,
          updatedAt: last.timestamp,
        ),
      );
    });
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  List<OvaSharedThread> threadsForWorkspace(OvaWorkspaceId ws) =>
      threads.where((t) => t.workspace == ws).toList();

  OvaSharedHistoryState copyWith({
    List<OvaSharedTurn>? turns,
    List<OvaLibraryEntry>? library,
    bool? loading,
  }) {
    return OvaSharedHistoryState(
      turns: turns ?? this.turns,
      library: library ?? this.library,
      loading: loading ?? this.loading,
    );
  }
}

final ovaSharedHistoryProvider =
    NotifierProvider<OvaSharedHistoryNotifier, OvaSharedHistoryState>(
  OvaSharedHistoryNotifier.new,
);

/// Unified History, Activity & Library Synchronization Layer.
///
/// Bridges:
/// 1. Ova Main Interface (`/hub/ai`)
/// 2. Ova Overlay Assistant (`OvaAssistantSheet` & `OvaFloatingDock`)
/// 3. Ova Live Voice Mode (both Main & Overlay)
class OvaSharedHistoryNotifier extends Notifier<OvaSharedHistoryState> {
  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _turnsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _agentSessionsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _librarySub;

  final List<OvaSharedTurn> _localTurns = [];
  List<OvaSharedTurn> _remoteTurns = [];
  List<OvaSharedTurn> _agentSessionTurns = [];
  final List<OvaLibraryEntry> _localLibrary = [];
  List<OvaLibraryEntry> _remoteLibrary = [];
  final Set<String> _deletedIds = {};

  bool get _firebaseReady => Firebase.apps.isNotEmpty;

  @override
  OvaSharedHistoryState build() {
    if (_firebaseReady) {
      try {
        _authSub = FirebaseAuth.instance.authStateChanges().listen(_bindUserStreams);
        _bindUserStreams(FirebaseAuth.instance.currentUser);
      } catch (e) {
        debugPrint('[OvaSharedHistory] Auth listener skipped: $e');
      }
    }
    ref.onDispose(() {
      _authSub?.cancel();
      _turnsSub?.cancel();
      _agentSessionsSub?.cancel();
      _librarySub?.cancel();
    });
    return const OvaSharedHistoryState();
  }

  void _bindUserStreams(User? user) {
    _turnsSub?.cancel();
    _agentSessionsSub?.cancel();
    _librarySub?.cancel();
    if (!_firebaseReady || user == null || user.isAnonymous) {
      _remoteTurns = [];
      _agentSessionTurns = [];
      _remoteLibrary = [];
      _rebuildState();
      return;
    }

    final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);
    _turnsSub = userDoc
        .collection('ai_interactions')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .listen(
      (snap) {
        _remoteTurns = snap.docs
            .map(OvaSharedTurn.fromFirestore)
            .where((t) => !_deletedIds.contains(t.id) && !_deletedIds.contains(t.threadId))
            .toList();
        _rebuildState();
      },
      onError: (Object e) => debugPrint('[OvaSharedHistory] turns stream error: $e'),
    );

    _agentSessionsSub = userDoc
        .collection('agent_sessions')
        .orderBy('updatedAtMs', descending: true)
        .limit(40)
        .snapshots()
        .listen(
      (snap) {
        _agentSessionTurns = snap.docs
            .where((doc) => !_deletedIds.contains(doc.id))
            .map((doc) {
              final d = doc.data();
              final title = (d['title'] ?? 'Agent Session').toString().trim();
              final preview = (d['lastPreview'] ?? '').toString().trim();
              final updMs = d['updatedAtMs'] is num
                  ? (d['updatedAtMs'] as num).toInt()
                  : DateTime.now().millisecondsSinceEpoch;
              return OvaSharedTurn(
                id: 'agent_${doc.id}',
                threadId: doc.id,
                threadTitle: title,
                query: title,
                response: preview,
                source: OvaOriginSource.main,
                workspace: OvaWorkspaceId.personal,
                timestamp: DateTime.fromMillisecondsSinceEpoch(updMs),
                status: (d['status'] ?? 'completed').toString(),
              );
            })
            .where((t) => t.query.isNotEmpty || t.response.isNotEmpty)
            .toList();
        _rebuildState();
      },
      onError: (Object e) => debugPrint('[OvaSharedHistory] agent_sessions stream error: $e'),
    );

    _librarySub = userDoc
        .collection('ova_library')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .listen(
      (snap) {
        _remoteLibrary = snap.docs
            .map(OvaLibraryEntry.fromFirestore)
            .where((e) => !_deletedIds.contains(e.id))
            .toList();
        _rebuildState();
      },
      onError: (Object e) => debugPrint('[OvaSharedHistory] library stream error: $e'),
    );
  }

  void _rebuildState() {
    // Merge local optimistic turns with remote Firestore turns without duplicates.
    final mergedTurns = <OvaSharedTurn>[];
    final seenSignatures = <String>{};

    for (final t in [..._remoteTurns, ..._localTurns, ..._agentSessionTurns]) {
      if (_deletedIds.contains(t.id) || _deletedIds.contains(t.threadId)) continue;
      final sig = t.id.startsWith('agent_')
          ? 'session|${t.threadId}'
          : '${t.threadId}|${t.query.trim()}|${t.source.name}';
      if (seenSignatures.add(sig)) {
        mergedTurns.add(t);
      }
    }
    mergedTurns.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final mergedLib = <OvaLibraryEntry>[];
    final seenLib = <String>{};
    for (final item in [..._remoteLibrary, ..._localLibrary]) {
      if (_deletedIds.contains(item.id)) continue;
      final sig = '${item.title.trim()}|${item.content.trim()}';
      if (seenLib.add(sig)) {
        mergedLib.add(item);
      }
    }
    mergedLib.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    state = OvaSharedHistoryState(
      turns: mergedTurns,
      library: mergedLib,
      loading: false,
    );
  }

  /// Generates a fresh thread ID for multi-turn workspace sessions.
  String newThreadId([String prefix = 'main']) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}';

  /// Records a completed turn in shared history (syncs across Main, Overlay & Voice).
  Future<String> recordTurn({
    required String query,
    required String response,
    required OvaOriginSource source,
    OvaWorkspaceId workspace = OvaWorkspaceId.personal,
    String? threadId,
    String? threadTitle,
    bool persistToFirestore = true,
  }) async {
    final q = query.trim();
    final r = response.trim();
    if (q.isEmpty && r.isEmpty) return threadId ?? newThreadId();

    final effectiveThreadId =
        (threadId != null && threadId.trim().isNotEmpty) ? threadId.trim() : newThreadId(source.name);
    final localId = 'local_${DateTime.now().microsecondsSinceEpoch}';

    final turn = OvaSharedTurn(
      id: localId,
      threadId: effectiveThreadId,
      threadTitle: threadTitle,
      query: q,
      response: r,
      source: source,
      workspace: workspace,
      timestamp: DateTime.now(),
      status: 'completed',
    );

    _localTurns.insert(0, turn);
    if (_localTurns.length > 60) {
      _localTurns.removeRange(60, _localTurns.length);
    }
    _rebuildState();

    if (persistToFirestore && _firebaseReady) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && !user.isAnonymous) {
          final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);
          await userDoc.collection('ai_interactions').add({
            'threadId': effectiveThreadId,
            'threadTitle': ?threadTitle,
            'query': q,
            'response': r,
            'status': 'completed',
            'kind': source.firestoreKind,
            'workspace': workspace.name,
            'timestamp': FieldValue.serverTimestamp(),
          });

          // Mirror into unified `agent_sessions` so Mobile Agent Workspace &
          // Desktop Workstation Agent display Voice, Quick Overlay, and Studio
          // conversations seamlessly under the user's account.
          final nowUtc = DateTime.now().toUtc();
          final nowMs = nowUtc.millisecondsSinceEpoch;
          final sessionRef = userDoc.collection('agent_sessions').doc(effectiveThreadId);
          final computedTitle = (threadTitle != null && threadTitle.trim().isNotEmpty)
              ? threadTitle.trim()
              : (q.length > 52 ? '${q.substring(0, 52)}…' : (q.isNotEmpty ? q : 'Ova ${source.badgeLabel}'));
          await sessionRef.set({
            'title': computedTitle,
            'agentMode': 'orchestrator',
            'effort': 'balanced',
            'fullComputerAccess': true,
            'status': 'idle',
            'lastPreview': r.length > 140 ? '${r.substring(0, 140)}…' : r,
            'originDevice': source == OvaOriginSource.voice ? 'mobile_voice' : 'mobile',
            'updatedAtMs': nowMs,
            'updatedAt': nowUtc,
          }, SetOptions(merge: true));

          final turnsCol = sessionRef.collection('turns');
          if (q.isNotEmpty) {
            await turnsCol.add({
              'createdAtMs': nowMs - 1,
              'role': 'user',
              'originDevice': source == OvaOriginSource.voice ? 'mobile_voice' : 'mobile',
              'authorLabel': 'You (${source.badgeLabel})',
              'text': q,
              'status': 'completed',
              'thinkingSteps': const <String>[],
              'thinkingDurationMs': 0,
              'toolCalls': const <Map<String, dynamic>>[],
              'artifacts': const <Map<String, dynamic>>[],
              'followUps': const <String>[],
              'contextChips': <String>[source.badgeLabel, workspace.shortLabel],
              'createdAt': nowUtc,
              'updatedAt': nowUtc,
            });
          }
          if (r.isNotEmpty) {
            await turnsCol.add({
              'createdAtMs': nowMs,
              'role': 'assistant',
              'originDevice': 'cloud',
              'authorLabel': 'Ova',
              'text': r,
              'status': 'completed',
              'thinkingSteps': const <String>[],
              'thinkingDurationMs': 0,
              'toolCalls': const <Map<String, dynamic>>[],
              'artifacts': const <Map<String, dynamic>>[],
              'followUps': const <String>[],
              'contextChips': <String>[source.badgeLabel],
              'createdAt': nowUtc,
              'updatedAt': nowUtc,
            });
          }
        }
      } catch (e) {
        debugPrint('[OvaSharedHistory] Firestore write failed: $e');
      }
    }

    return effectiveThreadId;
  }

  /// Deletes a single thread and all its turns.
  Future<void> deleteThread(String threadId) async {
    _deletedIds.add(threadId);
    final matchingIds = <String>[
      for (final t in [..._localTurns, ..._remoteTurns])
        if (t.threadId == threadId || t.id == threadId) t.id,
    ];
    for (final id in matchingIds) {
      _deletedIds.add(id);
    }
    _localTurns.removeWhere((t) => t.threadId == threadId || t.id == threadId);
    _remoteTurns.removeWhere((t) => t.threadId == threadId || t.id == threadId);
    _rebuildState();

    if (_firebaseReady) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && !user.isAnonymous) {
          final col = FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('ai_interactions');
          for (final docId in matchingIds.where((id) => !id.startsWith('local_'))) {
            await col.doc(docId).delete();
          }
        }
      } catch (e) {
        debugPrint('[OvaSharedHistory] deleteThread failed: $e');
      }
    }
  }

  /// Clears all shared conversation history for the current user.
  Future<void> clearAllHistory() async {
    final remoteDocIds = _remoteTurns.map((t) => t.id).toList();
    for (final t in [..._localTurns, ..._remoteTurns]) {
      _deletedIds.add(t.id);
      _deletedIds.add(t.threadId);
    }
    _localTurns.clear();
    _remoteTurns = [];
    _rebuildState();

    if (_firebaseReady) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && !user.isAnonymous) {
          final col = FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('ai_interactions');
          final batch = FirebaseFirestore.instance.batch();
          for (final id in remoteDocIds) {
            batch.delete(col.doc(id));
          }
          await batch.commit();
        }
      } catch (e) {
        debugPrint('[OvaSharedHistory] clearAllHistory failed: $e');
      }
    }
  }

  /// Saves a prompt, script breakdown, or AI output into the user's Ova Library.
  Future<void> saveToLibrary({
    required String title,
    required String content,
    String category = 'Output',
    OvaWorkspaceId workspace = OvaWorkspaceId.personal,
  }) async {
    final cleanTitle = title.trim().isEmpty ? 'Saved output' : title.trim();
    final cleanContent = content.trim();
    if (cleanContent.isEmpty) return;

    final localId = 'lib_${DateTime.now().microsecondsSinceEpoch}';
    final entry = OvaLibraryEntry(
      id: localId,
      title: cleanTitle.length > 64 ? '${cleanTitle.substring(0, 64)}…' : cleanTitle,
      content: cleanContent,
      category: category,
      workspace: workspace,
      createdAt: DateTime.now(),
    );

    _localLibrary.insert(0, entry);
    _rebuildState();

    if (_firebaseReady) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && !user.isAnonymous) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('ova_library')
              .add({
            'title': entry.title,
            'content': entry.content,
            'category': entry.category,
            'workspace': entry.workspace.name,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      } catch (e) {
        debugPrint('[OvaSharedHistory] saveToLibrary failed: $e');
      }
    }
  }

  /// Removes a saved item from the Ova Library.
  Future<void> deleteLibraryItem(String id) async {
    _deletedIds.add(id);
    _localLibrary.removeWhere((e) => e.id == id);
    _remoteLibrary.removeWhere((e) => e.id == id);
    _rebuildState();

    if (_firebaseReady && !id.startsWith('lib_')) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && !user.isAnonymous) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('ova_library')
              .doc(id)
              .delete();
        }
      } catch (e) {
        debugPrint('[OvaSharedHistory] deleteLibraryItem failed: $e');
      }
    }
  }
}
