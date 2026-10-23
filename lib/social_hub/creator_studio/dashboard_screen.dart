import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../backend/creator/models/analytics_metrics.dart';
import '../../../backend/creator/models/experimentation_models.dart';
import '../../../backend/creator/services/analytics_service.dart';
import '../../../backend/creator/services/experimentation_service.dart';
import 'package:oneova/shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  DashboardAnalytics? _data;
  List<TrialVideo> _activeTrials = [];
  bool _isLoading = true;
  String _period = '7d'; // 7d, 28d, 90d

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final data = await ref.read(analyticsServiceProvider).getDashboardMetrics('me', period: _period);
    final trials = await ref.read(experimentationServiceProvider).getActiveTrials();
    if (mounted) {
      setState(() {
        _data = data;
        _activeTrials = trials;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        title: Text('Creator Studio', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => context.pop(),
        ),
        actions: [
          DropdownButton<String>(
            value: _period,
            dropdownColor: context.surface,
            underline: const SizedBox(),
            icon: Icon(Icons.calendar_today, color: context.textPrimary, size: 16),
            style: TextStyle(color: context.textPrimary),
            items: const [
              DropdownMenuItem(value: '7d', child: Text('Last 7 Days')),
              DropdownMenuItem(value: '28d', child: Text('Last 28 Days')),
              DropdownMenuItem(value: '90d', child: Text('Last 90 Days')),
            ],
            onChanged: (val) {
              if (val != null) {
                _period = val;
                _loadData();
              }
            },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _isLoading
          ? const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOverviewGrid(_data!),
                  const SizedBox(height: 24),
                  if (_activeTrials.isNotEmpty) ...[
                    _buildSectionTitle('Active Trial Videos'),
                    _buildActiveTrials(),
                    const SizedBox(height: 24),
                  ],
                  _buildSectionTitle('Traffic Sources'),
                  _buildTrafficSources(_data!),
                  const SizedBox(height: 24),
                  _buildSectionTitle('Audience Demographics'),
                  _buildDemographics(_data!),
                  const SizedBox(height: 24),
                  _buildSectionTitle('Top Content'),
                  _buildTopContent(_data!),
                ],
              ),
            ),
    );
  }

  Widget _buildActiveTrials() {
    return Column(
      children: _activeTrials.map((t) {
        return Card(
          color: context.surface,
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: const Icon(Icons.science, color: Colors.blue),
            title: Text(t.title, style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
            subtitle: Text('${t.metrics.views} / ${t.config.targetViews} Views (Trial)', style: TextStyle(color: context.textSecondary)),
            trailing: Icon(Icons.chevron_right, color: context.textMuted),
            onTap: () => context.push('/creator_studio/trial/${t.id}'),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Text(
        title,
        style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildOverviewGrid(DashboardAnalytics data) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.5,
      children: [
        _buildStatCard('Views', _formatCount(data.totalViews), Icons.visibility),
        _buildStatCard('Followers', '${_formatCount(data.totalFollowers)} (+${data.followerGrowth})', Icons.group),
        _buildStatCard('Watch Time', '${data.totalWatchTime.inHours}h', Icons.timer),
        _buildStatCard('Completion', '${(data.averageCompletionRate * 100).toStringAsFixed(1)}%', Icons.check_circle_outline),
        _buildStatCard('Engagement', _formatCount(data.totalLikes + data.totalComments + data.totalShares), Icons.bolt),
        _buildStatCard('Est. Revenue', '\$${data.estimatedRevenue.toStringAsFixed(2)}', Icons.attach_money, color: Colors.green),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, {Color? color}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: color ?? context.textMuted, size: 16),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(color: context.textSecondary, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(color: context.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildTrafficSources(DashboardAnalytics data) {
    return Column(
      children: data.trafficSources.entries.map((e) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            children: [
              SizedBox(width: 100, child: Text(e.key, style: TextStyle(color: context.textPrimary))),
              Expanded(
                child: LinearProgressIndicator(
                  value: e.value,
                  backgroundColor: context.surfaceMid,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.brandBlue),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 16),
              Text('${(e.value * 100).toInt()}%', style: TextStyle(color: context.textSecondary)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDemographics(DashboardAnalytics data) {
    // Only show if legally/ethically appropriate and aggregated
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Age Distribution (Aggregated)', style: TextStyle(color: context.textSecondary, fontSize: 12)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: data.audienceDemographics.entries.map((e) {
              return Column(
                children: [
                  Text('${(e.value * 100).toInt()}%', style: TextStyle(color: context.textPrimary, fontSize: 12)),
                  const SizedBox(height: 4),
                  Container(
                    width: 30,
                    height: 100 * e.value,
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(e.key, style: TextStyle(color: context.textSecondary, fontSize: 10)),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopContent(DashboardAnalytics data) {
    return Column(
      children: data.topVideoIds.map((id) {
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 40,
            height: 60,
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(Icons.play_arrow, color: context.textMuted),
          ),
          title: Text('Video $id', style: TextStyle(color: context.textPrimary)),
          subtitle: Text('Top performer this period', style: TextStyle(color: context.textSecondary)),
          trailing: Icon(Icons.chevron_right, color: context.textMuted),
          onTap: () {
            context.push('/creator_studio/video/$id');
          },
        );
      }).toList(),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return count.toString();
  }
}
