enum TrialStatus {
  active,
  completed, // Test reached target audience size
  published, // Creator decided to push it live
  discarded, // Creator trashed it
  scheduled,
}

class TestAudienceConfig {
  final int targetViews; // How many people should see it during the test
  final bool followersOnly;
  final List<String> targetDemographics; // e.g., ['18-24', 'US']

  const TestAudienceConfig({
    required this.targetViews,
    this.followersOnly = true,
    this.targetDemographics = const [],
  });
}

class TrialMetrics {
  final int views;
  final Duration watchTime;
  final double completionRate;
  final int likes;
  final int comments;
  final int shares;
  final int follows;
  final double audienceResponseScore; // e.g., 0.0 to 1.0 sentiment or composite score

  const TrialMetrics({
    this.views = 0,
    this.watchTime = Duration.zero,
    this.completionRate = 0.0,
    this.likes = 0,
    this.comments = 0,
    this.shares = 0,
    this.follows = 0,
    this.audienceResponseScore = 0.0,
  });
}

class TrialVideo {
  final String id;
  final String creatorId;
  final String videoUrl;
  final String title;
  final TrialStatus status;
  final TestAudienceConfig config;
  final TrialMetrics metrics;
  final DateTime createdAt;

  // SAFETY: This explicitly marks the content as a trial, preventing standard distribution
  final bool isTrial = true; 

  const TrialVideo({
    required this.id,
    required this.creatorId,
    required this.videoUrl,
    required this.title,
    required this.status,
    required this.config,
    required this.metrics,
    required this.createdAt,
  });
}
