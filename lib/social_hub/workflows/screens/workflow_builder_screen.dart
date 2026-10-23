import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../backend/workflows/models/workflow_config.dart';
import '../../../backend/workflows/workflow_service.dart';
import '../../../shared/theme/app_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class WorkflowBuilderScreen extends ConsumerStatefulWidget {
  final WorkflowConfig? existingWorkflow;

  const WorkflowBuilderScreen({
    super.key,
    this.existingWorkflow,
  });

  @override
  ConsumerState<WorkflowBuilderScreen> createState() => _WorkflowBuilderScreenState();
}

class _WorkflowBuilderScreenState extends ConsumerState<WorkflowBuilderScreen> {
  late TextEditingController _nameController;
  WorkflowTriggerType _selectedTriggerType = WorkflowTriggerType.newMessage;
  List<WorkflowAction> _actions = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existingWorkflow?.name ?? '');
    if (widget.existingWorkflow != null) {
      _selectedTriggerType = widget.existingWorkflow!.trigger.type;
      _actions = List.from(widget.existingWorkflow!.actions);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveWorkflow() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name for the automation.')),
      );
      return;
    }

    if (_actions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one action.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final service = ref.read(workflowServiceProvider);

      final newWorkflow = WorkflowConfig(
        id: widget.existingWorkflow?.id ?? '',
        name: _nameController.text.trim(),
        ownerId: user.uid,
        trigger: WorkflowTrigger(
          type: _selectedTriggerType,
          config: {},
        ),
        actions: _actions,
        enabled: widget.existingWorkflow?.enabled ?? true,
      );

      if (widget.existingWorkflow == null) {
        await service.createWorkflow(newWorkflow);
      } else {
        await service.updateWorkflow(newWorkflow);
      }

      if (mounted) context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving workflow: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _addAction(WorkflowActionType type) {
    setState(() {
      _actions.add(WorkflowAction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: type,
        payload: _getDefaultPayloadForAction(type),
      ));
    });
  }
  
  Map<String, dynamic> _getDefaultPayloadForAction(WorkflowActionType type) {
    switch (type) {
      case WorkflowActionType.sendMessage:
        return {'content': 'Hello from Automation!', 'conversationId': '{{conversationId}}'};
      case WorkflowActionType.createTask:
        return {'title': 'Follow up with {{senderId}}', 'assigneeId': 'me'};
      case WorkflowActionType.callAi:
        return {'prompt': 'Analyze the message: {{content}}'};
      default:
        return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        title: Text(
          widget.existingWorkflow == null ? 'New Automation' : 'Edit Automation',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w900,
            color: context.textPrimary,
          ),
        ),
        iconTheme: IconThemeData(color: context.textPrimary),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 24,
                height: 24,
                child: AnimatedLoadingIndicator(color: AppColors.brandBlue, strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _saveWorkflow,
              child: Text(
                'Save',
                style: GoogleFonts.inter(
                  color: AppColors.brandBlue,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name Field
            TextField(
              controller: _nameController,
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: context.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Automation Name',
                hintStyle: GoogleFonts.inter(
                  color: context.textMuted,
                  fontWeight: FontWeight.w900,
                ),
                border: InputBorder.none,
              ),
            ),
            const SizedBox(height: 32),

            // Trigger Section
            _buildSectionHeader(context, 'WHEN', Icons.bolt),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.border, width: 1.0),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<WorkflowTriggerType>(
                  value: _selectedTriggerType,
                  dropdownColor: context.surface,
                  isExpanded: true,
                  icon: Icon(Icons.arrow_drop_down, color: context.textSecondary),
                  items: WorkflowTriggerType.values.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(
                        _formatEnumName(type.value),
                        style: GoogleFonts.inter(
                          color: context.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedTriggerType = val);
                  },
                ),
              ),
            ),

            const SizedBox(height: 32),
            _buildSectionHeader(context, 'DO THIS', Icons.play_arrow_rounded),
            const SizedBox(height: 16),

            // Actions List
            ..._actions.asMap().entries.map((entry) {
              final index = entry.key;
              final action = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: context.surfaceMid,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${index + 1}',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w900,
                          color: context.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: context.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: context.border, width: 1.0),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatEnumName(action.type.value),
                              style: GoogleFonts.inter(
                                color: context.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline, color: context.textSecondary),
                              onPressed: () {
                                setState(() {
                                  _actions.removeAt(index);
                                });
                              },
                            )
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 16),
            Center(
              child: OutlinedButton.icon(
                onPressed: () => _showAddActionModal(context),
                icon: const Icon(Icons.add, color: AppColors.brandBlue),
                label: Text(
                  'Add Action',
                  style: GoogleFonts.inter(
                    color: AppColors.brandBlue,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.brandBlue, width: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddActionModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Select Action',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: context.textPrimary,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: WorkflowActionType.values.length,
                  itemBuilder: (context, index) {
                    final type = WorkflowActionType.values[index];
                    return ListTile(
                      title: Text(
                        _formatEnumName(type.value),
                        style: GoogleFonts.inter(color: context.textPrimary),
                      ),
                      onTap: () {
                        context.pop();
                        _addAction(type);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: context.textSecondary, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w900,
            color: context.textSecondary,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  String _formatEnumName(String value) {
    return value.split('_').map((word) => word[0].toUpperCase() + word.substring(1)).join(' ');
  }
}
