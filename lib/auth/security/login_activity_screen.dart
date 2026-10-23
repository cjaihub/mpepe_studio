import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/theme/app_theme.dart';
import '../services/secure_logout_service.dart';
import 'login_history.dart';
import 'login_security.dart';

/// Settings → Security → Login activity: every sign-in and failed attempt on
/// this account, newest first, read live from `users/{uid}/login_history`.
class LoginActivityScreen extends ConsumerStatefulWidget {
  const LoginActivityScreen({super.key});

  @override
  ConsumerState<LoginActivityScreen> createState() => _LoginActivityScreenState();
}

class _LoginActivityScreenState extends ConsumerState<LoginActivityScreen> {
  String? _thisDeviceId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    LoginSecurity.instance.deviceId().then((id) {
      if (mounted) setState(() => _thisDeviceId = id);
    });
  }

  Future<void> _signOutEverywhere() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        title: Text('Sign out of all devices?',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
        content: Text(
          'Every phone and computer signed in to this account is signed out, including this one, '
          'and fingerprint sign-in is removed from them. You will sign in again here with your '
          'password and a text code.',
          style: GoogleFonts.inter(fontSize: 13, color: ctx.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out all', style: TextStyle(color: AppColors.brandPink, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await FirebaseFunctions.instance.httpsCallable('revokeAllSessions').call();
      await ref.read(secureLogoutServiceProvider).logout();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not sign out other devices. Check your connection and try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 50,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary),
          onPressed: () => context.canPop() ? context.pop() : context.go('/profile/security'),
        ),
        title: Text('Login activity',
            style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: context.textPrimary)),
      ),
      body: user == null || user.isAnonymous
          ? const _Empty('Sign in to see your login activity.')
          : StreamBuilder<List<LoginHistoryEntry>>(
              stream: LoginHistory.instance.watch(user.uid),
              builder: (context, snap) {
                if (snap.hasError) return _Empty('Could not load login activity: ${snap.error}');
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.brandBlue, strokeWidth: 2));
                }
                final list = snap.data!;
                final current = list.where((e) => e.success && e.deviceId == _thisDeviceId).firstOrNull;
                final failed = list.where((e) => !e.success).length;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  children: [
                    _section(context, 'This device'),
                    if (current != null)
                      _Card(children: [_EntryTile(entry: current, isThisDevice: true)])
                    else
                      const _Empty('This device has no recorded sign-in yet. It appears after your next sign-in.'),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 42,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _signOutEverywhere,
                        icon: _busy
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandPink))
                            : const Icon(Icons.logout_rounded, size: 18, color: AppColors.brandPink),
                        label: Text('Sign out of all devices',
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.brandPink)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppColors.brandPink.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                        ),
                      ),
                    ),
                    _section(context, failed > 0 ? 'All activity · $failed failed' : 'All activity'),
                    if (list.isEmpty)
                      const _Empty('No sign-ins recorded yet.')
                    else
                      _Card(children: [
                        for (final e in list) _EntryTile(entry: e, isThisDevice: e.deviceId == _thisDeviceId),
                      ]),
                    const SizedBox(height: 12),
                    Text(
                      'Places are approximate: from this phone\'s rough location when you allowed it, '
                      'otherwise from the network. Don\'t recognise a sign-in? Sign out of all devices '
                      'and change your password.',
                      style: GoogleFonts.inter(fontSize: 11, color: context.textMuted, height: 1.4),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

Widget _section(BuildContext context, String title) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 20, 2, 8),
      child: Text(title.toUpperCase(),
          style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: context.textMuted)),
    );

String _when(DateTime? t) {
  if (t == null) return 'just now';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.day}/${t.month}/${t.year} ${two(t.hour)}:${two(t.minute)}';
}

String _methodLabel(String method) {
  const names = {
    'password': 'Password',
    'smsOtp': 'Text code',
    'federated': 'Google',
    'biometric': 'Fingerprint',
    'pin': 'PIN',
    'deviceKey': 'Device key',
    'trustedDevice': 'Trusted device',
  };
  final parts = method.split('+').where((p) => p.isNotEmpty).map((p) => names[p] ?? p).toList();
  return parts.isEmpty ? 'Unknown' : parts.join(' + ');
}

String _failureLabel(String? code) => switch (code) {
      'invalid-verification-code' => 'wrong code',
      'session-expired' => 'code expired',
      'wrong-password' || 'invalid-credential' || 'invalid-login-credentials' || 'legacy-wrong-password' => 'wrong password',
      'too-many-requests' => 'too many tries',
      null || '' => 'failed',
      _ => code,
    };

class _EntryTile extends StatelessWidget {
  final LoginHistoryEntry entry;
  final bool isThisDevice;
  const _EntryTile({required this.entry, required this.isThisDevice});

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final color = e.success ? AppColors.brandBlue : AppColors.brandPink;
    final lines = <String>[
      [e.os, e.osVersion].where((x) => x.isNotEmpty).join(' '),
      if (e.appVersion.isNotEmpty) 'Oneova ${e.appVersion}',
    ].where((x) => x.isNotEmpty).join(' · ');
    final where = [
      if (e.place != null) e.place!,
      if (e.ipMasked != null) 'IP ${e.ipMasked}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(e.success ? Icons.check_circle_rounded : Icons.error_outline_rounded, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        e.deviceModel.isEmpty ? 'Unknown device' : e.deviceModel,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: context.textPrimary),
                      ),
                    ),
                    if (isThisDevice) ...[
                      const SizedBox(width: 6),
                      _Pill('This device', AppColors.brandBlue),
                    ],
                    if (e.newDevice && e.success) ...[
                      const SizedBox(width: 6),
                      _Pill('New', AppColors.brandPink),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  e.success
                      ? 'Signed in with ${_methodLabel(e.method)}'
                      : 'Failed: ${_methodLabel(e.method)}, ${_failureLabel(e.failureCode)}',
                  style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: color),
                ),
                if (lines.isNotEmpty)
                  Text(lines, style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary)),
                if (where.isNotEmpty)
                  Row(children: [
                    Icon(Icons.place_outlined, size: 12, color: context.textMuted),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(where,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 11, color: context.textMuted)),
                    ),
                  ]),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(_when(e.at), style: GoogleFonts.inter(fontSize: 10.5, color: context.textMuted)),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Text(text, style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: color)),
      );
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.border),
        ),
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: context.border, indent: 60),
            children[i],
          ],
        ]),
      );
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Text(text, style: GoogleFonts.inter(fontSize: 12.5, color: context.textMuted)),
      );
}
