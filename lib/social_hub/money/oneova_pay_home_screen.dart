import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';

import '../../backend/pay/oneova_pay_service.dart';
import '../../backend/pay/oneova_pay_sheet.dart';
import '../../shared/theme/app_theme.dart';

/// Oneova Pay home: the personal balance (top-ups, refunds, deliveries) and the
/// business balance (shop sales, scan to pay), each with its own actions.
/// Balances are live from the server; every action calls the server.
class OneovaPayHomeScreen extends ConsumerStatefulWidget {
  const OneovaPayHomeScreen({super.key, this.business = false});
  final bool business;

  @override
  ConsumerState<OneovaPayHomeScreen> createState() => _OneovaPayHomeScreenState();
}

class _OneovaPayHomeScreenState extends ConsumerState<OneovaPayHomeScreen> {
  late String _kind = widget.business ? 'business' : 'personal';
  bool _hidden = false;
  String? _currency = PayAccount.currency;

  OneovaPayService get _svc => ref.read(oneovaPayServiceProvider);

  @override
  void initState() {
    super.initState();
    if (_currency == null) {
      _svc.options().then((o) {
        if (mounted) setState(() => _currency = o.currency);
      }).catchError((_) {});
    }
  }

  void _toast(String t) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t), behavior: SnackBarBehavior.floating));

  Future<num?> _askAmount(String title, String currency, {int? maxMinor}) async {
    final c = TextEditingController();
    final v = await showModalBottomSheet<num>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: ctx.textPrimary)),
          if (maxMinor != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Available ${formatMinor(maxMinor, currency)}', style: TextStyle(color: ctx.textSecondary, fontSize: 13)),
            ),
          const SizedBox(height: 14),
          TextField(
            controller: c,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(color: ctx.textPrimary, fontSize: 26, fontWeight: FontWeight.w900),
            decoration: InputDecoration(prefixText: '$currency ', hintText: '0', border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, num.tryParse(c.text.replaceAll(',', '').trim())),
            style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue, minimumSize: const Size.fromHeight(48)),
            child: const Text('Continue', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    );
    c.dispose();
    return (v != null && v > 0) ? v : null;
  }

  Future<void> _topUp(String currency) async {
    final v = await _askAmount('Add money', currency);
    if (v == null || !mounted) return;
    final paid = await showOneovaPaySheet(
      context,
      purpose: 'topup',
      topupAmount: v,
      amountMinor: (v * (currencyExponent(currency) == 0 ? 1 : 100)).round(),
      currency: currency,
      title: 'Add to your balance',
    );
    if (paid?.succeeded == true) _toast('Money added.');
  }

  Future<void> _moveToPersonal(String currency, int availableMinor) async {
    final v = await _askAmount('Move to personal', currency, maxMinor: availableMinor);
    if (v == null || !mounted) return;
    final minor = (v * (currencyExponent(currency) == 0 ? 1 : 100)).round();
    if (minor > availableMinor) {
      _toast('That’s more than your business balance.');
      return;
    }
    try {
      final auth = LocalAuthentication();
      if (await auth.isDeviceSupported() &&
          !await auth.authenticate(localizedReason: 'Move ${formatMinor(minor, currency)} to personal', biometricOnly: false, persistAcrossBackgrounding: true)) {
        return;
      }
      await _svc.moveToPersonal(amountMinor: minor, currency: currency, idempotencyKey: 'mv${DateTime.now().microsecondsSinceEpoch}');
      HapticFeedback.mediumImpact();
      _toast('${formatMinor(minor, currency)} moved to your personal balance.');
    } catch (e) {
      _toast(e is FirebaseFunctionsException ? payErrorText(e, fallback: 'Couldn’t move it.') : 'Couldn’t move it.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final business = _kind == 'business';
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary),
          onPressed: () => context.canPop() ? context.pop() : context.go('/hub/home'),
        ),
        title: Text.rich(
          TextSpan(children: [
            TextSpan(text: 'Oneova ', style: TextStyle(color: context.textPrimary)),
            const TextSpan(text: 'Pay', style: TextStyle(color: AppColors.brandBlue)),
          ]),
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'History',
            icon: Icon(Icons.receipt_long_rounded, color: context.textPrimary),
            onPressed: () => context.push('/wallet/payments'),
          ),
        ],
      ),
      body: StreamBuilder<Map<String, ({int available, int pending, int locked})>>(
        stream: _svc.watchBalances(_kind),
        builder: (context, snap) {
          final balances = snap.data ?? const {};
          final currency = _currency ?? (balances.keys.isNotEmpty ? balances.keys.first : 'KES');
          final b = balances[currency] ?? (available: 0, pending: 0, locked: 0);
          final others = balances.entries.where((e) => e.key != currency && (e.value.available + e.value.pending + e.value.locked) > 0).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'personal', label: Text('Personal'), icon: Icon(Icons.person_rounded)),
                  ButtonSegment(value: 'business', label: Text('Business'), icon: Icon(Icons.storefront_rounded)),
                ],
                selected: {_kind},
                showSelectedIcon: false,
                onSelectionChanged: (s) {
                  HapticFeedback.selectionClick();
                  setState(() => _kind = s.first);
                },
                style: SegmentedButton.styleFrom(selectedBackgroundColor: AppColors.brandBlue, selectedForegroundColor: Colors.white),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: AppColors.brandBlue, borderRadius: BorderRadius.circular(AppRadius.xl)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(business ? 'Business balance' : 'Personal balance', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => setState(() => _hidden = !_hidden),
                      child: Icon(_hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.white70, size: 18),
                    ),
                    const Spacer(),
                    Icon(business ? Icons.storefront_rounded : Icons.account_balance_wallet_rounded, color: Colors.white70),
                  ]),
                  const SizedBox(height: 10),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _hidden ? '$currency ••••' : formatMinor(b.available, currency),
                      style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1),
                    ),
                  ),
                  if (!_hidden && (b.pending > 0 || b.locked > 0))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        [
                          if (b.pending > 0) '${formatMinor(b.pending, currency)} pending',
                          if (b.locked > 0) '${formatMinor(b.locked, currency)} on its way out',
                        ].join(' · '),
                        style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                      ),
                    ),
                  for (final e in others)
                    Text(_hidden ? '${e.key} ••••' : formatMinor(e.value.available, e.key), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ]),
              ),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.7,
                children: business
                    ? [
                        _Action(icon: Icons.qr_code_2_rounded, label: 'Request', onTap: () => context.push('/wallet/receive')),
                        _Action(icon: Icons.account_balance_rounded, label: 'Bank', onTap: () => context.push('/biz/payouts')),
                        _Action(
                          icon: Icons.swap_horiz_rounded,
                          label: 'To personal',
                          onTap: b.available > 0 ? () => _moveToPersonal(currency, b.available) : null,
                        ),
                        _Action(icon: Icons.insights_rounded, label: 'Sales', onTap: () => context.push('/wallet/receive')),
                      ]
                    : [
                        _Action(icon: Icons.add_card_rounded, label: 'Top up', onTap: () => _topUp(currency)),
                        _Action(icon: Icons.qr_code_2_rounded, label: 'Request', onTap: () => context.push('/wallet/receive')),
                        _Action(icon: Icons.account_balance_rounded, label: 'Bank', onTap: () => context.push('/biz/payouts')),
                        _Action(icon: Icons.qr_code_scanner_rounded, label: 'Scan', onTap: () => context.push('/wallet/scan')),
                      ],
              ),
              const SizedBox(height: 18),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.receipt_long_rounded, color: AppColors.brandBlue),
                title: Text('Transaction history', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w700)),
                subtitle: Text('Payments, top-ups and refunds', style: TextStyle(color: context.textSecondary, fontSize: 12)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/wallet/payments'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.verified_user_rounded, color: AppColors.brandBlue),
                title: Text('Identity and security', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w700)),
                subtitle: Text('Verify your ID to receive and withdraw', style: TextStyle(color: context.textSecondary, fontSize: 12)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/wallet/verify'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: context.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: enabled ? AppColors.brandBlue : context.textMuted, size: 28),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: enabled ? context.textPrimary : context.textMuted, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}
