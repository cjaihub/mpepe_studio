import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/components.dart';
import '../../auth/auth_repository.dart';
import '../models/communication_preference.dart';
import '../services/communication_manager_service.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class CommunicationManagerScreen extends ConsumerStatefulWidget {
  const CommunicationManagerScreen({super.key});

  @override
  ConsumerState<CommunicationManagerScreen> createState() => _CommunicationManagerScreenState();
}

class _CommunicationManagerScreenState extends ConsumerState<CommunicationManagerScreen> {
  PersonalizationSettings? _settings;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) return;
    
    // We override the family provider to use the current user ID
    final service = ref.read(communicationManagerProvider.notifier);
    final settings = await service.getSettings();
    
    if (mounted) {
      setState(() {
        _settings = settings;
        _isLoading = false;
      });
    }
  }

  Future<void> _updateSettings(PersonalizationSettings newSettings) async {
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) return;

    setState(() {
      _settings = newSettings;
    });

    final service = ref.read(communicationManagerProvider.notifier);
    try {
      await service.updateSettings(newSettings);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save settings.')),
        );
      }
    }
  }

  Future<void> _confirmReset() async {
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: const Text('Reset Personalization', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to reset your communication profile? This will delete all learned preferences and reset your AI access settings to OFF. This action cannot be undone.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandBlue),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final service = ref.read(communicationManagerProvider.notifier);
      await service.resetProfile();
      await _loadSettings();
    }
  }

  Future<void> _deletePreference(CommunicationPreference pref) async {
    final uid = ref.read(authRepositoryProvider).currentUser?.uid;
    if (uid == null) return;

    final service = ref.read(communicationManagerProvider.notifier);
    await service.deletePreference(pref.id);
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isMaster = false,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title, 
        style: TextStyle(
          color: Colors.white, 
          fontWeight: isMaster ? FontWeight.bold : FontWeight.normal,
          fontSize: isMaster ? 16 : 14,
        )
      ),
      subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppColors.brandBlue,
      ),
    );
  }

  Widget _buildBadge(PreferenceSource source) {
    Color bgColor;
    Color textColor;
    String text;

    switch (source) {
      case PreferenceSource.observed:
        bgColor = Colors.blue.withValues(alpha: 0.2);
        textColor = Colors.blue;
        text = 'OBSERVED';
        break;
      case PreferenceSource.userConfirmed:
        bgColor = Colors.green.withValues(alpha: 0.2);
        textColor = Colors.green;
        text = 'CONFIRMED';
        break;
      case PreferenceSource.aiSuggested:
        bgColor = Colors.orange.withValues(alpha: 0.2);
        textColor = Colors.orange;
        text = 'SUGGESTION';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(authRepositoryProvider).currentUser?.uid;
    if (uid == null) return const Scaffold(body: Center(child: Text("Not logged in")));

    final preferencesAsync = ref.watch(communicationManagerProvider);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        title: const Text('AI Personalization', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.pop(),
        ),
      ),
      body: _isLoading 
        ? const Center(child: AnimatedLoadingIndicator())
        : ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // Settings Card
            OnerovaCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('AI Communication Manager', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 8),
                  const Text(
                    'The AI learns your communication preferences to help draft better messages. You control exactly what it has access to.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  
                  _buildSwitchTile(
                    title: 'AI Personalization',
                    subtitle: 'Master toggle to enable or disable learning and personalized drafting.',
                    value: _settings?.personalizationEnabled ?? false,
                    isMaster: true,
                    onChanged: (val) {
                      _updateSettings(_settings!.copyWith(personalizationEnabled: val));
                    },
                  ),
                  
                  if (_settings?.personalizationEnabled == true) ...[
                    const Divider(color: AppColors.outline, height: 32),
                    
                    _buildSwitchTile(
                      title: 'Learn from my messages',
                      subtitle: 'Allow AI to securely analyze your outgoing messages.',
                      value: _settings?.learnFromMessages ?? false,
                      onChanged: (val) => _updateSettings(_settings!.copyWith(learnFromMessages: val)),
                    ),
                    _buildSwitchTile(
                      title: 'Learn from my approved conversations',
                      subtitle: 'Allow AI to learn from context in authorized threads.',
                      value: _settings?.learnFromApprovedConversations ?? false,
                      onChanged: (val) => _updateSettings(_settings!.copyWith(learnFromApprovedConversations: val)),
                    ),
                    _buildSwitchTile(
                      title: 'Learn from my edits',
                      subtitle: 'Analyze how you edit AI drafts to improve future suggestions.',
                      value: _settings?.learnFromEdits ?? false,
                      onChanged: (val) => _updateSettings(_settings!.copyWith(learnFromEdits: val)),
                    ),
                    _buildSwitchTile(
                      title: 'Learn from my reactions',
                      subtitle: 'Understand your tone preferences based on emojis and reactions.',
                      value: _settings?.learnFromReactions ?? false,
                      onChanged: (val) => _updateSettings(_settings!.copyWith(learnFromReactions: val)),
                    ),
                  ],
                ],
              ),
            ),
            
            // Auto Mode Link
            OnerovaCard(
              padding: const EdgeInsets.all(16),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.smart_toy, color: AppColors.brandBlue),
                ),
                title: const Text('Auto Mode Permissions', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text('Control autonomous messaging rules', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
                onTap: () => context.push('/settings/auto_mode'),
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Preferences List
            if (_settings?.personalizationEnabled == true) ...[
              const Text('Learned Preferences', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 16),
              
              preferencesAsync.when(
                loading: () => const Center(child: AnimatedLoadingIndicator()),
                error: (e, s) => Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.textSecondary))),
                data: (preferences) {
                  if (preferences.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Center(
                        child: Text("The AI hasn't learned any preferences yet. Ensure toggles are ON and interact with the app.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    );
                  }
                  
                  return Column(
                    children: preferences.map((pref) => Dismissible(
                      key: Key(pref.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: AppColors.brandBlue,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) => _deletePreference(pref),
                      child: OnerovaCard(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        pref.category.name.toUpperCase(), 
                                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, letterSpacing: 1),
                                      ),
                                      const Spacer(),
                                      _buildBadge(pref.source),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(pref.value, style: const TextStyle(color: Colors.white, fontSize: 16)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )).toList(),
                  );
                },
              ),
            ],

            const SizedBox(height: 48),

            // Danger Zone
            Center(
              child: TextButton.icon(
                onPressed: _confirmReset,
                icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                label: const Text('Reset Personalization Profile', style: TextStyle(color: Colors.redAccent)),
              ),
            ),
          ],
        ),
    );
  }
}
