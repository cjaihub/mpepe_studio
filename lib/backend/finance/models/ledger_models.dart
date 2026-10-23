import 'package:cloud_firestore/cloud_firestore.dart';

enum TransactionStatus {
  pending,
  authorized,
  captured,
  settled,
  failed,
  voided,
}

enum RefundState {
  none,
  partial,
  full,
}

enum TransactionType {
  credit,
  debit,
}

class LedgerEntry {
  final String id;
  final String transactionId; // Provider's transaction ID (e.g. Stripe pi_xxx)
  final String userId; // The creator or user who owns this ledger
  final TransactionType type;
  final double amount; // Absolute value. Debit means funds leaving, Credit means funds arriving.
  final String currency;
  final TransactionStatus status;
  final RefundState refundState;
  final String source; // e.g. "subscription", "gift", "premium_series"
  final DateTime createdAt;
  final String? authorizationToken; // Audit reference
  final List<String> auditLog; // History of state changes

  const LedgerEntry({
    required this.id,
    required this.transactionId,
    required this.userId,
    required this.type,
    required this.amount,
    this.currency = 'USD',
    required this.status,
    this.refundState = RefundState.none,
    required this.source,
    required this.createdAt,
    this.authorizationToken,
    this.auditLog = const [],
  });

  factory LedgerEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return LedgerEntry(
      id: doc.id,
      transactionId: data['transactionId'] ?? '',
      userId: data['userId'] ?? '',
      type: TransactionType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => TransactionType.credit,
      ),
      amount: (data['amount'] ?? 0.0).toDouble(),
      currency: data['currency'] ?? 'USD',
      status: TransactionStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => TransactionStatus.pending,
      ),
      refundState: RefundState.values.firstWhere(
        (e) => e.name == data['refundState'],
        orElse: () => RefundState.none,
      ),
      source: data['source'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      authorizationToken: data['authorizationToken'],
      auditLog: List<String>.from(data['auditLog'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'transactionId': transactionId,
      'userId': userId,
      'type': type.name,
      'amount': amount,
      'currency': currency,
      'status': status.name,
      'refundState': refundState.name,
      'source': source,
      'createdAt': createdAt,
      'authorizationToken': authorizationToken,
      'auditLog': auditLog,
    };
  }
}
