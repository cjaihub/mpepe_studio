class VideoAnalytics {
  final String postId;
  final int views;
  final int likes;
  final int comments;
  final int shares;
  final int saves;
  
  // Retention & Watch Time
  final double firstSecondRetention; // e.g. 0.85 for 85%
  final double threeSecondRetention;
  final double completionRate;
  final Duration averageWatchDuration;
  final int rewatches;
  
  // Funnel
  final int followsGenerated;
  final int profileVisits;
  final int conversion; // if linked to a product/series

  const VideoAnalytics({
    required this.postId,
    this.views = 0,
    this.likes = 0,
    this.comments = 0,
    this.shares = 0,
    this.saves = 0,
    this.firstSecondRetention = 0.0,
    this.threeSecondRetention = 0.0,
    this.completionRate = 0.0,
    this.averageWatchDuration = Duration.zero,
    this.rewatches = 0,
    this.followsGenerated = 0,
    this.profileVisits = 0,
    this.conversion = 0,
  });
}

class DashboardAnalytics {
  final String creatorId;
  final int totalViews;
  final Duration totalWatchTime;
  final int totalFollowers;
  final int followerGrowth; // e.g. +150 in the period
  final int totalLikes;
  final int totalComments;
  final int totalShares;
  final int totalSaves;
  
  final double averageCompletionRate;
  final int totalRewatches;
  final double estimatedRevenue;

  final Map<String, double> trafficSources; // e.g. 'For You': 0.7, 'Following': 0.2, 'Profile': 0.1
  final Map<String, double> audienceDemographics; // Highly aggregated, e.g. '18-24': 0.4
  final int postingActivity; // Posts in period

  final List<String> topVideoIds;
  final List<String> topSoundIds;

  const DashboardAnalytics({
    required this.creatorId,
    this.totalViews = 0,
    this.totalWatchTime = Duration.zero,
    this.totalFollowers = 0,
    this.followerGrowth = 0,
    this.totalLikes = 0,
    this.totalComments = 0,
    this.totalShares = 0,
    this.totalSaves = 0,
    this.averageCompletionRate = 0.0,
    this.totalRewatches = 0,
    this.estimatedRevenue = 0.0,
    this.trafficSources = const {},
    this.audienceDemographics = const {},
    this.postingActivity = 0,
    this.topVideoIds = const [],
    this.topSoundIds = const [],
  });
}
