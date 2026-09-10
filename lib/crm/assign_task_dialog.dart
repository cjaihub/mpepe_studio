import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../backend/user_service.dart';
import '../../backend/task_service.dart';
import '../../shared/widgets/components.dart';

class AssignTaskDialog extends ConsumerStatefulWidget {
  final AppUser user;
  const AssignTaskDialog({super.key, required this.user});

  @override
  ConsumerState<AssignTaskDialog> createState() => _AssignTaskDialogState();
}

class _AssignTaskDialogState extends ConsumerState<AssignTaskDialog> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  String _selectedPriority = 'medium';
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 7));
  bool _isSaving = false;

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Theme.of(context).colorScheme.primary,
              onPrimary: Colors.white,
              surface: Theme.of(context).colorScheme.surface,
              onSurface: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _attemptCancel() async {
    if (_titleController.text.isNotEmpty || _descController.text.isNotEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text('Discard Task?', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
          content: Text('You have unsaved changes. Are you sure you want to discard them?', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8))),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Keep Editing', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _saveTask() async {
    if (_titleController.text.isEmpty) return;
    setState(() => _isSaving = true);

    final newTask = UserTask(
      id: '',
      title: _titleController.text,
      description: _descController.text,
      assignedUserId: widget.user.id,
      status: 'pending',
      priority: _selectedPriority,
      dueDate: _selectedDate,
      createdAt: DateTime.now(),
    );

    await ref.read(taskProvider.notifier).createTask(newTask);
    
    // Refresh user tasks
    ref.invalidate(userTaskProvider(widget.user.id));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task assigned successfully!'), backgroundColor: Colors.green),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: Text('Assign Task to ${widget.user.fullName}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(
                labelText: 'Task Title',
                labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.outline)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.primary)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(
                labelText: 'Description (Optional)',
                labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.outline)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.primary)),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedPriority,
              dropdownColor: Theme.of(context).colorScheme.surface,
              decoration: InputDecoration(
                labelText: 'Priority',
                labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.outline)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.primary)),
              ),
              items: [
                DropdownMenuItem(value: 'low', child: Text('Low', style: TextStyle(color: Colors.green))),
                DropdownMenuItem(value: 'medium', child: Text('Medium', style: TextStyle(color: Colors.orange))),
                DropdownMenuItem(value: 'high', child: Text('High', style: TextStyle(color: Colors.red))),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _selectedPriority = val);
              },
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () => _selectDate(context),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Due Date',
                  labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.outline)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                    ),
                    Icon(Icons.calendar_today, size: 18, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _attemptCancel,
          child: Text('Cancel', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
        ),
        _isSaving
            ? const CircularProgressIndicator()
            : MpepeButton(
                text: 'Assign',
                onPressed: _saveTask,
              ),
      ],
    );
  }
}
