enum CounterType {
  followers,
  following,
  likes,
  views,
  comments,
  shares,
  saves,
  subscriptions,
  unread,
  notifications,
  analytics,
}

class CounterEntity {
  final String entityId;
  final CounterType type;
  int serverValue; // Authoritative
  int localDelta;  // Optimistic pending change

  CounterEntity({
    required this.entityId,
    required this.type,
    this.serverValue = 0,
    this.localDelta = 0,
  });

  // Derived/Authoritative UI value
  int get displayValue => serverValue + localDelta;
}

class CounterTransaction {
  final String transactionId;
  final String entityId;
  final CounterType type;
  final int increment;
  final DateTime timestamp;

  const CounterTransaction({
    required this.transactionId,
    required this.entityId,
    required this.type,
    required this.increment,
    required this.timestamp,
  });
}
