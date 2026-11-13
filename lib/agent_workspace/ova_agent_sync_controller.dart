import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/ai_brain_service.dart';
import '../backend/remote_connect_service.dart';
import '../backend/secure_pairing/crypto_utils.dart';
import '../backend/secure_pairing/secure_pairing_service.dart';
import '../desktop_agent/desktop_firebase_rest_client.dart';
import '../desktop_agent/macos_mouse_ffi.dart';
import '../ova_assistant/services/ova_shared_history_service.dart';
import 'ova_agent_mac_executor.dart';
import 'ova_agent_models.dart';
import 'ova_wispr_flow_service.dart';

class OvaAgentWorkspaceState {
  final List<OvaAgentSession> sessions;
  final String? activeSessionId;
  final List<OvaAgentTurn> turns;
  final OvaAgentMode selectedMode;
  final OvaAgentEffort selectedEffort;
  final OvaWorkspaceViewMode viewMode;
  final OvaWisprTarget wisprTarget;
  final bool fullComputerAccess;
  final bool handsFreeWispr;
  final bool loading;
  final bool sending;
  final String? workstationDeviceId;
  final String? workstationName;
  final String? workstationActiveWindow;
  final bool workstationOnline;
  final Map<String, dynamic> workstationTelemetry;
  final List<OvaLiveActionEvent> recentActions;
  final List<OvaWisprHistoryItem> wisprHistory;
  final OvaAgentArtifact? inspectedArtifact;
  final String? errorBanner;
  final bool webSearchEnabled;
  final List<OvaAgentMemory> memories;
  final String? authUid;
  final String? authDisplayName;
  final String? authUsername;
  final String? authEmail;
  final String? authPhone;
  final String? authPhotoUrl;
  final bool isAccountUser;

  const OvaAgentWorkspaceState({
    this.sessions = const [],
    this.activeSessionId,
    this.turns = const [],
    this.selectedMode = OvaAgentMode.orchestrator,
    this.selectedEffort = OvaAgentEffort.balanced,
    this.viewMode = OvaWorkspaceViewMode.agentChat,
    this.wisprTarget = OvaWisprTarget.composer,
    this.fullComputerAccess = true,
    this.handsFreeWispr = false,
    this.loading = false,
    this.sending = false,
    this.workstationDeviceId,
    this.workstationName,
    this.workstationActiveWindow,
    this.workstationOnline = false,
    this.workstationTelemetry = const {},
    this.recentActions = const [],
    this.wisprHistory = const [],
    this.inspectedArtifact,
    this.errorBanner,
    this.webSearchEnabled = false,
    this.memories = const [],
    this.authUid,
    this.authDisplayName,
    this.authUsername,
    this.authEmail,
    this.authPhone,
    this.authPhotoUrl,
    this.isAccountUser = false,
  });

  String get displayAccountName {
    if (authDisplayName != null && authDisplayName!.trim().isNotEmpty) {
      return authDisplayName!.trim();
    }
    if (authUsername != null && authUsername!.trim().isNotEmpty) {
      return '@${authUsername!.trim()}';
    }
    if (authPhone != null && authPhone!.trim().isNotEmpty) {
      return authPhone!.trim();
    }
    if (authEmail != null && authEmail!.trim().isNotEmpty) {
      return authEmail!.trim();
    }
    return 'Oneova Creator';
  }

  String get accountAvatarInitial {
    final name = displayAccountName;
    for (int i = 0; i < name.length; i++) {
      final char = name[i];
      if (RegExp(r'[a-zA-Z0-9]').hasMatch(char)) {
        return char.toUpperCase();
      }
    }
    return 'O';
  }

  OvaAgentSession? get activeSession {
    if (activeSessionId == null) return null;
    for (final s in sessions) {
      if (s.id == activeSessionId) return s;
    }
    return null;
  }

  List<OvaAgentPlanStep> get activePlan => activeSession?.plan ?? const [];

  bool get isBusy {
    if (sending) return true;
    final st = activeSession?.status;
    if (st == 'thinking' || st == 'running_tools' || st == 'synthesizing') {
      return true;
    }
    return turns.any((t) => t.isBusy);
  }

  List<OvaAgentArtifact> get allArtifacts => [
        for (final t in turns) ...t.artifacts,
      ];

  OvaAgentWorkspaceState copyWith({
    List<OvaAgentSession>? sessions,
    String? activeSessionId,
    bool clearActiveSession = false,
    List<OvaAgentTurn>? turns,
    OvaAgentMode? selectedMode,
    OvaAgentEffort? selectedEffort,
    OvaWorkspaceViewMode? viewMode,
    OvaWisprTarget? wisprTarget,
    bool? fullComputerAccess,
    bool? handsFreeWispr,
    bool? loading,
    bool? sending,
    String? workstationDeviceId,
    bool clearWorkstation = false,
    String? workstationName,
    String? workstationActiveWindow,
    bool? workstationOnline,
    Map<String, dynamic>? workstationTelemetry,
    List<OvaLiveActionEvent>? recentActions,
    List<OvaWisprHistoryItem>? wisprHistory,
    OvaAgentArtifact? inspectedArtifact,
    bool clearInspectedArtifact = false,
    String? errorBanner,
    bool clearErrorBanner = false,
    bool? webSearchEnabled,
    List<OvaAgentMemory>? memories,
    String? authUid,
    String? authDisplayName,
    String? authUsername,
    String? authEmail,
    String? authPhone,
    String? authPhotoUrl,
    bool? isAccountUser,
    bool clearAuthUser = false,
  }) {
    return OvaAgentWorkspaceState(
      sessions: sessions ?? this.sessions,
      activeSessionId:
          clearActiveSession ? null : (activeSessionId ?? this.activeSessionId),
      turns: turns ?? this.turns,
      selectedMode: selectedMode ?? this.selectedMode,
      selectedEffort: selectedEffort ?? this.selectedEffort,
      viewMode: viewMode ?? this.viewMode,
      wisprTarget: wisprTarget ?? this.wisprTarget,
      fullComputerAccess: fullComputerAccess ?? this.fullComputerAccess,
      handsFreeWispr: handsFreeWispr ?? this.handsFreeWispr,
      loading: loading ?? this.loading,
      sending: sending ?? this.sending,
      workstationDeviceId: clearWorkstation
          ? null
          : (workstationDeviceId ?? this.workstationDeviceId),
      workstationName:
          clearWorkstation ? null : (workstationName ?? this.workstationName),
      workstationActiveWindow: clearWorkstation
          ? null
          : (workstationActiveWindow ?? this.workstationActiveWindow),
      workstationOnline: clearWorkstation
          ? false
          : (workstationOnline ?? this.workstationOnline),
      workstationTelemetry: clearWorkstation
          ? const {}
          : (workstationTelemetry ?? this.workstationTelemetry),
      recentActions: recentActions ?? this.recentActions,
      wisprHistory: wisprHistory ?? this.wisprHistory,
      inspectedArtifact: clearInspectedArtifact
          ? null
          : (inspectedArtifact ?? this.inspectedArtifact),
      errorBanner:
          clearErrorBanner ? null : (errorBanner ?? this.errorBanner),
      webSearchEnabled: webSearchEnabled ?? this.webSearchEnabled,
      memories: memories ?? this.memories,
      authUid: clearAuthUser ? null : (authUid ?? this.authUid),
      authDisplayName:
          clearAuthUser ? null : (authDisplayName ?? this.authDisplayName),
      authUsername:
          clearAuthUser ? null : (authUsername ?? this.authUsername),
      authEmail: clearAuthUser ? null : (authEmail ?? this.authEmail),
      authPhone: clearAuthUser ? null : (authPhone ?? this.authPhone),
      authPhotoUrl:
          clearAuthUser ? null : (authPhotoUrl ?? this.authPhotoUrl),
      isAccountUser:
          clearAuthUser ? false : (isAccountUser ?? this.isAccountUser),
    );
  }
}

final ovaAgentSyncProvider =
    NotifierProvider<OvaAgentSyncNotifier, OvaAgentWorkspaceState>(
  OvaAgentSyncNotifier.new,
);

/// Real-Time Bidirectional Sync, Autonomous Computer-Use Orchestrator, Wispr
/// Voice Bridge, and Live Mouse/Keyboard Dispatcher across Mobile & Desktop.
class OvaAgentSyncNotifier extends Notifier<OvaAgentWorkspaceState> {
  final DesktopFirebaseRestClient _desktopCloud =
      DesktopFirebaseRestClient.instance;

  StreamSubscription<User?>? _mobileAuthSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _mobileComputersSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _mobileSessionsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _mobileTurnsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _mobileMemoriesSub;

  StreamSubscription<List<DesktopRestDoc>>? _desktopSessionsSub;
  StreamSubscription<List<DesktopRestDoc>>? _desktopTurnsSub;
  StreamSubscription<List<DesktopRestDoc>>? _desktopMemoriesSub;
  Timer? _desktopToolSweepTimer;

