import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shared/widgets/oneova_smart_status_banner.dart';
import 'secure_pairing/crypto_utils.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

class LinkedComputer {
  final String id;
  final String name;
  final bool isOnline;
  final bool isLocked;
  final bool isSleeping;
  final String? activeWindow;
  final bool requiresPasskey;
  final String os;
  final Map<String, dynamic> systemInfo;
  final Map<String, dynamic> software;
  final DateTime? lastSeenAt;

  LinkedComputer({
    required this.id,
    required this.name,
    required this.isOnline,
    this.isLocked = false,
    this.isSleeping = false,
    this.activeWindow,
    this.requiresPasskey = false,
    this.os = '',
    this.systemInfo = const {},
    this.software = const {},
    this.lastSeenAt,
  });

  String get deviceId => id;
  String get computerName => name;

  LinkedComputer copyWith({
    String? id,
    String? name,
    bool? isOnline,
    bool? isLocked,
    bool? isSleeping,
    String? activeWindow,
    bool? requiresPasskey,
    String? os,
    Map<String, dynamic>? systemInfo,
    Map<String, dynamic>? software,
    DateTime? lastSeenAt,
  }) {
    return LinkedComputer(
      id: id ?? this.id,
      name: name ?? this.name,
      isOnline: isOnline ?? this.isOnline,
      isLocked: isLocked ?? this.isLocked,
      isSleeping: isSleeping ?? this.isSleeping,
      activeWindow: activeWindow ?? this.activeWindow,
      requiresPasskey: requiresPasskey ?? this.requiresPasskey,
      os: os ?? this.os,
      systemInfo: systemInfo ?? this.systemInfo,
      software: software ?? this.software,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }
}

class RemoteConnectState {
  final ConnectionStatus status;
  final String? activeComputerId;
  final List<LinkedComputer> linkedComputers;
  final Map<String, enc.Key> activeKeys;
  final String? errorMessage;
  final bool isRefreshing;
  final DateTime? lastSyncedAt;

  RemoteConnectState({
    this.status = ConnectionStatus.disconnected,
    this.activeComputerId,
    this.linkedComputers = const [],
    this.activeKeys = const {},
    this.errorMessage,
    this.isRefreshing = false,
    this.lastSyncedAt,
  });

  List<LinkedComputer> get computers => linkedComputers;

  LinkedComputer? get activeComputer {
    if (linkedComputers.isEmpty) return null;
    if (activeComputerId != null) {
      for (final c in linkedComputers) {
        if (c.id == activeComputerId) return c;
      }
    }
    for (final c in linkedComputers) {
      if (c.isOnline) return c;
    }
    return linkedComputers.first;
  }

  RemoteConnectState copyWith({
    ConnectionStatus? status,
    String? activeComputerId,
    List<LinkedComputer>? linkedComputers,
    Map<String, enc.Key>? activeKeys,
    String? errorMessage,
    bool? isRefreshing,
    DateTime? lastSyncedAt,
  }) {
    return RemoteConnectState(
      status: status ?? this.status,
      activeComputerId: activeComputerId ?? this.activeComputerId,
      linkedComputers: linkedComputers ?? this.linkedComputers,
      activeKeys: activeKeys ?? this.activeKeys,
      errorMessage: errorMessage ?? this.errorMessage,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}

class RemoteConnectService extends Notifier<RemoteConnectState> {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  static const _prefsKey = 'linked_computer_tokens';
  static const _keysPrefsKey = 'linked_computer_aes_keys';
  static const int _heartbeatFreshnessSeconds = 75;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ownerComputersSub;
  final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>> _tokenSubs = {};
  final Map<String, Map<String, dynamic>> _rawComputerData = {};
  final Map<String, bool> _previousOnlineByDevice = {};
  Timer? _stalenessTimer;

  @override
  RemoteConnectState build() {
    ref.onDispose(_disposeSubscriptions);
    _initializeListeners();
    return RemoteConnectState();
  }

  void _disposeSubscriptions() {
    _authSub?.cancel();
    _ownerComputersSub?.cancel();
    for (final sub in _tokenSubs.values) {
      sub.cancel();
    }
    _tokenSubs.clear();
    _stalenessTimer?.cancel();
  }

  static DateTime? parseLastSeen(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw);
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    return null;
  }

  static bool computeIsOnline(Map<String, dynamic> data) {
    final connectedFlag =
        (data['desktop_connected'] as bool?) ?? (data['status'] == 'online');
    if (!connectedFlag) return false;
    final statusStr = (data['status'] ?? '').toString().toLowerCase();
    if (statusStr == 'offline') return false;

    final lastSeen = parseLastSeen(data['last_seen']);
    if (lastSeen == null) {
      return connectedFlag;
    }
    final ageSeconds = DateTime.now().difference(lastSeen).inSeconds;
    return ageSeconds < _heartbeatFreshnessSeconds;
  }

  Future<void> _initializeListeners() async {
    await _loadPersistedTokensAndKeys();
    if (Firebase.apps.isEmpty) return;

    _authSub?.cancel();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _subscribeOwnerComputers(user?.uid);
    });
    _subscribeOwnerComputers(FirebaseAuth.instance.currentUser?.uid);

