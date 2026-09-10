import 'package:flutter_riverpod/flutter_riverpod.dart';

class AnalyticsRepository {
  // Mocking a backend cache to avoid pulling from APIs every time
  Future<Map<String, dynamic>> fetchAnalytics({required String platform, bool forceRefresh = false}) async {
    // In a real app, this would hit the backend:
    // GET /api/analytics?platform=$platform
    // The backend would check its own DB (cache) and only hit YouTube/TikTok APIs if the cache is stale.
    // This secures the API keys and manages usage limitations.
    
    // Simulate network/db delay
    await Future.delayed(const Duration(milliseconds: 800));

    if (platform == 'youtube') {
      return {
        'totalReach': '1.8M',
        'reachChange': '+8%',
        'reachIsPositive': true,
        'avgEngagement': '6.2%',
        'engagementChange': '+1.5%',
        'engagementIsPositive': true,
        'revenue': '\$8,420',
        'revenueChange': '+5%',
        'revenueIsPositive': true,
        'viewsData': [40, 50, 45, 60, 55, 70, 65],
      };
    } else if (platform == 'tiktok') {
      return {
        'totalReach': '600K',
        'reachChange': '+4%',
        'reachIsPositive': true,
        'avgEngagement': '2.3%',
        'engagementChange': '-0.5%',
        'engagementIsPositive': false,
        'revenue': '\$4,100',
        'revenueChange': '-1%',
        'revenueIsPositive': false,
        'viewsData': [30, 35, 30, 45, 40, 50, 45],
      };
    } else {
      // 'all'
      return {
        'totalReach': '2.4M',
        'reachChange': '+12%',
        'reachIsPositive': true,
        'avgEngagement': '8.5%',
        'engagementChange': '+2.1%',
        'engagementIsPositive': true,
        'youtubeRevenue': '\$8,420',
        'tiktokFund': '\$4,100',
        'youtubeViewsData': [40, 50, 45, 60, 55, 70, 65],
        'tiktokViewsData': [30, 35, 30, 45, 40, 50, 45],
      };
    }
  }
}

final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  return AnalyticsRepository();
});
