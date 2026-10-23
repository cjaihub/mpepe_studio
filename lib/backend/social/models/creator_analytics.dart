class CreatorAnalytics {
  final int views;
  final Duration watchTime;
  final int followers;
  final int likes;
  final int comments;
  final int shares;
  final int saves;
  final int profileVisits;
  final int follows; // Number of people who followed from content this period
  final double revenue; // Estimated or actual revenue

  const CreatorAnalytics({
    this.views = 0,
    this.watchTime = Duration.zero,
    this.followers = 0,
    this.likes = 0,
    this.comments = 0,
    this.shares = 0,
    this.saves = 0,
    this.profileVisits = 0,
    this.follows = 0,
    this.revenue = 0.0,
  });

  CreatorAnalytics copyWith({
    int? views,
    Duration? watchTime,
    int? followers,
    int? likes,
    int? comments,
    int? shares,
    int? saves,
    int? profileVisits,
    int? follows,
    double? revenue,
  }) {
    return CreatorAnalytics(
      views: views ?? this.views,
      watchTime: watchTime ?? this.watchTime,
      followers: followers ?? this.followers,
      likes: likes ?? this.likes,
      comments: comments ?? this.comments,
      shares: shares ?? this.shares,
      saves: saves ?? this.saves,
      profileVisits: profileVisits ?? this.profileVisits,
      follows: follows ?? this.follows,
      revenue: revenue ?? this.revenue,
    );
  }
}