    _stalenessTimer?.cancel();
    _stalenessTimer = Timer.periodic(const Duration(seconds: 18), (_) {
      _rebuildComputersFromRaw();
    });
  }

  void _subscribeOwnerComputers(String? uid) {
    _ownerComputersSub?.cancel();
    _ownerComputersSub = null;
    if (uid == null || uid.isEmpty || Firebase.apps.isEmpty) {
      return;
    }

    _ownerComputersSub = _firestore
        .collection('registered_computers')
        .where('owner_uid', isEqualTo: uid)
        .snapshots()
        .listen(
      (snapshot) {
        final ownerDocIds = <String>{};
        for (final doc in snapshot.docs) {
          ownerDocIds.add(doc.id);
          _rawComputerData[doc.id] = doc.data();
        }
        // Remove deleted owner docs unless explicitly pinned in token subs
        final toRemove = _rawComputerData.keys
            .where((id) => !ownerDocIds.contains(id) && !_tokenSubs.containsKey(id))
            .toList();
        for (final id in toRemove) {
          _rawComputerData.remove(id);
        }
        _rebuildComputersFromRaw();
      },
      onError: (Object e) {
        debugPrint('[RemoteConnect] Owner computers stream error: $e');
      },
    );
  }

  Future<void> _loadPersistedTokensAndKeys() async {
    List<String> tokens = const [];
    String? keysStr;
    try {
      final prefs = await SharedPreferences.getInstance();
      tokens = prefs.getStringList(_prefsKey) ?? [];
      keysStr = prefs.getString(_keysPrefsKey);
    } catch (_) {
      return;
    }

    final loadedKeys = <String, enc.Key>{};
    if (keysStr != null) {
      try {
        final map = jsonDecode(keysStr) as Map<String, dynamic>;
        map.forEach((k, v) {
          loadedKeys[k] = enc.Key.fromBase64(v as String);
        });
        state = state.copyWith(activeKeys: loadedKeys);
      } catch (_) {}
    }

    if (tokens.isEmpty || Firebase.apps.isEmpty) return;

    for (final token in tokens) {
      _watchComputerToken(token);
    }
  }

  void _watchComputerToken(String token) {
    if (_tokenSubs.containsKey(token) || Firebase.apps.isEmpty) return;
    _tokenSubs[token] = _firestore
        .collection('registered_computers')
        .doc(token)
        .snapshots()
        .listen(
      (snapshot) {
        if (snapshot.exists && snapshot.data() != null) {
          _rawComputerData[token] = snapshot.data()!;
        } else {
          _rawComputerData.remove(token);
        }
        _rebuildComputersFromRaw();
      },
      onError: (Object e) {
        debugPrint('[RemoteConnect] Token watch error ($token): $e');
      },
    );
  }

  LinkedComputer _mapComputer(String id, Map<String, dynamic> data) {
    final name = (data['computer_name'] as String?)?.trim().isNotEmpty == true
        ? (data['computer_name'] as String).trim()
        : 'Workstation';
    final isOnline = computeIsOnline(data);
    final isLocked = data['is_locked'] as bool? ?? (data['status'] == 'locked');
    final isSleeping = data['is_sleeping'] as bool? ?? (data['status'] == 'sleep');
    final activeWindow = data['active_window'] as String? ??
        data['current_app'] as String? ??
        'Desktop';
    final requiresPasskey = data['requires_passkey'] as bool? ?? false;
    final lastSeen = parseLastSeen(data['last_seen']);

    return LinkedComputer(
      id: id,
      name: name,
      isOnline: isOnline,
      isLocked: isLocked,
      isSleeping: isSleeping,
      activeWindow: activeWindow,
      requiresPasskey: requiresPasskey,
      os: data['os'] as String? ?? 'macOS',
      systemInfo: Map<String, dynamic>.from(data['system_info'] as Map? ?? const {}),
      software: Map<String, dynamic>.from(data['software'] as Map? ?? const {}),
      lastSeenAt: lastSeen,
    );
  }

