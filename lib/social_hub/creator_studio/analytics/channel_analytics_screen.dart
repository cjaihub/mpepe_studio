import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../backend/creator/models/channel_analytics_models.dart';
import '../../../../backend/creator/services/channel_analytics_service.dart';
import '../../../shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class ChannelAnalyticsScreen extends ConsumerStatefulWidget {
  const ChannelAnalyticsScreen({super.key});

  @override
  ConsumerState<ChannelAnalyticsScreen> createState() => _ChannelAnalyticsScreenState();
}

class _ChannelAnalyticsScreenState extends ConsumerState<ChannelAnalyticsScreen> {
  ChannelAnalyticsOverview? _overview;
  AudienceDemographics? _demographics;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final service = ref.read(channelAnalyticsServiceProvider);
    
    // Attempt to load from Firestore (mock data will return 0s unless populated)
    final overview = await service.getChannelOverview();
    final demo = await service.getAudienceDemographics();

    if (mounted) {
      setState(() {
        _overview = overview;
        _demographics = demo;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: context.bg,
        body: const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),
      );
    }

    final d = _overview!;

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('Channel Analytics', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Overview Grid
            Text('Overview', style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.5,
              children: [
                _buildStatCard('Views', _formatCount(d.totalViews), Icons.visibility),
                _buildStatCard('Reach', _formatCount(d.reach), Icons.cell_tower),
                _buildStatCard('Watch Time (h)', (d.totalWatchTime.inHours).toString(), Icons.timer),
                _buildStatCard('Followers', _formatCount(d.totalFollowers), Icons.people),
                _buildStatCard('Profile Visits', _formatCount(d.profileVisits), Icons.account_circle),
                _buildStatCard('Revenue', '\$${d.estimatedRevenue.toStringAsFixed(2)}', Icons.monetization_on),
              ],
            ),
            const SizedBox(height: 32),

            // Engagement Section
            Text('Engagement Summary', style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMetricCol('Likes', _formatCount(d.totalLikes)),
                  _buildMetricCol('Comments', _formatCount(d.totalComments)),
                  _buildMetricCol('Shares', _formatCount(d.totalShares)),
                  _buildMetricCol('Saves', _formatCount(d.totalSaves)),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Demographics Section
            Text('Audience Demographics', style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (_demographics != null && _demographics!.topRegions.isNotEmpty) ...[
              Text('Top Regions', style: TextStyle(color: context.textSecondary, fontSize: 14)),
              const SizedBox(height: 8),
              ..._demographics!.topRegions.entries.map((e) => _buildBar(e.key, e.value)),
              const SizedBox(height: 16),
            ] else ...[
              Text('Not enough data to show demographics.', style: TextStyle(color: context.textMuted, fontStyle: FontStyle.italic)),
            ],

            const SizedBox(height: 32),
            // Comparison Tools
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  // Opens a dialog or pushes a new screen to compare specific videos
                },
                icon: const Icon(Icons.compare_arrows, color: AppColors.brandBlue),
                label: const Text('Compare Videos', style: TextStyle(color: AppColors.brandBlue)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.brandBlue),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: context.textMuted, size: 14),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(color: context.textSecondary, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildMetricCol(String label, String value) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: context.textSecondary, fontSize: 12)),
      ],
    );
  }

  Widget _buildBar(String label, double percentage) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: context.textPrimary)),
            Text('${(percentage * 100).toInt()}%', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: percentage,
          backgroundColor: context.surfaceMid,
          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.brandBlue),
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return count.toString();
  }
}
