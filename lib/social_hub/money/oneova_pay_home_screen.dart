import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:local_auth/local_auth.dart';

import '../../backend/pay/oneova_pay_service.dart';
import '../../backend/pay/oneova_pay_sheet.dart';
import '../../backend/money/money_service.dart';
import '../../backend/user_service.dart';
import '../../shared/theme/app_theme.dart';

/// Oneova Pay home: the personal balance (top-ups, refunds, deliveries) and the
/// business balance (shop sales, scan to pay), each with its own actions.
/// Balances are live from the server; every action calls the server.
class OneovaPayHomeScreen extends ConsumerStatefulWidget {
  const OneovaPayHomeScreen({super.key, this.business = false, this.asTab = false});
  final bool business;

  /// Shown as the Wallet tab (no back button; the intro plays once per session).
  final bool asTab;

  @override
  ConsumerState<OneovaPayHomeScreen> createState() => _OneovaPayHomeScreenState();
}

class _OneovaPayHomeScreenState extends ConsumerState<OneovaPayHomeScreen> {
  late String _kind = widget.business ? 'business' : 'personal';
  bool _hidden = false;
  static bool _introShown = false;
  late bool _introDone = _introShown || !widget.asTab;
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

  // ─── Sheets for things that need a licence first (honest, no fake data) ───