  void _rebuildComputersFromRaw() {
    final nextList = <LinkedComputer>[];
    for (final entry in _rawComputerData.entries) {
      final comp = _mapComputer(entry.key, entry.value);
      nextList.add(comp);

      final prevOnline = _previousOnlineByDevice[comp.id];
      if (prevOnline != null && prevOnline != comp.isOnline) {
        OneovaSmartStatus.recordEvent(
          title: comp.isOnline
              ? '${comp.name} Connected'
              : '${comp.name} Offline',
          subtitle: comp.isOnline
              ? 'Active window: ${comp.activeWindow ?? "Desktop"}'
              : 'Waiting for background auto-reconnect heartbeat.',
          kind: comp.isOnline ? OneovaStatusKind.success : OneovaStatusKind.warning,
          source: 'Device Link',
        );
      }
      _previousOnlineByDevice[comp.id] = comp.isOnline;
    }

    nextList.sort((a, b) {
      if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
      final aTime = a.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });

    String? nextActiveId = state.activeComputerId;
    final currentActive = nextActiveId == null
        ? null
        : nextList.where((c) => c.id == nextActiveId).firstOrNull;

    if (currentActive == null || (!currentActive.isOnline && nextList.any((c) => c.isOnline))) {
      final firstOnline = nextList.where((c) => c.isOnline).firstOrNull;
      nextActiveId = firstOnline?.id ?? (nextList.isNotEmpty ? nextList.first.id : null);
    }

    final anyOnline = nextList.any((c) => c.isOnline);
    final nextStatus = anyOnline
        ? ConnectionStatus.connected
        : (nextList.isNotEmpty ? ConnectionStatus.disconnected : state.status);

    state = state.copyWith(
      linkedComputers: nextList,
      activeComputerId: nextActiveId,
      status: nextStatus,
      lastSyncedAt: DateTime.now(),
    );
  }

