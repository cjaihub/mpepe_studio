import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../backend/user_service.dart';
import '../../backend/task_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/components.dart';
import '../../shared/widgets/studio_background.dart';
import '../auth/auth_repository.dart';
import 'assign_task_dialog.dart';

class CrmDashboardScreen extends ConsumerWidget {
  const CrmDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final usersState = ref.watch(userProvider);
    
    if (authState.value == null || usersState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final uid = authState.value!.uid;
    final users = usersState.value ?? [];
    final currentUser = users.firstWhere((u) => u.id == uid, orElse: () => AppUser(id: '', fullName: '', email: '', role: 'Client', department: '', status: '', createdAt: DateTime.now()));

    if (currentUser.role != 'Admin' && currentUser.role != 'Manager' && currentUser.role != 'Staff') {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
            onPressed: () => context.pop(),
          ),
          title: Text('Access Denied', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        ),
        body: const Center(
          child: Text('You do not have permission to view the CRM dashboard.'),
        ),
      );
    }

    return DefaultTabController(
      length: 4,
      child: StudioBackground(
        backgroundIcons: const [Icons.people_outline, Icons.movie_creation, Icons.auto_awesome, Icons.admin_panel_settings_outlined],
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              _buildStatsRow(context, ref),
              TabBar(
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                indicatorColor: Theme.of(context).colorScheme.primary,
                isScrollable: true,
                tabs: const [
                  Tab(text: 'Productions Kanban'),
                  Tab(text: 'AI Bookings'),
                  Tab(text: 'Staff Directory'),
                  Tab(text: 'Global Tasks'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _ProductionsKanbanTab(),
                    _AIBookingsTab(),
                    _StaffDirectoryTab(),
                    _GlobalTasksTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
                onPressed: () => context.pop(),
              ),
              Text('CRM Admin Panel', style: AppTheme.h1Style.copyWith(fontSize: 20)),
            ],
          ),
          ElevatedButton.icon(
            onPressed: () => context.push('/crm/approvals'),
            icon: const Icon(Icons.verified_user),
            label: const Text('Approvals'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(BuildContext context, WidgetRef ref) {
    final usersState = ref.watch(userProvider);
    final tasksState = ref.watch(taskProvider);

    final staffCount = usersState.value?.length ?? 0;
    final totalTasks = tasksState.value?.length ?? 0;
    final pendingTasks = tasksState.value?.where((t) => t.status != 'completed').length ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      child: Row(
        children: [
          _StatBox(title: 'Total Staff', value: staffCount.toString(), color: Colors.blue),
          const SizedBox(width: 16),
          _StatBox(title: 'Pending Tasks', value: pendingTasks.toString(), color: Colors.orange),
          const SizedBox(width: 16),
          _StatBox(title: 'Total Tasks', value: totalTasks.toString(), color: Colors.green),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  const _StatBox({required this.title, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 4),
            Text(title, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// DIRECTORY TAB
// ---------------------------------------------------------
class _StaffDirectoryTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersState = ref.watch(userProvider);
    final users = usersState.value ?? [];

    if (usersState.isLoading) return const Center(child: CircularProgressIndicator());
    if (users.isEmpty) return _buildEmptyState(context, 'No staff found.', Icons.people_outline);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 16.0),
      itemCount: users.length,
      itemBuilder: (context, index) {
        return _UserCrmCard(user: users[index]).animate().fadeIn(delay: (index * 50).ms).slideX(begin: 0.05);
      },
    );
  }
}

class _UserCrmCard extends ConsumerWidget {
  final AppUser user;
  
  const _UserCrmCard({required this.user});

  Color _getRoleColor(String role) {
    final r = role.toLowerCase();
    if (r.contains('admin')) return Colors.red;
    if (r.contains('creator')) return Colors.purple;
    if (r.contains('editor')) return Colors.teal;
    return Colors.blue;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roleColor = _getRoleColor(user.role);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MpepeCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: roleColor,
                child: Text(user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : 'U', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.fullName, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: roleColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                          child: Text(user.role, style: TextStyle(color: roleColor, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        Text(user.department, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.assignment_add, color: Theme.of(context).colorScheme.primary),
                tooltip: 'Assign Task',
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AssignTaskDialog(user: user),
                  );
                },
          ),
        ],
      ),
      ],
      ),
      ),
    );
  }
}

