import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../auth/security/login_security.dart';
import '../../auth/services/oneova_biometrics_service.dart';
import '../../auth/services/secure_logout_service.dart';
import '../../shared/theme/app_theme.dart';
import '../ova_guard_service.dart';

/// Security & login: Ova Guard risk status, alerts, recent security events,
/// signed-in devices, and sign-in protection switches.
class SecurityCenterScreen extends ConsumerStatefulWidget {
  const SecurityCenterScreen({super.key});

  @override
  ConsumerState<SecurityCenterScreen> createState() => _SecurityCenterScreenState();
}

class _SecurityCenterScreenState extends ConsumerState<SecurityCenterScreen> {
  String? _thisDeviceId;
  bool? _fingerprintOn;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    LoginSecurity.instance.deviceId().then((id) {
      if (mounted) setState(() => _thisDeviceId = id);
    });
    _loadFingerprint();
  }

  Future<void> _loadFingerprint() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final bio = ref.read(oneovaBiometricsServiceProvider);
    final on = await bio.isUserEnrolled(uid) && await bio.getEnrolledUserId() == uid;
    if (mounted) setState(() => _fingerprintOn = on);
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? AppColors.brandPink : AppColors.brandBlue,
    ));
  }

  Future<void> _run(Future<void> Function() job, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
      if (done != null) _snack(done);
    } catch (e) {
      _snack('Something went wrong: ${e is Exception ? e.toString().replaceFirst('Exception: ', '') : e}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _secure({String? eventId}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        title: Text('Secure your account?',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
        content: Text(
          'Every device, including this one, is signed out and all fingerprint sign-in keys are removed. '
          'You will sign in again with your password and an SMS code. If someone else changed your password, '
          'use "Forgot password" on the sign-in screen.',
          style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: ctx.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brandPink),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Secure my account'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => ref.read(ovaGuardServiceProvider).secureAccount(eventId: eventId));
  }

  Future<void> _toggleFingerprint(bool on) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final bio = ref.read(oneovaBiometricsServiceProvider);
    await _run(() async {
      final result = on
          ? await bio.enrollUserBiometrics(
              userId: user.uid,
              userEmail: user.email ?? '',
              displayName: user.displayName,
            )
          : await bio.revokeUserBiometrics(userId: user.uid);
      if (!result.isSuccess) throw Exception(result.errorMessage ?? 'Fingerprint check failed.');
      await _loadFingerprint();
    }, done: on ? 'Fingerprint sign-in is on for this phone.' : 'Fingerprint sign-in is off.');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ovaGuardStateProvider).value ?? const <String, dynamic>{};
    final events = ref.watch(ovaGuardEventsProvider);
    final devices = ref.watch(ovaGuardDevicesProvider);
    final open = (events.value ?? const []).where((e) => e.data()['status'] == 'open').toList();

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 50,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary),
          onPressed: () => context.canPop() ? context.pop() : context.go('/profile/me'),
        ),
        title: Text('Security & login',
            style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: context.textPrimary)),
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            _RiskCard(state: state, busy: _busy, onSecure: () => _secure()),
            for (final e in open) ...[
              const SizedBox(height: 10),
              _AlertCard(
                event: e,
                onYes: () => _run(() => ref.read(ovaGuardServiceProvider).confirm(e.id), done: 'Thanks. Marked as you.'),
                onSecure: () => _secure(eventId: e.id),
              ),
            ],
            _section('Recent activity'),
            events.when(
              loading: () => const _Loading(),
              error: (e, _) => _EmptyLine('Could not load activity: $e'),
              data: (list) => list.isEmpty
                  ? const _EmptyLine('No security events yet. New sign-ins and account changes will show here.')
                  : _Card(
                      children: [
                        for (final e in list.take(15))
                          _EventTile(event: e, onTap: () => _showEvent(e)),
                      ],
                    ),
            ),
            _section('Login activity'),
            _Card(children: [
              ListTile(
                dense: true,
                leading: const Icon(Icons.history_rounded, color: AppColors.brandBlue),
                title: Text('See every sign-in',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: context.textPrimary)),
                subtitle: Text('Device, app version, place, method and failed tries',
                    style: GoogleFonts.inter(fontSize: 11, color: context.textMuted)),
                trailing: Icon(Icons.chevron_right_rounded, color: context.textMuted),
                onTap: () => context.push('/settings/login-activity'),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.link_rounded, color: AppColors.brandBlue),
                title: Text('Sign-in methods',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: context.textPrimary)),
                subtitle: Text('Link your phone number and Google to this account',
                    style: GoogleFonts.inter(fontSize: 11, color: context.textMuted)),
                trailing: Icon(Icons.chevron_right_rounded, color: context.textMuted),
                onTap: () => context.push('/settings/sign-in-methods'),
              ),
            ]),
            _section('Where you are signed in'),
            devices.when(
              loading: () => const _Loading(),
              error: (e, _) => _EmptyLine('Could not load devices: $e'),
              data: (list) {
                final active = list.where((d) => d.data()['revoked'] != true).toList();
                if (active.isEmpty) return const _EmptyLine('Devices appear here after they open Oneova.');
                return _Card(children: [
                  for (final d in active)
                    _DeviceTile(
                      device: d,
                      isThis: d.id == _thisDeviceId,
                      onLogOut: () async {
                        if (d.id == _thisDeviceId) {
                          await ref.read(secureLogoutServiceProvider).logout();
                          return;
                        }
                        await _run(() => ref.read(ovaGuardServiceProvider).logOutDevice(d.id),
                            done: 'Logged out. Its fingerprint key was removed; it signs out next time it is online.');
                      },
                    ),
                ]);
              },
            ),
            _section('Sign-in protection'),
            _Card(children: [
              _SwitchRow(
                icon: Icons.verified_user_rounded,
                title: '2-step sign-in',
                subtitle: 'Always on: every sign-in needs two checks, and a new phone needs an SMS code.',
                value: true,
                onChanged: null,
              ),
              _SwitchRow(
                icon: Icons.fingerprint_rounded,
                title: 'Fingerprint sign-in on this phone',
                subtitle: 'The key stays in this phone\'s secure hardware. Oneova stores only its hash.',
                value: _fingerprintOn ?? false,
                onChanged: _fingerprintOn == null ? null : _toggleFingerprint,
              ),
            ]),
            _section('Oneova Shield encryption'),
            const _Card(children: [
              _InfoRow(Icons.lock_rounded, '1:1 chats, photos, videos, voice notes', 'End-to-end encrypted'),
              _InfoRow(Icons.call_rounded, '1:1 and small group calls',
                  'End-to-end (frame encryption) when both apps are up to date; otherwise encrypted in transit (DTLS-SRTP)'),
              _InfoRow(Icons.groups_rounded, 'Group chats', 'Encrypted in transit and at rest, not end-to-end'),
              _InfoRow(Icons.live_tv_rounded, 'Live streams', 'Encrypted in transit (TLS/SRTP); servers relay them to viewers'),
              _InfoRow(Icons.place_rounded, 'Shared locations, Ova assistant', 'Encrypted in transit and at rest, not end-to-end'),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 20, 2, 8),
        child: Text(title.toUpperCase(),
            style: GoogleFonts.inter(
                fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: context.textMuted)),
      );

  void _showEvent(QueryDocumentSnapshot<Map<String, dynamic>> e) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (_) => _EventSheet(event: e),
    );
  }
}