  /// Forces an immediate server fetch of all account-linked & token-paired workstations.
  Future<void> refreshComputers() async {
    if (Firebase.apps.isEmpty) return;
    state = state.copyWith(isRefreshing: true, errorMessage: null);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        final snap = await _firestore
            .collection('registered_computers')
            .where('owner_uid', isEqualTo: uid)
            .get(const GetOptions(source: Source.serverAndCache));
        for (final doc in snap.docs) {
          _rawComputerData[doc.id] = doc.data();
        }
      }
      for (final token in _tokenSubs.keys.toList()) {
        final doc = await _firestore
            .collection('registered_computers')
            .doc(token)
            .get(const GetOptions(source: Source.serverAndCache));
        if (doc.exists && doc.data() != null) {
          _rawComputerData[token] = doc.data()!;
        }
      }
      _rebuildComputersFromRaw();
    } catch (e) {
      debugPrint('[RemoteConnect] Refresh error: $e');
      state = state.copyWith(errorMessage: e.toString());
    } finally {
      state = state.copyWith(isRefreshing: false, lastSyncedAt: DateTime.now());
    }
  }

  Future<void> linkComputer(String token, {enc.Key? aesKey}) async {
    state = state.copyWith(status: ConnectionStatus.connecting, errorMessage: null);

    try {
      final prefs = await SharedPreferences.getInstance();
      final tokens = prefs.getStringList(_prefsKey) ?? [];

      if (!tokens.contains(token)) {
        tokens.add(token);
        await prefs.setStringList(_prefsKey, tokens);
      }

      if (aesKey != null) {
        final currentKeys = Map<String, enc.Key>.from(state.activeKeys);
        currentKeys[token] = aesKey;

        final mapForPrefs = currentKeys.map((k, v) => MapEntry(k, v.base64));
        await prefs.setString(_keysPrefsKey, jsonEncode(mapForPrefs));

        state = state.copyWith(activeKeys: currentKeys);
      }

      _watchComputerToken(token);

      final doc = await _firestore.collection('registered_computers').doc(token).get();
      if (doc.exists && doc.data() != null) {
        _rawComputerData[token] = doc.data()!;
        _rebuildComputersFromRaw();
      }

      state = state.copyWith(status: ConnectionStatus.connected, activeComputerId: token);
    } catch (e) {
      debugPrint('Connection error: $e');
      state = state.copyWith(status: ConnectionStatus.error, errorMessage: e.toString());
    }
  }

  /// Extracts a 6-digit E2EE session PIN from a QR payload or manual code.
  static String? extractPairingPin(String raw) {
    final trimmed = raw.trim();
    if (RegExp(r'^\d{6}$').hasMatch(trimmed)) {
      return trimmed;
    }
    if (trimmed.startsWith('ONEOVA-PAIR:')) {
      final rest = trimmed.substring('ONEOVA-PAIR:'.length).trim();
      if (RegExp(r'^\d{6}$').hasMatch(rest)) return rest;
      try {
        final decoded = jsonDecode(rest) as Map<String, dynamic>;
        final pin = (decoded['pin'] ?? '').toString().trim();
        if (RegExp(r'^\d{6}$').hasMatch(pin)) return pin;
      } catch (_) {}
    }
    final uri = Uri.tryParse(trimmed);
    if (uri != null) {
      final qpPin = uri.queryParameters['pin']?.trim();
      if (qpPin != null && RegExp(r'^\d{6}$').hasMatch(qpPin)) return qpPin;
    }
    return null;
  }

  /// Completes an E2EE 6-digit PIN or QR session handshake with a Oneova Desktop Agent.
  Future<String> pairWithSessionPin(String rawPinOrQr) async {
    final pin = extractPairingPin(rawPinOrQr);
    if (pin == null) {
      throw Exception('Invalid Oneova pairing code or QR session.');
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Please sign in to Oneova first.');
    }

    final doc = await _firestore.collection('desktop_pairing').doc(pin).get();
    if (!doc.exists || doc.data() == null) {
      throw Exception('Session code expired or not found. Refresh the code on your computer.');
    }

    final data = doc.data()!;
    final salt = (data['salt'] ?? '').toString();
    final computerName = (data['computer_name'] ?? 'Workstation').toString();
    final agentUid = data['agent_uid'] as String?;
    final osName = (data['os'] as String?) ?? 'macOS';

    if (salt.isEmpty) {
      throw Exception('Malformed pairing session.');
    }

    final key = CryptoUtils.deriveKeyFromPin(pin, salt);
    final encryptedUid = CryptoUtils.encryptPayload(user.uid, key);
    final cleanHost = computerName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final deviceId = 'desktop_${user.uid}_$cleanHost';

    await _firestore.collection('registered_computers').doc(deviceId).set({
      'owner_uid': user.uid,
      if (agentUid != null && agentUid.isNotEmpty) 'agent_uid': agentUid,
      'computer_name': computerName,
      'os': osName,
      'desktop_connected': true,
      'status': 'online',
      'is_locked': false,
      'is_sleeping': false,
      'requires_passkey': false,
      'last_seen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _firestore
        .collection('desktop_pairing')
        .doc(pin)
        .collection('responses')
        .doc(user.uid)
        .set({
      'encrypted_uid': encryptedUid,
      'mobile_name': 'Oneova Mobile',
      'timestamp': FieldValue.serverTimestamp(),
    });

    await linkComputer(deviceId, aesKey: key);
    OneovaSmartStatus.recordEvent(
      title: 'Paired with $computerName',
      subtitle: 'Secure E2EE device link established.',
      kind: OneovaStatusKind.success,
      source: 'Pairing',
    );
    return deviceId;
  }

  Future<void> unlinkComputer(String token, {bool deleteFromAccount = false}) async {
    try {
      await _tokenSubs.remove(token)?.cancel();
      final prefs = await SharedPreferences.getInstance();
      final tokens = prefs.getStringList(_prefsKey) ?? [];
      tokens.remove(token);
      await prefs.setStringList(_prefsKey, tokens);

      if (deleteFromAccount && Firebase.apps.isNotEmpty) {
        try {
          await _firestore.collection('registered_computers').doc(token).delete();
        } catch (_) {}
      }

      _rawComputerData.remove(token);
      _previousOnlineByDevice.remove(token);
      final currentList = List<LinkedComputer>.from(state.linkedComputers)
        ..removeWhere((c) => c.id == token);
      final nextActive = state.activeComputerId == token
          ? (currentList.isNotEmpty ? currentList.first.id : null)
          : state.activeComputerId;
      state = state.copyWith(linkedComputers: currentList, activeComputerId: nextActive);
    } catch (e) {
      debugPrint('Error unlinking computer: $e');
    }
  }

  Future<String?> sendCommand(
    String softwareId,
    String command,
    Map<String, dynamic> payload, {
    String? targetComputerId,
  }) async {
    final activeId = targetComputerId ?? state.activeComputerId ?? state.activeComputer?.id;
    if (activeId == null) return null;

    try {
      final sessionRef = _firestore.collection('registered_computers').doc(activeId);

      String encryptedPayload = '';
      final key = state.activeKeys[activeId];
      if (key != null) {
        final payloadJson = jsonEncode(payload);
        encryptedPayload = CryptoUtils.encryptPayload(payloadJson, key);
      }

      final docRef = await sessionRef.collection('commands').add({
        'software_id': softwareId,
        'command': command,
        'payload_encrypted': encryptedPayload,
        'payload': key == null ? payload : null,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending',
      });
      return docRef.id;
    } catch (e) {
      debugPrint('Error sending command: $e');
      return null;
    }
  }

  Stream<DocumentSnapshot>? listenToCommand(String commandId) {
    final targetId = state.activeComputerId ?? state.activeComputer?.id;
    if (targetId == null) return null;
    return _firestore
        .collection('registered_computers')
        .doc(targetId)
        .collection('commands')
        .doc(commandId)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>>? watchCommandHistory({
    String? computerId,
    int limit = 20,
  }) {
    if (Firebase.apps.isEmpty) return null;
    final targetId = computerId ?? state.activeComputerId ?? state.activeComputer?.id;
    if (targetId == null || targetId.isEmpty) return null;
    return _firestore
        .collection('registered_computers')
        .doc(targetId)
        .collection('commands')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots();
  }

  void setActiveComputer(String id) {
    state = state.copyWith(activeComputerId: id, status: ConnectionStatus.connected);
  }

  Future<String?> unlockWorkstation({String? passkey, String? password}) async {
    final activeId = state.activeComputerId ?? state.activeComputer?.id;
    if (activeId == null) return null;

    final cmdId = await sendCommand('system', 'unlock_workstation', {
      'passkey': passkey ?? 'biometric_passkey_verified',
      'password': password,
      'timestamp': DateTime.now().toIso8601String(),
    });

    final currentList = List<LinkedComputer>.from(state.linkedComputers);
    final idx = currentList.indexWhere((c) => c.id == activeId);
    if (idx >= 0) {
      currentList[idx] = currentList[idx].copyWith(
        isLocked: false,
        isSleeping: false,
        isOnline: true,
      );
      state = state.copyWith(linkedComputers: currentList);
    }

    try {
      await _firestore.collection('registered_computers').doc(activeId).update({
        'is_locked': false,
        'is_sleeping': false,
        'desktop_connected': true,
        'status': 'online',
      });
    } catch (_) {}

    return cmdId;
  }

  Future<String?> sleepWorkstation() async {
    final activeId = state.activeComputerId ?? state.activeComputer?.id;
    if (activeId == null) return null;

    final cmdId = await sendCommand('system', 'sleep_workstation', {
      'action': 'sleep',
      'timestamp': DateTime.now().toIso8601String(),
    });

    final currentList = List<LinkedComputer>.from(state.linkedComputers);
    final idx = currentList.indexWhere((c) => c.id == activeId);
    if (idx >= 0) {
      currentList[idx] = currentList[idx].copyWith(
        isSleeping: true,
        isLocked: true,
      );
      state = state.copyWith(linkedComputers: currentList);
    }

    try {
      await _firestore.collection('registered_computers').doc(activeId).update({
        'is_locked': true,
        'is_sleeping': true,
        'status': 'sleep',
      });
    } catch (_) {}

    return cmdId;
  }

  Future<String?> executeComputerCommand(String command, {Map<String, dynamic>? payload}) async {
    final activeId = state.activeComputerId ?? state.activeComputer?.id;
    if (activeId == null) return null;

    String softwareId = 'system';
    final lower = command.toLowerCase();
    if (lower.contains('render') ||
        lower.contains('timeline') ||
        lower.contains('dr') ||
        lower.contains('pr')) {
      softwareId = 'dr';
    }

    return await sendCommand(softwareId, command, payload ?? {});
  }

  void disconnect() {
    state = state.copyWith(status: ConnectionStatus.disconnected);
  }
}

final remoteConnectProvider = NotifierProvider<RemoteConnectService, RemoteConnectState>(() {
  return RemoteConnectService();
});
