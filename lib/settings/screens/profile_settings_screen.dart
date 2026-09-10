import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/components.dart';
import '../../providers/settings_provider.dart';
import '../commands/update_setting_command.dart';
import '../../shared/undo/undo_manager.dart';
import '../../shared/undo/undo_snackbar.dart';

class ProfileSettingsScreen extends ConsumerStatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  ConsumerState<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends ConsumerState<ProfileSettingsScreen> {
  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController();
  bool _initialized = false;
  Timer? _debounce;
  late Map<String, dynamic> _lastSavedProfile;

  @override
  void dispose() {
    _debounce?.cancel();
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _onTextChanged(Map<String, dynamic> currentProfile) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      _autoSave(currentProfile);
    });
  }

  void _autoSave(Map<String, dynamic> currentProfile) {
    final newProfile = {
      ...currentProfile,
      'displayName': _displayNameController.text,
      'bio': _bioController.text,
    };
    
    if (newProfile['displayName'] == _lastSavedProfile['displayName'] && newProfile['bio'] == _lastSavedProfile['bio']) return;

    final command = UpdateSettingCommand(
      ref: ref,
      category: 'profile',
      undoData: _lastSavedProfile,
      data: newProfile,
      name: 'Update Profile',
    );

    ref.read(undoManagerProvider.notifier).executeAndRegister(command);
    _lastSavedProfile = newProfile;
    
    UndoSnackbar.show(context, ref, 'Profile auto-saved');
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        title: Text('Profile Settings', style: AppTheme.h2Style),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.pop(),
        ),
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
        data: (settings) {
          final profile = settings['profile'] as Map<String, dynamic>? ?? {};
          if (!_initialized) {
            _lastSavedProfile = profile;
            _displayNameController.text = profile['displayName'] ?? '';
            _bioController.text = profile['bio'] ?? '';
            _initialized = true;
          }

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              MpepeCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Display Name', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _displayNameController,
                      onChanged: (_) => _onTextChanged(profile),
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Your creator name',
                        hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.5)),
                        filled: true,
                        fillColor: AppColors.darkBackground,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.outline),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.outline),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('Bio', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _bioController,
                      onChanged: (_) => _onTextChanged(profile),
                      maxLines: 4,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Tell your audience about yourself',
                        hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.5)),
                        filled: true,
                        fillColor: AppColors.darkBackground,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.outline),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.outline),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              // Manual save button removed since we now auto-save.
            ],
          );
        },
      ),
    );
  }
}

