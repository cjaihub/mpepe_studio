import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pinput/pinput.dart';

import '../../shared/theme/app_theme.dart';

/// Email one-time code, sent from Oneova's Gmail (functions/src/emailCodes.ts).
///
/// `/auth/email_code?purpose=verify_email` (default): confirm the account's
/// email, or a new one the user types.
/// `/auth/email_code?purpose=sensitive_action`: a fresh "it's really me"
/// check; pops `true` when it passes.
class EmailCodeScreen extends StatefulWidget {
  final String purpose;
  const EmailCodeScreen({super.key, this.purpose = 'verify_email'});

  @override
  State<EmailCodeScreen> createState() => _EmailCodeScreenState();
}

class _EmailCodeScreenState extends State<EmailCodeScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _sending = false;
  bool _verifying = false;
  bool _sent = false;
  bool _done = false;
  String? _error;
  int _resendIn = 0;
  DateTime? _expiresAt;
  Timer? _tick;

  bool get _verify => widget.purpose != 'sensitive_action';

  @override
  void initState() {
    super.initState();
    _email.text = FirebaseAuth.instance.currentUser?.email ?? '';
  }

  @override
  void dispose() {
    _tick?.cancel();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _device {
    if (kIsWeb) return 'Web';
    return '${Platform.operatingSystem[0].toUpperCase()}${Platform.operatingSystem.substring(1)} ${Platform.operatingSystemVersion.split(' ').first}';
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    if (_verify && !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final res = await FirebaseFunctions.instance.httpsCallable('sendEmailCode').call<Map<String, dynamic>>({
        'purpose': widget.purpose,
        if (_verify) 'email': email,
        'deviceLabel': _device,
        'platform': kIsWeb ? 'web' : Platform.operatingSystem,
      });
      final mins = (res.data['expiresInMinutes'] as num?)?.toInt() ?? 10;
      final resend = (res.data['resendInSeconds'] as num?)?.toInt() ?? 60;
      if (!mounted) return;
      setState(() {
        _sent = true;
        _expiresAt = DateTime.now().add(Duration(minutes: mins));
        _resendIn = resend;
      });
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        setState(() => _resendIn = (_resendIn - 1).clamp(0, 9999));
      });
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'Could not send the code.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not send the code. Check your connection.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _check(String code) async {
    if (_verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await FirebaseFunctions.instance.httpsCallable('verifyEmailCode').call<Map<String, dynamic>>({
        'purpose': widget.purpose,
        if (_verify) 'email': _email.text.trim(),
        'code': code,
      });
      await FirebaseAuth.instance.currentUser?.reload();
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _done = true);
      if (!_verify) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (mounted) context.pop(true);
      }
    } on FirebaseFunctionsException catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        setState(() => _error = e.message ?? 'That code didn’t work.');
        _code.clear();
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pin = PinTheme(
      width: 44,
      height: 50,
      textStyle: GoogleFonts.inter(fontSize: 19, fontWeight: FontWeight.w700, color: context.textPrimary),
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: context.border, width: 1),
      ),
    );
    final title = _verify ? 'Verify your email' : 'Confirm it’s you';
    final lead = _verify
        ? 'We’ll email a 6-digit code from Oneova Security. It expires in 10 minutes.'
        : 'We’ll email a 6-digit code to the address on your account before this change.';

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 50,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary),
          onPressed: () => context.canPop() ? context.pop(false) : context.go('/hub/home'),
        ),
        title: Text(title, style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: context.textPrimary)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppColors.brandBlue.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.md)),
              child: Icon(_done ? Icons.verified_rounded : Icons.mark_email_unread_rounded, color: AppColors.brandBlue, size: 22),
            ).animate().fadeIn(duration: 220.ms).scaleXY(begin: 0.9, end: 1),
            const SizedBox(height: 14),
            Text(lead, style: GoogleFonts.inter(fontSize: 13, height: 1.4, color: context.textSecondary)),
            const SizedBox(height: 16),
            if (_done)
              _doneCard(context)
            else ...[
              if (_verify)
                TextField(
                  controller: _email,
                  enabled: !_sent,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  style: GoogleFonts.inter(fontSize: 13.5, color: context.textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Email',
                    labelStyle: GoogleFonts.inter(fontSize: 12.5, color: context.textMuted),
                    prefixIcon: Icon(Icons.alternate_email_rounded, size: 18, color: context.textMuted),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: const BorderSide(color: AppColors.brandBlue)),
                    disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border)),
                  ),
                ),
              if (_sent) ...[
                const SizedBox(height: 18),
                Text('Enter the code', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
                const SizedBox(height: 10),
                Center(
                  child: Pinput(
                    controller: _code,
                    length: 6,
                    autofocus: true,
                    defaultPinTheme: pin,
                    focusedPinTheme: pin.copyBorderWith(border: Border.all(color: AppColors.brandBlue, width: 1)),
                    errorPinTheme: pin.copyBorderWith(border: Border.all(color: AppColors.brandPink, width: 1)),
                    forceErrorState: _error != null,
                    onCompleted: _check,
                  ),
                ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.08, end: 0),
                const SizedBox(height: 10),
                Row(children: [
                  Icon(Icons.schedule_rounded, size: 14, color: context.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _expiresAt == null ? '' : 'Expires at ${TimeOfDay.fromDateTime(_expiresAt!).format(context)} · works once',
                      style: GoogleFonts.inter(fontSize: 11.5, color: context.textMuted),
                    ),
                  ),
                  TextButton(
                    onPressed: _resendIn > 0 || _sending ? null : _send,
                    child: Text(_resendIn > 0 ? 'Resend in ${_resendIn}s' : 'Resend',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: _resendIn > 0 ? context.textMuted : AppColors.brandBlue)),
                  ),
                ]),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.error_outline_rounded, size: 15, color: AppColors.brandPink),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_error!, style: GoogleFonts.inter(fontSize: 12, color: context.textPrimary))),
                ]).animate().shakeX(hz: 4, amount: 3, duration: 300.ms),
              ],
              const SizedBox(height: 18),
              if (!_sent)
                SizedBox(
                  height: 42,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                    ),
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded, size: 17, color: Colors.white),
                    label: Text('Email me a code', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ),
              if (_verifying)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: LinearProgressIndicator(minHeight: 2, color: AppColors.brandBlue),
                ),
              const SizedBox(height: 18),
              Text(
                'Oneova will never ask for this code by phone, chat or email. If you get a code you didn’t ask for, open Profile → Security.',
                style: GoogleFonts.inter(fontSize: 11, height: 1.4, color: context.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _doneCard(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.5)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_verify ? 'Email verified' : 'Confirmed',
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: context.textPrimary)),
          const SizedBox(height: 4),
          Text(
            _verify ? '${_email.text.trim()} is now verified on your account. Security alerts will go there.' : 'You can continue.',
            style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: context.textSecondary),
          ),
          if (_verify) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: context.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                ),
                onPressed: () => context.canPop() ? context.pop(true) : context.go('/hub/home'),
                child: Text('Done', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: context.textPrimary)),
              ),
            ),
          ],
        ]),
      ).animate().fadeIn(duration: 240.ms).slideY(begin: 0.06, end: 0);
}
