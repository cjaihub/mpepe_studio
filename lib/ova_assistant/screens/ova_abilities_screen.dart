import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/theme/app_theme.dart';
import '../services/ova_abilities.dart';
import '../services/ova_device_control.dart';
import '../services/ova_device_hub.dart';

/// Opt-in screen for everything Ova can see or control on this phone.
/// Each ability says what it reads, where the data goes and the Play Store risk.
class OvaAbilitiesScreen extends ConsumerStatefulWidget {
  const OvaAbilitiesScreen({super.key});

  @override
  ConsumerState<OvaAbilitiesScreen> createState() => _OvaAbilitiesScreenState();
}

class _OvaAbilitiesScreenState extends ConsumerState<OvaAbilitiesScreen> with WidgetsBindingObserver {
  OvaAccessStatus _access = const OvaAccessStatus();

  bool get _android => !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from a system settings page: re-check what was granted.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final a = await ref.read(ovaDeviceHubProvider).status();
    if (!mounted) return;
    setState(() => _access = a);
  }

  Future<bool> _confirm(String title, String body) async {
    HapticFeedback.lightImpact();
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl), side: BorderSide(color: ctx.border)),
        title: Text(title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
        content: Text(body, style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: ctx.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: GoogleFonts.inter(color: ctx.textSecondary))),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              minimumSize: const Size(0, 38),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Allow', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _toggleNotifications(bool v) async {
    final n = ref.read(ovaAbilitiesProvider.notifier);
    if (!v) return n.setReadNotifications(false);
    final ok = await _confirm(
      'Let Ova read notifications?',
      'Ova will see the title and text of notifications from your apps (for example WhatsApp messages) so it can tell you what is new and reply when you ask.\n\n'
          'They stay on this phone. Only when you ask Ova about them is the text sent to the AI service to answer.\n\n'
          'Next, Android opens "Notification access": turn on Oneova.',
    );
    if (!ok) return;
    n.setReadNotifications(true);
    if (!_access.notificationAccess) await ref.read(ovaDeviceHubProvider).openNotificationAccess();
  }

  Future<void> _toggleScreen(bool v) async {
    final n = ref.read(ovaAbilitiesProvider.notifier);
    if (!v) return n.setScreenControl(false);
    final ok = await _confirm(
      'Let Ova control the screen?',
      'With the Accessibility service on, Ova can read what is on screen and tap, type and scroll in other apps when you ask it to. '
          'Password fields are never read. Typing, tapping and locking ask for your fingerprint first.\n\n'
          'Next, Android opens Accessibility: tap "Oneova Ova" and turn it on.',
    );
    if (!ok) return;
    n.setScreenControl(true);
    if (!_access.accessibility) await ref.read(ovaDeviceControlProvider).openAccessibilitySettings();
  }

  @override
  Widget build(BuildContext context) {
    final ab = ref.watch(ovaAbilitiesProvider);
    final n = ref.read(ovaAbilitiesProvider.notifier);
    final tiles = <Widget>[
      _section('Everywhere in Oneova'),
      _tile(
        icon: Icons.bubble_chart_rounded,
        title: 'Floating Ova bubble',
        body: 'A small Ova button on every screen. Drag it anywhere; tap for quick actions.',
        value: ab.bubble,
        onChanged: n.setBubble,
      ),
      _tile(
        icon: Icons.auto_awesome_rounded,
        title: 'Live suggestions',
        body: 'Action buttons that change with the screen you are on and what just happened on your phone.',
        value: ab.suggestions,
        onChanged: n.setSuggestions,
      ),
      _tile(
        icon: Icons.notifications_active_rounded,
        title: 'Tell me when a task finishes',
        body: 'A notification when Ova or an AI Lab agent finishes while you are in another app.',
        value: ab.finishAlerts,
        onChanged: n.setFinishAlerts,
      ),
      _section('On this phone'),
      _tile(
        icon: Icons.phone_android_rounded,
        title: 'Device state',
        body: 'Battery, network, storage, memory, ringer, calls in progress and what is playing. No special permission.',
        value: ab.deviceState,
        onChanged: n.setDeviceState,
        androidOnly: true,
        play: _Play.ok,
      ),
      _tile(
        icon: Icons.notifications_rounded,
        title: 'Read & reply to notifications',
        body: 'See new messages from any app and reply from Ova without opening the app. Also shows what music is playing.',
        value: ab.readNotifications,
        onChanged: _toggleNotifications,
        androidOnly: true,
        granted: _access.notificationAccess,
        onGrant: () => ref.read(ovaDeviceHubProvider).openNotificationAccess(),
        play: _Play.disclosure,
      ),
      _infoTile(
        icon: Icons.password_rounded,
        title: 'One-time codes',
        body: 'Sign-in and verification codes fill in by themselves: Google asks "Allow Oneova to read this message?" for that one text. '
            'Oneova never asks for SMS permission and cannot read your other texts.',
        badge: _Play.ok,
      ),
      _tile(
        icon: Icons.accessibility_new_rounded,
        title: 'Screen control',
        body: 'Read the screen and tap, type and scroll inside other apps for multi-step tasks.',
        value: ab.screenControl,
        onChanged: _toggleScreen,
        androidOnly: true,
        granted: _access.accessibility,
        onGrant: () => ref.read(ovaDeviceControlProvider).openAccessibilitySettings(),
        play: _Play.restricted,
      ),
      _tile(
        icon: Icons.do_not_disturb_on_rounded,
        title: 'Do Not Disturb & silent mode',
        body: 'Lets Ova turn Do Not Disturb on or off and switch the phone to silent.',
        value: _access.dndAccess,
        onChanged: (_) => ref.read(ovaDeviceHubProvider).openDndAccess(),
        androidOnly: true,
        play: _Play.ok,
      ),
      const SizedBox(height: 10),
      _linkTile(Icons.gesture_rounded, 'Ways to open Ova', 'Draw "O", button shortcut, lock screen', '/ova/triggers'),
      _linkTile(Icons.key_rounded, 'AI key', 'Needed for chat answers', '/settings/ai'),
      const SizedBox(height: 14),
      Text(
        'Everything Ova reads stays on this phone. The text you ask Ova about is sent to the AI service only to answer that question.',
        style: GoogleFonts.inter(fontSize: 11, height: 1.4, color: context.textMuted),
      ),
    ];

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 50,
        leading: IconButton(icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary), onPressed: () => context.pop()),
        title: Text('Ova abilities', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: context.textPrimary)),
      ),
      body: RefreshIndicator(
        color: AppColors.brandBlue,
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
          children: [
            for (var i = 0; i < tiles.length; i++) tiles[i].animate(delay: (20 * i).ms).fadeIn(duration: 220.ms).slideY(begin: 0.05, end: 0),
          ],
        ),
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
        child: Text(t.toUpperCase(),
            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: context.textMuted)),
      );

  Widget _tile({
    required IconData icon,
    required String title,
    required String body,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool androidOnly = false,
    bool? granted,
    VoidCallback? onGrant,
    _Play? play,
  }) {
    final unavailable = androidOnly && !_android;
    final needsGrant = !unavailable && value && granted == false;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: needsGrant ? AppColors.brandPink.withValues(alpha: 0.5) : context.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: AppColors.brandBlue.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.sm)),
                child: Icon(icon, size: 16, color: AppColors.brandBlue),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
                    const SizedBox(height: 2),
                    Text(body, style: GoogleFonts.inter(fontSize: 11.5, height: 1.35, color: context.textSecondary)),
                    if (play != null && !unavailable) ...[
                      const SizedBox(height: 6),
                      _playBadge(play),
                    ],
                  ],
                ),
              ),
              Switch.adaptive(
                value: unavailable ? false : value,
                activeTrackColor: AppColors.brandBlue,
                onChanged: unavailable
                    ? null
                    : (v) {
                        HapticFeedback.selectionClick();
                        onChanged(v);
                      },
              ),
            ],
          ),
          if (unavailable)
            Padding(
              padding: const EdgeInsets.only(left: 40, top: 4),
              child: Text('Not possible on iOS: Apple does not let apps do this.',
                  style: GoogleFonts.inter(fontSize: 11, color: context.textMuted)),
            ),
          if (needsGrant && onGrant != null)
            Padding(
              padding: const EdgeInsets.only(left: 40, top: 6),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, size: 13, color: AppColors.brandPink),
                const SizedBox(width: 6),
                Expanded(child: Text('Android access is still off.', style: GoogleFonts.inter(fontSize: 11, color: context.textPrimary))),
                TextButton(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: onGrant,
                  child: Text('Turn on', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brandBlue)),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _infoTile({required IconData icon, required String title, required String body, _Play? badge}) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: context.border, width: 1),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: AppColors.brandBlue.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.sm)),
            child: Icon(icon, size: 16, color: AppColors.brandBlue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
              const SizedBox(height: 2),
              Text(body, style: GoogleFonts.inter(fontSize: 11.5, height: 1.35, color: context.textSecondary)),
              if (badge != null) ...[const SizedBox(height: 6), _playBadge(badge)],
            ]),
          ),
        ]),
      );

  Widget _playBadge(_Play p) {
    final (label, color) = switch (p) {
      _Play.ok => ('PLAY STORE OK', AppColors.brandBlue),
      _Play.disclosure => ('PLAY: NEEDS DISCLOSURE', AppColors.brandBlue),
      _Play.restricted => ('PLAY: RESTRICTED API', AppColors.brandPink),
      _Play.blocked => ('PLAY: LIKELY BLOCKED', AppColors.brandPink),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(label, style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: color)),
    );
  }

  Widget _linkTile(IconData icon, String title, String sub, String route) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: context.border),
        ),
        child: ListTile(
          dense: true,
          leading: Icon(icon, size: 18, color: AppColors.brandBlue),
          title: Text(title, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: context.textPrimary)),
          subtitle: Text(sub, style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary)),
          trailing: Icon(Icons.chevron_right_rounded, color: context.textMuted),
          onTap: () {
            HapticFeedback.selectionClick();
            context.push(route);
          },
        ),
      );
}

enum _Play { ok, disclosure, restricted, blocked }
