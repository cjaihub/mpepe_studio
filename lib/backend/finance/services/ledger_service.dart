import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/ledger_models.dart';

final ledgerServiceProvider = Provider<LedgerService>((ref) {
  return LedgerService();
});

final currentBalanceProvider = StreamProvider<double>((ref) {
  return ref.watch(ledgerServiceProvider).streamCalculatedBalance();
});

final ledgerHistoryProvider = StreamProvider<List<LedgerEntry>>((ref) {
  return ref.watch(ledgerServiceProvider).streamLedgerHistory();
});

class LedgerService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _userId => _auth.currentUser?.uid;

  /// Retrieves the ledger history for the current user.
  Stream<List<LedgerEntry>> streamLedgerHistory() {
    final uid = _userId;
    if (uid == null) return const Stream.empty();

    return _firestore
        .collection('ledgers')
        .doc(uid)
        .collection('entries')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) => 
            snapshot.docs.map((doc) => LedgerEntry.fromFirestore(doc)).toList());
  }

  /// Calculates balance dynamically from ledger entries rather than a hard-coded field.
  Stream<double> streamCalculatedBalance() {
    final uid = _userId;
    if (uid == null) return Stream.value(0.0);

    return _firestore
        .collection('ledgers')
        .doc(uid)
        .collection('entries')
        .where('status', isEqualTo: TransactionStatus.settled.name)
        .snapshots()
        .map((snapshot) {
      double balance = 0.0;
      for (final doc in snapshot.docs) {
        final entry = LedgerEntry.fromFirestore(doc);
        if (entry.refundState == RefundState.full) {
          continue; // Refunded transactions don't count towards balance
        }
        
        double effectiveAmount = entry.amount;
        if (entry.refundState == RefundState.partial) {
          // In a real system, partial refunds require a separate contra-entry in the ledger.
          // For simplicity, we assume partial logic is handled via linked contra-entries.
        }

        if (entry.type == TransactionType.credit) {
          balance += effectiveAmount;
        } else if (entry.type == TransactionType.debit) {
          balance -= effectiveAmount;
        }
      }
      return balance;
    });
  }

  /// Appends an entry to the immutable ledger.
  /// Backend functions should ideally write to this ledger, not the client.
  Future<void> logTransaction(LedgerEntry entry) async {
    final uid = _userId;
    if (uid == null) return;
    
    // In production, this client call would trigger a cloud function to ensure non-repudiation.
    await _firestore
        .collection('ledgers')
        .doc(uid)
        .collection('entries')
        .doc(entry.id)
        .set(entry.toMap());
  }
}
