import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../backend/user_service.dart';
import '../../shared/widgets/components.dart';
import '../auth/auth_repository.dart';

class AdminApprovalScreen extends ConsumerWidget {
  const AdminApprovalScreen({super.key});

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

    if (currentUser.role != 'Admin' && currentUser.role != 'Manager') {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
            onPressed: () => context.pop(),
          ),
          title: Text('Access Denied', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        ),
        body: const Center(
          child: Text('You do not have permission to view approvals.'),
        ),
      );
    }


    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => context.pop(),
        ),
        title: Text('Pending Approvals', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
      ),
      body: usersState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error loading users: $e')),
        data: (users) {
          final pendingUsers = users.where((u) => u.status == 'pending').toList();
          
          if (pendingUsers.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 64, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
                  const SizedBox(height: 16),
                  Text('No pending approvals', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7), fontSize: 16)),
                ],
              ),
            ).animate().fadeIn();
          }
          
          return ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: pendingUsers.length,
            itemBuilder: (context, index) {
              final user = pendingUsers[index];
              return _buildPendingUserCard(context, ref, user).animate().fadeIn(delay: Duration(milliseconds: 100 * index)).slideX(begin: 0.05);
            },
          );
        },
      ),
    );
  }

  Widget _buildPendingUserCard(BuildContext context, WidgetRef ref, AppUser user) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: Theme.of(context).colorScheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                  child: Text(
                    user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?',
                    style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(user.email, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('Pending', style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfoCol(context, 'Role', user.role),
                _buildInfoCol(context, 'Dept.', user.department.isEmpty ? 'N/A' : user.department),
                _buildInfoCol(context, 'Date', '${user.createdAt.day}/${user.createdAt.month}/${user.createdAt.year}'),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OneovaButton(
                text: 'Review & Approve',
                onPressed: () => _showApprovalDialog(context, ref, user),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCol(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 11)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }

  void _showApprovalDialog(BuildContext context, WidgetRef ref, AppUser user) {
    final titleController = TextEditingController();
    final positionController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Approve ${user.fullName}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Assign official job title and position.', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7), fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: titleController,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(
                labelText: 'Job Title (e.g. Senior Editor)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: positionController,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(
                labelText: 'Position (e.g. Post-Production)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white),
            onPressed: () async {
              if (titleController.text.isEmpty || positionController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please provide a job title and position.'), backgroundColor: Colors.red),
                );
                return;
              }
              
              await ref.read(userProvider.notifier).approveUser(
                user.id,
                titleController.text,
                positionController.text,
              );
              
              if (context.mounted) {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${user.fullName} approved successfully!'), backgroundColor: Colors.green),
                );
              }
            },
            child: const Text('Approve Access'),
          ),
        ],
      ),
    );
  }
}