// ───────────────────────── Pieces ─────────────────────────

Color _riskColor(String? risk) => risk == 'high'
    ? AppColors.brandPink
    : risk == 'medium'
        ? AppColors.brandPink.withValues(alpha: 0.7)
        : AppColors.brandBlue;

String _ago(dynamic ts) {
  if (ts is! Timestamp) return 'just now';
  final d = DateTime.now().difference(ts.toDate());
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  if (d.inDays < 30) return '${d.inDays} d ago';
  final t = ts.toDate();
  return '${t.day}/${t.month}/${t.year}';
}

IconData _eventIcon(String? type) => switch (type) {
      'new_device' => Icons.phone_android_rounded,
      'new_country' || 'impossible_travel' => Icons.public_rounded,
      'auth_failures' => Icons.password_rounded,
      'password_changed' => Icons.key_rounded,
      'email_changed' => Icons.alternate_email_rounded,
      'phone_changed' => Icons.sim_card_rounded,
      'message_spike' => Icons.forum_rounded,
      'follow_spike' => Icons.person_add_alt_rounded,
      'session_reuse' => Icons.devices_other_rounded,
      'biometric_key_added' => Icons.fingerprint_rounded,
      'account_secured' => Icons.shield_rounded,
      _ => Icons.login_rounded,
    };

