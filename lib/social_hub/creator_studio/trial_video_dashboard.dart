import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../backend/creator/models/experimentation_models.dart';
import '../../../backend/creator/services/experimentation_service.dart';
import 'package:oneova/shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class TrialVideoDashboard extends ConsumerStatefulWidget {
  final String trialId;
  const TrialVideoDashboard({super.key, required this.trialId});

  @override
  ConsumerState<TrialVideoDashboard> createState() => _TrialVideoDashboardState();
}

class _TrialVideoDashboardState extends ConsumerState<TrialVideoDashboard> {
  TrialVideo? _trial;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTrial();
  }

  Future<void> _loadTrial() async {
    final trial = await ref.read(experimentationServiceProvider).getTrialVideo(widget.trialId);
    if (mounted) {
      setState(() {
        _trial = trial;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleAction(String action) async {
    final service = ref.read(experimentationServiceProvider);
    
    // Safety check confirmation dialog
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surface,
        title: Text('Confirm $action', style: TextStyle(color: context.textPrimary)),
        content: Text('Are you sure you want to ${action.toLowerCase()} this trial video?', style: TextStyle(color: context.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: context.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action, style: const TextStyle(color: AppColors.brandBlue, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ) ?? false;

    if (!confirm) return;

    setState(() => _isLoading = true);

    try {
      if (action == 'Publish') {
        await service.publishTrial(widget.trialId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Video published successfully!')));
          context.pop();
        }
      } else if (action == 'Discard') {
        await service.discardTrial(widget.trialId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trial discarded.')));
          context.pop();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
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

    final t = _trial!;
    final m = t.metrics;

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        title: Text('Trial Video Analysis', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
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
            // Status Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.science, color: Colors.blue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Status: ${t.status.name.toUpperCase()}', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('Target: ${t.config.targetViews} views (Followers Only: ${t.config.followersOnly})', style: TextStyle(color: context.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Metrics Grid
            Text('Audience Response', style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.5,
              children: [
                _buildStatCard('Views', m.views.toString(), Icons.visibility, progress: m.views / t.config.targetViews),
                _buildStatCard('Completion', '${(m.completionRate * 100).toInt()}%', Icons.check_circle, color: m.completionRate > 0.5 ? Colors.green : Colors.orange),
                _buildStatCard('Likes', m.likes.toString(), Icons.favorite),
                _buildStatCard('Comments', m.comments.toString(), Icons.comment),
                _buildStatCard('Shares', m.shares.toString(), Icons.share),
                _buildStatCard('Score', '${(m.audienceResponseScore * 10).toStringAsFixed(1)}/10', Icons.analytics, color: Colors.purpleAccent),
              ],
            ),
            const SizedBox(height: 32),

            // Actions
            Text('Trial Actions', style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _handleAction('Publish'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Publish Video', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _handleAction('Discard'),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: context.border),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Discard', style: TextStyle(color: context.textPrimary)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  // E.g. _handleAction('Expand') or open dialog to change config
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.blue),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Expand Test Distribution', style: TextStyle(color: Colors.blue)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, {Color? color, double? progress}) {
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
          if (progress != null) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: context.surfaceMid,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
              minHeight: 4,
            ),
          ],
        ],
      ),
    );
  }
}
