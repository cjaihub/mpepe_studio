import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../backend/notifications/models/notification_preferences.dart';
import '../../../backend/notifications/providers/notification_service.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class NotificationPreferencesScreen extends ConsumerWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(notificationPreferencesProvider);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: context.textPrimary),
        title: Text(
          'Notification Settings',
          style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w700),
        ),
      ),
      body: prefsAsync.when(
        data: (prefs) => _buildPreferencesList(context, ref, prefs),
        loading: () => const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),
        error: (err, stack) => Center(
          child: Text('Error loading preferences: $err', style: TextStyle(color: context.textPrimary)),
        ),
      ),
    );
  }

  Widget _buildPreferencesList(BuildContext context, WidgetRef ref, NotificationPreferences prefs) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader(context, 'Quiet Hours (Do Not Disturb)'),
        _buildSwitchTile(
          context: context,
          title: 'Enable Do Not Disturb',
          subtitle: 'Mutes notifications during quiet hours.',
          value: prefs.dndEnabled,
          onChanged: (val) {
            _updatePrefs(ref, prefs, dndEnabled: val);
          },
        ),
        if (prefs.dndEnabled) ...[
          _buildTimeSelector(
            context: context,
            title: 'Start Time',
            hour: prefs.quietHoursStart,
            onChanged: (val) => _updatePrefs(ref, prefs, quietHoursStart: val),
          ),
          _buildTimeSelector(
            context: context,
            title: 'End Time',
            hour: prefs.quietHoursEnd,
            onChanged: (val) => _updatePrefs(ref, prefs, quietHoursEnd: val),
          ),
        ],
        const SizedBox(height: 24),
        _buildSectionHeader(context, 'Delivery Methods'),
        _buildSwitchTile(
          context: context,
          title: 'Push Notifications',
          value: prefs.pushEnabled,
          onChanged: (val) => _updatePrefs(ref, prefs, pushEnabled: val),
        ),
        _buildSwitchTile(
          context: context,
          title: 'Email Notifications',
          value: prefs.emailEnabled,
          onChanged: (val) => _updatePrefs(ref, prefs, emailEnabled: val),
        ),
        const SizedBox(height: 24),
        _buildSectionHeader(context, 'Notification Categories'),
        _buildCategoryTile(context, ref, prefs, 'messages', 'Direct Messages'),
        _buildCategoryTile(context, ref, prefs, 'mentions', 'Mentions & Tags'),
        _buildCategoryTile(context, ref, prefs, 'reactions', 'Reactions & Likes'),
        _buildCategoryTile(context, ref, prefs, 'follows', 'New Followers'),
        _buildCategoryTile(context, ref, prefs, 'calls', 'Incoming Calls'),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0, top: 8.0),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.inter(
          color: context.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required BuildContext context,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 16),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: GoogleFonts.inter(color: context.textMuted, fontSize: 13),
            )
          : null,
      value: value,
      activeThumbColor: AppColors.brandBlue,
      onChanged: onChanged,
    );
  }

  Widget _buildCategoryTile(BuildContext context, WidgetRef ref, NotificationPreferences prefs, String categoryId, String title) {
    final isEnabled = prefs.categoryOverrides[categoryId] ?? true;
    return _buildSwitchTile(
      context: context,
      title: title,
      value: isEnabled,
      onChanged: (val) {
        final newOverrides = Map<String, bool>.from(prefs.categoryOverrides);
        newOverrides[categoryId] = val;
        _updatePrefs(ref, prefs, categoryOverrides: newOverrides);
      },
    );
  }

  Widget _buildTimeSelector({
    required BuildContext context,
    required String title,
    required int hour,
    required ValueChanged<int> onChanged,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w500),
      ),
      trailing: DropdownButton<int>(
        dropdownColor: context.surfaceMid,
        value: hour,
        underline: const SizedBox(),
        items: List.generate(24, (index) {
          final ampm = index < 12 ? 'AM' : 'PM';
          final h = index == 0 ? 12 : (index > 12 ? index - 12 : index);
          return DropdownMenuItem(
            value: index,
            child: Text(
              '$h:00 $ampm',
              style: GoogleFonts.inter(color: context.textPrimary),
            ),
          );
        }),
        onChanged: (val) {
          if (val != null) onChanged(val);
        },
      ),
    );
  }

  void _updatePrefs(
    WidgetRef ref,
    NotificationPreferences oldPrefs, {
    bool? pushEnabled,
    bool? emailEnabled,
    bool? dndEnabled,
    int? quietHoursStart,
    int? quietHoursEnd,
    Map<String, bool>? categoryOverrides,
  }) {
    final newPrefs = NotificationPreferences(
      pushEnabled: pushEnabled ?? oldPrefs.pushEnabled,
      emailEnabled: emailEnabled ?? oldPrefs.emailEnabled,
      inAppEnabled: oldPrefs.inAppEnabled,
      soundEnabled: oldPrefs.soundEnabled,
      ringtone: oldPrefs.ringtone,
      vibrateEnabled: oldPrefs.vibrateEnabled,
      desktopEnabled: oldPrefs.desktopEnabled,
      mobileEnabled: oldPrefs.mobileEnabled,
      previewMessageContent: oldPrefs.previewMessageContent,
      dndEnabled: dndEnabled ?? oldPrefs.dndEnabled,
      quietHoursStart: quietHoursStart ?? oldPrefs.quietHoursStart,
      quietHoursEnd: quietHoursEnd ?? oldPrefs.quietHoursEnd,
      categoryOverrides: categoryOverrides ?? oldPrefs.categoryOverrides,
    );

    ref.read(notificationServiceProvider).updatePreferences(newPrefs);
  }
}