  String? _boundBaseCollectionPath;
  String? _boundTurnsSessionId;
  // Session whose turns are currently in `state.turns` from the desktop turns
  // poller; lets the tool sweep reuse them instead of re-listing.
  String? _desktopTurnsSnapshotSessionId;
  String? _desktopMemoriesUid;
  final Set<String> _migratedLegacyUids = {};
  bool _desktopSweepInFlight = false;
  final Map<String, DateTime> _desktopSweepListedAt = {};
  static const Duration _desktopSweepListGap = Duration(seconds: 5);
  int _cancelGeneration = 0;
  final Set<String> _executingTurnLocks = {};

  bool get _isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
  bool get _firebaseReady => !_isDesktop && Firebase.apps.isNotEmpty;

  @override
  OvaAgentWorkspaceState build() {
    if (!_isDesktop && _firebaseReady) {
      ref.listen<RemoteConnectState>(remoteConnectProvider, (prev, next) {
        if (prev?.activeComputerId != next.activeComputerId &&
            next.activeComputerId != null) {
          _rebindMobileForComputerOverride(next.activeComputerId!);
        }
      });

      try {
        _mobileAuthSub = FirebaseAuth.instance
            .authStateChanges()
            .listen(_onMobileAuthChanged);
        _onMobileAuthChanged(FirebaseAuth.instance.currentUser);
      } catch (e) {
        debugPrint('[OvaAgentSync] Mobile auth bind skipped: $e');
      }
    }

    ref.onDispose(_disposeAllSubscriptions);
    return const OvaAgentWorkspaceState();
  }

  void _disposeAllSubscriptions() {
    _mobileAuthSub?.cancel();
    _mobileComputersSub?.cancel();
    _mobileSessionsSub?.cancel();
    _mobileTurnsSub?.cancel();
    _mobileMemoriesSub?.cancel();
    _desktopSessionsSub?.cancel();
    _desktopTurnsSub?.cancel();
    _desktopMemoriesSub?.cancel();
    _desktopToolSweepTimer?.cancel();
  }

  // ---------------------------------------------------------------------------
  // Desktop Binding (macOS OneOva.app via Keychain-Free REST Client)
  // ---------------------------------------------------------------------------

  void bindDesktopWorkstation({
    required String deviceId,
    required String computerName,
    String? activeWindow,
    String? ownerUid,
  }) {
    if (!_isDesktop) return;

    final effectiveUid = ownerUid ?? _desktopCloud.currentUid;
    final nextBase = effectiveUid != null
        ? 'users/$effectiveUid/agent_sessions'
        : 'registered_computers/$deviceId/agent_sessions';

    state = state.copyWith(
      workstationDeviceId: deviceId,
      workstationName: computerName,
      workstationActiveWindow: activeWindow ?? state.workstationActiveWindow,
      workstationOnline: true,
      clearErrorBanner: true,
    );

    if (effectiveUid != null) {
      _bindDesktopMemories(effectiveUid);
      // Copying legacy sessions reads and rewrites every old turn; once per
      // account per run is enough.
      if (_migratedLegacyUids.add('$deviceId|$effectiveUid')) {
        unawaited(_migrateLegacySessions(deviceId, effectiveUid));
      }
      unawaited(_fetchDesktopUserProfile(effectiveUid));
    }

    if (_boundBaseCollectionPath == nextBase && _desktopSessionsSub != null) {
      return;
    }

    _boundBaseCollectionPath = nextBase;
    _desktopSessionsSub?.cancel();
    _desktopTurnsSub?.cancel();
    _boundTurnsSessionId = null;

    _desktopSessionsSub = _desktopCloud
        .watchCollection(
          nextBase,
          interval: const Duration(milliseconds: 850),
          idleInterval: const Duration(seconds: 4),
          keepFast: () => state.sending || state.activeSession?.status ==
              'thinking' || state.activeSession?.status == 'running_tools',
        )
        .listen(
      (docs) {
        final list = docs
            .map((d) => OvaAgentSession.fromMap(d.id, d.data))
            .toList()
          ..sort(_compareSessions);

        String? nextActive = state.activeSessionId;
        final liveRemote = list
            .where((s) =>
                s.status == 'thinking' ||
                s.status == 'running_tools' ||
                s.status == 'awaiting_approval')
            .firstOrNull;
        if (nextActive == null || !list.any((s) => s.id == nextActive)) {
          nextActive = (liveRemote ?? list.firstOrNull)?.id;
        } else if (liveRemote != null &&
            liveRemote.id != nextActive &&
            state.activeSession?.status == 'idle') {
          nextActive = liveRemote.id;
        }

        state = state.copyWith(
          sessions: list,
          activeSessionId: nextActive,
          loading: false,
        );

        if (nextActive != null && nextActive != _boundTurnsSessionId) {
          _bindDesktopTurnsStream(nextActive);
        }

        unawaited(_sweepDesktopPendingTools(deviceId, list));
      },
      onError: (Object e) {
        debugPrint('[OvaAgentSync] Desktop sessions stream notice: $e');
      },
    );

    _desktopToolSweepTimer?.cancel();
    _desktopToolSweepTimer = Timer.periodic(
      const Duration(milliseconds: 1050),
      (_) {
        if (state.workstationDeviceId != null && state.sessions.isNotEmpty) {
          unawaited(
            _sweepDesktopPendingTools(
                state.workstationDeviceId!, state.sessions),
          );
        }
      },
    );
  }

  void updateDesktopActiveWindow(String activeWindow) {
    if (!_isDesktop || activeWindow == state.workstationActiveWindow) return;
    state = state.copyWith(workstationActiveWindow: activeWindow);
  }

  void unbindDesktopWorkstation() {
    _desktopSessionsSub?.cancel();
    _desktopTurnsSub?.cancel();
    _desktopMemoriesSub?.cancel();
    _desktopToolSweepTimer?.cancel();
    _desktopSessionsSub = null;
    _desktopTurnsSub = null;
    _desktopMemoriesSub = null;
    _desktopToolSweepTimer = null;
    _boundBaseCollectionPath = null;
    _boundTurnsSessionId = null;
    _desktopTurnsSnapshotSessionId = null;
    _desktopMemoriesUid = null;
    _desktopSweepListedAt.clear();
    state = const OvaAgentWorkspaceState();
  }

  Future<void> _migrateLegacySessions(String deviceId, String uid) async {
    try {
      final legacyDocs = await _desktopCloud.listDocuments(
        'registered_computers/$deviceId/agent_sessions',
        pageSize: 60,
      );
      for (final doc in legacyDocs) {
        await _desktopCloud.setDocument(
          'users/$uid/agent_sessions/${doc.id}',
          doc.data,
          merge: true,
        );
        final turns = await _desktopCloud.listDocuments(
          'registered_computers/$deviceId/agent_sessions/${doc.id}/turns',
          pageSize: 100,
        );
        for (final t in turns) {
          await _desktopCloud.setDocument(
            'users/$uid/agent_sessions/${doc.id}/turns/${t.id}',
            t.data,
            merge: true,
          );
        }
      }
    } catch (e) {
      debugPrint('[OvaAgentSync] Legacy session migration note: $e');
    }
  }

  Future<void> _fetchDesktopUserProfile(String uid) async {
    try {
      final docData = await _desktopCloud.getDocument('users/$uid');
      if (docData != null) {
        state = state.copyWith(
          authUid: uid,
          authDisplayName: (docData['displayName'] ?? docData['fullName'] ?? 'Oneova Creator').toString(),
          authUsername: (docData['username'] ?? '').toString(),
          authEmail: (docData['email'] ?? docData['recoveryEmail'] ?? '').toString(),
          authPhone: (docData['phone'] ?? docData['phoneNumber'] ?? '').toString(),
          authPhotoUrl: (docData['photoUrl'] ?? docData['profilePhotoUrl'] ?? docData['photoURL'] ?? '').toString(),
          isAccountUser: true,
        );
      }
    } catch (e) {
      debugPrint('[OvaAgentSync] Desktop user profile note: $e');
    }
  }

