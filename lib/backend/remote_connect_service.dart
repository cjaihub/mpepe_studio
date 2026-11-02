import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:encrypt/encrypt.dart' as enc;
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
  });

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
    );
  }
}

class RemoteConnectState {
  final ConnectionStatus status;
  final String? activeComputerId;
  final List<LinkedComputer> linkedComputers;
  final Map<String, enc.Key> activeKeys;
  final String? errorMessage;

  RemoteConnectState({
    this.status = ConnectionStatus.disconnected,
    this.activeComputerId,
    this.linkedComputers = const [],
    this.activeKeys = const {},
    this.errorMessage,
  });

  RemoteConnectState copyWith({
    ConnectionStatus? status,
    String? activeComputerId,
    List<LinkedComputer>? linkedComputers,
    Map<String, enc.Key>? activeKeys,
    String? errorMessage,
  }) {
    return RemoteConnectState(
      status: status ?? this.status,
      activeComputerId: activeComputerId ?? this.activeComputerId,
      linkedComputers: linkedComputers ?? this.linkedComputers,
      activeKeys: activeKeys ?? this.activeKeys,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class RemoteConnectService extends Notifier<RemoteConnectState> {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  static const _prefsKey = 'linked_computer_tokens';
  static const _keysPrefsKey = 'linked_computer_aes_keys';

  @override
  RemoteConnectState build() {
    _loadLinkedComputers();
    return RemoteConnectState();
  }

  Future<void> _loadLinkedComputers() async {
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
      final map = jsonDecode(keysStr) as Map<String, dynamic>;
      map.forEach((k, v) {
        loadedKeys[k] = enc.Key.fromBase64(v as String);
      });
      state = state.copyWith(activeKeys: loadedKeys);
    }

    if (tokens.isEmpty || Firebase.apps.isEmpty) return;

    // Listen to each token
    for (String token in tokens) {
      _firestore.collection('registered_computers').doc(token).snapshots().listen((snapshot) {
        if (snapshot.exists) {
          final data = snapshot.data();
          if (data != null) {
            final name = data['computer_name'] as String? ?? 'Unknown Computer';
            final isOnline = data['desktop_connected'] as bool? ?? false;
            final isLocked = data['is_locked'] as bool? ?? (data['status'] == 'locked');
            final isSleeping = data['is_sleeping'] as bool? ?? (data['status'] == 'sleep');
            final activeWindow = data['active_window'] as String? ?? data['current_app'] as String? ?? 'Studio Workspace';
            final requiresPasskey = data['requires_passkey'] as bool? ?? true;
            
            _updateComputerInState(LinkedComputer(
              id: token,
              name: name,
              isOnline: isOnline,
              isLocked: isLocked,
              isSleeping: isSleeping,
              activeWindow: activeWindow,
              requiresPasskey: requiresPasskey,
              os: data['os'] as String? ?? '',
              systemInfo: Map<String, dynamic>.from(data['system_info'] as Map? ?? const {}),
            ));
          }
        }
      });
    }
  }

  void _updateComputerInState(LinkedComputer computer) {
    final currentList = List<LinkedComputer>.from(state.linkedComputers);
    final index = currentList.indexWhere((c) => c.id == computer.id);
    if (index >= 0) {
      currentList[index] = computer;
    } else {
      currentList.add(computer);
    }
    state = state.copyWith(linkedComputers: currentList);
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
      
      // Force load it immediately
      final doc = await _firestore.collection('registered_computers').doc(token).get();
      if (doc.exists) {
        final data = doc.data()!;
        final isLocked = data['is_locked'] as bool? ?? (data['status'] == 'locked');
        final isSleeping = data['is_sleeping'] as bool? ?? (data['status'] == 'sleep');
        final activeWindow = data['active_window'] as String? ?? data['current_app'] as String? ?? 'Studio Workspace';
        final requiresPasskey = data['requires_passkey'] as bool? ?? true;

        _updateComputerInState(LinkedComputer(
          id: token,
          name: data['computer_name'] ?? 'New Computer',
          isOnline: data['desktop_connected'] ?? false,
          isLocked: isLocked,
          isSleeping: isSleeping,
          activeWindow: activeWindow,
          requiresPasskey: requiresPasskey,
          os: data['os'] as String? ?? '',
          systemInfo: Map<String, dynamic>.from(data['system_info'] as Map? ?? const {}),
        ));
      }

      state = state.copyWith(status: ConnectionStatus.connected, activeComputerId: token);
    } catch (e) {
      debugPrint('Connection error: $e');
      state = state.copyWith(status: ConnectionStatus.error, errorMessage: e.toString());
    }
  }

  Future<void> unlinkComputer(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tokens = prefs.getStringList(_prefsKey) ?? [];
      tokens.remove(token);
      await prefs.setStringList(_prefsKey, tokens);
      final currentList = List<LinkedComputer>.from(state.linkedComputers)..removeWhere((c) => c.id == token);
      final activeId = state.activeComputerId == token ? null : state.activeComputerId;
      state = state.copyWith(linkedComputers: currentList, activeComputerId: activeId);
    } catch (e) {
      debugPrint('Error unlinking computer: $e');
    }
  }

  Future<String?> sendCommand(String softwareId, String command, Map<String, dynamic> payload) async {
    final activeId = state.activeComputerId;
    if (activeId == null) return null;

    try {
      final sessionRef = _firestore.collection('registered_computers').doc(activeId);
      
      // Encrypt the payload if we have a key
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
        // Fallback for unencrypted for backwards compatibility/testing if key missing
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
    if (state.activeComputerId == null) return null;
    return _firestore
        .collection('registered_computers')
        .doc(state.activeComputerId)
        .collection('commands')
        .doc(commandId)
        .snapshots();
  }

  void setActiveComputer(String id) {
    state = state.copyWith(activeComputerId: id, status: ConnectionStatus.connected);
  }

  Future<String?> unlockWorkstation({String? passkey, String? password}) async {
    final activeId = state.activeComputerId;
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
        'last_unlocked': FieldValue.serverTimestamp(),
      });
    } catch (_) {}

    return cmdId;
  }

  Future<String?> sleepWorkstation() async {
    final activeId = state.activeComputerId;
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
    final activeId = state.activeComputerId;
    if (activeId == null) return null;

    String softwareId = 'system';
    final lower = command.toLowerCase();
    if (lower.contains('render') || lower.contains('timeline') || lower.contains('dr') || lower.contains('pr')) {
      softwareId = 'dr';
    }

    return await sendCommand(softwareId, command, payload ?? {});
  }

  void disconnect() {
    state = state.copyWith(status: ConnectionStatus.disconnected, activeComputerId: null);
  }
}

final remoteConnectProvider = NotifierProvider<RemoteConnectService, RemoteConnectState>(() {
  return RemoteConnectService();
});
