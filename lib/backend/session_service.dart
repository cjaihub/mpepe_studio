import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Firestore path helpers
// /users/{uid}/sessions/{sessionId}
// /users/{uid}/sessions/{sessionId}/webrtc_signaling/{doc}
// ─────────────────────────────────────────────────────────────────────────────

class OnerovaSession {
  final String id;          // Firestore document ID
  final String ownerUid;
  final String desktopId;   // registered_computers doc ID
  final String desktopName;
  final String mobileName;
  final DateTime pairedAt;
  final String status;      // "connected" | "disconnected"
  final DateTime? lastSeenDesktop;
  final DateTime? lastSeenMobile;

  OnerovaSession({
    required this.id,
    required this.ownerUid,
    required this.desktopId,
    required this.desktopName,
    required this.mobileName,
    required this.pairedAt,
    required this.status,
    this.lastSeenDesktop,
    this.lastSeenMobile,
  });

  factory OnerovaSession.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return OnerovaSession(
      id: doc.id,
      ownerUid: d['owner_uid'] as String? ?? '',
      desktopId: d['desktop_id'] as String? ?? '',
      desktopName: d['desktop_name'] as String? ?? 'Unknown Desktop',
      mobileName: d['mobile_name'] as String? ?? 'Unknown Mobile',
      pairedAt: (d['paired_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: d['status'] as String? ?? 'disconnected',
      lastSeenDesktop: (d['last_seen_desktop'] as Timestamp?)?.toDate(),
      lastSeenMobile: (d['last_seen_mobile'] as Timestamp?)?.toDate(),
    );
  }

  /// Desktop heartbeat is fresh if it was written within the last 60 seconds.
  bool get isDesktopAlive {
    if (lastSeenDesktop == null) return false;
    return DateTime.now().difference(lastSeenDesktop!).inSeconds < 60;
  }

  /// Mobile heartbeat is fresh if it was written within the last 60 seconds.
  bool get isMobileAlive {
    if (lastSeenMobile == null) return false;
    return DateTime.now().difference(lastSeenMobile!).inSeconds < 60;
  }

  bool get isLive => status == 'connected' && isDesktopAlive;

  Map<String, dynamic> toMap() => {
    'owner_uid': ownerUid,
    'desktop_id': desktopId,
    'desktop_name': desktopName,
    'mobile_name': mobileName,
    'paired_at': Timestamp.fromDate(pairedAt),
    'status': status,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Session State
// ─────────────────────────────────────────────────────────────────────────────

class SessionState {
  final OnerovaSession? activeSession;
  final List<OnerovaSession> allSessions;
  final bool isLoading;
  final String? errorMessage;

  const SessionState({
    this.activeSession,
    this.allSessions = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  SessionState copyWith({
    OnerovaSession? activeSession,
    bool clearActiveSession = false,
    List<OnerovaSession>? allSessions,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SessionState(
      activeSession: clearActiveSession ? null : (activeSession ?? this.activeSession),
      allSessions: allSessions ?? this.allSessions,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Session Service
// ─────────────────────────────────────────────────────────────────────────────

class SessionService extends Notifier<SessionState> {
  final _firestore = FirebaseFirestore.instance;
  StreamSubscription<QuerySnapshot>? _sessionsSubscription;
  Timer? _mobileHeartbeatTimer;
  Timer? _heartbeatCheckTimer;

  @override
  SessionState build() {
    ref.onDispose(_dispose);
    _init();
    return const SessionState(isLoading: true);
  }

  void _dispose() {
    _sessionsSubscription?.cancel();
    _mobileHeartbeatTimer?.cancel();
    _heartbeatCheckTimer?.cancel();
  }

  Future<void> _init() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      state = const SessionState();
      return;
    }
    _startSessionListener(user.uid);
    _startHeartbeatChecker();
  }

  // ── Real-time session listener ─────────────────────────────────────────────
  void _startSessionListener(String uid) {
    _sessionsSubscription?.cancel();
    _sessionsSubscription = _firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .where('status', isEqualTo: 'connected')
        .orderBy('paired_at', descending: true)
        .snapshots()
        .listen((snapshot) {
      final sessions = snapshot.docs.map(OnerovaSession.fromDoc).toList();
      final activeSession = sessions.isNotEmpty ? sessions.first : null;

      state = state.copyWith(
        allSessions: sessions,
        activeSession: activeSession,
        isLoading: false,
        clearError: true,
      );

      // Start sending mobile heartbeats once we have an active session
      if (activeSession != null) {
        _startMobileHeartbeat(uid, activeSession.id);
      } else {
        _mobileHeartbeatTimer?.cancel();
      }
    }, onError: (e) {
      debugPrint('[SessionService] Listener error: $e');
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    });
  }

  // ── Mobile heartbeat — keeps the mobile presence alive every 30s ──────────
  void _startMobileHeartbeat(String uid, String sessionId) {
    _mobileHeartbeatTimer?.cancel();
    _sendMobileHeartbeat(uid, sessionId);
    _mobileHeartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _sendMobileHeartbeat(uid, sessionId);
    });
  }

  Future<void> _sendMobileHeartbeat(String uid, String sessionId) async {
    try {
      await _firestore
          .collection('users').doc(uid)
          .collection('sessions').doc(sessionId)
          .update({'last_seen_mobile': FieldValue.serverTimestamp()});
    } catch (e) {
      debugPrint('[SessionService] Heartbeat write failed: $e');
    }
  }

  // ── Heartbeat checker — detects silent desktop death every 15s ────────────
  void _startHeartbeatChecker() {
    _heartbeatCheckTimer?.cancel();
    _heartbeatCheckTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final session = state.activeSession;
      if (session == null) return;
      if (!session.isDesktopAlive) {
        debugPrint('[SessionService] Desktop heartbeat stale — marking disconnected.');
        _markSessionDisconnected(session);
      }
    });
  }

  // ── Create a new session after pairing ────────────────────────────────────
  /// Called by ConnectScreen after validating the 6-digit PIN.
  /// Returns the created session document ID.
  Future<String?> createSession({
    required String desktopId,
    required String desktopName,
    required String mobileName,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      state = state.copyWith(errorMessage: 'You must be signed in to start a session.');
      return null;
    }

    try {
      state = state.copyWith(isLoading: true, clearError: true);

      // Invalidate any pre-existing connected sessions for this desktop
      final existing = await _firestore
          .collection('users').doc(user.uid)
          .collection('sessions')
          .where('desktop_id', isEqualTo: desktopId)
          .where('status', isEqualTo: 'connected')
          .get();
      for (final doc in existing.docs) {
        await doc.reference.update({'status': 'disconnected'});
      }

      // Write new session
      final sessionRef = _firestore
          .collection('users').doc(user.uid)
          .collection('sessions')
          .doc();

      await sessionRef.set({
        'owner_uid': user.uid,
        'desktop_id': desktopId,
        'desktop_name': desktopName,
        'mobile_name': mobileName,
        'paired_at': FieldValue.serverTimestamp(),
        'status': 'connected',
        'last_seen_mobile': FieldValue.serverTimestamp(),
        'last_seen_desktop': FieldValue.serverTimestamp(),
      });

      // Also update the registered_computers doc so the Desktop Agent knows
      // which session to use for signaling.
      await _firestore.collection('registered_computers').doc(desktopId).update({
        'active_session': {
          'session_id': sessionRef.id,
          'owner_uid': user.uid,
          'mobile_name': mobileName,
          'connected_at': FieldValue.serverTimestamp(),
          'status': 'active',
        },
      });

      debugPrint('[SessionService] Created session: ${sessionRef.id}');
      return sessionRef.id;
    } catch (e) {
      debugPrint('[SessionService] createSession error: $e');
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return null;
    }
  }

  // ── Disconnect (with optional Firestore update) ───────────────────────────
  Future<void> disconnectSession({OnerovaSession? session}) async {
    final target = session ?? state.activeSession;
    if (target == null) return;

    await _markSessionDisconnected(target);
  }

  Future<void> _markSessionDisconnected(OnerovaSession session) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _mobileHeartbeatTimer?.cancel();

    try {
      await _firestore
          .collection('users').doc(user.uid)
          .collection('sessions').doc(session.id)
          .update({'status': 'disconnected'});

      // Notify the Desktop Agent as well
      await _firestore
          .collection('registered_computers').doc(session.desktopId)
          .update({'active_session.status': 'disconnected'})
          .catchError((_) {});
    } catch (e) {
      debugPrint('[SessionService] Disconnect error: $e');
    }
  }

  /// Returns the Firestore reference to the WebRTC signaling subcollection
  /// for the current active session.
  CollectionReference? get signalingCollection {
    final user = FirebaseAuth.instance.currentUser;
    final session = state.activeSession;
    if (user == null || session == null) return null;
    return _firestore
        .collection('users').doc(user.uid)
        .collection('sessions').doc(session.id)
        .collection('webrtc_signaling');
  }

  /// Returns the signaling collection for a specific session.
  CollectionReference signalingFor(String uid, String sessionId) {
    return _firestore
        .collection('users').doc(uid)
        .collection('sessions').doc(sessionId)
        .collection('webrtc_signaling');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final sessionProvider = NotifierProvider<SessionService, SessionState>(() {
  return SessionService();
});