// ---------------------------------------------------------
// GLOBAL TASKS TAB
// ---------------------------------------------------------
class _GlobalTasksTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksState = ref.watch(taskProvider);
    final usersState = ref.watch(userProvider);
    
    final tasks = tasksState.value ?? [];
    final users = usersState.value ?? [];

    if (tasksState.isLoading) return const Center(child: CircularProgressIndicator());
    if (tasks.isEmpty) return _buildEmptyState(context, 'No tasks exist in the system yet.', Icons.assignment_outlined);

    // Sort tasks: pending first, then by due date
    final sortedTasks = List<UserTask>.from(tasks)..sort((a, b) {
      if (a.status == 'pending' && b.status == 'completed') return -1;
      if (a.status == 'completed' && b.status == 'pending') return 1;
      return a.dueDate.compareTo(b.dueDate);
    });

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 16.0),
      itemCount: sortedTasks.length,
      itemBuilder: (context, index) {
        final task = sortedTasks[index];
        final assignedUser = users.firstWhere((u) => u.id == task.assignedUserId, orElse: () => AppUser(id: '', fullName: 'Unknown', email: '', role: '', department: '', status: 'unknown', createdAt: DateTime.now()));
        return _GlobalTaskCard(task: task, assignedUserName: assignedUser.fullName).animate().fadeIn(delay: (index * 50).ms).slideX(begin: 0.05);
      },
    );
  }
}

class _GlobalTaskCard extends ConsumerWidget {
  final UserTask task;
  final String assignedUserName;

  const _GlobalTaskCard({required this.task, required this.assignedUserName});

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'high': return Colors.red;
      case 'medium': return Colors.orange;
      case 'low': return Colors.green;
      default: return Colors.grey;
    }
  }

  Future<void> _confirmCompletion(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Confirm Completion', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Text('Are you sure you want to mark "${task.title}" as completed?', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (result == true) {
      await ref.read(taskProvider.notifier).updateTaskStatus(task.id, 'completed');
      ref.invalidate(userTaskProvider(task.assignedUserId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task marked as completed!'), backgroundColor: Colors.green),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCompleted = task.status == 'completed';
    final pColor = _getPriorityColor(task.priority);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isCompleted ? Colors.green.withValues(alpha: 0.3) : Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: isCompleted ? null : () => _confirmCompletion(context, ref),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Icon(isCompleted ? Icons.check_circle : Icons.radio_button_unchecked, color: isCompleted ? Colors.green : Theme.of(context).colorScheme.outline, size: 24),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.title,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    decoration: isCompleted ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: pColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                child: Text(task.priority.toUpperCase(), style: TextStyle(color: pColor, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          if (task.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 28.0),
              child: Text(task.description, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7), fontSize: 12)),
            ),
          ],
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 28.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.person, size: 14, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                    const SizedBox(width: 4),
                    Text(assignedUserName, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
                  ],
                ),
                Row(
                  children: [
                    Icon(Icons.calendar_today, size: 14, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                    const SizedBox(width: 4),
                    Text('${task.dueDate.month}/${task.dueDate.day}/${task.dueDate.year}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _buildEmptyState(BuildContext context, String message, IconData icon) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 48, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
        const SizedBox(height: 16),
        Text(message, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 14)),
      ],
    ),
  );
}

// ---------------------------------------------------------
// PRODUCTIONS KANBAN TAB
// ---------------------------------------------------------
class _ProductionsKanbanTab extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ProductionsKanbanTab> createState() => _ProductionsKanbanTabState();
}

class _ProductionsKanbanTabState extends ConsumerState<_ProductionsKanbanTab> {
  final List<String> columns = ['pending', 'in_progress', 'review', 'completed'];
  final Map<String, String> columnTitles = {
    'pending': 'To Do',
    'in_progress': 'In Progress',
    'review': 'Review',
    'completed': 'Done',
  };

