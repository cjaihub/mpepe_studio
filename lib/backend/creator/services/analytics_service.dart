import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/analytics_metrics.dart';

final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return AnalyticsService();
});

class AnalyticsService {
  Future<DashboardAnalytics> getDashboardMetrics(String creatorId, {String period = '7d'}) async {
    // In production, this aggregates from real backend records in BigQuery/Firestore
    await Future.delayed(const Duration(milliseconds: 300));
    
    return DashboardAnalytics(
      creatorId: creatorId,
      totalViews: 1250400,
      totalWatchTime: const Duration(hours: 4500),
      totalFollowers: 145000,
      followerGrowth: 1200,
      totalLikes: 89000,
      totalComments: 4500,
      totalShares: 1200,
      totalSaves: 3400,
      averageCompletionRate: 0.65,
      totalRewatches: 45000,
      estimatedRevenue: 450.25,
      trafficSources: {
        'For You': 0.72,
        'Following': 0.15,
        'Profile': 0.08,
        'External': 0.05,
      },
      audienceDemographics: {
        '18-24': 0.45,
        '25-34': 0.35,
        '35-44': 0.15,
        'Other': 0.05,
      },
      postingActivity: 12,
      topVideoIds: ['post_1', 'post_2'],
      topSoundIds: ['sound_1'],
    );
  }

  Future<VideoAnalytics> getVideoAnalytics(String postId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    
    return VideoAnalytics(
      postId: postId,
      views: 45000,
      likes: 3200,
      comments: 145,
      shares: 89,
      saves: 412,
      firstSecondRetention: 0.88,
      threeSecondRetention: 0.65,
      completionRate: 0.42,
      averageWatchDuration: const Duration(seconds: 14),
      rewatches: 1200,
      followsGenerated: 45,
      profileVisits: 890,
      conversion: 12, // e.g. Series purchases
    );
  }
}
