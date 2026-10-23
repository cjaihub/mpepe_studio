import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/theme/app_theme.dart';
import '../widgets/settings_kit.dart';

/// Reels feed behaviour. Read live by `ShortVideoFeedScreen`, so changes
/// apply to the feed immediately and follow the user across devices.
class ReelsPlaybackSettingsScreen extends ConsumerWidget {
  const ReelsPlaybackSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CompactSettingsScaffold(
      title: 'Reels & Playback',
      children: [
        SettingsAsyncBody(builder: (settings) {
          final data = settingsCategory(settings, 'playback');
          void write(String key, dynamic v, String label) =>
              settingsWrite(ref, category: 'playback', current: data, key: key, value: v, label: label);

          return Column(
            children: [
              SettingsSection(
                label: 'Look',
                children: [
                  SettingsChoiceTile<String>(
                    icon: Icons.contrast_rounded,
                    title: 'Reels theme',
                    subtitle: 'Feed background, top bar and overlays',
                    accent: AppColors.brandPink,
                    options: const {'followApp': 'Follow app', 'dark': 'Always dark'},
                    value: data['reelsTheme'] as String? ?? 'followApp',
                    onChanged: (v) => write('reelsTheme', v, 'Reels theme'),
                  ),
                ],
              ),
              SettingsSection(
                label: 'Playback',
                children: [
                  SettingsSwitchTile(
                    icon: Icons.keyboard_double_arrow_down_rounded,
                    title: 'Auto-scroll',
                    subtitle: 'Move to the next reel when one ends',
                    value: data['autoScroll'] as bool? ?? false,
                    onChanged: (v) => write('autoScroll', v, 'Auto-scroll'),
                  ),
                  SettingsSwitchTile(
                    icon: Icons.repeat_rounded,
                    title: 'Loop videos',
                    subtitle: 'Replay the current reel',
                    value: data['loopVideos'] as bool? ?? true,
                    onChanged: (v) => write('loopVideos', v, 'Loop videos'),
                  ),
                  SettingsSwitchTile(
                    icon: Icons.vibration_rounded,
                    title: 'Like haptics',
                    subtitle: 'Vibrate on double-tap like',
                    accent: AppColors.brandPink,
                    value: data['likeHaptics'] as bool? ?? true,
                    onChanged: (v) => write('likeHaptics', v, 'Like haptics'),
                  ),
                ],
              ),
            ],
          );
        }),
      ],
    );
  }
}
