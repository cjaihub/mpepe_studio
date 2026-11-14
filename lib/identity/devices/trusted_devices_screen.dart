import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../pay/security/device_key.dart';
import '../../pay/security/face_approval_card.dart';
import '../../pay/security/payment_device_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/compact/compact.dart';

/// `/id/devices`: the phones that can approve payments. Register this phone
/// (hardware key + biometric), confirm it with an email code, check it live
/// with the face card, and remove phones you no longer use.
class TrustedDevicesScreen extends StatefulWidget {
  const TrustedDevicesScreen({super.key});

  @override
  State<TrustedDevicesScreen> createState() => _TrustedDevicesScreenState();
}

class _TrustedDevicesScreenState extends State<TrustedDevicesScreen> {
  final _svc = PaymentDeviceService.instance;
  PaymentDeviceStatus? _status;
  List<PaymentDevice> _devices = const [];
  bool _working = false;
  int _cardKey = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await _svc.status();
      final d = await _svc.list();
      if (mounted) {
        setState(() {
          _status = s;
          _devices = d;
        });
      }
    } catch (e) {
      _toast(_messageOf(e));
      if (mounted) setState(() => _status ??= PaymentDeviceStatus.notRegistered);
    }
  }

  String _messageOf(Object e) => switch (e) {
        FirebaseFunctionsException(:final message) => message ?? 'Something went wrong. Try again.',
        DeviceKeyException() => e.message,
        _ => 'Something went wrong. Try again.',
      };

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _run(Future<void> Function() f) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await f();
    } catch (e) {
      _toast(_messageOf(e));
    } finally {
      if (mounted) setState(() => _working = false);
      await _load();
    }
  }

  Future<void> _register() => _run(() async {
        await _svc.register();
        await _confirmWithEmail();
      });

  Future<void> _confirmWithEmail() async {
    final ok = await context.push<bool>('/auth/email_code?purpose=sensitive_action');
    if (ok != true) return;
    final coolDown = await _svc.trust();
    _toast(coolDown == null
        ? 'This phone can now approve payments.'
        : 'This phone can approve payments. Large payments unlock in 24 hours, because it’s a new phone.');
    setState(() => _cardKey++);
  }

  Future<void> _remove(PaymentDevice d) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove this phone?'),
        content: Text('${d.label} won’t be able to approve payments. You can register it again later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
        ],
      ),
    );
    if (yes == true) await _run(() => _svc.revoke(d.id));
  }

  Future<FaceGateOutcome> _check() async {
    try {
      final r = await _svc.verify(title: 'Check it’s you', subtitle: 'Your fingerprint or face, then Oneova checks this phone’s key');
      if (!r.registered) {
        if (mounted) _load();
        return FaceGateOutcome.notRegistered;
      }
      return r.ok ? FaceGateOutcome.approved : FaceGateOutcome.failed;
    } on DeviceKeyException catch (e) {
      if (e.code != 'cancelled') _toast(e.message);
      return e.code == 'cancelled' ? FaceGateOutcome.cancelled : FaceGateOutcome.failed;
    }
  }

  String _subtitle(PaymentDevice d) {
    final parts = <String>[
      if (d.thisPhone) 'This phone',
      switch (d.hardware) { 'strongbox' => 'StrongBox chip', 'tee' => 'Secure chip', _ => 'Secure key' },
      if (!d.trusted) 'Needs email confirm',
      if (d.trusted && d.coolDownUntil != null && d.coolDownUntil!.isAfter(DateTime.now()))
        'Large payments from ${TimeOfDay.fromDateTime(d.coolDownUntil!).format(context)}',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        toolbarHeight: 50,
        title: Text('Payment phones', style: AppTypography.pageTitle(context.textPrimary)),
      ),
      body: s == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  ..._thisPhone(s),
                  if (_devices.isNotEmpty)
                    CompactGroup(
                      title: 'Phones that can approve payments',
                      children: [
                        for (final d in _devices)
                          CompactRow(
                            icon: d.thisPhone ? Icons.smartphone_rounded : Icons.phone_android_rounded,
                            title: d.label,
                            subtitle: _subtitle(d),
                            dot: !d.trusted,
                            trailing: IconButton(
                              tooltip: 'Remove',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.remove_circle_outline_rounded, size: 20, color: context.textMuted),
                              onPressed: _working ? null : () => _remove(d),
                            ),
                          ),
                      ],
                    ),
                  const CompactSectionHeader('How it keeps you safe'),
                  Text(
                    'Each phone makes its own key inside its security chip. The key only works after your fingerprint or face, '
                    'and it never leaves the phone. Oneova checks the key on every payment. A new phone needs a code from your '
                    'email, and waits 24 hours before large payments.',
                    style: AppTypography.small(context.textSecondary),
                  ),
                ],
              ),
            ),
    );
  }

  List<Widget> _thisPhone(PaymentDeviceStatus s) {
    Widget action(String label, VoidCallback? onTap) => SizedBox(
          height: 40,
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
            onPressed: _working ? null : onTap,
            child: _working
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(label),
          ),
        );
    Widget note(IconData icon, String title, String body, [Widget? button]) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: CompactCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(icon, size: 20, color: AppColors.brandBlue),
                  const SizedBox(width: 10),
                  Expanded(child: Text(title, style: AppTypography.sectionTitle(context.textPrimary))),
                ]),
                const SizedBox(height: 6),
                Text(body, style: AppTypography.small(context.textSecondary)),
                if (button != null) ...[const SizedBox(height: 10), button],
              ],
            ),
          ),
        );
    return switch (s) {
      PaymentDeviceStatus.unsupported => [
          note(Icons.phonelink_erase_rounded, 'This phone can’t approve payments',
              'Payments need a phone with a security chip and a fingerprint or face sensor.'),
        ],
      PaymentDeviceStatus.noBiometrics => [
          note(Icons.fingerprint_rounded, 'Add a fingerprint or face first',
              'Open your phone’s settings, add a fingerprint or face, then come back here.'),
        ],
      PaymentDeviceStatus.notRegistered => [
          note(Icons.phonelink_lock_rounded, 'Register this phone',
              'Make a payment key on this phone. You’ll use your fingerprint or face, then a code from your email.',
              action('Register this phone', _register)),
        ],
      PaymentDeviceStatus.needsTrust => [
          note(Icons.mark_email_read_outlined, 'Confirm this phone',
              'We’ll email you a code to make sure it’s you adding this phone.', action('Send code', () => _run(_confirmWithEmail))),
        ],
      PaymentDeviceStatus.trusted => [
          const SizedBox(height: 8),
          FaceApprovalCard(
            key: ValueKey(_cardKey),
            title: 'Check it’s you',
            subtitle: 'This is how payments are approved',
            onConfirm: _check,
            onRegister: _register,
          ),
        ],
    };
  }
}
