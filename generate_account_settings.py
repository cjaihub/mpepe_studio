import os

TEMPLATE = """import 'package:flutter/material.dart';
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
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        title: Text('Account', style: Theme.of(context).textTheme.displayMedium!),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          MpepeCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Email Address', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                const SizedBox(height: 8),
                TextField(
                  enabled: false,
                  controller: TextEditingController(text: email),
                  style: const TextStyle(color: AppColors.textSecondary),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.darkBackground,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.outline),
                    ),
                    disabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.outline),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          MpepeCard(
            child: ListTile(
              leading: const Icon(Icons.lock_outline, color: AppColors.textPrimary),
              title: const Text('Change Password', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
              trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password reset email sent (Mock)')),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          MpepeCard(
            child: ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.mpepeMaroon),
              title: const Text('Delete Account', style: TextStyle(color: AppColors.mpepeMaroon, fontWeight: FontWeight.bold)),
              trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
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
        backgroundColor: AppColors.darkSurface,
        title: const Text('Delete Account', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        content: const Text(
          'Are you sure you want to delete your account? This action is permanent and cannot be undone.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textPrimary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Account deletion requested (Mock)')),
              );
            },
            child: const Text('Delete', style: TextStyle(color: AppColors.mpepeMaroon, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
"""

with open("lib/settings/screens/account_settings_screen.dart", "w") as f:
    f.write(TEMPLATE)

print("Generated AccountSettingsScreen")
