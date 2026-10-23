import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/components.dart';
import '../../providers/settings_provider.dart';
import '../commands/update_setting_command.dart';
import '../../shared/undo/undo_manager.dart';
import '../../shared/undo/undo_snackbar.dart';
import '../widgets/settings_kit.dart';

/// Screen allowing complete user customization of the Oneova Chat panel:
/// button placements, hold durations, creator quick-bar limits, voice recording behavior,
/// and haptic feedback levels — fully persisted in Firestore `user_settings`.
class ChatSettingsScreen extends ConsumerWidget {
  const ChatSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        title: Row(
          children: [
            Text('Chat & Messaging', style: AppTheme.h2Style.copyWith(color: context.topBarFg)),
            const SizedBox(width: 8),
            const SettingsSaveIndicator(),
          ],
        ),
        backgroundColor: AppColors.brandBlue,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, size: 18, color: context.topBarFg),
          onPressed: () => context.pop(),
        ),
      ),
      body: settingsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.brandBlue),
        ),
        error: (e, s) => Center(
          child: Text('Error loading settings: $e', style: TextStyle(color: context.textSecondary)),
        ),
        data: (settings) {
          final chatSettings = settings['chat'] as Map<String, dynamic>? ?? {};

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            children: [
              // 1. Action Buttons Placement & Alignment
              _buildSectionHeader(context, 'Buttons & Layout Placement'),
              OneovaCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _buildSwitchTile(
                      context,
                      ref,
                      icon: Icons.auto_awesome_rounded,
                      title: 'AI Studio Companion FAB',
                      subtitle: 'Floating AI helper button on chat inbox',
                      category: 'chat',
                      keyName: 'showAiStudioFab',
                      value: chatSettings['showAiStudioFab'] ?? true,
                    ),
                    _buildDivider(context),
                    _buildSwitchTile(
                      context,
                      ref,
                      icon: Icons.add_comment_rounded,
                      title: 'Compose Message FAB',
                      subtitle: 'Floating "+" button to start new chats',
                      category: 'chat',
                      keyName: 'showComposeFab',
                      value: chatSettings['showComposeFab'] ?? true,
                    ),
                    _buildDivider(context),
                    _buildAlignmentTile(context, ref, chatSettings),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 2. Button Hold & Gesture Durations
              _buildSectionHeader(context, 'Hold & Press Durations'),
              OneovaCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.brandBlue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.touch_app_rounded, color: AppColors.brandBlue, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hold Duration Sensitivity',
                                style: GoogleFonts.inter(
                                  color: context.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Adjust how long you hold for voice recording & quick actions',
                                style: GoogleFonts.inter(
                                  color: context.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildHoldDurationSelector(context, ref, chatSettings),
                    const SizedBox(height: 16),
                    _buildDivider(context),
                    const SizedBox(height: 12),
                    _buildVoiceModeSelector(context, ref, chatSettings),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 3. Panel Density & Contact Bar
              _buildSectionHeader(context, 'Screen Density & Feed Items'),
              OneovaCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _buildQuickCreatorsSelector(context, ref, chatSettings),
                    _buildDivider(context),
                    _buildSwitchTile(
                      context,
                      ref,
                      icon: Icons.verified_rounded,
                      title: 'Creator Pro Banner',
                      subtitle: 'Display AI Studio VIP banner above chats',
                      category: 'chat',
                      keyName: 'showCreatorProBanner',
                      value: chatSettings['showCreatorProBanner'] ?? true,
                    ),
                    _buildDivider(context),
                    _buildSwitchTile(
                      context,
                      ref,
                      icon: Icons.keyboard_return_rounded,
                      title: 'Enter Key Sends Message',
                      subtitle: 'Press Enter to instantly transmit text',
                      category: 'chat',
                      keyName: 'enterIsSend',
                      value: chatSettings['enterIsSend'] ?? false,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 4. Sound & Haptics
              _buildSectionHeader(context, 'Tactile & Haptic Feedback'),
              OneovaCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _buildSwitchTile(
                      context,
                      ref,
                      icon: Icons.volume_up_rounded,
                      title: 'Chat Sound Effects',
                      subtitle: 'Play audio cues when sending and receiving',
                      category: 'chat',
                      keyName: 'chatSoundEffects',
                      value: chatSettings['chatSoundEffects'] ?? true,
                    ),
                    _buildDivider(context),
                    _buildHapticSelector(context, ref, chatSettings),
                  ],
                ),
              ),

              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        title,
        style: GoogleFonts.inter(
          color: AppColors.brandBlue,
          fontWeight: FontWeight.w800,
          fontSize: 13,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Divider(
      height: 1,
      color: context.border,
      indent: 56,
      endIndent: 16,
    );
  }

  Widget _buildSwitchTile(
    BuildContext context,
    WidgetRef ref, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String category,
    required String keyName,
    required bool value,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.brandBlue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.brandBlue, size: 20),
      ),
      title: Text(
        title,
        style: GoogleFonts.inter(
          color: context.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.inter(
          color: context.textMuted,
          fontSize: 11.5,
        ),
      ),
      trailing: Switch(
        value: value,
        onChanged: (newVal) {
          final command = UpdateSettingCommand(
            ref: ref,
            category: category,
            undoData: {keyName: value},
            data: {keyName: newVal},
            name: 'Toggle $title',
          );
          ref.read(undoManagerProvider.notifier).executeAndRegister(command);
          UndoSnackbar.show(context, ref, '$title ${newVal ? "enabled" : "disabled"}');
        },
        activeThumbColor: AppColors.brandBlue,
        activeTrackColor: AppColors.brandBlue.withValues(alpha: 0.35),
      ),
    );
  }

  Widget _buildAlignmentTile(BuildContext context, WidgetRef ref, Map<String, dynamic> chatSettings) {
    final String currentAlignment = chatSettings['fabAlignment'] ?? 'right';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.brandPink.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.pan_tool_alt_rounded, color: AppColors.brandPink, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Button Placement Side',
                  style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
                ),
                Text(
                  'Right-hand mode or left-hand thumb access',
                  style: GoogleFonts.inter(color: context.textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'left', label: Text('Left', style: TextStyle(fontSize: 12))),
              ButtonSegment(value: 'right', label: Text('Right', style: TextStyle(fontSize: 12))),
            ],
            selected: {currentAlignment},
            onSelectionChanged: (set) {
              final val = set.first;
              ref.read(settingsProvider.notifier).updateSetting('chat', 'fabAlignment', val);
              HapticFeedback.selectionClick();
            },
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return AppColors.brandBlue;
                }
                return context.surfaceMid;
              }),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                return context.textPrimary;
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHoldDurationSelector(BuildContext context, WidgetRef ref, Map<String, dynamic> chatSettings) {
    final int currentDuration = chatSettings['holdDurationMs'] ?? 350;

    final durations = [
      {'ms': 200, 'label': '200ms', 'desc': 'Fast'},
      {'ms': 350, 'label': '350ms', 'desc': 'Balanced'},
      {'ms': 500, 'label': '500ms', 'desc': 'Firm'},
      {'ms': 750, 'label': '750ms', 'desc': 'Deliberate'},
    ];

    return Row(
      children: durations.map((d) {
        final ms = d['ms'] as int;
        final isSelected = currentDuration == ms;

        return Expanded(
          child: GestureDetector(
            onTap: () {
              ref.read(settingsProvider.notifier).updateSetting('chat', 'holdDurationMs', ms);
              HapticFeedback.selectionClick();
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.brandBlue : context.surfaceMid,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? AppColors.brandBlue : context.border,
                  width: 1.2,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    d['label'] as String,
                    style: GoogleFonts.inter(
                      color: isSelected ? Colors.white : context.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    d['desc'] as String,
                    style: GoogleFonts.inter(
                      color: isSelected ? Colors.white70 : context.textMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildVoiceModeSelector(BuildContext context, WidgetRef ref, Map<String, dynamic> chatSettings) {
    final String mode = chatSettings['voiceRecordMode'] ?? 'hold';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Voice Recording Gesture',
                style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
              Text(
                'Choose how you record audio memos',
                style: GoogleFonts.inter(color: context.textMuted, fontSize: 11.5),
              ),
            ],
          ),
        ),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'hold', label: Text('Hold', style: TextStyle(fontSize: 12))),
            ButtonSegment(value: 'tap', label: Text('Tap', style: TextStyle(fontSize: 12))),
          ],
          selected: {mode},
          onSelectionChanged: (set) {
            final val = set.first;
            ref.read(settingsProvider.notifier).updateSetting('chat', 'voiceRecordMode', val);
            HapticFeedback.selectionClick();
          },
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return AppColors.brandPink;
              }
              return context.surfaceMid;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return Colors.white;
              }
              return context.textPrimary;
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickCreatorsSelector(BuildContext context, WidgetRef ref, Map<String, dynamic> chatSettings) {
    final int limit = chatSettings['quickCreatorsLimit'] ?? 5;

    final options = [
      {'val': 0, 'label': 'Hide'},
      {'val': 3, 'label': '3'},
      {'val': 5, 'label': '5'},
      {'val': 10, 'label': '10'},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.brandBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.people_alt_rounded, color: AppColors.brandBlue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quick Creator Bubbles',
                  style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
                ),
                Text(
                  limit == 0 ? 'Disabled (clean look)' : 'Showing top $limit creators',
                  style: GoogleFonts.inter(color: context.textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 6,
            children: options.map((opt) {
              final val = opt['val'] as int;
              final isSel = limit == val;

              return GestureDetector(
                onTap: () {
                  ref.read(settingsProvider.notifier).updateSetting('chat', 'quickCreatorsLimit', val);
                  HapticFeedback.selectionClick();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSel ? AppColors.brandBlue : context.surfaceMid,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSel ? AppColors.brandBlue : context.border,
                    ),
                  ),
                  child: Text(
                    opt['label'] as String,
                    style: GoogleFonts.inter(
                      color: isSel ? Colors.white : context.textPrimary,
                      fontSize: 11.5,
                      fontWeight: isSel ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHapticSelector(BuildContext context, WidgetRef ref, Map<String, dynamic> chatSettings) {
    final String intensity = chatSettings['hapticIntensity'] ?? 'medium';

    final options = ['off', 'light', 'medium', 'heavy'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.brandPink.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.vibration_rounded, color: AppColors.brandPink, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Haptic Intensity',
                  style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
                ),
                Text(
                  'Vibration feedback on tap and hold',
                  style: GoogleFonts.inter(color: context.textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          DropdownButton<String>(
            value: intensity,
            dropdownColor: context.surface,
            underline: const SizedBox.shrink(),
            items: options.map((opt) {
              return DropdownMenuItem<String>(
                value: opt,
                child: Text(
                  opt.toUpperCase(),
                  style: GoogleFonts.inter(
                    color: context.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              );
            }).toList(),
            onChanged: (newVal) {
              if (newVal == null) return;
              ref.read(settingsProvider.notifier).updateSetting('chat', 'hapticIntensity', newVal);
              if (newVal == 'light') HapticFeedback.lightImpact();
              if (newVal == 'medium') HapticFeedback.mediumImpact();
              if (newVal == 'heavy') HapticFeedback.heavyImpact();
            },
          ),
        ],
      ),
    );
  }
}