class _RiskCard extends StatelessWidget {
  final Map<String, dynamic> state;
  final bool busy;
  final VoidCallback onSecure;
  const _RiskCard({required this.state, required this.busy, required this.onSecure});

  @override
  Widget build(BuildContext context) {
    final level = state['riskLevel'] as String? ?? 'low';
    final color = _riskColor(level);
    final headline = switch (level) {
      'high' => 'Action needed',
      'medium' => 'Worth a look',
      _ => 'All clear',
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(level == 'low' ? Icons.verified_user_rounded : Icons.gpp_maybe_rounded, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Ova Guard · $headline',
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: context.textPrimary)),
                const SizedBox(height: 2),
                Text(state['riskReason'] as String? ?? 'Watching sign-ins, devices and account changes.',
                    style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary)),
              ]),
            ),
            if (busy)
              const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue)),
          ]),
          const SizedBox(height: 10),
          Text(
            'Ova Guard flags new devices, new countries, impossible travel, failed sign-ins, password/email/phone '
            'changes, message or follow bursts and new fingerprint keys, using fixed rules you can read on each event.',
            style: GoogleFonts.inter(fontSize: 11, height: 1.35, color: context.textMuted),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brandPink,
                side: BorderSide(color: AppColors.brandPink.withValues(alpha: 0.6)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
              onPressed: onSecure,
              icon: const Icon(Icons.lock_reset_rounded, size: 16),
              label: Text('Secure my account', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> event;
  final VoidCallback onYes;
  final VoidCallback onSecure;
  const _AlertCard({required this.event, required this.onYes, required this.onSecure});

  @override
  Widget build(BuildContext context) {
    final e = event.data();
    final reasons = (e['reasons'] as List?)?.cast<String>() ?? const [];
    final where = [e['deviceLabel'], e['geo']?['city'], e['geo']?['country']].whereType<String>().join(' · ');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.5), width: 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_eventIcon(e['type'] as String?), size: 18, color: AppColors.brandPink),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${e['title'] ?? 'Unusual activity'} · Was this you?',
                style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
          ),
        ]),
        const SizedBox(height: 6),
        for (final r in reasons)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text('• $r', style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary)),
          ),
        if (where.isNotEmpty)
          Text('$where · ${_ago(e['at'])}', style: GoogleFonts.inter(fontSize: 11, color: context.textMuted)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 38,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.textPrimary,
                  side: BorderSide(color: context.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                ),
                onPressed: onYes,
                child: Text('Yes, it was me', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 38,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandPink,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                ),
                onPressed: onSecure,
                child: Text('Secure my account', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _EventTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> event;
  final VoidCallback onTap;
  const _EventTile({required this.event, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final e = event.data();
    final risk = e['risk'] as String?;
    final reasons = (e['reasons'] as List?)?.cast<String>() ?? const [];
    final where = [e['deviceLabel'], e['geo']?['country']].whereType<String>().join(' · ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Icon(_eventIcon(e['type'] as String?), size: 18, color: _riskColor(risk)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e['title'] as String? ?? 'Security event',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary)),
              if (reasons.isNotEmpty)
                Text(reasons.first,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary)),
              Text([if (where.isNotEmpty) where, _ago(e['at'])].join(' · '),
                  style: GoogleFonts.inter(fontSize: 10.5, color: context.textMuted)),
            ]),
          ),
          if (risk != null && risk != 'low') _Pill(risk.toUpperCase(), _riskColor(risk)),
        ]),
      ),
    );
  }
}

