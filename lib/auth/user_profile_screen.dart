import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../backend/user_service.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';
import '../shared/widgets/theme_toggle_button.dart';
import 'auth_repository.dart';
import 'services/secure_logout_service.dart';

class UserProfileScreen extends ConsumerStatefulWidget {
  const UserProfileScreen({super.key});

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  bool _isEditing = false;
  late TextEditingController _nameController;
  late TextEditingController _titleController;
  late TextEditingController _positionController;
  AppUser? _currentUserData;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _titleController = TextEditingController();
    _positionController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _titleController.dispose();
    _positionController.dispose();
    super.dispose();
  }

  void _populateData(AppUser user) {
    if (_currentUserData == null || _currentUserData!.id != user.id) {
      _nameController.text = user.fullName;
      _titleController.text = user.jobTitle ?? '';
      _positionController.text = user.position ?? '';
      _currentUserData = user;
    }
  }

  Future<void> _saveProfile(String uid) async {
    setState(() => _isEditing = false);
    
    await ref.read(userProvider.notifier).updateUserProfile(uid, {
      'fullName': _nameController.text,
      // For now, allow editing these, though logically an admin might lock them.
      // Alternatively, we could conditionally lock them based on role.
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully'), backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final uid = authState.value?.uid;
    final usersState = ref.watch(userProvider);
    
    if (uid == null || usersState.isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
            onPressed: () => context.pop(),
          ),
          title: Text('My Profile', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final users = usersState.value ?? [];
    final currentUser = users.firstWhere(
      (u) => u.id == uid, 
      orElse: () => AppUser(id: uid, fullName: 'Unknown', email: 'unknown', role: 'Staff', department: '', status: 'pending', createdAt: DateTime.now()),
    );
    
    _populateData(currentUser);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => context.pop(),
        ),
        title: Text('My Profile', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
        actions: [
          const ThemeToggleButton(),
          IconButton(
            icon: Icon(_isEditing ? Icons.save : Icons.edit, color: Theme.of(context).colorScheme.primary),
            onPressed: () {
              if (_isEditing) {
                _saveProfile(uid);
              } else {
                setState(() => _isEditing = true);
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                          child: Text(
                            _nameController.text.isNotEmpty ? _nameController.text[0].toUpperCase() : 'M',
                            style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
                          ),
                        ),
                        if (_isEditing)
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (!_isEditing) ...[
                      Text(_nameController.text, style: AppTheme.h1Style.copyWith(fontSize: 24)),
                      const SizedBox(height: 4),
                      if (_titleController.text.isNotEmpty || _positionController.text.isNotEmpty)
                        Text('${_titleController.text} ${(_titleController.text.isNotEmpty && _positionController.text.isNotEmpty) ? '•' : ''} ${_positionController.text}', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
                    ]
                  ],
                ),
              ).animate().fadeIn().slideY(begin: -0.1),
              
              const SizedBox(height: 32),
              
              Text('Personal Information', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.bold)).animate().fadeIn(delay: 200.ms),
              const SizedBox(height: 16),
              
              _buildProfileCard(
                context,
                children: [
                  _buildFieldRow('Full Name', _nameController, Icons.person_outline),
                  const Divider(height: 32),
                  // Render Job Title & Position as Read-only unless admin
                  _buildReadOnlyRow('Job Title', currentUser.jobTitle ?? 'Not Assigned', Icons.work_outline),
                  const Divider(height: 32),
                  _buildReadOnlyRow('Position', currentUser.position ?? 'Not Assigned', Icons.badge_outlined),
                ],
              ).animate().fadeIn(delay: 300.ms).slideX(begin: 0.05),
              
              const SizedBox(height: 24),
              Text('Account Details', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.bold)).animate().fadeIn(delay: 400.ms),
              const SizedBox(height: 16),
              
              _buildProfileCard(
                context,
                children: [
                  _buildReadOnlyRow('Email', currentUser.email, Icons.email_outlined),
                  const Divider(height: 32),
                  _buildReadOnlyRow('Role', currentUser.role, Icons.security_outlined),
                  const Divider(height: 32),
                  _buildReadOnlyRow('Department', currentUser.department.isNotEmpty ? currentUser.department : 'General', Icons.business_outlined),
                  const Divider(height: 32),
                  _buildReadOnlyRow('Status', currentUser.status.toUpperCase(), Icons.check_circle_outline, color: currentUser.status == 'active' ? Colors.green : Colors.orange),
                ],
              ).animate().fadeIn(delay: 500.ms).slideX(begin: 0.05),
              
              const SizedBox(height: 32),
              Text('Security', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.bold)).animate().fadeIn(delay: 400.ms),
              const SizedBox(height: 16),

              _buildProfileCard(
                context,
                children: [
                  _buildReadOnlyRow('Last Login',
                      FirebaseAuth.instance.currentUser?.metadata.lastSignInTime != null
                          ? _formatDate(FirebaseAuth.instance.currentUser!.metadata.lastSignInTime!)
                          : 'Unknown',
                      Icons.login_rounded),
                  const Divider(height: 32),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('PIN change coming soon — use Settings'),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      );
                    },
                    child: Row(
                      children: [
                        Icon(Icons.pin_outlined,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                            size: 24),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('PIN / Lock Screen',
                                  style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                      fontSize: 12)),
                              const SizedBox(height: 4),
                              Text('Change or disable your PIN',
                                  style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurface,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 15)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
                      ],
                    ),
                  ),
                  const Divider(height: 32),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      context.push('/auth/linked_devices');
                    },
                    child: Row(
                      children: [
                        Icon(Icons.devices_outlined,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                            size: 24),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Linked Devices',
                                  style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                      fontSize: 12)),
                              const SizedBox(height: 4),
                              Text('Manage your studio computers',
                                  style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurface,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 15)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
                      ],
                    ),
                  ),
                ],
              ).animate().fadeIn(delay: 500.ms).slideX(begin: 0.05),

              const SizedBox(height: 48),

              // Danger zone — secure logout
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 18),
                        const SizedBox(width: 8),
                        const Text('Danger Zone',
                            style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                        label: const Text('Sign Out Securely',
                            style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.redAccent),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () => _showLogoutConfirmation(context),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 600.ms),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ── Secure logout confirmation sheet ─────────────────────────────────────────
  void _showLogoutConfirmation(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 28),
              ),
              const SizedBox(height: 16),
              const Text(
                'Sign Out Securely?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'The following will be cleared from this device:',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              ..._logoutItems(context),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await ref.read(secureLogoutServiceProvider).logout();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Yes, Sign Out',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _logoutItems(BuildContext context) {
    final items = [
      (Icons.lock_outline, 'PIN and biometric session'),
      (Icons.timer_outlined, 'Active session & timeout timer'),
      (Icons.person_outline, 'Cached profile data'),
      (Icons.drafts_outlined, 'Any saved signup drafts'),
    ];
    return items
        .map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(item.$1, size: 18,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 10),
                Text(item.$2,
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.7))),
              ],
            ),
          ),
        )
        .toList();
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return "${diff.inMinutes}m ago";
    if (diff.inHours < 24) return "${diff.inHours}h ago";
    return "${date.day}/${date.month}/${date.year}";
  }


  Widget _buildProfileCard(BuildContext context, {required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildFieldRow(String label, TextEditingController controller, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), size: 24),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
              if (_isEditing)
                TextField(
                  controller: controller,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w500, fontSize: 15),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                    border: UnderlineInputBorder(),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(controller.text, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w500, fontSize: 15)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnlyRow(String label, String value, IconData icon, {Color? color}) {
    return Row(
      children: [
        Icon(icon, color: color ?? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), size: 24),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(value, style: TextStyle(color: color ?? Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w500, fontSize: 15)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
