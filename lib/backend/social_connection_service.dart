import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SocialConnection {
  final String platform;
  final String accountName;
  final DateTime connectedAt;

  SocialConnection({
    required this.platform,
    required this.accountName,
    required this.connectedAt,
  });

  factory SocialConnection.fromMap(Map<String, dynamic> data) {
    return SocialConnection(
      platform: data['platform'] ?? '',
      accountName: data['accountName'] ?? '',
      connectedAt: (data['connectedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'platform': platform,
      'accountName': accountName,
      'connectedAt': FieldValue.serverTimestamp(),
    };
  }
}

class SocialConnectionService extends AsyncNotifier<List<SocialConnection>> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  Future<List<SocialConnection>> build() async {
    return _loadConnections();
  }

  String get _userId => _auth.currentUser?.uid ?? 'mock_user_123';

  Future<List<SocialConnection>> _loadConnections() async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(_userId)
          .collection('social_connections')
          .get();
          
      final connections = snapshot.docs
          .map((doc) => SocialConnection.fromMap(doc.data()))
          .toList();
          
      return connections;
    } catch (e) {
      // ignore: avoid_print
      print('Error loading connections: $e');
      // Fallback to empty list so UI doesn't break if Firestore fails
      return [];
    }
  }

  Future<void> addConnection(String platform, String accountName) async {
    try {
      final newConnection = SocialConnection(
        platform: platform,
        accountName: accountName,
        connectedAt: DateTime.now(),
      );
      
      await _firestore
          .collection('users')
          .doc(_userId)
          .collection('social_connections')
          .doc(platform.toLowerCase())
          .set(newConnection.toMap());

      final updated = await _loadConnections();
      state = AsyncValue.data(updated);
    } catch (e) {
      // ignore: avoid_print
      print('Error adding connection: $e');
      // If error occurs (e.g. firestore not enabled), mock the state update for the UI demo
      if (state.hasValue) {
         final currentList = state.value!;
         state = AsyncValue.data([...currentList, SocialConnection(
           platform: platform, 
           accountName: accountName, 
           connectedAt: DateTime.now()
         )]);
      }
    }
  }
}

final socialConnectionProvider = AsyncNotifierProvider<SocialConnectionService, List<SocialConnection>>(() {
  return SocialConnectionService();
});
