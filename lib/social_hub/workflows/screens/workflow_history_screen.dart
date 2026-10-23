import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../backend/workflows/models/workflow_execution.dart';
import '../../../backend/workflows/workflow_service.dart';
import '../../../shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class WorkflowHistoryScreen extends ConsumerWidget {
  final String workflowId;

  const WorkflowHistoryScreen({
    super.key,
    required this.workflowId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(workflowExecutionsStreamProvider(workflowId));

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        title: Text(
          'Execution History',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w900,
            color: context.textPrimary,
          ),
        ),
        iconTheme: IconThemeData(color: context.textPrimary),
      ),
      body: historyAsync.when(
        data: (executions) {
          if (executions.isEmpty) {
            return Center(
              child: Text(
                'No executions yet.',
                style: GoogleFonts.inter(color: context.textSecondary),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: executions.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final exec = executions[index];
              return _ExecutionTile(execution: exec);
            },
          );
        },
        loading: () => const Center(
          child: AnimatedLoadingIndicator(color: AppColors.brandBlue),
        ),
        error: (error, stack) => Center(
          child: Text(
            'Failed to load history.',
            style: GoogleFonts.inter(color: context.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _ExecutionTile extends StatelessWidget {
  final WorkflowExecution execution;

  const _ExecutionTile({required this.execution});

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(_getStatusIcon(), color: statusColor, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    execution.status.value.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w900,
                      color: statusColor,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              Text(
                timeago.format(execution.startedAt),
                style: GoogleFonts.inter(
                  color: context.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          if (execution.error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                execution.error!,
                style: GoogleFonts.inter(
                  color: Colors.redAccent,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getStatusColor(BuildContext context) {
    switch (execution.status) {
      case ExecutionStatus.success:
        return Colors.green;
      case ExecutionStatus.failed:
      case ExecutionStatus.aborted:
        return Colors.red;
      case ExecutionStatus.running:
        return AppColors.brandBlue;
      default:
        return context.textSecondary;
    }
  }

  IconData _getStatusIcon() {
    switch (execution.status) {
      case ExecutionStatus.success:
        return Icons.check_circle_outline;
      case ExecutionStatus.failed:
      case ExecutionStatus.aborted:
        return Icons.error_outline;
      case ExecutionStatus.running:
        return Icons.sync;
      default:
        return Icons.hourglass_empty;
    }
  }
}