  void _bindDesktopTurnsStream(String sessionId) {
    final base = _boundBaseCollectionPath;
    if (base == null) return;
    _boundTurnsSessionId = sessionId;
    _desktopTurnsSnapshotSessionId = null;
    _desktopTurnsSub?.cancel();
    _desktopTurnsSub = _desktopCloud
        .watchCollection(
          '$base/$sessionId/turns',
          interval: const Duration(milliseconds: 700),
          idleInterval: const Duration(seconds: 3),
          keepFast: () => state.sending || state.activeSession?.status ==
              'thinking' || state.activeSession?.status == 'running_tools',
        )
        .listen(
      (docs) {
        if (docs.isEmpty && state.sending && state.turns.isNotEmpty) {
          // Keep optimistic in-flight turns until first cloud write settles
          return;
        }
        final sorted = docs
            .map((d) => OvaAgentTurn.fromMap(d.id, d.data))
            .toList()
          ..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
        if (_boundTurnsSessionId == sessionId) {
          _desktopTurnsSnapshotSessionId = sessionId;
        }
        state = state.copyWith(turns: sorted);
      },
      onError: (Object e) {
        debugPrint('[OvaAgentSync] Desktop turns stream notice: $e');
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Mobile Real-Time Auto-Discovery & Firestore Snapshot Sync
  // ---------------------------------------------------------------------------

  void _onMobileAuthChanged(User? user) {
    _mobileComputersSub?.cancel();
    _mobileSessionsSub?.cancel();
    _mobileTurnsSub?.cancel();
    _mobileMemoriesSub?.cancel();
    _boundBaseCollectionPath = null;
    _boundTurnsSessionId = null;

    if (user == null || user.isAnonymous) {
      state = const OvaAgentWorkspaceState();
      return;
    }

    state = state.copyWith(
      authUid: user.uid,
      authEmail: user.email,
      authDisplayName: user.displayName,
      authPhotoUrl: user.photoURL,
      isAccountUser: true,
    );
    unawaited(_fetchMobileUserProfile(user.uid));

    _bindMobileMemories(user.uid);
    // Unconditionally bind the user account agent_sessions collection so all chats
    // (both mobile and Mac) are rendered under the user's unified account.
    _bindMobileSessionsCollection('users/${user.uid}/agent_sessions');

    _mobileComputersSub = FirebaseFirestore.instance
        .collection('registered_computers')
        .where('owner_uid', isEqualTo: user.uid)
        .snapshots()
        .listen(
      (snap) {
        final explicitId = ref.read(remoteConnectProvider).activeComputerId;
        QueryDocumentSnapshot<Map<String, dynamic>>? chosen;

        if (explicitId != null) {
          for (final d in snap.docs) {
            if (d.id == explicitId) {
              chosen = d;
              break;
            }
          }
        }

        if (chosen == null && snap.docs.isNotEmpty) {
          final sortedDocs = [...snap.docs]..sort((a, b) {
              final aOnline = _isComputerDocOnline(a.data()) ? 1 : 0;
              final bOnline = _isComputerDocOnline(b.data()) ? 1 : 0;
              if (aOnline != bOnline) return bOnline.compareTo(aOnline);
              final aSeen = (a.data()['last_seen'] as Timestamp?)
                      ?.millisecondsSinceEpoch ??
                  0;
              final bSeen = (b.data()['last_seen'] as Timestamp?)
                      ?.millisecondsSinceEpoch ??
                  0;
              return bSeen.compareTo(aSeen);
            });
          chosen = sortedDocs.first;
        }

        if (chosen != null) {
          final d = chosen.data();
          final online = _isComputerDocOnline(d);
          final sysInfo = d['system_info'];
          state = state.copyWith(
            workstationDeviceId: chosen.id,
            workstationName:
                (d['computer_name'] ?? 'Mac Workstation').toString(),
            workstationActiveWindow:
                (d['active_window'] ?? 'Desktop').toString(),
            workstationOnline: online,
            workstationTelemetry:
                sysInfo is Map ? Map<String, dynamic>.from(sysInfo) : const {},
          );
        } else {
          state = state.copyWith(clearWorkstation: true);
        }
      },
      onError: (Object e) {
        debugPrint('[OvaAgentSync] Computers discovery notice: $e');
      },
    );
  }

  void _rebindMobileForComputerOverride(String deviceId) {
    if (_isDesktop || !_firebaseReady) return;
    state = state.copyWith(workstationDeviceId: deviceId);
  }

  bool _isComputerDocOnline(Map<String, dynamic> d) {
    final connected = d['desktop_connected'] == true;
    final status = (d['status'] ?? '').toString();
    if (!connected || status != 'online') return false;
    final lastSeen = (d['last_seen'] as Timestamp?)?.toDate();
    if (lastSeen == null) return connected;
    return DateTime.now().difference(lastSeen).inSeconds < 75;
  }

  void _bindMobileSessionsCollection(String collectionPath) {
    if (_boundBaseCollectionPath == collectionPath &&
        _mobileSessionsSub != null) {
      return;
    }
    _boundBaseCollectionPath = collectionPath;
    _mobileSessionsSub?.cancel();
    _mobileTurnsSub?.cancel();
    _boundTurnsSessionId = null;

    _mobileSessionsSub = FirebaseFirestore.instance
        .collection(collectionPath)
        .limit(50)
        .snapshots()
        .listen(
      (snap) {
        final list = snap.docs
            .map((d) => OvaAgentSession.fromMap(d.id, d.data()))
            .toList()
          ..sort(_compareSessions);

        String? nextActive = state.activeSessionId;
        final liveDesktop = list
            .where((s) =>
                s.originDevice == 'mac' &&
                (s.status == 'thinking' ||
                    s.status == 'running_tools' ||
                    s.status == 'awaiting_approval'))
            .firstOrNull;

        if (nextActive == null || !list.any((s) => s.id == nextActive)) {
          nextActive = (liveDesktop ?? list.firstOrNull)?.id;
        } else if (liveDesktop != null &&
            liveDesktop.id != nextActive &&
            state.turns.isEmpty) {
          nextActive = liveDesktop.id;
        }

        state = state.copyWith(
          sessions: list,
          activeSessionId: nextActive,
          loading: false,
        );

        if (nextActive != null && nextActive != _boundTurnsSessionId) {
          _bindMobileTurnsCollection(nextActive);
        } else if (nextActive == null) {
          state = state.copyWith(turns: const []);
        }
      },
      onError: (Object e) {
        debugPrint('[OvaAgentSync] Mobile sessions snapshot error: $e');
      },
    );
  }

  void _bindMobileTurnsCollection(String sessionId) {
    final base = _boundBaseCollectionPath;
    if (base == null) return;
    _boundTurnsSessionId = sessionId;
    _mobileTurnsSub?.cancel();

    _mobileTurnsSub = FirebaseFirestore.instance
        .collection('$base/$sessionId/turns')
        .limit(120)
        .snapshots()
        .listen(
      (snap) {
        if (snap.docs.isEmpty && state.sending && state.turns.isNotEmpty) {
          return;
        }
        final sorted = snap.docs
            .map((d) => OvaAgentTurn.fromMap(d.id, d.data()))
            .toList()
          ..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
        state = state.copyWith(turns: sorted);
      },
      onError: (Object e) {
        debugPrint('[OvaAgentSync] Mobile turns snapshot error: $e');
      },
    );
  }

  Future<void> _fetchMobileUserProfile(String uid) async {
    try {
      final snap = await FirebaseFirestore.instance.doc('users/$uid').get();
      if (snap.exists && snap.data() != null) {
        final d = snap.data()!;
        state = state.copyWith(
          authDisplayName: (d['displayName'] ?? d['fullName'] ?? state.authDisplayName)?.toString(),
          authUsername: (d['username'] ?? state.authUsername)?.toString(),
          authEmail: (d['email'] ?? d['recoveryEmail'] ?? state.authEmail)?.toString(),
          authPhone: (d['phone'] ?? d['phoneNumber'] ?? state.authPhone)?.toString(),
          authPhotoUrl: (d['photoUrl'] ?? d['profilePhotoUrl'] ?? d['photoURL'] ?? state.authPhotoUrl)?.toString(),
        );
      }
    } catch (e) {
      debugPrint('[OvaAgentSync] Mobile user profile notice: $e');
    }
  }

  void setAuthUser({
    String? uid,
    String? displayName,
    String? username,
    String? email,
    String? phone,
    String? photoUrl,
    bool isAccountUser = true,
  }) {
    state = state.copyWith(
      authUid: uid,
      authDisplayName: displayName,
      authUsername: username,
      authEmail: email,
      authPhone: phone,
      authPhotoUrl: photoUrl,
      isAccountUser: isAccountUser,
    );
  }

  void clearAuthUser() {
    state = state.copyWith(clearAuthUser: true);
  }

  static int _compareSessions(OvaAgentSession a, OvaAgentSession b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    return b.updatedAtMs.compareTo(a.updatedAtMs);
  }

  // ---------------------------------------------------------------------------
  // User Controls: View Modes, Access Level, Wispr Target, Sessions, Artifacts
  // ---------------------------------------------------------------------------

  void setViewMode(OvaWorkspaceViewMode mode) {
    state = state.copyWith(viewMode: mode);
  }

  void setWisprTarget(OvaWisprTarget target) {
    state = state.copyWith(wisprTarget: target);
  }

  void setHandsFreeWispr(bool enabled) {
    state = state.copyWith(handsFreeWispr: enabled);
  }

  Future<void> setFullComputerAccess(bool enabled) async {
    state = state.copyWith(fullComputerAccess: enabled);
    recordLiveActionEvent(
      category: 'system',
      summary: enabled
          ? 'Enabled Full Computer Access (Autonomous Auto-Run)'
          : 'Switched to Supervised Mode (Ask before mutating actions)',
    );
    final base = _boundBaseCollectionPath;
    final sessionId = state.activeSessionId;
    if (base != null && sessionId != null) {
      unawaited(
        _writeDoc(
          '$base/$sessionId',
          {'fullComputerAccess': enabled},
          merge: true,
        ).catchError((_) {}),
      );
    }
  }

  void setAgentMode(OvaAgentMode mode) {
    state = state.copyWith(selectedMode: mode);
  }

  void setEffort(OvaAgentEffort effort) {
    state = state.copyWith(selectedEffort: effort);
  }

  void inspectArtifact(OvaAgentArtifact? artifact) {
    if (artifact == null) {
      state = state.copyWith(clearInspectedArtifact: true);
    } else {
      state = state.copyWith(inspectedArtifact: artifact);
    }
  }

  void clearError() {
    state = state.copyWith(clearErrorBanner: true);
  }

  void recordLiveActionEvent({
    required String category,
    required String summary,
    String? originOverride,
  }) {
    final evt = OvaLiveActionEvent(
      id: 'act_${DateTime.now().microsecondsSinceEpoch}',
      category: category,
      summary: summary,
      origin: originOverride ?? (_isDesktop ? 'mac' : 'mobile'),
      timestamp: DateTime.now(),
    );
    final updated = [evt, ...state.recentActions];
    if (updated.length > 24) {
      updated.removeRange(24, updated.length);
    }
    state = state.copyWith(recentActions: updated);
  }

  void recordWisprHistoryItem({
    required String text,
    required String targetLabel,
  }) {
    final item = OvaWisprHistoryItem(
      id: 'wspr_${DateTime.now().microsecondsSinceEpoch}',
      text: text,
      targetLabel: targetLabel,
      activeApp: state.workstationActiveWindow ?? 'Desktop',
      createdAt: DateTime.now(),
    );
    final updated = [item, ...state.wisprHistory];
    if (updated.length > 20) {
      updated.removeRange(20, updated.length);
    }
    state = state.copyWith(wisprHistory: updated);
  }

  // ---------------------------------------------------------------------------
  // Direct Live Mouse, Keyboard & Wispr-to-Mac-Cursor Dispatch
  // ---------------------------------------------------------------------------

  /// Injects Wispr-polished speech or text directly into the active Mac cursor
  /// (either locally on macOS via `pasteTextInstant` or remotely from Mobile
  /// over the encrypted/live `commands` bridge!).
  Future<bool> injectWisprToMacCursor(
    String text, {
    bool pressEnter = false,
  }) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return false;

    recordLiveActionEvent(
      category: 'wispr',
      summary:
          'Wispr → ${state.workstationActiveWindow ?? "Mac"}: "${cleaned.length > 44 ? "${cleaned.substring(0, 44)}…" : cleaned}"',
    );
    recordWisprHistoryItem(text: cleaned, targetLabel: 'Mac Cursor');

    if (_isDesktop && Platform.isMacOS) {
      await MacOSMouseController.pasteTextInstant(
        cleaned,
        pressEnter: pressEnter,
      );
      return true;
    }

    return dispatchDirectMacCommand(
      'paste_text',
      payload: {
        'text': cleaned,
        'pressEnter': pressEnter,
        'source': 'wispr_mobile',
      },
      softwareId: 'wispr_flow',
      logCategory: 'wispr',
      logSummary: null,
    );
  }

  /// Dispatches low-latency mouse, keyboard, AppleScript, or system actions to
  /// the paired Mac workstation (or runs directly when invoked on macOS).
  Future<bool> dispatchDirectMacCommand(
    String command, {
    Map<String, dynamic> payload = const {},
    String softwareId = 'input_deck',
    String logCategory = 'keyboard',
    String? logSummary,
  }) async {
    if (logSummary != null && logSummary.isNotEmpty) {
      recordLiveActionEvent(category: logCategory, summary: logSummary);
    }

    if (_isDesktop && Platform.isMacOS) {
      await _executeLocalDirectCommand(command, payload);
      return true;
    }

    final deviceId = state.workstationDeviceId;
    if (deviceId == null || !_firebaseReady) {
      state = state.copyWith(
        errorBanner: 'Pair or wake your Mac workstation to send live input.',
      );
      return false;
    }

    // Fast path: if RemoteConnectService has an active E2EE key for the
    // same computer, dispatch through it immediately; otherwise write
    // directly to `registered_computers/$deviceId/commands`!
    final rcState = ref.read(remoteConnectProvider);
    if (rcState.activeComputerId == deviceId &&
        rcState.status == ConnectionStatus.connected &&
        rcState.activeKeys.containsKey(deviceId)) {
      final cmdId = await ref
          .read(remoteConnectProvider.notifier)
          .sendCommand(softwareId, command, payload);
      return cmdId != null;
    }

    try {
      String? encryptedPayload;
      final activeKey = ref.read(securePairingProvider).activeKey;
      if (activeKey != null && payload.isNotEmpty) {
        encryptedPayload =
            CryptoUtils.encryptPayload(jsonEncode(payload), activeKey);
      }

      await FirebaseFirestore.instance
          .collection('registered_computers')
          .doc(deviceId)
          .collection('commands')
          .add({
        'software_id': softwareId,
        'command': command,
        if (encryptedPayload != null)
          'payload_encrypted': encryptedPayload
        else if (payload.isNotEmpty)
          'payload': payload,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('[OvaAgentSync] dispatchDirectMacCommand error: $e');
      return false;
    }
  }

  Future<void> _executeLocalDirectCommand(
    String command,
    Map<String, dynamic> payload,
  ) async {
    switch (command) {
      case 'mouse_move':
        final dx = (payload['dx'] as num?)?.toDouble() ?? 0.0;
        final dy = (payload['dy'] as num?)?.toDouble() ?? 0.0;
        MacOSMouseController.moveBy(dx, dy);
      case 'mouse_move_to':
        final x = (payload['x'] as num?)?.toDouble() ?? 0.0;
        final y = (payload['y'] as num?)?.toDouble() ?? 0.0;
        MacOSMouseController.moveTo(x, y);
      case 'mouse_left_click':
        MacOSMouseController.click();
      case 'mouse_right_click':
        MacOSMouseController.rightClick();
      case 'mouse_double_click':
        MacOSMouseController.doubleClick();
      case 'mouse_left_down':
        MacOSMouseController.leftClickDown();
      case 'mouse_left_up':
        MacOSMouseController.leftClickUp();
      case 'mouse_scroll':
        final dy = (payload['dy'] as num?)?.toDouble() ?? 0.0;
        MacOSMouseController.scroll(dy);
      case 'key_tap':
        await MacOSMouseController.tapKey((payload['key'] ?? '').toString());
      case 'key_combination':
        await MacOSMouseController.sendHotkey(
          (payload['combo'] ?? '').toString(),
        );
      case 'paste_text':
      case 'type_text':
        await MacOSMouseController.pasteTextInstant(
          (payload['text'] ?? '').toString(),
          pressEnter: payload['pressEnter'] == true,
        );
      case 'system_control':
        await OvaAgentMacExecutor.instance.execute(
          OvaAgentToolCall(
            id: 'direct_sys',
            name: 'system_control',
            title: 'System Control',
            args: payload,
          ),
        );
      case 'open_mac_app':
        await OvaAgentMacExecutor.instance.execute(
          OvaAgentToolCall(
            id: 'direct_open',
            name: 'open_mac_app',
            title: 'Open App',
            args: payload,
          ),
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Shared User Memories across Mobile & Mac
  // ---------------------------------------------------------------------------

  void _bindDesktopMemories(String uid) {
    if (_desktopMemoriesUid == uid && _desktopMemoriesSub != null) return;
    _desktopMemoriesUid = uid;
    _desktopMemoriesSub?.cancel();
    _desktopMemoriesSub = _desktopCloud
        .watchCollection(
          'users/$uid/agent_memories',
          interval: const Duration(milliseconds: 1400),
          idleInterval: const Duration(seconds: 10),
        )
        .listen(
      (docs) {
        final list = docs
            .map((d) => OvaAgentMemory.fromMap(d.id, d.data))
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        state = state.copyWith(memories: list);
      },
      onError: (Object e) {
        debugPrint('[OvaAgentSync] Desktop memories stream notice: $e');
      },
    );
  }

  void _bindMobileMemories(String uid) {
    _mobileMemoriesSub?.cancel();
    _mobileMemoriesSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('agent_memories')
        .snapshots()
        .listen(
      (snap) {
        final list = snap.docs
            .map((d) => OvaAgentMemory.fromMap(d.id, d.data()))
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        state = state.copyWith(memories: list);
      },
      onError: (Object e) {
        debugPrint('[OvaAgentSync] Mobile memories stream notice: $e');
      },
    );
  }

  Future<void> saveUserMemory(String key, String content) async {
    final cleanKey = key.trim();
    final cleanContent = content.trim();
    if (cleanKey.isEmpty || cleanContent.isEmpty) return;

    if (_isDesktop) {
      final uid = _desktopCloud.currentUid;
      if (uid == null) return;
      final now = DateTime.now();
      await _desktopCloud.addDocument('users/$uid/agent_memories', {
        'key': cleanKey,
        'content': cleanContent,
        'originDevice': 'mac',
        'updatedAt': now.toIso8601String(),
        'updatedAtMs': now.millisecondsSinceEpoch,
      });
    } else {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('agent_memories')
          .add({
        'key': cleanKey,
        'content': cleanContent,
        'originDevice': 'mobile',
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  Future<void> deleteUserMemory(String memoryId) async {
    if (memoryId.isEmpty) return;
    if (_isDesktop) {
      final uid = _desktopCloud.currentUid;
      if (uid == null) return;
      await _desktopCloud.deleteDocument('users/$uid/agent_memories/$memoryId');
    } else {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('agent_memories')
          .doc(memoryId)
          .delete();
    }
  }

  Future<String?> createNewSession({
    String? title,
    OvaAgentMode? mode,
  }) async {
    final base = _resolveOrCreateBasePath();
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final sessionId = 'sess_$nowMs';
    final initialTitle = title ?? 'New Chat';
    final selectedMode = mode ?? state.selectedMode;

    final newSession = OvaAgentSession(
      id: sessionId,
      title: initialTitle,
      agentMode: selectedMode,
      effort: state.selectedEffort,
      fullComputerAccess: state.fullComputerAccess,
      status: 'idle',
      lastPreview: 'Ready for new instruction',
      originDevice: _isDesktop ? 'mac' : 'mobile',
      deviceId: state.workstationDeviceId,
      computerName: state.workstationName,
      turnCount: 0,
      updatedAtMs: nowMs,
      createdAt: now,
      updatedAt: now,
    );

    _boundTurnsSessionId = sessionId;
    _mobileTurnsSub?.cancel();
    _desktopTurnsSub?.cancel();

    state = state.copyWith(
      activeSessionId: sessionId,
      sessions: [newSession, ...state.sessions.where((s) => s.id != sessionId)],
      turns: const [],
      clearInspectedArtifact: true,
      clearErrorBanner: true,
    );

    if (base != null) {
      unawaited(_writeDoc('$base/$sessionId', newSession.toFirestoreMap(), merge: true));
      if (_isDesktop) {
        _bindDesktopTurnsStream(sessionId);
      } else {
        _bindMobileTurnsCollection(sessionId);
      }
    }

    return sessionId;
  }

  void startNewSession() {
    unawaited(createNewSession());
  }

  void selectSession(String sessionId) {
    if (sessionId == state.activeSessionId) return;
    final found = state.sessions.where((s) => s.id == sessionId).firstOrNull;
    state = state.copyWith(
      activeSessionId: sessionId,
      selectedMode: found?.agentMode ?? state.selectedMode,
      selectedEffort: found?.effort ?? state.selectedEffort,
      fullComputerAccess:
          found?.fullComputerAccess ?? state.fullComputerAccess,
      clearInspectedArtifact: true,
      clearErrorBanner: true,
    );
    if (_isDesktop) {
      _bindDesktopTurnsStream(sessionId);
    } else {
      _bindMobileTurnsCollection(sessionId);
    }
  }

  Future<void> togglePinSession(OvaAgentSession session) async {
    final base = _boundBaseCollectionPath;
    if (base == null) return;
    await _writeDoc(
      '$base/${session.id}',
      {'pinned': !session.pinned},
      merge: true,
    );
  }

  Future<void> deleteSession(String sessionId) async {
    final base = _boundBaseCollectionPath;
    if (base == null) return;
    try {
      final turns = await _listTurnDocs(sessionId);
      for (final t in turns) {
        await _deleteDoc('$base/$sessionId/turns/${t.id}');
      }
      await _deleteDoc('$base/$sessionId');
      if (state.activeSessionId == sessionId) {
        startNewSession();
      }
    } catch (e) {
      debugPrint('[OvaAgentSync] deleteSession error: $e');
    }
  }

  void setWebSearchEnabled(bool enabled) {
    state = state.copyWith(webSearchEnabled: enabled);
  }

  void toggleWebSearch() {
    state = state.copyWith(webSearchEnabled: !state.webSearchEnabled);
  }

  Future<void> renameSession(String sessionId, String newTitle) async {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;
    final base = _boundBaseCollectionPath;
    if (base == null) return;
    try {
      await _writeDoc(
        '$base/$sessionId',
        {
          'title': trimmed,
          'updatedAt': DateTime.now().toUtc(),
        },
        merge: true,
      );
      final updated = state.sessions.map((s) {
        if (s.id == sessionId) return s.copyWith(title: trimmed);
        return s;
      }).toList();
      state = state.copyWith(sessions: updated);
    } catch (e) {
      debugPrint('[OvaAgentSync] renameSession error: $e');
    }
  }

  Future<void> stopCurrentTurn() async {
    _cancelGeneration++;
    state = state.copyWith(sending: false);
    final base = _boundBaseCollectionPath;
    final sessionId = state.activeSessionId;
    if (base == null || sessionId == null) return;

    await _writeDoc(
      '$base/$sessionId',
      {'status': 'idle', 'updatedAt': DateTime.now().toUtc()},
      merge: true,
    );
    for (final t in state.turns.where((t) => t.isBusy)) {
      await _writeDoc(
        '$base/$sessionId/turns/${t.id}',
        {
          'status': 'completed',
          'text': t.text.isEmpty ? '_Stopped by user._' : t.text,
          'updatedAt': DateTime.now().toUtc(),
        },
        merge: true,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Send Prompt & Multi-Round Autonomous Agentic Execution Loop
  // ---------------------------------------------------------------------------

  Future<void> sendPrompt(
    String rawPrompt, {
    List<String> contextChips = const [],
    String? screenContextLabel,
  }) async {
    final prompt = rawPrompt.trim();
    if (prompt.isEmpty || state.sending) return;

    final base = _resolveOrCreateBasePath();
    if (base == null) {
      state = state.copyWith(
        errorBanner:
            'Sign in with your Oneova account to start synced Agent sessions.',
      );
      return;
    }

    final gen = ++_cancelGeneration;
    final origin = _isDesktop ? 'mac' : 'mobile';
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;

    String sessionId = state.activeSessionId ?? 'sess_$nowMs';
    final existingSession = state.activeSession;
    final isNewSession = state.activeSessionId == null ||
        existingSession == null ||
        (existingSession.turnCount == 0 &&
            (existingSession.title == 'New Chat' ||
                existingSession.title.isEmpty));

    // Snapshot existing turns BEFORE starting stream watchers so an empty initial
    // poll can never wipe out `userTurn` before `_invokeAgentCloudFunction`!
    final priorTurnsSnapshot = List<OvaAgentTurn>.from(state.turns);

    final sessionTitle = _deriveTitle(prompt);
    final userTurnId = 'turn_${nowMs}_u';
    final assistantTurnId = 'turn_${nowMs + 1}_a';

    recordLiveActionEvent(
      category: 'agent',
      summary:
          'Prompt (${origin == "mac" ? "Mac" : "Mobile"}): "${prompt.length > 48 ? "${prompt.substring(0, 48)}…" : prompt}"',
    );

    final resolvedContextChips = <String>[
      ...contextChips,
      if (state.webSearchEnabled && !contextChips.contains('Web Search'))
        'Web Search',
    ];

    final userTurn = OvaAgentTurn(
      id: userTurnId,
      createdAtMs: nowMs,
      role: 'user',
      originDevice: origin,
      authorLabel: _isDesktop
          ? (state.workstationName ?? Platform.localHostname)
          : 'Oneova Mobile',
      text: prompt,
      status: 'completed',
      contextChips: resolvedContextChips,
      createdAt: now,
    );

    final placeholderAssistant = OvaAgentTurn(
      id: assistantTurnId,
      createdAtMs: nowMs + 1,
      role: 'assistant',
      originDevice: origin,
      authorLabel: 'Ova Agent',
      text: '',
      status: 'thinking',
      thinkingSteps: [
        'Routing instruction via ${state.selectedMode.label} (${state.fullComputerAccess ? "Full Computer Access" : "Supervised"})...',
        if (state.workstationOnline)
          'Linked to ${state.workstationName ?? "Mac"} • Active window: ${state.workstationActiveWindow ?? "Desktop"}',
      ],
      createdAt: now.add(const Duration(milliseconds: 1)),
    );

    state = state.copyWith(
      activeSessionId: sessionId,
      turns: [...priorTurnsSnapshot, userTurn, placeholderAssistant],
      sending: true,
      viewMode: OvaWorkspaceViewMode.agentChat,
      clearErrorBanner: true,
    );

    // Write turns FIRST so collection watchers immediately see them!
    await _writeDoc(
      '$base/$sessionId/turns/$userTurnId',
      userTurn.toFirestoreMap(),
      merge: true,
    );
    await _writeDoc(
      '$base/$sessionId/turns/$assistantTurnId',
      placeholderAssistant.toFirestoreMap(),
      merge: true,
    );

    if (isNewSession) {
      final newSession = OvaAgentSession(
        id: sessionId,
        title: sessionTitle,
        agentMode: state.selectedMode,
        effort: state.selectedEffort,
        fullComputerAccess: state.fullComputerAccess,
        status: 'thinking',
        lastPreview: prompt,
        originDevice: origin,
        deviceId: state.workstationDeviceId,
        computerName: state.workstationName,
        turnCount: 1,
        updatedAtMs: nowMs,
        createdAt: existingSession?.createdAt ?? now,
        updatedAt: now,
      );
      await _writeDoc(
        '$base/$sessionId',
        newSession.toFirestoreMap(),
        merge: true,
      );
      if (_isDesktop) {
        _bindDesktopTurnsStream(sessionId);
      } else {
        _bindMobileTurnsCollection(sessionId);
      }
    } else {
      final updatedTitle =
          (existingSession.title == 'New Chat' || existingSession.title.isEmpty)
              ? sessionTitle
              : existingSession.title;
      await _writeDoc(
        '$base/$sessionId',
        {
          'title': updatedTitle,
          'agentMode': state.selectedMode.wireValue,
          'effort': state.selectedEffort.wireValue,
          'fullComputerAccess': state.fullComputerAccess,
          'status': 'thinking',
          'lastPreview': prompt,
          'turnCount': existingSession.turnCount + 1,
          'updatedAtMs': nowMs,
          'updatedAt': now.toUtc(),
        },
        merge: true,
      );
    }

    final thinkSw = Stopwatch()..start();

    try {
      final historyMessages = _buildModelMessages(
        priorTurns: [...priorTurnsSnapshot, userTurn],
        extraContextChips: contextChips,
      );

      final result = await _invokeAgentCloudFunction(
        messages: historyMessages,
        fallbackPrompt: prompt,
        phase: 'initial',
        loopIteration: 0,
        screenContextLabel: screenContextLabel,
      );

      if (gen != _cancelGeneration) return;
      thinkSw.stop();

      final parsedThinking = _parseStringList(result['thinking']);
      final subMap = result['subagent'];
      final subagent = subMap is Map
          ? OvaSubagentBadge.fromMap(Map<String, dynamic>.from(subMap))
          : OvaSubagentBadge(
              id: state.selectedMode.wireValue,
              label: state.selectedMode.label,
              role: state.selectedMode.subtitle,
            );

      final plan = (result['plan'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((m) => OvaAgentPlanStep.fromMap(Map<String, dynamic>.from(m)))
          .toList();

      final rawTools = (result['toolCalls'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();

      final toolCalls = rawTools
          .where((m) {
            final wireStatus = m['status']?.toString();
            final isServerExecuted =
                wireStatus == 'completed' || wireStatus == 'error';
            return isServerExecuted || state.workstationOnline;
          })
          .map((m) {
            final wireStatus = m['status']?.toString();
            final isServerCompleted = wireStatus == 'completed';
            final isServerError = wireStatus == 'error';
            final needsApproval = !isServerCompleted &&
                !isServerError &&
                !state.fullComputerAccess &&
                (m['risk']?.toString() == 'approval_required' ||
                    m['requiresApproval'] == true);
            final resolvedStatus = isServerCompleted
                ? OvaToolCallStatus.completed
                : isServerError
                    ? OvaToolCallStatus.error
                    : (needsApproval
                        ? OvaToolCallStatus.awaitingApproval
                        : OvaToolCallStatus.pendingMac);
            return OvaAgentToolCall(
              id: (m['id'] ?? 'tc_${DateTime.now().microsecondsSinceEpoch}')
                  .toString(),
              name: (m['name'] ?? 'inspect_workstation').toString(),
              title:
                  (m['title'] ?? m['name'] ?? 'Agent action').toString(),
              args: m['args'] is Map
                  ? Map<String, dynamic>.from(m['args'] as Map)
                  : const {},
              requiresApproval: needsApproval,
              status: resolvedStatus,
              output: m['output']?.toString(),
              durationMs: (m['durationMs'] as num?)?.toInt(),
            );
          })
          .toList();

      final artifacts = (result['artifacts'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((m) => OvaAgentArtifact.fromMap(Map<String, dynamic>.from(m)))
          .toList();

      final followUps = _parseStringList(result['followUps']);
      final reply = (result['reply'] ?? '').toString().trim();

      final hasApprovalGate = toolCalls
          .any((tc) => tc.status == OvaToolCallStatus.awaitingApproval);
      final hasPendingTools = toolCalls.any((tc) => !tc.status.isTerminal);

      final nextTurnStatus = hasApprovalGate
          ? 'awaiting_approval'
          : (hasPendingTools ? 'running_tools' : 'completed');
      final nextSessionStatus = hasApprovalGate
          ? 'awaiting_approval'
          : (hasPendingTools ? 'running_tools' : 'idle');

      final updatedAssistant = OvaAgentTurn(
        id: assistantTurnId,
        createdAtMs: nowMs + 1,
        role: 'assistant',
        originDevice: origin,
        authorLabel: subagent.label,
        text: reply,
        status: nextTurnStatus,
        thinkingSteps: parsedThinking,
        thinkingDurationMs: thinkSw.elapsedMilliseconds,
        subagent: subagent,
        toolCalls: toolCalls,
        artifacts: artifacts,
        followUps: followUps,
        createdAt: placeholderAssistant.createdAt,
      );

      await _writeDoc(
        '$base/$sessionId/turns/$assistantTurnId',
        updatedAssistant.toFirestoreMap(),
        merge: true,
      );

      final updatedMs = DateTime.now().millisecondsSinceEpoch;
      await _writeDoc(
        '$base/$sessionId',
        {
          'status': nextSessionStatus,
          'activeSubagent': subagent.label,
          'plan': plan.map((p) => p.toMap()).toList(),
          'lastPreview': _cleanPreview(reply.isNotEmpty ? reply : prompt),
          'updatedAtMs': updatedMs,
          'updatedAt': DateTime.now().toUtc(),
        },
        merge: true,
      );

      if (!hasPendingTools && !_isDesktop && reply.isNotEmpty) {
        unawaited(
          _mirrorToMobileHistory(prompt, reply, sessionId, sessionTitle),
        );
      }

      if (artifacts.isNotEmpty && state.inspectedArtifact == null) {
        state = state.copyWith(inspectedArtifact: artifacts.first);
      }

      if (_isDesktop &&
          hasPendingTools &&
          !hasApprovalGate &&
          state.workstationDeviceId != null) {
        unawaited(
          _executeMacToolsForTurn(
            deviceId: state.workstationDeviceId!,
            sessionId: sessionId,
            turn: updatedAssistant,
          ),
        );
      }
    } catch (e) {
      debugPrint('[OvaAgentSync] Turn error, invoking local synthesis: $e');
      thinkSw.stop();
      final fallbackText = await _buildResilientFallback(prompt);
      await _writeDoc(
        '$base/$sessionId/turns/$assistantTurnId',
        {
          'status': 'completed',
          'text': fallbackText,
          'thinkingSteps': [
            'Cloud agent endpoint reported: $e',
            'Synthesized resilient response locally.',
          ],
          'thinkingDurationMs': thinkSw.elapsedMilliseconds,
          'updatedAt': DateTime.now().toUtc(),
        },
        merge: true,
      );
      await _writeDoc(
        '$base/$sessionId',
        {
          'status': 'idle',
          'lastPreview': _cleanPreview(fallbackText),
          'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
          'updatedAt': DateTime.now().toUtc(),
        },
        merge: true,
      );
    } finally {
      if (gen == _cancelGeneration) {
        state = state.copyWith(sending: false);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Human-in-the-Loop Tool Approval (Works Live from Mobile OR Desktop!)
  // ---------------------------------------------------------------------------

  Future<void> decideToolApproval({
    required String sessionId,
    required OvaAgentTurn turn,
    required String toolCallId,
    required bool approved,
  }) async {
    final base = _boundBaseCollectionPath;
    if (base == null) return;

    final approver = _isDesktop ? 'Mac' : 'Mobile';
    final updatedCalls = turn.toolCalls.map((tc) {
      if (tc.id != toolCallId) return tc;
      return tc.copyWith(
        status:
            approved ? OvaToolCallStatus.approved : OvaToolCallStatus.denied,
        approvedBy: approver,
        output: approved ? null : 'Denied by user on $approver.',
      );
    }).toList();

    final stillWaitingApproval = updatedCalls
        .any((tc) => tc.status == OvaToolCallStatus.awaitingApproval);
    final anyRunnable = updatedCalls.any((tc) =>
        tc.status == OvaToolCallStatus.approved ||
        tc.status == OvaToolCallStatus.pendingMac);

    final nextStatus = stillWaitingApproval
        ? 'awaiting_approval'
        : (anyRunnable ? 'running_tools' : 'completed');

    await _writeDoc(
      '$base/$sessionId/turns/${turn.id}',
      {
        'toolCalls': updatedCalls.map((t) => t.toMap()).toList(),
        'status': nextStatus,
        'updatedAt': DateTime.now().toUtc(),
      },
      merge: true,
    );

    await _writeDoc(
      '$base/$sessionId',
      {
        'status': nextStatus == 'completed' ? 'idle' : nextStatus,
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
        'updatedAt': DateTime.now().toUtc(),
      },
      merge: true,
    );

    if (_isDesktop && anyRunnable && state.workstationDeviceId != null) {
      final refreshedTurn = OvaAgentTurn(
        id: turn.id,
        createdAtMs: turn.createdAtMs,
        role: turn.role,
        originDevice: turn.originDevice,
        authorLabel: turn.authorLabel,
        text: turn.text,
        status: nextStatus,
        thinkingSteps: turn.thinkingSteps,
        thinkingDurationMs: turn.thinkingDurationMs,
        subagent: turn.subagent,
        toolCalls: updatedCalls,
        artifacts: turn.artifacts,
        followUps: turn.followUps,
        createdAt: turn.createdAt,
      );
      unawaited(
        _executeMacToolsForTurn(
          deviceId: state.workstationDeviceId!,
          sessionId: sessionId,
          turn: refreshedTurn,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Desktop Automatic Tool Execution & Multi-Round Autonomous Agentic Loop
  // ---------------------------------------------------------------------------

  Future<void> _sweepDesktopPendingTools(
    String deviceId,
    List<OvaAgentSession> sessions,
  ) async {
    if (!_isDesktop || _desktopSweepInFlight) return;
    final candidates = sessions.where(
      (s) => s.status == 'running_tools' || s.status == 'awaiting_approval',
    );
    if (candidates.isEmpty) return;

    _desktopSweepInFlight = true;
    try {
      for (final session in candidates) {
        try {
          final List<OvaAgentTurn> turns;
          if (session.id == _desktopTurnsSnapshotSessionId &&
              session.id == _boundTurnsSessionId) {
            // Already kept fresh by the turns poller — no extra read.
            turns = state.turns;
          } else {
            final now = DateTime.now();
            final last = _desktopSweepListedAt[session.id];
            if (last != null && now.difference(last) < _desktopSweepListGap) {
              continue;
            }
            _desktopSweepListedAt[session.id] = now;
            turns = await _listTurnDocs(session.id);
          }
          for (final turn in turns) {
            final hasRunnable = turn.toolCalls.any(
              (tc) =>
                  tc.status == OvaToolCallStatus.pendingMac ||
                  tc.status == OvaToolCallStatus.approved,
            );
            if (hasRunnable) {
              // Per-turn locks stop duplicates; don't let one long tool run
              // hold up the sweep of other sessions.
              unawaited(
                _executeMacToolsForTurn(
                  deviceId: deviceId,
                  sessionId: session.id,
                  turn: turn,
                ),
              );
            }
          }
        } catch (e) {
          debugPrint('[OvaAgentSync] Sweep notice (${session.id}): $e');
        }
      }
    } finally {
      _desktopSweepInFlight = false;
    }
  }

  Future<void> _executeMacToolsForTurn({
    required String deviceId,
    required String sessionId,
    required OvaAgentTurn turn,
  }) async {
    final lockKey = '$sessionId/${turn.id}';
    if (!_executingTurnLocks.add(lockKey)) return;

    final base = _boundBaseCollectionPath ??
        _resolveOrCreateBasePath() ??
        'registered_computers/$deviceId/agent_sessions';
    final sessionMeta =
        state.sessions.where((s) => s.id == sessionId).firstOrNull;
    final autonomous =
        sessionMeta?.fullComputerAccess ?? state.fullComputerAccess;

    try {
      var calls = [...turn.toolCalls];
      var thinkingSteps = [...turn.thinkingSteps];
      var artifacts = [...turn.artifacts];
      var followUps = [...turn.followUps];
      var currentReply = turn.text;
      List<OvaAgentPlanStep>? latestPlan = sessionMeta?.plan;
      int loopIteration = 0;

      while (loopIteration < 3) {
        bool executedAnyThisPass = false;

        for (var i = 0; i < calls.length; i++) {
          final tc = calls[i];
          if (tc.status != OvaToolCallStatus.pendingMac &&
              tc.status != OvaToolCallStatus.approved) {
            continue;
          }

          recordLiveActionEvent(
            category: tc.name.contains('mouse')
                ? 'mouse'
                : (tc.name.contains('key') || tc.name.contains('type')
                    ? 'keyboard'
                    : 'agent'),
            summary: 'Running ${tc.name}: ${tc.title}',
          );

          calls[i] = tc.copyWith(status: OvaToolCallStatus.running);
          await _writeDoc(
            '$base/$sessionId/turns/${turn.id}',
            {
              'status': 'running_tools',
              'toolCalls': calls.map((c) => c.toMap()).toList(),
              'updatedAt': DateTime.now().toUtc(),
            },
            merge: true,
          );

          final execRes = await OvaAgentMacExecutor.instance.execute(tc);
          calls[i] = calls[i].copyWith(
            status: execRes.ok
                ? OvaToolCallStatus.completed
                : OvaToolCallStatus.error,
            output: execRes.output,
            exitCode: execRes.exitCode,
            durationMs: execRes.durationMs,
          );
          executedAnyThisPass = true;

          await _writeDoc(
            '$base/$sessionId/turns/${turn.id}',
            {
              'toolCalls': calls.map((c) => c.toMap()).toList(),
              'updatedAt': DateTime.now().toUtc(),
            },
            merge: true,
          );
        }

        if (!executedAnyThisPass) break;

        final stillPendingApproval = calls.any(
          (tc) => tc.status == OvaToolCallStatus.awaitingApproval,
        );
        if (stillPendingApproval) {
          await _writeDoc(
            '$base/$sessionId/turns/${turn.id}',
            {'status': 'awaiting_approval', 'updatedAt': DateTime.now().toUtc()},
            merge: true,
          );
          await _writeDoc(
            '$base/$sessionId',
            {'status': 'awaiting_approval', 'updatedAt': DateTime.now().toUtc()},
            merge: true,
          );
          return;
        }

        loopIteration++;
        final canContinueAgenticLoop = autonomous && loopIteration < 3;

        await _writeDoc(
          '$base/$sessionId/turns/${turn.id}',
          {'status': 'synthesizing', 'updatedAt': DateTime.now().toUtc()},
          merge: true,
        );
        await _writeDoc(
          '$base/$sessionId',
          {'status': 'synthesizing', 'updatedAt': DateTime.now().toUtc()},
          merge: true,
        );

        final allTurns = await _listTurnDocs(sessionId);
        final toolDigest = calls
            .map(
              (c) =>
                  'TOOL ${c.name} (${c.status.wireValue}, ${c.durationMs ?? 0}ms):\n${c.output ?? ""}',
            )
            .join('\n\n---\n\n');

        final nextPhase =
            canContinueAgenticLoop ? 'agentic_continue' : 'post_tool_synthesis';

        final synthMessages = [
          ..._buildModelMessages(
            priorTurns: allTurns.where((t) => t.id != turn.id).toList(),
            extraContextChips: const [],
          ),
          {
            'role': 'user',
            'content': canContinueAgenticLoop
                ? 'Live tool outputs from ${Platform.localHostname} (Autonomous Round $loopIteration/3):\n\n$toolDigest\n\nIf another workstation action is needed to complete or verify the user request, emit the next toolCalls; otherwise return toolCalls: [] and provide the complete final reply.'
                : 'The workstation finished running all requested tools on ${Platform.localHostname}:\n\n$toolDigest\n\nProvide the final synthesis, mark completed plan steps, and include any helpful artifacts.',
          },
        ];

        try {
          final synth = await _invokeAgentCloudFunction(
            messages: synthMessages,
            phase: nextPhase,
            loopIteration: loopIteration,
            fullComputerAccessOverride: autonomous,
          );

          final moreThinking = _parseStringList(synth['thinking']);
          if (moreThinking.isNotEmpty) {
            thinkingSteps = [
              ...thinkingSteps,
              ...moreThinking.where((s) => !thinkingSteps.contains(s)),
            ].take(12).toList();
          }

          final r = (synth['reply'] ?? '').toString().trim();
          if (r.isNotEmpty) currentReply = r;

          final arts = (synth['artifacts'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map((m) => OvaAgentArtifact.fromMap(Map<String, dynamic>.from(m)))
              .toList();
          if (arts.isNotEmpty) {
            artifacts = [...artifacts, ...arts];
          }

          final fups = _parseStringList(synth['followUps']);
          if (fups.isNotEmpty) followUps = fups;

          final rawPlan = synth['plan'] as List<dynamic>?;
          if (rawPlan != null && rawPlan.isNotEmpty) {
            latestPlan = rawPlan
                .whereType<Map>()
                .map((m) => OvaAgentPlanStep.fromMap(Map<String, dynamic>.from(m)))
                .toList();
          }

          final nextRawTools =
              (synth['toolCalls'] as List<dynamic>? ?? const [])
                  .whereType<Map>()
                  .map((m) => Map<String, dynamic>.from(m))
                  .toList();

          if (canContinueAgenticLoop && nextRawTools.isNotEmpty) {
            final nextBatch = nextRawTools.map((m) {
              final wireStatus = m['status']?.toString();
              final isServerCompleted = wireStatus == 'completed';
              final isServerError = wireStatus == 'error';
              final needsApproval = !isServerCompleted &&
                  !isServerError &&
                  !autonomous &&
                  (m['risk']?.toString() == 'approval_required' ||
                      m['requiresApproval'] == true);
              final resolvedStatus = isServerCompleted
                  ? OvaToolCallStatus.completed
                  : isServerError
                      ? OvaToolCallStatus.error
                      : (needsApproval
                          ? OvaToolCallStatus.awaitingApproval
                          : OvaToolCallStatus.pendingMac);
              return OvaAgentToolCall(
                id: (m['id'] ?? 'tc_${DateTime.now().microsecondsSinceEpoch}')
                    .toString(),
                name: (m['name'] ?? 'inspect_workstation').toString(),
                title:
                    (m['title'] ?? m['name'] ?? 'Autonomous step').toString(),
                args: m['args'] is Map
                    ? Map<String, dynamic>.from(m['args'] as Map)
                    : const {},
                requiresApproval: needsApproval,
                status: resolvedStatus,
                output: m['output']?.toString(),
                durationMs: (m['durationMs'] as num?)?.toInt(),
              );
            }).toList();

            calls = [...calls, ...nextBatch];
            await _writeDoc(
              '$base/$sessionId/turns/${turn.id}',
              {
                'status': 'running_tools',
                'thinkingSteps': thinkingSteps,
                'toolCalls': calls.map((c) => c.toMap()).toList(),
                'updatedAt': DateTime.now().toUtc(),
              },
              merge: true,
            );
            continue;
          }
        } catch (e) {
          debugPrint('[OvaAgentSync] Post-tool synthesis fallback: $e');
          currentReply =
              '${currentReply.isNotEmpty ? "$currentReply\n\n" : ""}Executed ${calls.length} workstation tool(s) on `${Platform.localHostname}`.';
        }
        break;
      }

      await _writeDoc(
        '$base/$sessionId/turns/${turn.id}',
        {
          'status': 'completed',
          'text': currentReply,
          'thinkingSteps': thinkingSteps,
          'toolCalls': calls.map((c) => c.toMap()).toList(),
          'artifacts': artifacts.map((a) => a.toMap()).toList(),
          'followUps': followUps,
          'updatedAt': DateTime.now().toUtc(),
        },
        merge: true,
      );

      final completedPlan = latestPlan ??
          (sessionMeta?.plan
                  .map((p) => p.copyWith(status: OvaPlanStepStatus.completed))
                  .toList() ??
              const []);

      await _writeDoc(
        '$base/$sessionId',
        {
          'status': 'idle',
          'plan': completedPlan.map((p) => p.toMap()).toList(),
          'lastPreview': _cleanPreview(currentReply),
          'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
          'updatedAt': DateTime.now().toUtc(),
        },
        merge: true,
      );
    } finally {
      _executingTurnLocks.remove(lockKey);
    }
  }

  // ---------------------------------------------------------------------------
  // Cloud Function & Firestore Transport Abstraction
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _invokeAgentCloudFunction({
    required List<Map<String, String>> messages,
    required String phase,
    String? fallbackPrompt,
    int loopIteration = 0,
    bool? fullComputerAccessOverride,
    String? screenContextLabel,
  }) async {
    final payload = <String, dynamic>{
      'mode': 'agent_turn',
      'messages': messages,
      if (fallbackPrompt != null && fallbackPrompt.isNotEmpty)
        'prompt': fallbackPrompt,
      'agentMode': state.selectedMode.wireValue,
      'effort': state.selectedEffort.wireValue,
      'originDevice': _isDesktop ? 'mac' : 'mobile',
      'phase': phase,
      'loopIteration': loopIteration,
      'fullComputerAccess':
          fullComputerAccessOverride ?? state.fullComputerAccess,
      if (state.webSearchEnabled) 'webSearch': true,
      if (state.workstationDeviceId != null)
        'deviceId': state.workstationDeviceId,
      if (screenContextLabel != null && screenContextLabel.isNotEmpty)
        'screenContextLabel': screenContextLabel,
      'workstationContext': {
        'connected': state.workstationOnline,
        'computerName': state.workstationName ?? 'Unlinked',
        'os': _isDesktop ? Platform.operatingSystem : 'macos',
        'activeWindow': state.workstationActiveWindow ?? 'Desktop',
        'workspaceCwd': _isDesktop ? Directory.current.path : '~',
        'telemetry': state.workstationTelemetry,
      },
    };

    if (_isDesktop) {
      return _desktopCloud.callCallable(
        'ovaAgentExecuteTurn',
        payload,
        timeout: const Duration(seconds: 75),
      );
    }

    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable(
      'ovaAgentExecuteTurn',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 75)),
    );
    final res = await callable.call<dynamic>(payload);
    final data = res.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw StateError('Unexpected agent payload format.');
  }

  String? _resolveOrCreateBasePath() {
    if (_boundBaseCollectionPath != null) return _boundBaseCollectionPath;
    if (_isDesktop) {
      final uid = _desktopCloud.currentUid;
      if (uid != null && uid.isNotEmpty) {
        final path = 'users/$uid/agent_sessions';
        _boundBaseCollectionPath = path;
        return path;
      }
      if (state.workstationDeviceId != null) {
        final path =
            'registered_computers/${state.workstationDeviceId}/agent_sessions';
        _boundBaseCollectionPath = path;
        return path;
      }
    }
    if (_firebaseReady) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        final path = 'users/$uid/agent_sessions';
        _boundBaseCollectionPath = path;
        _bindMobileSessionsCollection(path);
        return path;
      }
    }
    return null;
  }

  Future<void> _writeDoc(
    String docPath,
    Map<String, dynamic> data, {
    bool merge = true,
  }) async {
    if (_isDesktop) {
      await _desktopCloud.setDocument(docPath, data, merge: merge);
    } else {
      await FirebaseFirestore.instance
          .doc(docPath)
          .set(data, SetOptions(merge: merge));
    }
  }

  Future<void> _deleteDoc(String docPath) async {
    if (_isDesktop) {
      await _desktopCloud.deleteDocument(docPath);
    } else {
      await FirebaseFirestore.instance.doc(docPath).delete();
    }
  }

  Future<List<OvaAgentTurn>> _listTurnDocs(String sessionId) async {
    final base = _boundBaseCollectionPath;
    if (base == null) return const [];
    final path = '$base/$sessionId/turns';
    if (_isDesktop) {
      final docs = await _desktopCloud.listDocuments(path, pageSize: 120);
      return docs.map((d) => OvaAgentTurn.fromMap(d.id, d.data)).toList()
        ..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
    }
    final snap =
        await FirebaseFirestore.instance.collection(path).limit(120).get();
    return snap.docs
        .map((d) => OvaAgentTurn.fromMap(d.id, d.data()))
        .toList()
      ..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
  }

  List<Map<String, String>> _buildModelMessages({
    required List<OvaAgentTurn> priorTurns,
    required List<String> extraContextChips,
  }) {
    final out = <Map<String, String>>[];
    for (final t in priorTurns) {
      if (t.text.trim().isEmpty && t.toolCalls.isEmpty) continue;
      if (t.isUser) {
        final ctxPrefix = t.contextChips.isNotEmpty
            ? '[Context: ${t.contextChips.join(" | ")}]\n'
            : '';
        out.add({'role': 'user', 'content': '$ctxPrefix${t.text}'});
      } else {
        final toolsSummary = t.toolCalls.isNotEmpty
            ? '\n[Executed Tools: ${t.toolCalls.map((c) => "${c.name}=${c.status.wireValue}").join(", ")}]'
            : '';
        out.add({'role': 'assistant', 'content': '${t.text}$toolsSummary'});
      }
    }
    if (extraContextChips.isNotEmpty &&
        out.isNotEmpty &&
        out.last['role'] == 'user') {
      out[out.length - 1] = {
        'role': 'user',
        'content':
            '[Attached Context: ${extraContextChips.join(" | ")}]\n${out.last['content']}',
      };
    }
    return out;
  }

  Future<String> _buildResilientFallback(String prompt) async {
    if (!_isDesktop) {
      try {
        final brain = ref.read(aiBrainProvider);
        final res = await brain.processRequest([
          {'role': 'user', 'content': prompt},
        ]);
        if (res is AiTextResponse && res.text.trim().isNotEmpty) {
          return res.text.trim();
        }
      } catch (_) {}
    }
    return 'I recorded your instruction (`$prompt`). Check your network connection or workstation pairing to continue live multi-step execution.';
  }

  Future<void> _mirrorToMobileHistory(
    String prompt,
    String reply,
    String sessionId,
    String sessionTitle,
  ) async {
    try {
      await ref.read(ovaSharedHistoryProvider.notifier).recordTurn(
            query: prompt,
            response: reply,
            source: OvaOriginSource.main,
            threadId: sessionId,
            threadTitle: sessionTitle,
          );
    } catch (_) {}
  }

  static List<String> _parseStringList(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static String _deriveTitle(String prompt) {
    final oneLine = prompt.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.length <= 48) return oneLine;
    return '${oneLine.substring(0, 48)}…';
  }

  static String _cleanPreview(String raw) {
    final clean = raw.replaceAll(RegExp(r'[#*_`\n]+'), ' ').trim();
    if (clean.length <= 96) return clean;
    return '${clean.substring(0, 96)}…';
  }
}
