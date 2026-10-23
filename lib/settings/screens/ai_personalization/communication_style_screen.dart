import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oneova/backend/ai_agents/omni_command/communication_style_engine.dart';
import 'package:oneova/shared/theme/app_theme.dart';
import 'package:go_router/go_router.dart';

class CommunicationStyleScreen extends ConsumerStatefulWidget {
  const CommunicationStyleScreen({super.key});

  @override
  ConsumerState<CommunicationStyleScreen> createState() => _CommunicationStyleScreenState();
}

class _CommunicationStyleScreenState extends ConsumerState<CommunicationStyleScreen> {
  @override
  Widget build(BuildContext context) {
    final style = ref.watch(communicationStyleEngineProvider);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Personal Communication Style',
          style: TextStyle(
            color: context.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: context.textSecondary),
            tooltip: 'Reset Style',
            onPressed: () => _resetStyle(),
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildLearningControl(context, ref, style.isLearningEnabled),
          const SizedBox(height: 24),
          Text('Observed Style Parameters', style: TextStyle(color: context.textSecondary, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildMetricCard(context, 'Tone', style.tone),
          const SizedBox(height: 8),
          _buildMetricCard(context, 'Verbosity', style.verbosity),
          const SizedBox(height: 8),
          _buildMetricCard(context, 'Format', style.format),
          const SizedBox(height: 8),
          _buildMetricCard(context, 'Language', style.language),
          const SizedBox(height: 8),
          _buildMetricCard(context, 'Emojis', style.emojiStyle),
          const SizedBox(height: 8),
          _buildMetricCard(context, 'Greetings', style.greetingStyle),
          const SizedBox(height: 8),
          _buildMetricCard(context, 'Sign-offs', style.closingStyle),
        ],
      ),
    );
  }

  Widget _buildLearningControl(BuildContext context, WidgetRef ref, bool isLearningEnabled) {
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              isLearningEnabled ? Icons.auto_awesome : Icons.pause_circle_outline,
              color: isLearningEnabled ? AppColors.brandBlue : context.textSecondary,
            ),
            title: Text('Learn My Style', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
            subtitle: Text('AI will passively analyze authorized messages to match your communication style.', style: TextStyle(color: context.textSecondary)),
            trailing: Switch(
              activeThumbColor: AppColors.brandBlue,
              value: isLearningEnabled,
              onChanged: (val) {
                ref.read(communicationStyleEngineProvider.notifier).setLearningEnabled(val);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(BuildContext context, String label, StyleMetric metric) {
    IconData confidenceIcon;
    Color confidenceColor;

    switch (metric.confidence) {
      case ConfidenceLevel.OBSERVED:
        confidenceIcon = Icons.visibility;
        confidenceColor = Colors.blue;
        break;
      case ConfidenceLevel.USER_CONFIRMED:
        confidenceIcon = Icons.verified;
        confidenceColor = Colors.green;
        break;
      case ConfidenceLevel.TEMPORARY:
        confidenceIcon = Icons.access_time;
        confidenceColor = Colors.orange;
        break;
      case ConfidenceLevel.AI_SUGGESTED:
        confidenceIcon = Icons.lightbulb;
        confidenceColor = AppColors.brandBlue;
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        title: Text(label, style: TextStyle(color: context.textSecondary, fontSize: 12)),
        subtitle: Text(metric.value, style: TextStyle(color: context.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
        trailing: Tooltip(
          message: 'Confidence: \${metric.confidence.name}',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: confidenceColor.withAlpha(25),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(confidenceIcon, size: 14, color: confidenceColor),
                const SizedBox(width: 4),
                Text(
                  metric.confidence.name.replaceAll('_', ' '),
                  style: TextStyle(color: confidenceColor, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        onTap: () {
          // Future: Open edit dialog for this specific metric
        },
      ),
    );
  }

  Future<void> _resetStyle() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        title: Text('Reset Learned Style?', style: TextStyle(color: ctx.textPrimary)),
        content: Text('This will delete all observed style parameters and reset to AI suggestions.', style: TextStyle(color: ctx.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: ctx.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandBlue),
            child: const Text('Reset', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(communicationStyleEngineProvider.notifier).resetStyle();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Style reset to defaults.')));
      }
    }
  }
}