  void _comingSoon(IconData icon, String title, String body) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: _payGradient),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: c.textPrimary)),
            const SizedBox(height: 6),
            Text(body, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 13.5, height: 1.4, color: c.textSecondary)),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(c);
                context.push('/wallet/scan');
              },
              style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue, minimumSize: const Size.fromHeight(46)),
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
              label: Text('Scan to pay a shop', style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      ),
    );
  }

  void _settings() {
    HapticFeedback.selectionClick();
    Widget tile(BuildContext c, IconData icon, String title, String sub, String route) => ListTile(
          leading: Icon(icon, color: AppColors.brandBlue),
          title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: c.textPrimary)),
          subtitle: Text(sub, style: GoogleFonts.inter(fontSize: 12, color: c.textSecondary)),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () {
            Navigator.pop(c);
            context.push(route);
          },
        );
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            tile(c, Icons.verified_user_rounded, 'Identity and security', 'Verify your ID to receive and withdraw', '/wallet/verify'),
            tile(c, Icons.account_balance_rounded, 'Payout methods', 'Mobile money and bank accounts', '/wallet/withdraw'),
            tile(c, Icons.storefront_rounded, 'Shop earnings', 'Sales and deliveries balance, withdraw', '/biz/payouts'),
            tile(c, Icons.receipt_long_rounded, 'Withdrawals', 'Every withdrawal and its status', '/wallet/withdrawals'),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_introDone) return _Intro(onDone: () => setState(() => _introDone = _introShown = true));
    final business = _kind == 'business';
    final me = ref.watch(currentUserProfileProvider).value;
    final photo = me?.profilePhotoUrl ?? '';
    return Scaffold(
      backgroundColor: context.bg,
      body: SafeArea(
        bottom: false,
        child: StreamBuilder<Map<String, ({int available, int pending, int locked})>>(
          stream: _svc.watchBalances(_kind),
          builder: (context, snap) {
            final balances = snap.data ?? const {};
            final currency = _currency ?? (balances.keys.isNotEmpty ? balances.keys.first : 'KES');
            final b = balances[currency] ?? (available: 0, pending: 0, locked: 0);
            final others = balances.entries.where((e) => e.key != currency && (e.value.available + e.value.pending + e.value.locked) > 0).toList();
            return Stack(children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 120),
                children: [
                  // Header: back (outside the tab), logo, avatar.
                  Row(children: [
                    if (!widget.asTab)
                      IconButton(
                        icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary),
                        onPressed: () => context.canPop() ? context.pop() : context.go('/hub/home'),
                      ),
                    const _PayLogo(size: 30),
                    const SizedBox(width: 8),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: 'Oneova ', style: TextStyle(color: context.textPrimary)),
                        const TextSpan(text: 'Pay', style: TextStyle(color: AppColors.brandBlue)),
                      ]),
                      style: GoogleFonts.inter(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.4),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: _settings,
                      child: CircleAvatar(
                        radius: 19,
                        backgroundColor: context.surfaceMid,
                        backgroundImage: photo.startsWith('http') ? NetworkImage(photo) : null,
                        child: photo.startsWith('http') ? null : Icon(Icons.person_rounded, color: context.textMuted),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  // Personal / business switch.
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(color: context.surfaceMid, borderRadius: BorderRadius.circular(999)),
                    child: Row(children: [
                      for (final (k, label, icon) in const [
                        ('personal', 'Personal', Icons.person_rounded),
                        ('business', 'Business', Icons.storefront_rounded),
                      ])
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _kind = k);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              height: 36,
                              decoration: BoxDecoration(
                                color: _kind == k ? AppColors.brandBlue : Colors.transparent,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(icon, size: 16, color: _kind == k ? Colors.white : context.textSecondary),
                                const SizedBox(width: 6),
                                Text(label,
                                    style: GoogleFonts.inter(
                                        fontSize: 13, fontWeight: FontWeight.w700, color: _kind == k ? Colors.white : context.textSecondary)),
                              ]),
                            ),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  _balanceCard(business, currency, b, others),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.55,
                    children: business
                        ? [
                            _Action(icon: Icons.download_rounded, label: 'Request', onTap: () => context.push('/wallet/receive')),
                            _Action(icon: Icons.account_balance_rounded, label: 'Bank', onTap: () => context.push('/biz/payouts')),
                            _Action(
                              icon: Icons.swap_horiz_rounded,
                              label: 'To personal',
                              onTap: b.available > 0 ? () => _moveToPersonal(currency, b.available) : null,
                            ),
                            _Action(icon: Icons.insights_rounded, label: 'Sales', onTap: () => context.push('/wallet/receive')),
                          ]
                        : [
                            _Action(
                              icon: Icons.send_rounded,
                              label: 'Send',
                              onTap: () => _comingSoon(Icons.send_rounded, 'Send money to people',
                                  'Person-to-person transfers open once Oneova Pay’s e-money licence is in place. You can already pay shops by scanning their code.'),
                            ),
                            _Action(icon: Icons.download_rounded, label: 'Request', onTap: () => context.push('/wallet/receive')),
                            _Action(icon: Icons.account_balance_rounded, label: 'Bank', onTap: () => context.push('/biz/payouts')),
                            _Action(icon: Icons.qr_code_scanner_rounded, label: 'Scan', onTap: () => context.push('/wallet/scan')),
                          ],
                  ),
                  const SizedBox(height: 18),
                  const _CoinsCard(),
                  const SizedBox(height: 18),
                  const _QuickAccess(),
                ],
              ),
              Positioned(left: 14, right: 14, bottom: 12, child: _payBar()),
            ]);
          },
        ),
      ),
    );
  }

  Widget _balanceCard(bool business, String currency, ({int available, int pending, int locked}) b,
      List<MapEntry<String, ({int available, int pending, int locked})>> others) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1A63D6), AppColors.brandBlue, Color(0xFF081F4D)]),
        boxShadow: [BoxShadow(color: AppColors.brandBlue.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(business ? 'Business balance' : 'Total balance',
                  style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.85), fontSize: 13.5, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _hidden = !_hidden);
                },
                child: Icon(_hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.white70, size: 18),
              ),
            ]),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                _hidden ? '$currency ••••' : formatMinor(b.available, currency),
                style: GoogleFonts.inter(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1),
              ),
            ),
            if (!_hidden && (b.pending > 0 || b.locked > 0))
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  [
                    if (b.pending > 0) '${formatMinor(b.pending, currency)} pending',
                    if (b.locked > 0) '${formatMinor(b.locked, currency)} on its way out',
                  ].join(' · '),
                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
                ),
              ),
            for (final e in others)
              Text(_hidden ? '${e.key} ••••' : formatMinor(e.value.available, e.key),
                  style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700)),
            if (!business) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => _topUp(currency),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(999)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 4),
                    Text('Add money', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                  ]),
                ),
              ),
            ],
          ]),
        ),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(colors: [Colors.white.withValues(alpha: 0.22), AppColors.brandPink.withValues(alpha: 0.35)]),
          ),
          child: Icon(business ? Icons.storefront_rounded : Icons.account_balance_wallet_rounded, color: Colors.white, size: 32),
        ),
      ]),
    );
  }

  /// Home · History · Pay (scan) · Cards · Settings.
  Widget _payBar() {
    Widget item(IconData icon, String label, VoidCallback onTap, {bool active = false}) => Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 22, color: active ? AppColors.brandBlue : context.textSecondary),
              const SizedBox(height: 2),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 10.5, fontWeight: active ? FontWeight.w800 : FontWeight.w600, color: active ? AppColors.brandBlue : context.textSecondary)),
            ]),
          ),
        );
    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: context.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Row(children: [
        item(Icons.home_rounded, 'Home', () {}, active: true),
        item(Icons.history_rounded, 'History', () => context.push('/wallet/payments')),
        Expanded(
          child: Center(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                context.push('/wallet/scan');
              },
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF0B1A3D),
                  boxShadow: [BoxShadow(color: AppColors.brandBlue.withValues(alpha: 0.45), blurRadius: 16, offset: const Offset(0, 6))],
                ),
                child: const Center(child: _PayLogo(size: 30)),
              ),
            ),
          ),
        ),
        item(Icons.credit_card_rounded, 'Cards', () => _comingSoon(Icons.credit_card_rounded, 'Your Oneova card',
            'A digital card in Oneova’s design is coming with our card-issuing partner. We never show sample card numbers.')),
        item(Icons.settings_rounded, 'Settings', _settings),
      ]),
    );
  }
}

