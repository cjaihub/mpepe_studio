import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../backend/notifications/models/notification_preferences.dart';
import '../../backend/notifications/providers/notification_service.dart';
import '../../backend/notifications/services/follower_alert_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/services/oneova_sound_service.dart';

/// Notification Settings
/// Everything saves instantly to `users/{uid}/settings/notifications`, which the
/// in-app banner, the ring and the server push (functions/src/notifications.ts)
/// all read.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(notificationPreferencesProvider);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        toolbarHeight: 50,
        backgroundColor: AppColors.brandBlue,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: context.topBarFg, size: 18),
          onPressed: () => context.canPop() ? context.pop() : context.go('/hub/home'),
        ),
        title: Text(
          'Notifications',
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800, color: context.topBarFg, letterSpacing: -0.3),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              final p = prefsAsync.value ?? NotificationPreferences();
              OneOvaSoundService().auditionTone(p.soundEnabled ? p.ringtone : 'mute');
            },
            icon: Icon(Icons.notifications_active_rounded, size: 16, color: context.topBarFg),
            label: Text('Test ring', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: context.topBarFg)),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: prefsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandBlue)),
        error: (e, _) => _ErrorState(onRetry: () => ref.invalidate(notificationPreferencesProvider)),
        data: (prefs) => _SettingsBody(prefs: prefs),
      ),
    );
  }
}

class _SettingsBody extends ConsumerWidget {
  final NotificationPreferences prefs;
  const _SettingsBody({required this.prefs});

  void _save(WidgetRef ref, Map<String, dynamic> fields) {
    HapticFeedback.selectionClick();
    ref.read(notificationServiceProvider).updatePreferenceFields({
      ...fields,
      // Lets the server apply quiet hours in the user's own timezone.
      'timezoneOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
    });
  }

  void _setCategories(WidgetRef ref, List<String> categories, bool on) {
    _save(ref, {
      'categoryOverrides': {for (final c in categories) c: on},
    });
  }

  bool _on(List<String> categories) => categories.every(prefs.isCategoryEnabled);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final master = prefs.inAppEnabled || prefs.pushEnabled;

