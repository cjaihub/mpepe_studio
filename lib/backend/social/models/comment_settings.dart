enum CommentPermission {
  everyone,
  followers,
  friends,
  nobody,
}

enum CommentSortType {
  top,
  latest,
  creator,
  friends,
}

class CommentSettings {
  final String postId;
  final CommentPermission permission;
  final bool requireApproval;
  final List<String> keywordFilters;
  final List<String> blockedWords;
  final int? commentLimit; 
  final Duration? slowModeDelay; 

  const CommentSettings({
    required this.postId,
    this.permission = CommentPermission.everyone,
    this.requireApproval = false,
    this.keywordFilters = const [],
    this.blockedWords = const [],
    this.commentLimit,
    this.slowModeDelay,
  });
}