  @override
  Widget build(BuildContext context) {
    final tasksState = ref.watch(taskProvider);
    final usersState = ref.watch(userProvider);
    
    if (tasksState.isLoading) return const Center(child: CircularProgressIndicator());
    
    final allTasks = tasksState.value ?? [];
    final allUsers = usersState.value ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(18.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Task Kanban Board', style: AppTheme.h1Style.copyWith(fontSize: 18)),
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add),
                label: const Text('New Task'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: columns.map((status) {
                final colTasks = allTasks.where((t) => (t.status == status) || (status == 'pending' && !columns.contains(t.status))).toList();
                return _buildDragTargetColumn(status, colTasks, allUsers);
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDragTargetColumn(String status, List<UserTask> tasks, List<AppUser> users) {
    final colorScheme = Theme.of(context).colorScheme;
    return DragTarget<UserTask>(
      onAcceptWithDetails: (details) async {
        final task = details.data;
        if (task.status != status) {
          await ref.read(taskProvider.notifier).updateTaskStatus(task.id, status);
          ref.invalidate(userTaskProvider(task.assignedUserId));
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;
        return Container(
          width: 300,
          margin: const EdgeInsets.only(left: 18, bottom: 18),
          decoration: BoxDecoration(
            color: isHovered 
                ? colorScheme.primary.withValues(alpha: 0.1) 
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isHovered ? colorScheme.primary : colorScheme.outline.withValues(alpha: 0.1),
              width: isHovered ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(columnTitles[status]!, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: colorScheme.onSurface)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                      child: Text('${tasks.length}', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: tasks.length,
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    final assignedUser = users.firstWhere((u) => u.id == task.assignedUserId, orElse: () => AppUser(id: '', fullName: 'Unknown', email: '', role: '', department: '', status: 'unknown', createdAt: DateTime.now()));
                    return Draggable<UserTask>(
                      data: task,
                      feedback: Material(
                        color: Colors.transparent,
                        child: Opacity(
                          opacity: 0.8,
                          child: SizedBox(
                            width: 268,
                            child: _KanbanCard(task: task, user: assignedUser),
                          ),
                        ),
                      ),
                      childWhenDragging: Opacity(
                        opacity: 0.3,
                        child: _KanbanCard(task: task, user: assignedUser),
                      ),
                      child: _KanbanCard(task: task, user: assignedUser),
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
}

class _KanbanCard extends StatelessWidget {
  final UserTask task;
  final AppUser user;

  const _KanbanCard({required this.task, required this.user});

  void _showUserTooltip(BuildContext context, TapDownDetails details) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        details.globalPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: Text(user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : 'U', style: const TextStyle(color: Colors.white)),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('@${user.fullName.replaceAll(' ', '').toLowerCase()}', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Role: ${user.role}', style: const TextStyle(fontSize: 13)),
              Text('Dept: ${user.department}', style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(icon: const Icon(Icons.chat, size: 20), onPressed: () {}),
                  IconButton(icon: const Icon(Icons.mail, size: 20), onPressed: () {}),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: task.priority == 'high' ? Colors.red.withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  task.priority.toUpperCase(),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: task.priority == 'high' ? Colors.red : Colors.blue),
                ),
              ),
              PopupMenuButton(
                icon: Icon(Icons.more_horiz, size: 16, color: colorScheme.onSurface.withValues(alpha: 0.4)),
                itemBuilder: (context) => [
                  const PopupMenuItem(child: Text('Edit')),
                  const PopupMenuItem(child: Text('Delete')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(task.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 12, color: colorScheme.onSurface.withValues(alpha: 0.5)),
                  const SizedBox(width: 4),
                  Text('${task.dueDate.month}/${task.dueDate.day}', style: TextStyle(fontSize: 12, color: colorScheme.onSurface.withValues(alpha: 0.5))),
                ],
              ),
              GestureDetector(
                onTapDown: (details) => _showUserTooltip(context, details),
                child: Tooltip(
                  message: 'Assigned to ${user.fullName}',
                  child: CircleAvatar(
                    radius: 12,
                    backgroundColor: colorScheme.secondaryContainer,
                    child: Text(
                      user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : 'U',
                      style: TextStyle(fontSize: 10, color: colorScheme.onSecondaryContainer, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------
// AI BOOKINGS TAB
// ---------------------------------------------------------
class _AIBookingsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(18.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('AI Agent Sessions', style: AppTheme.h1Style.copyWith(fontSize: 18)),
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.settings),
                label: const Text('Agent Settings'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                  foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            children: [
              _buildBookingCard(context, 'John Doe', 'Audio Tracking (4hrs)', 'Tomorrow, 10:00 AM', true),
              _buildBookingCard(context, 'Sarah Smith', 'Video Shoot (8hrs)', 'Aug 30, 09:00 AM', false),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBookingCard(BuildContext context, String client, String service, String time, bool isConfirmed) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MpepeCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
          CircleAvatar(
            backgroundColor: isConfirmed ? Colors.green.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
            child: Icon(isConfirmed ? Icons.check : Icons.access_time, color: isConfirmed ? Colors.green : Colors.orange),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(client, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(service, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7), fontSize: 13)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.calendar_today, size: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                    const SizedBox(width: 4),
                    Text(time, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chat),
            tooltip: 'View AI Chat Log',
            onPressed: () {},
          ),
        ],
      ),
    ),
  );
}
}

