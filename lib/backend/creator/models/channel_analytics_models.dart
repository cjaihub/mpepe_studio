class ChannelAnalyticsOverview {
  final int totalViews;
  final int reach;
  final Duration totalWatchTime;
  final int totalFollowers;
  final int totalLikes;
  final int totalComments;
  final int totalShares;
  final int totalSaves;
  final int profileVisits;
  final int followsGenerated;
  final double estimatedRevenue;

  const ChannelAnalyticsOverview({
    required this.totalViews,
    required this.reach,
    required this.totalWatchTime,
    required this.totalFollowers,
    required this.totalLikes,
    required this.totalComments,
    required this.totalShares,
    required this.totalSaves,
    required this.profileVisits,
    required this.followsGenerated,
    required this.estimatedRevenue,
  });
}

class AudienceDemographics {
  final Map<String, double> topRegions; // Region to percentage (e.g., {"US": 0.45})
  final Map<String, double> topLanguages; // e.g., {"en": 0.8}
  final List<String> contentInterests;
  final Map<String, int> activePeriods; // hour/day format to active user count

  const AudienceDemographics({
    required this.topRegions,
    required this.topLanguages,
    required this.contentInterests,
    required this.activePeriods,
  });
}

class VideoComparison {
  final String videoAId;
  final String videoBId;
  final int viewsDiff; // + indicates A > B
  final double retentionDiff; // + indicates A > B
  final String winner;

  const VideoComparison({
    required this.videoAId,
    required this.videoBId,
    required this.viewsDiff,
    required this.retentionDiff,
    required this.winner,
  });
}
