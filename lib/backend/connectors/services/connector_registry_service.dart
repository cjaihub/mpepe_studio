import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/connector_models.dart';

class ConnectorRegistryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // The definitive source of truth for ConnectedAccounts.
  CollectionReference<Map<String, dynamic>> _userConnectors(String userId) {
    return _firestore.collection('users').doc(userId).collection('connected_accounts');
  }

  Future<void> saveConnectedAccount(String userId, ConnectedAccount account) async {
    // We shouldn't save credentials here directly unless it's a secure environment 
    // or handled via Cloud Functions/Secret Manager, but for the architecture canonical record:
    await _userConnectors(userId).doc(account.externalAccountId).set({
      'externalAccountId': account.externalAccountId,
      'platformId': account.platformId,
      'connectorId': account.connectorId,
      'displayName': account.displayName,
      'username': account.username,
      'accountType': account.accountType,
      'status': account.status,
      'capabilities': account.capabilities.map((c) => c.toString().split('.').last).toList(),
      'scopes': account.scopes,
      'connectedAt': account.connectedAt.toIso8601String(),
      'lastValidatedAt': account.lastValidatedAt?.toIso8601String(),
      'lastSyncAt': account.lastSyncAt?.toIso8601String(),
      'reauthRequired': account.reauthRequired,
      'metadata': account.metadata,
      // Credentials omitted from client-readable Firestore
    }, SetOptions(merge: true));
  }

  Stream<List<ConnectedAccount>> watchConnectedAccounts(String userId) {
    return _userConnectors(userId).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return ConnectedAccount(
          externalAccountId: data['externalAccountId'],
          platformId: data['platformId'],
          connectorId: data['connectorId'],
          displayName: data['displayName'],
          username: data['username'],
          accountType: data['accountType'],
          status: data['status'],
          capabilities: (data['capabilities'] as List).map((c) => PlatformCapability.values.firstWhere((e) => e.toString().split('.').last == c)).toList(),
          scopes: List<String>.from(data['scopes'] ?? []),
          connectedAt: DateTime.parse(data['connectedAt']),
          lastValidatedAt: data['lastValidatedAt'] != null ? DateTime.parse(data['lastValidatedAt']) : null,
          lastSyncAt: data['lastSyncAt'] != null ? DateTime.parse(data['lastSyncAt']) : null,
          reauthRequired: data['reauthRequired'] ?? false,
          metadata: data['metadata'] ?? {},
        );
      }).toList();
    });
  }

  Future<void> removeConnectedAccount(String userId, String externalAccountId) async {
    await _userConnectors(userId).doc(externalAccountId).delete();
  }

  /// Returns an in-memory snapshot of connected accounts (populated via [loadAccounts]).
  /// Used by the OmniToolRegistry for synchronous access.
  List<ConnectorSummary> getAllConnectors() => List.unmodifiable(_cachedAccounts);

  final List<ConnectorSummary> _cachedAccounts = [];

  Future<void> loadAccounts(String userId) async {
    final snapshot = await _userConnectors(userId).get();
    _cachedAccounts
      ..clear()
      ..addAll(snapshot.docs.map((doc) {
          final d = doc.data();
          return ConnectorSummary(
            id: d['connectorId'] ?? doc.id,
            platform: d['platformId'] ?? '',
            displayName: d['displayName'] ?? '',
            isConnected: d['status'] == 'connected',
            capabilities: List<String>.from(
              (d['capabilities'] as List<dynamic>?) ?? [],
            ),
          );
        }));
  }
}

/// Lightweight connector summary safe to pass to AI tools (no credentials).
class ConnectorSummary {
  final String id;
  final String platform;
  final String displayName;
  final bool isConnected;
  final List<String> capabilities;

  const ConnectorSummary({
    required this.id,
    required this.platform,
    required this.displayName,
    required this.isConnected,
    required this.capabilities,
  });
}

final connectorRegistryServiceProvider = Provider<ConnectorRegistryService>((ref) {
  return ConnectorRegistryService();
});
