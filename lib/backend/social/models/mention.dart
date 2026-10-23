class Mention {
  final String userId;
  final int start;
  final int end;

  Mention({
    required this.userId,
    required this.start,
    required this.end,
  });

  factory Mention.fromMap(Map<String, dynamic> map) {
    return Mention(
      userId: map['userId'] ?? '',
      start: map['start'] ?? 0,
      end: map['end'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'start': start,
      'end': end,
    };
  }
}
