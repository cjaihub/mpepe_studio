import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'telemetry_models.dart';
import '../remote_connect_service.dart';
import '../secure_pairing/crypto_utils.dart';

final telemetryStreamProvider = StreamProvider.autoDispose<TelemetryData?>((ref) {
  final connectState = ref.watch(remoteConnectProvider);
  final activeId = connectState.activeComputerId;
  final activeKey = activeId != null ? connectState.activeKeys[activeId] : null;

  if (activeId == null || activeKey == null) {
    return Stream.value(null);
  }

  return FirebaseFirestore.instance
      .collection('registered_computers')
      .doc(activeId)
      .collection('telemetry')
      .doc('latest')
      .snapshots()
      .map((snapshot) {
    if (!snapshot.exists) return null;
    final data = snapshot.data();
    if (data == null) return null;

    final encrypted = data['payload_encrypted'] as String?;
    if (encrypted != null) {
      final decryptedJson = CryptoUtils.decryptPayload(encrypted, activeKey);
      if (decryptedJson != null) {
        return TelemetryData.fromJson(jsonDecode(decryptedJson));
      }
    }
    return null;
  });
});
