import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/components.dart';

class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? 'Not logged in';

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        title: Text('Account', style: Theme.of(context).textTheme.displayMedium?.copyWith(color: context.textPrimary) ?? TextStyle(color: context.textPrimary)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: context.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          OnerovaCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Email Address', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                const SizedBox(height: 8),
                TextField(
                  enabled: false,
                  controller: TextEditingController(text: email),
                  style: TextStyle(color: context.textSecondary),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: context.bg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: context.border),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: context.border),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OnerovaCard(
            child: ListTile(
              leading: Icon(Icons.lock_outline, color: context.textPrimary),
              title: Text('Change Password', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
              trailing: Icon(Icons.chevron_right, color: context.textMuted),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password reset email sent (Mock)')),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          OnerovaCard(
            child: ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.brandBlue),
              title: const Text('Delete Account', style: TextStyle(color: AppColors.brandBlue, fontWeight: FontWeight.bold)),
              trailing: Icon(Icons.chevron_right, color: context.textMuted),
              onTap: () {
                _showDeleteConfirmation(context);
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.surface,
        title: Text('Delete Account', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to delete your account? This action is permanent and cannot be undone.',
          style: TextStyle(color: context.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: context.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Account deletion requested (Mock)')),
              );
            },
            child: const Text('Delete', style: TextStyle(color: AppColors.brandBlue, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
