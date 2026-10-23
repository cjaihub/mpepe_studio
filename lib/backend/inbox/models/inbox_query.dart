import 'package:cloud_firestore/cloud_firestore.dart';

class InboxQuery {
  final String? platformId;
  final String? channelType;
  final bool? unread;
  final String? priority;
  final bool? needsReply;
  final String? assignedTo;
  final String? searchQuery;
  final String? sortField;
  final bool descending;
  final DateTime? startDate;
  final DateTime? endDate;
  final int limit;
  final DocumentSnapshot? startAfter;

  const InboxQuery({
    this.platformId,
    this.channelType,
    this.unread,
    this.priority,
    this.needsReply,
    this.assignedTo,
    this.searchQuery,
    this.sortField = 'updatedAt',
    this.descending = true,
    this.startDate,
    this.endDate,
    this.limit = 50,
    this.startAfter,
  });

  InboxQuery copyWith({
    String? platformId,
    String? channelType,
    bool? unread,
    String? priority,
    bool? needsReply,
    String? assignedTo,
    String? searchQuery,
    String? sortField,
    bool? descending,
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
    DocumentSnapshot? startAfter,
  }) {
    return InboxQuery(
      platformId: platformId ?? this.platformId,
      channelType: channelType ?? this.channelType,
      unread: unread ?? this.unread,
      priority: priority ?? this.priority,
      needsReply: needsReply ?? this.needsReply,
      assignedTo: assignedTo ?? this.assignedTo,
      searchQuery: searchQuery ?? this.searchQuery,
      sortField: sortField ?? this.sortField,
      descending: descending ?? this.descending,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      limit: limit ?? this.limit,
      startAfter: startAfter ?? this.startAfter,
    );
  }
}
