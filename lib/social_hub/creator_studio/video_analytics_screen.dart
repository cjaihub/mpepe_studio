import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../backend/creator/models/analytics_metrics.dart';
import '../../../backend/creator/services/analytics_service.dart';
import 'package:oneova/shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class VideoAnalyticsScreen extends ConsumerStatefulWidget {
  final String videoId;
  const VideoAnalyticsScreen({super.key, required this.videoId});

  @override
  ConsumerState<VideoAnalyticsScreen> createState() => _VideoAnalyticsScreenState();
}

class _VideoAnalyticsScreenState extends ConsumerState<VideoAnalyticsScreen> {
  VideoAnalytics? _data;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final data = await ref.read(analyticsServiceProvider).getVideoAnalytics(widget.videoId);
    if (mounted) {
      setState(() {
        _data = data;
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

    final d = _data!;

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        title: Text('Video Analytics', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Core Stats
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildMetricCol('Views', _formatCount(d.views)),
                _buildMetricCol('Likes', _formatCount(d.likes)),
                _buildMetricCol('Comments', _formatCount(d.comments)),
                _buildMetricCol('Shares', _formatCount(d.shares)),
              ],
            ),
            const SizedBox(height: 32),

            // Retention Funnel
            Text('Retention Funnel', style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildRetentionBar('First Second', d.firstSecondRetention),
            const SizedBox(height: 12),
            _buildRetentionBar('3-Second', d.threeSecondRetention),
            const SizedBox(height: 12),
            _buildRetentionBar('Completion Rate', d.completionRate),
            const SizedBox(height: 32),

            // Engagement Depth
            Text('Engagement Depth', style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildListTile(Icons.timer, 'Avg. Watch Duration', '${d.averageWatchDuration.inSeconds}s'),
            _buildListTile(Icons.repeat, 'Rewatches', _formatCount(d.rewatches)),
            _buildListTile(Icons.bookmark, 'Saves', _formatCount(d.saves)),
            const SizedBox(height: 32),

            // Conversion
            Text('Conversion Impact', style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildListTile(Icons.person_add, 'Follows Generated', '+${_formatCount(d.followsGenerated)}'),
            _buildListTile(Icons.account_circle, 'Profile Visits', _formatCount(d.profileVisits)),
            _buildListTile(Icons.shopping_cart, 'Series/Product Conversions', _formatCount(d.conversion)),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCol(String label, String value) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: context.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: context.textSecondary, fontSize: 12)),
      ],
    );
  }

  Widget _buildRetentionBar(String label, double rate) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: context.textPrimary)),
            Text('${(rate * 100).toInt()}%', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: rate,
          backgroundColor: context.surfaceMid,
          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.brandBlue),
          minHeight: 12,
          borderRadius: BorderRadius.circular(6),
        ),
      ],
    );
  }

  Widget _buildListTile(IconData icon, String title, String trailing) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: context.textMuted, size: 20),
          const SizedBox(width: 12),
          Text(title, style: TextStyle(color: context.textPrimary)),
          const Spacer(),
          Text(trailing, style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return count.toString();
  }
}