    Widget category(IconData icon, String title, String subtitle, List<String> cats, {Color? tint}) {
      return _ToggleRow(
        icon: icon,
        tint: tint,
        title: title,
        subtitle: subtitle,
        value: _on(cats),
        enabled: master,
        onChanged: (v) => _setCategories(ref, cats, v),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      children: [
        _MasterCard(
          prefs: prefs,
          onChanged: (v) => _save(ref, {'inAppEnabled': v, 'pushEnabled': v}),
        ),
        const SizedBox(height: 12),
        _ModeSelector(
          prefs: prefs,
          enabled: master,
          onSelected: (overrides) => _save(ref, {'categoryOverrides': overrides}),
        ),
        const SizedBox(height: 18),
        _Section(
          title: 'From people you follow',
          children: [
            category(Icons.sensors_rounded, 'Goes live', 'Ring me when a creator I follow starts a live', const ['live'], tint: AppColors.brandPink),
            category(Icons.play_circle_outline_rounded, 'New posts', 'Reels and photos the moment they drop', const ['newPost']),
            _ToggleRow(
              icon: Icons.ring_volume_rounded,
              tint: AppColors.brandPink,
              title: 'Ring for live',
              subtitle: 'Double ring + strong haptic for go-live alerts',
              value: prefs.ringForLive,
              enabled: master && prefs.isCategoryEnabled('live'),
              onChanged: (v) => _save(ref, {'ringForLive': v}),
            ),
            _NavRow(
              icon: Icons.manage_accounts_rounded,
              title: 'Choose creators',
              subtitle: 'Turn posts or live alerts on per person',
              onTap: () => _CreatorAlertsSheet.show(context),
            ),
          ],
        ),
        _Section(
          title: 'Interactions',
          children: [
            category(Icons.favorite_border_rounded, 'Likes & reactions', 'When someone likes your content', const ['like', 'reaction']),
            category(Icons.chat_bubble_outline_rounded, 'Comments & replies', 'New comments and replies to yours', const ['comment', 'reply']),
            category(Icons.alternate_email_rounded, 'Mentions', 'When someone @mentions you', const ['mention']),
            category(Icons.person_add_alt_1_rounded, 'New followers', 'Follows and follow requests', const ['newFollower', 'followRequest']),
            category(Icons.repeat_rounded, 'Shares & reposts', 'When your content is shared', const ['share', 'repost']),
          ],
        ),
        _Section(
          title: 'Messages & calls',
          children: [
            category(Icons.forum_outlined, 'Messages', 'Direct and group chats', const ['newMessage']),
            category(Icons.phone_missed_rounded, 'Missed calls', 'Calls you could not pick up', const ['missedCall']),
            _ToggleRow(
              icon: Icons.visibility_outlined,
              title: 'Show previews',
              subtitle: 'Message text on the lock screen and banners',
              value: prefs.previewMessageContent,
              enabled: master,
              onChanged: (v) => _save(ref, {'previewMessageContent': v}),
            ),
          ],
        ),
        _Section(
          title: 'Sound & ring',
          children: [
            _ToggleRow(
              icon: Icons.volume_up_rounded,
              title: 'Sound',
              subtitle: 'Play a ring with every alert',
              value: prefs.soundEnabled,
              enabled: master,
              onChanged: (v) => _save(ref, {'soundEnabled': v}),
            ),
            _ToneSelector(
              selected: prefs.ringtone,
              enabled: master && prefs.soundEnabled,
              onSelected: (t) => _save(ref, {'ringtone': t}),
            ),
            _ToggleRow(
              icon: Icons.vibration_rounded,
              title: 'Vibrate',
              subtitle: 'Haptic tap with each alert',
              value: prefs.vibrateEnabled,
              enabled: master,
              onChanged: (v) => _save(ref, {'vibrateEnabled': v}),
            ),
            _ToggleRow(
              icon: Icons.looks_one_outlined,
              title: 'Unread badges',
              subtitle: 'Counter on the bell',
              value: prefs.showBadges,
              onChanged: (v) => _save(ref, {'showBadges': v}),
            ),
          ],
        ),
        _Section(
          title: 'Quiet hours',
          children: [
            _QuietHours(
              prefs: prefs,
              onChanged: (fields) => _save(ref, fields),
            ),
          ],
        ),
        _Section(
          title: 'Delivery',
          children: [
            _ToggleRow(
              icon: Icons.notifications_outlined,
              title: 'In-app banners',
              subtitle: 'Drop-down alerts while you use Oneova',
              value: prefs.inAppEnabled,
              onChanged: (v) => _save(ref, {'inAppEnabled': v}),
            ),
            _ToggleRow(
              icon: Icons.phone_iphone_rounded,
              title: 'Push notifications',
              subtitle: 'Alerts when Oneova is closed',
              value: prefs.pushEnabled,
              onChanged: (v) => _save(ref, {'pushEnabled': v}),
            ),
            _ToggleRow(
              icon: Icons.mail_outline_rounded,
              title: 'Email summaries',
              subtitle: 'Occasional digest of what you missed',
              value: prefs.emailEnabled,
              onChanged: (v) => _save(ref, {'emailEnabled': v}),
            ),
          ],
        ),
        _Section(
          title: 'Studio & account',
          children: [
            category(Icons.auto_awesome_outlined, 'AI suggestions', 'Ova tips and finished AI tasks', const ['aiSuggestion', 'automation']),
            category(Icons.insights_rounded, 'Analytics alerts', 'Milestones and reach changes', const ['analyticsAlert']),
            category(Icons.campaign_outlined, 'Product updates', 'News from Oneova', const ['system']),
            const _LockedRow(
              icon: Icons.shield_outlined,
              title: 'Security alerts',
              subtitle: 'Always on to protect your account',
            ),
          ],
        ),
      ].animate(interval: 25.ms).fadeIn(duration: 220.ms).slideY(begin: 0.03, end: 0),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Building blocks
// ─────────────────────────────────────────────────────────────────────────────

class _MasterCard extends StatelessWidget {
  final NotificationPreferences prefs;
  final ValueChanged<bool> onChanged;
  const _MasterCard({required this.prefs, required this.onChanged});

  String _status() {
    final on = prefs.inAppEnabled || prefs.pushEnabled;
    if (!on) return 'Paused — you will not be alerted';
    if (prefs.isInQuietHours()) return 'Quiet hours active · banners muted until ${_hourLabel(prefs.quietHoursEnd)}';
    final parts = <String>[
      prefs.soundEnabled ? 'Ring on' : 'Silent',
      if (prefs.dndEnabled) 'Quiet ${_hourLabel(prefs.quietHoursStart)}–${_hourLabel(prefs.quietHoursEnd)}',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final on = prefs.inAppEnabled || prefs.pushEnabled;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: on
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.brandBlue, AppColors.brandBlue.withValues(alpha: 0.82)],
              )
            : null,
        color: on ? null : context.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: on ? Colors.transparent : context.border, width: 1.0),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: on ? Colors.white.withValues(alpha: 0.16) : context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(
              on ? Icons.notifications_active_rounded : Icons.notifications_paused_rounded,
              color: on ? Colors.white : context.textSecondary,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Allow notifications',
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: on ? Colors.white : context.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  _status(),
                  style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w500, color: on ? Colors.white.withValues(alpha: 0.85) : context.textSecondary),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: on,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.brandPink,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// One-tap presets that rewrite the category switches.
class _ModeSelector extends StatelessWidget {
  final NotificationPreferences prefs;
  final bool enabled;
  final ValueChanged<Map<String, bool>> onSelected;
  const _ModeSelector({required this.prefs, required this.enabled, required this.onSelected});

  static const _social = ['like', 'reaction', 'comment', 'reply', 'mention', 'newFollower', 'followRequest', 'share', 'repost'];
  static const _following = ['live', 'newPost'];
  static const _extras = ['aiSuggestion', 'automation', 'analyticsAlert', 'system'];

  static Map<String, bool> _preset(String id) {
    switch (id) {
      case 'following':
        return {for (final c in _social) c: false, for (final c in _following) c: true, for (final c in _extras) c: false, 'newMessage': true, 'missedCall': true};
      case 'essentials':
        return {for (final c in _social) c: false, for (final c in _following) c: false, for (final c in _extras) c: false, 'mention': true, 'newMessage': true, 'missedCall': true, 'live': true};
      default:
        return {for (final c in [..._social, ..._following, ..._extras, 'newMessage', 'missedCall']) c: true};
    }
  }

  String? _current() {
    for (final id in ['all', 'following', 'essentials']) {
      final p = _preset(id);
      if (p.entries.every((e) => prefs.isCategoryEnabled(e.key) == e.value)) return id;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final current = _current();
    const modes = [
      ('all', 'Everything', Icons.all_inclusive_rounded),
      ('following', 'Following', Icons.people_alt_outlined),
      ('essentials', 'Essentials', Icons.bolt_rounded),
    ];
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: context.surfaceMid,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: context.border, width: 1.0),
        ),
        child: Row(
          children: [
            for (final m in modes)
              Expanded(
                child: GestureDetector(
                  onTap: enabled ? () => onSelected(_preset(m.$1)) : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 36,
                    decoration: BoxDecoration(
                      color: current == m.$1 ? AppColors.brandBlue : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.sm + 1),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(m.$3, size: 14, color: current == m.$1 ? Colors.white : context.textSecondary),
                        const SizedBox(width: 5),
                        Text(
                          m.$2,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: current == m.$1 ? Colors.white : context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              title.toUpperCase(),
              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: context.textMuted),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.border, width: 1.0),
            ),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, indent: 52, color: context.border),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  final IconData icon;
  final Color? tint;
  const _IconTile({required this.icon, this.tint});

  @override
  Widget build(BuildContext context) {
    final c = tint ?? AppColors.brandBlue;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(icon, size: 16, color: c),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final Color? tint;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.tint,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        onTap: enabled ? () => onChanged(!value) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              _IconTile(icon: icon, tint: tint),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary)),
                    const SizedBox(height: 1),
                    Text(subtitle, style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary)),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.82,
                child: Switch.adaptive(
                  value: value,
                  activeThumbColor: Colors.white,
                  activeTrackColor: AppColors.brandBlue,
                  onChanged: enabled ? onChanged : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _NavRow({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            _IconTile(icon: icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary)),
                  const SizedBox(height: 1),
                  Text(subtitle, style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}

class _LockedRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _LockedRow({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          _IconTile(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary)),
                const SizedBox(height: 1),
                Text(subtitle, style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary)),
              ],
            ),
          ),
          Icon(Icons.lock_outline_rounded, size: 15, color: context.textMuted),
        ],
      ),
    );
  }
}