const _payGradient = LinearGradient(colors: [AppColors.brandBlue, AppColors.brandPink]);

/// Interlocking-loop mark in the brand gradient (Oneova Pay).
class _PayLogo extends StatelessWidget {
  const _PayLogo({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => ShaderMask(
        shaderCallback: (r) => const LinearGradient(colors: [AppColors.brandPink, Color(0xFF7B3CFF), Color(0xFF2D8CFF)]).createShader(r),
        child: Icon(Icons.all_inclusive_rounded, size: size, color: Colors.white),
      );
}

/// Short branded intro the first time the wallet opens in a session.
class _Intro extends StatefulWidget {
  const _Intro({required this.onDone});
  final VoidCallback onDone;

  @override
  State<_Intro> createState() => _IntroState();
}

class _IntroState extends State<_Intro> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1300), () {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: context.bg,
        body: GestureDetector(
          onTap: widget.onDone,
          child: Stack(children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 220,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.brandBlue.withValues(alpha: 0), AppColors.brandBlue.withValues(alpha: 0.35), const Color(0xFF7B3CFF).withValues(alpha: 0.45)],
                  ),
                ),
              ),
            ),
            Center(
              child: FadeTransition(
                opacity: CurvedAnimation(parent: _c, curve: Curves.easeOut),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.9, end: 1).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutBack)),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const _PayLogo(size: 96),
                    const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: 'Oneova ', style: TextStyle(color: context.textPrimary)),
                        const TextSpan(text: 'Pay', style: TextStyle(color: AppColors.brandBlue)),
                      ]),
                      style: GoogleFonts.inter(fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: -1),
                    ),
                    const SizedBox(height: 8),
                    Text('Fast. Secure. Premium.', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: context.textSecondary)),
                    const SizedBox(height: 14),
                    Container(width: 120, height: 3, decoration: BoxDecoration(gradient: _payGradient, borderRadius: BorderRadius.circular(2))),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      );
}

/// Coins (bought) and Diamonds (earned from gifts) — the creator wallet.
class _CoinsCard extends ConsumerWidget {
  const _CoinsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(creatorWalletProvider).value;
    Widget half(IconData icon, Color color, String label, String value, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary)),
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: context.textPrimary)),
                ]),
              ),
            ]),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: context.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: context.border)),
      child: Row(children: [
        half(Icons.monetization_on_rounded, const Color(0xFFF5A524), 'Coins', '${w?.coins ?? 0}', () => context.push('/wallet/coins')),
        Container(width: 1, height: 32, color: context.border, margin: const EdgeInsets.symmetric(horizontal: 10)),
        half(Icons.diamond_rounded, AppColors.brandPink, 'Diamonds', '${w?.availableDiamonds ?? 0}', () => context.push('/wallet/withdraw')),
      ]),
    );
  }
}

/// Shops you can pay right away (open 3D shops).
class _QuickAccess extends StatelessWidget {
  const _QuickAccess();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('biz_shops').where('status', isEqualTo: 'open').limit(3).snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('Quick access', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: context.textPrimary))),
            GestureDetector(
              onTap: () => context.push('/shops'),
              child: Row(children: [
                Text('See all', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.brandBlue)),
                const Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.brandBlue),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          for (final d in docs)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: context.surface,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => context.push('/shops/${d.id}'),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: context.surfaceMid,
                        backgroundImage: '${d.data()['avatarUrl'] ?? ''}'.startsWith('http') ? NetworkImage('${d.data()['avatarUrl']}') : null,
                        child: '${d.data()['avatarUrl'] ?? ''}'.startsWith('http') ? null : const Icon(Icons.storefront_rounded, color: AppColors.brandPink),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${d.data()['name'] ?? 'Shop'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w800, color: context.textPrimary)),
                          Text(
                            (d.data()['tagline'] as String?)?.isNotEmpty == true ? d.data()['tagline'] as String : 'Online store',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 12, color: AppColors.brandBlue),
                          ),
                        ]),
                      ),
                      const Icon(Icons.arrow_forward_rounded, color: AppColors.brandBlue),
                    ]),
                  ),
                ),
              ),
            ),
        ]);
      },
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
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: context.border)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            ShaderMask(
              shaderCallback: (r) => (enabled ? const LinearGradient(colors: [AppColors.brandBlue, Color(0xFF2D8CFF)]) : LinearGradient(colors: [context.textMuted, context.textMuted])).createShader(r),
              child: Icon(icon, color: Colors.white, size: 30),
            ),
            const SizedBox(height: 8),
            Text(label, style: GoogleFonts.inter(fontSize: 14.5, color: enabled ? context.textPrimary : context.textMuted, fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
    );
  }
}
