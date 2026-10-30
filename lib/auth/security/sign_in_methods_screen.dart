import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/theme/app_theme.dart';
import '../auth_repository.dart';
import '../services/account_link_service.dart';
import '../services/oneova_smart_phone_engine.dart';

/// Settings → Security → Sign-in methods. Links a phone number and a Google
/// account to the signed-in Oneova account, so every method opens the same
/// account (one Firebase user, one `users/{uid}` profile).
class SignInMethodsScreen extends ConsumerStatefulWidget {
  const SignInMethodsScreen({super.key});

  @override
  ConsumerState<SignInMethodsScreen> createState() => _SignInMethodsScreenState();
}

class _SignInMethodsScreenState extends ConsumerState<SignInMethodsScreen> {
  bool _busy = false;
  final _phoneEngine = OneovaSmartPhoneEngine();

  User? get _user => FirebaseAuth.instance.currentUser;

  UserInfo? _provider(String id) {
    for (final p in _user?.providerData ?? const <UserInfo>[]) {
      if (p.providerId == id) return p;
    }
    return null;
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.brandBlue,
      content: Text(text),
    ));
  }

  Future<void> _run(Future<void> Function() action, {required String label, required String done}) async {
    setState(() => _busy = true);
    try {
      await action();
      await _user?.reload();
      _toast(done);
    } on FirebaseAuthException catch (e) {
      _toast(AccountLinkService.linkErrorMessage(e, label));
    } catch (e) {
      final text = e.toString();
      if (!text.contains('cancel')) _toast('Could not update your $label: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _linkGoogle() async {
    final user = _user;
    if (user == null) return;
    HapticFeedback.lightImpact();
    await _run(() => ref.read(accountLinkServiceProvider).linkGoogle(user),
        label: 'Google account', done: 'Google is linked. You can sign in with it next time.');
  }

  Future<void> _unlink(String providerId, String label) async {
    final user = _user;
    if (user == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        title: Text('Unlink $label?', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
        content: Text('You won\'t be able to sign in with it until you link it again.',
            style: GoogleFonts.inter(fontSize: 12.5, color: ctx.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Unlink', style: TextStyle(color: AppColors.brandPink)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => ref.read(accountLinkServiceProvider).unlink(user, providerId),
        label: label, done: '$label unlinked.');
  }

  Future<void> _linkPhone() async {
    final user = _user;
    if (user == null) return;
    final country = await _phoneEngine.detectCountrySilently();
    if (!mounted) return;
    final raw = await _prompt(
      title: 'Link a phone number',
      hint: 'Phone number (e.g. ${country.dialCode} ${country.formatHint.replaceFirst('e.g. ', '')})',
      keyboard: TextInputType.phone,
    );
    if (raw == null || raw.trim().isEmpty) return;
    final phone = _phoneEngine.parseAndNormalize(input: raw, fallbackCountry: country).e164;
    if (phone.length < 9) {
      _toast('Please enter a valid phone number.');
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).verifyPhoneNumber(
            phoneNumber: phone,
            verificationCompleted: (cred) async {
              await _run(() => ref.read(accountLinkServiceProvider).linkPhone(user, cred),
                  label: 'phone number', done: '$phone is linked.');
            },
            verificationFailed: (e) {
              if (mounted) setState(() => _busy = false);
              _toast(e.message ?? 'Could not send the code.');
            },
            codeSent: (verificationId, _) async {
              if (mounted) setState(() => _busy = false);
              final code = await _prompt(
                title: 'Enter the code',
                hint: '6-digit code sent to $phone',
                keyboard: TextInputType.number,
              );
              if (code == null || code.trim().length < 6) return;
              final cred = PhoneAuthProvider.credential(verificationId: verificationId, smsCode: code.trim());
              await _run(() => ref.read(accountLinkServiceProvider).linkPhone(user, cred),
                  label: 'phone number', done: '$phone is linked.');
            },
            codeAutoRetrievalTimeout: (_) {},
          );
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _toast('Could not send the code: $e');
    }
  }

  Future<String?> _prompt({required String title, required String hint, required TextInputType keyboard}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        title: Text(title, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: keyboard,
          style: GoogleFonts.inter(fontSize: 13, color: ctx.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(fontSize: 12, color: ctx.textMuted),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(controller.text), child: const Text('Continue')),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final phone = _provider('phone');
    final google = _provider('google.com');
    final others = (_user?.providerData ?? const <UserInfo>[])
        .where((p) => !const {'phone', 'google.com', 'password'}.contains(p.providerId))
        .toList();

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
        title: Text('Sign-in methods',
            style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: context.textPrimary)),
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              'Link every way you sign in, so your phone number and Google open the same Oneova account.',
              style: GoogleFonts.inter(fontSize: 12.5, height: 1.35, color: context.textSecondary),
            ),
            const SizedBox(height: 14),
            Container(
              decoration: AppDecorations.groupedSection(context),
              child: Column(
                children: [
                  _MethodTile(
                    icon: Icons.phone_iphone_rounded,
                    title: 'Phone number',
                    subtitle: phone?.phoneNumber ?? _user?.phoneNumber ?? 'Not linked',
                    linked: phone != null,
                    onLink: _linkPhone,
                    onUnlink: () => _unlink('phone', 'phone number'),
                  ),
                  Divider(height: 1, color: context.border),
                  _MethodTile(
                    icon: Icons.g_mobiledata_rounded,
                    title: 'Google',
                    subtitle: google?.email ?? 'Not linked',
                    linked: google != null,
                    onLink: _linkGoogle,
                    onUnlink: () => _unlink('google.com', 'Google account'),
                  ),
                  for (final p in others) ...[
                    Divider(height: 1, color: context.border),
                    _MethodTile(
                      icon: Icons.link_rounded,
                      title: AccountLinkService.labelFor(p.providerId),
                      subtitle: p.email ?? p.displayName ?? 'Linked',
                      linked: true,
                      onLink: null,
                      onUnlink: () => _unlink(p.providerId, AccountLinkService.labelFor(p.providerId)),
                    ),
                  ],
                ],
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator(color: AppColors.brandBlue)),
            ],
          ],
        ),
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.linked,
    required this.onLink,
    required this.onUnlink,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool linked;
  final VoidCallback? onLink;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: AppColors.brandBlue),
      title: Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: context.textPrimary)),
      subtitle: Text(subtitle, style: GoogleFonts.inter(fontSize: 11, color: context.textMuted)),
      trailing: linked
          ? TextButton(
              onPressed: onUnlink,
              child: Text('Unlink', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: context.textSecondary)),
            )
          : TextButton(
              onPressed: onLink,
              child: Text('Link', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brandBlue)),
            ),
    );
  }
}