class _EventSheet extends ConsumerStatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> event;
  const _EventSheet({required this.event});

  @override
  ConsumerState<_EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends ConsumerState<_EventSheet> {
  String? _summary;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _summary = widget.event.data()['aiSummary'] as String?;
  }

  Future<void> _explain() async {
    setState(() => _loading = true);
    try {
      final s = await ref.read(ovaGuardServiceProvider).explain(widget.event.id);
      if (mounted) setState(() => _summary = s.isEmpty ? 'Ova could not explain this one.' : s);
    } catch (e) {
      if (mounted) setState(() => _summary = 'Ova is unavailable right now.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event.data();
    final reasons = (e['reasons'] as List?)?.cast<String>() ?? const [];
    final rows = <(String, String?)>[
      ('Risk', '${(e['risk'] as String? ?? 'low').toUpperCase()} · score ${e['score'] ?? 0}/100'),
      ('Device', e['deviceLabel'] as String?),
      ('Platform', e['platform'] as String?),
      ('Location', [e['geo']?['city'], e['geo']?['country']].whereType<String>().join(', ')),
      ('Network', e['ipMasked'] as String?),
      ('When', _ago(e['at'])),
      ('Status', e['status'] as String?),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e['title'] as String? ?? 'Security event',
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: context.textPrimary)),
          const SizedBox(height: 8),
          Text('Why Ova Guard flagged it',
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: context.textMuted)),
          for (final r in reasons)
            Text('• $r', style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: context.textSecondary)),
          const SizedBox(height: 10),
          for (final (k, v) in rows)
            if (v != null && v.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(children: [
                  SizedBox(
                      width: 78,
                      child: Text(k, style: GoogleFonts.inter(fontSize: 11.5, color: context.textMuted))),
                  Expanded(child: Text(v, style: GoogleFonts.inter(fontSize: 12, color: context.textPrimary))),
                ]),
              ),
          const SizedBox(height: 12),
          if (_summary != null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: context.border),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Ova explains (AI, advisory only)',
                    style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.brandBlue)),
                const SizedBox(height: 4),
                Text(_summary!, style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: context.textPrimary)),
              ]),
            )
          else
            SizedBox(
              height: 38,
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _explain,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.brandBlue,
                  side: BorderSide(color: AppColors.brandBlue.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                ),
                icon: _loading
                    ? const SizedBox(
                        width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue))
                    : const Icon(Icons.auto_awesome_rounded, size: 16),
                label: Text('Explain with Ova', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ),
        ]),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> device;
  final bool isThis;
  final VoidCallback onLogOut;
  const _DeviceTile({required this.device, required this.isThis, required this.onLogOut});

  @override
  Widget build(BuildContext context) {
    final d = device.data();
    final platform = d['platform'] as String? ?? '';
    final where = [d['lastCity'], d['lastCountry']].whereType<String>().join(', ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(children: [
        Icon(platform == 'iOS' ? Icons.phone_iphone_rounded : (platform == 'web' ? Icons.laptop_rounded : Icons.phone_android_rounded),
            size: 20, color: context.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(d['label'] as String? ?? 'Device',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary)),
              ),
              if (isThis) ...[const SizedBox(width: 6), const _Pill('THIS PHONE', AppColors.brandBlue)],
            ]),
            Text([if (where.isNotEmpty) where, 'active ${_ago(d['lastSeenAt'])}'].join(' · '),
                style: GoogleFonts.inter(fontSize: 11, color: context.textMuted)),
          ]),
        ),
        TextButton(
          onPressed: onLogOut,
          style: TextButton.styleFrom(foregroundColor: AppColors.brandPink, visualDensity: VisualDensity.compact),
          child: Text('Log out', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      child: Row(children: [
        Icon(icon, size: 20, color: AppColors.brandBlue),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary)),
            Text(subtitle, style: GoogleFonts.inter(fontSize: 11, height: 1.3, color: context.textMuted)),
          ]),
        ),
        Switch.adaptive(value: value, onChanged: onChanged, activeTrackColor: AppColors.brandBlue),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String status;
  const _InfoRow(this.icon, this.title, this.status);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 17, color: context.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.textPrimary)),
            Text(status, style: GoogleFonts.inter(fontSize: 11, height: 1.3, color: context.textMuted)),
          ]),
        ),
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1),
      ),
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: context.border),
          children[i],
        ],
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(text,
          style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: color)),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
            child: SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue))),
      );
}

class _EmptyLine extends StatelessWidget {
  final String text;
  const _EmptyLine(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Text(text, style: GoogleFonts.inter(fontSize: 12, color: context.textMuted)),
      );
}
