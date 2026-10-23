import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oneova/backend/ai_agents/omni_command/omni_assistant_profile_models.dart';
import 'package:oneova/backend/ai_agents/omni_command/omni_assistant_service.dart';
import 'package:oneova/shared/theme/app_theme.dart';
import 'package:go_router/go_router.dart';

class OmniAssistantPreferencesScreen extends ConsumerStatefulWidget {
  const OmniAssistantPreferencesScreen({super.key});

  @override
  ConsumerState<OmniAssistantPreferencesScreen> createState() => _OmniAssistantPreferencesScreenState();
}

class _OmniAssistantPreferencesScreenState extends ConsumerState<OmniAssistantPreferencesScreen> {
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: ref.read(omniAssistantServiceProvider).preferredName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _updateProfile(ConversationStyleProfile newProfile) {
    ref.read(omniAssistantServiceProvider.notifier).saveProfile(newProfile);
  }

  Future<void> _resetPreferences() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        title: Text('Reset Assistant Personality?', style: TextStyle(color: ctx.textPrimary, fontWeight: FontWeight.bold)),
        content: Text("This will reset Omni Command's tone, language, and response length back to defaults.", style: TextStyle(color: ctx.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: ctx.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandBlue),
            child: const Text('Confirm Reset', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(omniAssistantServiceProvider.notifier).resetPreferences();
      if (mounted) {
        _nameController.text = 'User';
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preferences reset to default.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(omniAssistantServiceProvider);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Omni Assistant Identity',
          style: TextStyle(
            color: context.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: context.textSecondary),
            tooltip: 'Reset Personality',
            onPressed: _resetPreferences,
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Profile', style: TextStyle(color: context.textSecondary, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildCard(
            context,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.person, color: context.textPrimary),
                  title: Text('Preferred Name', style: TextStyle(color: context.textPrimary)),
                  subtitle: TextField(
                    controller: _nameController,
                    style: TextStyle(color: context.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'What should the assistant call you?',
                      hintStyle: TextStyle(color: context.textMuted),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (val) {
                      _updateProfile(profile.copyWith(preferredName: val));
                    },
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.check, color: AppColors.brandBlue),
                    onPressed: () {
                      _updateProfile(profile.copyWith(preferredName: _nameController.text));
                      FocusScope.of(context).unfocus();
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text('Tone & Personality', style: TextStyle(color: context.textSecondary, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildCard(
            context,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.message, color: context.textPrimary),
                  title: Text('Primary Tone', style: TextStyle(color: context.textPrimary)),
                  trailing: DropdownButton<TonePreference>(
                    value: profile.toneProfile.primaryTone,
                    dropdownColor: context.surfaceMid,
                    underline: const SizedBox(),
                    items: TonePreference.values.map((tone) {
                      return DropdownMenuItem(
                        value: tone,
                        child: Text(tone.name.toUpperCase(), style: TextStyle(color: context.textPrimary)),
                      );
                    }).toList(),
                    onChanged: (newTone) {
                      if (newTone != null) {
                        _updateProfile(profile.copyWith(
                          toneProfile: profile.toneProfile.copyWith(primaryTone: newTone),
                        ));
                      }
                    },
                  ),
                ),
                Divider(color: context.border),
                SwitchListTile(
                  activeThumbColor: AppColors.brandBlue,
                  secondary: Icon(Icons.emoji_emotions, color: context.textPrimary),
                  title: Text('Use Emojis', style: TextStyle(color: context.textPrimary)),
                  value: profile.toneProfile.useEmojis,
                  onChanged: (val) {
                    _updateProfile(profile.copyWith(
                      toneProfile: profile.toneProfile.copyWith(useEmojis: val),
                    ));
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text('Response Preferences', style: TextStyle(color: context.textSecondary, fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildCard(
            context,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.format_align_left, color: context.textPrimary),
                  title: Text('Explanation Depth', style: TextStyle(color: context.textPrimary)),
                  trailing: DropdownButton<ExplanationDepth>(
                    value: profile.responsePreference.explanationDepth,
                    dropdownColor: context.surfaceMid,
                    underline: const SizedBox(),
                    items: ExplanationDepth.values.map((depth) {
                      return DropdownMenuItem(
                        value: depth,
                        child: Text(depth.name.toUpperCase(), style: TextStyle(color: context.textPrimary)),
                      );
                    }).toList(),
                    onChanged: (newDepth) {
                      if (newDepth != null) {
                        _updateProfile(profile.copyWith(
                          responsePreference: profile.responsePreference.copyWith(explanationDepth: newDepth),
                        ));
                      }
                    },
                  ),
                ),
                Divider(color: context.border),
                SwitchListTile(
                  activeThumbColor: AppColors.brandBlue,
                  secondary: Icon(Icons.help_outline, color: context.textPrimary),
                  title: Text('Ask Follow-up Questions', style: TextStyle(color: context.textPrimary)),
                  subtitle: Text('Only when useful', style: TextStyle(color: context.textSecondary)),
                  value: profile.responsePreference.askFollowUpQuestions,
                  onChanged: (val) {
                    _updateProfile(profile.copyWith(
                      responsePreference: profile.responsePreference.copyWith(askFollowUpQuestions: val),
                    ));
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, {required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}