class _ToneSelector extends StatelessWidget {
  final String selected;
  final bool enabled;
  final ValueChanged<String> onSelected;
  const _ToneSelector({required this.selected, required this.enabled, required this.onSelected});

  static const _labels = {
    'celestial': 'Celestial',
    'studio_pop': 'Studio pop',
    'soft_bloom': 'Soft bloom',
    'executive': 'Executive',
    'voice_cue': 'Voice cue',
    'mute': 'Haptic only',
  };

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(52, 2, 12, 10),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final tone in kNotificationTones)
              GestureDetector(
                onTap: enabled
                    ? () {
                        onSelected(tone);
                        OneOvaSoundService().auditionTone(tone);
                      }
                    : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected == tone ? AppColors.brandBlue : context.surfaceMid,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(color: selected == tone ? AppColors.brandBlue : context.border, width: 1.0),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        selected == tone ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded,
                        size: 13,
                        color: selected == tone ? Colors.white : context.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _labels[tone] ?? tone,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: selected == tone ? Colors.white : context.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _hourLabel(int h) {
  final suffix = h < 12 ? 'AM' : 'PM';
  final hour = h % 12 == 0 ? 12 : h % 12;
  return '$hour $suffix';
}

class _QuietHours extends StatelessWidget {
  final NotificationPreferences prefs;
  final ValueChanged<Map<String, dynamic>> onChanged;
  const _QuietHours({required this.prefs, required this.onChanged});

  Future<void> _pick(BuildContext context, bool start) async {
    final initial = TimeOfDay(hour: start ? prefs.quietHoursStart : prefs.quietHoursEnd, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: initial, helpText: start ? 'Quiet from' : 'Quiet until');
    if (picked == null) return;
    onChanged({start ? 'quietHoursStart' : 'quietHoursEnd': picked.hour});
  }

  @override
  Widget build(BuildContext context) {
    Widget timeChip(String label, int hour, bool start) {
      return Expanded(
        child: GestureDetector(
          onTap: prefs.dndEnabled ? () => _pick(context, start) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: context.border, width: 1.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: context.textMuted, letterSpacing: 0.4)),
                const SizedBox(height: 2),
                Text(_hourLabel(hour), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: context.textPrimary)),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        _ToggleRow(
          icon: Icons.bedtime_outlined,
          title: 'Quiet hours',
          subtitle: 'Silence banners and pushes overnight — security still gets through',
          value: prefs.dndEnabled,
          onChanged: (v) => onChanged({'dndEnabled': v}),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: prefs.dndEnabled
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(52, 0, 12, 12),
                  child: Row(
                    children: [
                      timeChip('FROM', prefs.quietHoursStart, true),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.arrow_forward_rounded, size: 14, color: context.textMuted),
                      ),
                      timeChip('UNTIL', prefs.quietHoursEnd, false),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 36, color: context.textMuted),
          const SizedBox(height: 10),
          Text('Could not load your settings', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: context.textPrimary)),
          const SizedBox(height: 10),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue, minimumSize: const Size(0, 38)),
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-creator alerts
// ─────────────────────────────────────────────────────────────────────────────

class _CreatorAlertsSheet extends ConsumerWidget {
  const _CreatorAlertsSheet();

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (_) => const _CreatorAlertsSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creators = ref.watch(followedCreatorAlertsProvider);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(width: 36, height: 4, decoration: BoxDecoration(color: context.border, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Text('Creators you follow', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: context.textPrimary)),
                  const Spacer(),
                  Text('Posts · Live', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: context.textMuted)),
                ],
              ),
            ),
            Divider(height: 1, color: context.border),
            Expanded(
              child: creators.when(
                loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandBlue)),
                error: (_, _) => Center(child: Text('Could not load who you follow', style: GoogleFonts.inter(color: context.textSecondary))),
                data: (list) => list.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Follow creators to choose who can ring you when they post or go live.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(fontSize: 13, color: context.textSecondary),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => Divider(height: 1, indent: 64, color: context.border),
                        itemBuilder: (_, i) => _CreatorAlertRow(setting: list[i]),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreatorAlertRow extends ConsumerWidget {
  final CreatorAlertSetting setting;
  const _CreatorAlertRow({required this.setting});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(alertUserCardProvider(setting.creatorId)).value;
    final name = (user?.fullName.isNotEmpty ?? false) ? user!.fullName : (user?.username ?? 'Creator');
    final photo = user?.profilePhotoUrl;
    final service = ref.read(followerAlertServiceProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: context.surfaceMid,
            backgroundImage: photo != null && photo.isNotEmpty ? NetworkImage(photo) : null,
            child: photo == null || photo.isEmpty
                ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: context.textPrimary))
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary)),
          ),
          _MiniToggle(
            icon: Icons.play_circle_outline_rounded,
            active: setting.posts,
            color: AppColors.brandBlue,
            tooltip: 'New posts',
            onTap: () => service.setCreatorAlerts(setting.creatorId, posts: !setting.posts),
          ),
          const SizedBox(width: 6),
          _MiniToggle(
            icon: Icons.sensors_rounded,
            active: setting.live,
            color: AppColors.brandPink,
            tooltip: 'Live',
            onTap: () => service.setCreatorAlerts(setting.creatorId, live: !setting.live),
          ),
        ],
      ),
    );
  }
}

class _MiniToggle extends StatelessWidget {
  final IconData icon;
  final bool active;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  const _MiniToggle({required this.icon, required this.active, required this.color, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$tooltip ${active ? 'on' : 'off'}',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 34,
          height: 30,
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.14) : context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: active ? color.withValues(alpha: 0.6) : context.border, width: 1.0),
          ),
          child: Icon(active ? icon : Icons.notifications_off_outlined, size: 16, color: active ? color : context.textMuted),
        ),
      ),
    );
  }
}
