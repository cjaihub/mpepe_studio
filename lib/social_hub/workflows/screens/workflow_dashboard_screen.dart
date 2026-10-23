import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../backend/workflows/models/workflow_config.dart';
import '../../../backend/workflows/workflow_service.dart';
import '../../../shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class WorkflowDashboardScreen extends ConsumerWidget {
  const WorkflowDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workflowsAsync = ref.watch(workflowsStreamProvider);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        title: Text(
          'Automations',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w900,
            fontSize: 24,
            color: context.textPrimary,
          ),
        ),
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: context.textPrimary),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/automations/builder'),
        backgroundColor: AppColors.brandBlue,
        icon: const Icon(Icons.bolt, color: Colors.white),
        label: Text(
          'New Automation',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: workflowsAsync.when(
        data: (workflows) {
          if (workflows.isEmpty) {
            return _buildEmptyState(context);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: workflows.length,
            separatorBuilder: (context, index) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              final workflow = workflows[index];
              return _WorkflowCard(workflow: workflow);
            },
          );
        },
        loading: () => const Center(
          child: AnimatedLoadingIndicator(color: AppColors.brandBlue),
        ),
        error: (error, stack) => Center(
          child: Text(
            'Failed to load automations.',
            style: GoogleFonts.inter(color: context.textSecondary),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 64,
              color: AppColors.brandBlue,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No Automations Yet',
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Create your first automation to put\nONEOVA on autopilot.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 16,
              color: context.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowCard extends ConsumerWidget {
  final WorkflowConfig workflow;

  const _WorkflowCard({required this.workflow});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            context.push('/automations/builder', extra: workflow);
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _getIconForTrigger(workflow.trigger.type),
                          color: AppColors.brandBlue,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          workflow.name.isEmpty ? 'Untitled Workflow' : workflow.name,
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: context.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    Switch(
                      value: workflow.enabled,
                      activeThumbColor: AppColors.brandBlue,
                      onChanged: (val) {
                        ref
                            .read(workflowServiceProvider)
                            .toggleWorkflowEnabled(workflow.id, val);
                      },
                    ),
                  ],
                ),
                if (workflow.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    workflow.description,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: context.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    _buildPill(
                      context,
                      '${workflow.actions.length} Action${workflow.actions.length == 1 ? '' : 's'}',
                      Icons.play_arrow_rounded,
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () {
                        context.push('/automations/${workflow.id}/history');
                      },
                      child: _buildPill(context, 'History', Icons.history, highlight: true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPill(BuildContext context, String text, IconData icon, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: highlight ? AppColors.brandBlue.withValues(alpha: 0.1) : context.surfaceMid,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: highlight ? AppColors.brandBlue : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: highlight ? AppColors.brandBlue : context.textSecondary,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: highlight ? AppColors.brandBlue : context.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIconForTrigger(WorkflowTriggerType type) {
    switch (type) {
      case WorkflowTriggerType.newMessage:
        return Icons.chat_bubble_rounded;
      case WorkflowTriggerType.keyword:
        return Icons.saved_search_rounded;
      case WorkflowTriggerType.scheduledTime:
        return Icons.schedule_rounded;
      case WorkflowTriggerType.webhook:
        return Icons.webhook_rounded;
      case WorkflowTriggerType.aiClassification:
        return Icons.auto_awesome;
      default:
        return Icons.bolt;
    }
  }
}
