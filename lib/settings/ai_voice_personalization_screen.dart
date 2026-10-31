import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';
import '../providers/settings_provider.dart';
import 'commands/update_setting_command.dart';
import '../shared/undo/undo_manager.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class AiVoicePersonalizationScreen extends ConsumerWidget {
  const AiVoicePersonalizationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        title: Text(
          'Ova Voice',
          style: GoogleFonts.inter(
            color: context.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: context.textPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: AnimatedLoadingIndicator()),
        error: (e, s) => Center(child: Text('Error: $e', style: TextStyle(color: context.textSecondary))),
        data: (settings) {
          final categoryData = settings['ai_voice'] as Map<String, dynamic>? ?? {};

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            children: [
              _buildSectionHeader(context, 'Voice chat'),
              _buildSwitch(context, ref, categoryData, 'voiceEnabled', 'Voice chat with Ova', 'High-speed two-way spoken conversation with Ova'),
              _buildSwitch(context, ref, categoryData, 'naturalSpeech', 'Natural Human Cadence', 'Subtle dynamic pauses, breath modulation, and emotional pitch'),
              _buildSwitch(context, ref, categoryData, 'backgroundMusic', 'Studio Atmosphere Music', 'Play subtle royalty-free lofi beats while speaking'),
              const SizedBox(height: 16),
              _buildSectionHeader(context, 'Account check'),
              _buildSwitch(context, ref, categoryData, 'voiceSelfRepair', 'Voice-Activated System Repair', 'Allows voice commands like "Repair my account" or "Fix feed" to auto-heal cache and indexes'),
              _buildSwitch(context, ref, categoryData, 'backgroundSelfHeal', 'Background Auto-Upgrade', 'Lets Ova fix small problems and update in the background'),
              const SizedBox(height: 16),
              // Model choice is a developer setting; people just talk to Ova.
              if (kDebugMode) ...[
                _buildSectionHeader(context, 'AI model (developer)'),
                _buildModelSelector(context, ref, categoryData),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: AppColors.brandBlue,
        ),
      ),
    );
  }

  Widget _buildSwitch(BuildContext context, WidgetRef ref, Map<String, dynamic> currentData, String key, String title, String subtitle) {
    final value = currentData[key] as bool? ?? (key == 'voiceEnabled' || key == 'voiceSelfRepair');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: OneovaCard(
        child: SwitchListTile(
          value: value,
          title: Text(
            title,
            style: GoogleFonts.inter(
              color: context.textPrimary,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: GoogleFonts.inter(
              color: context.textSecondary,
              fontSize: 11.5,
            ),
          ),
          activeThumbColor: AppColors.brandBlue,
          activeTrackColor: AppColors.brandBlue.withValues(alpha: 0.3),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          onChanged: (newValue) {
            final newData = Map<String, dynamic>.from(currentData);
            newData[key] = newValue;
            final command = UpdateSettingCommand(
              ref: ref,
              category: 'ai_voice',
              undoData: currentData,
              data: newData,
              name: 'Update $title',
            );
            ref.read(undoManagerProvider.notifier).executeAndRegister(command);
          },
        ),
      ),
    );
  }

  Widget _buildModelSelector(BuildContext context, WidgetRef ref, Map<String, dynamic> currentData) {
    final selected = currentData['selectedModel'] as String? ?? 'gemini-2.5-flash';
    final models = [
      {'id': 'gemini-2.5-flash', 'name': 'Gemini 2.5 Flash', 'desc': 'Ultra-fast sub-second voice latency & reasoning (Recommended)'},
      {'id': 'gemini-2.0-flash-exp', 'name': 'Gemini 2.0 Flash Live', 'desc': 'Native bi-directional multi-modal audio WebSocket stream'},
      {'id': 'openrouter/google/gemini-2.5-flash', 'name': 'OpenRouter Gemini Multi-Model', 'desc': 'OpenRouter global gateway with vision & voice fallback'},
    ];

    return OneovaCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: models.map((m) {
            final isCurrent = selected == m['id'];
            return InkWell(
              onTap: () {
                final newData = Map<String, dynamic>.from(currentData);
                newData['selectedModel'] = m['id'];
                final command = UpdateSettingCommand(
                  ref: ref,
                  category: 'ai_voice',
                  undoData: currentData,
                  data: newData,
                  name: 'Update AI Voice Model',
                );
                ref.read(undoManagerProvider.notifier).executeAndRegister(command);
              },
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isCurrent ? AppColors.brandBlue.withValues(alpha: 0.08) : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(
                    color: isCurrent ? AppColors.brandBlue : context.border,
                    width: 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isCurrent ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: isCurrent ? AppColors.brandBlue : context.textMuted,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m['name']!,
                            style: GoogleFonts.inter(
                              color: isCurrent ? AppColors.brandBlue : context.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            m['desc']!,
                            style: GoogleFonts.inter(
                              color: context.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
