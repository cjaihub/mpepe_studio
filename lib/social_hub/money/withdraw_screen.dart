import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../backend/money/insights_logic.dart';
import '../../backend/money/money_models.dart';
import '../../backend/money/money_service.dart';
import '../../shared/theme/app_theme.dart';
import 'money_widgets.dart';

/// Withdraw earnings (`/wallet/withdraw`). Identity must be verified first;
/// the country comes from location (falling back to SIM / phone / language),
/// which picks the rails: mobile money and banks in Africa, Stripe elsewhere.
class WithdrawScreen extends ConsumerStatefulWidget {
  const WithdrawScreen({super.key});

  @override
  ConsumerState<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends ConsumerState<WithdrawScreen> {
  late Future<PayoutOptions> _options = _detect();
  String? _methodId;
  double? _usd;
  bool _sending = false;
  Map<String, dynamic>? _result;

  Future<PayoutOptions> _detect() async {
    final svc = ref.read(moneyServiceProvider);
    await svc.syncWallet();
    return svc.payoutOptions();
  }

  @override
  Widget build(BuildContext context) {
    if (_result != null) return _Success(result: _result!);
    final kyc = ref.watch(kycProvider);
    final wallet = ref.watch(creatorWalletProvider).value ?? const CreatorWallet();
    return MoneyScaffold(
      title: 'Withdraw',
      actions: [
        IconButton(
          tooltip: 'All withdrawals',
          icon: Icon(Icons.receipt_long_rounded, size: 20, color: context.textSecondary),
          onPressed: () => context.push('/wallet/withdrawals'),
        ),
      ],
      body: kyc.isLoading && !kyc.hasValue
          ? const Center(child: CircularProgressIndicator(color: AppColors.brandBlue))
          : !(kyc.value?.verified ?? false)
              ? _VerifyGate(wallet: wallet, kyc: kyc.value ?? const KycState())
              : FutureBuilder<PayoutOptions>(
                  future: _options,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return _Problem(message: moneyError(snap.error!), onRetry: () => setState(() => _options = _detect()));
                    }
                    if (!snap.hasData) return const _Detecting();
                    return _form(snap.data!, wallet);
                  },
                ),
    );
  }

  Widget _form(PayoutOptions o, CreatorWallet wallet) {
    final methods = (ref.watch(payoutMethodsProvider).value ?? const <PayoutMethod>[])
        .where((m) => o.rails.any((r) => r.rail == m.rail && r.provider == m.provider) && m.country == o.country || (m.rail == 'stripe' && o.rails.any((r) => r.rail == 'stripe')))
        .toList();
    final method = methods.where((m) => m.id == _methodId).firstOrNull ?? methods.firstOrNull;
    final maxUsd = min(wallet.availableUsd, o.maxUsd > 0 ? o.maxUsd : wallet.availableUsd);
    final enough = maxUsd >= o.minUsd;
    final usd = enough ? (_usd ?? maxUsd).clamp(o.minUsd, maxUsd).toDouble() : 0.0;
    final fee = method == null ? 0.0 : PayoutOptions.feeFor(method.rail, usd);
    final net = max(0.0, usd - fee);
    final localCurrency = method?.rail == 'stripe' ? 'USD' : o.currency;
    final rate = localCurrency == 'USD' ? 1.0 : (o.usdRate ?? 0);

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _CountryCard(o: o, onRedetect: () => setState(() => _options = _detect())),
        const SizedBox(height: 12),
        if (!enough)
          GrowthBanner(
            title: 'Almost there!',
            body: wallet.availableUsd + wallet.pendingUsd >= o.minUsd
                ? '${money(wallet.pendingUsd, 'USD')} is still in its $holdDays-day hold. It unlocks soon, then you can withdraw.'
                : 'You need ${money(o.minUsd - wallet.availableUsd, 'USD')} more to withdraw. Every gift gets you closer.',
          )
        else
          GrowthBanner(title: 'Your hard work pays 💪', body: 'You have ${money(wallet.availableUsd, 'USD')} ready. Send it home in a few taps.'),
        const SectionTitle('Send to'),
        if (o.rails.isEmpty)
          MoneyCard(
            child: Text(
              'Payouts in ${o.countryName ?? o.country} are opening soon. Your Diamonds stay safe in your wallet until then.',
              style: TextStyle(fontSize: 12.5, color: context.textSecondary),
            ),
          )
        else ...[
          for (final m in methods)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _MethodTile(
                m: m,
                selected: m.id == method?.id,
                onTap: () => setState(() => _methodId = m.id),
                onDelete: () => ref.read(moneyServiceProvider).deletePayoutMethod(m.id),
              ),
            ),
          MoneyCard(
            onTap: () => _addMethod(o),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.add_circle_outline_rounded, size: 20, color: AppColors.brandBlue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    o.rails.map((r) => r.label).join(' · '),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.brandBlue),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (enough && method != null) ...[
          const SectionTitle('Amount'),
          MoneyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(money(usd, 'USD'), style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: context.textPrimary)),
                if (rate > 0 && localCurrency != 'USD')
                  Text('≈ ${money(net * rate, localCurrency)} after fees', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.textSecondary)),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(activeTrackColor: AppColors.brandBlue, thumbColor: AppColors.brandBlue, inactiveTrackColor: context.surfaceMid),
                  child: Slider(
                    value: usd,
                    min: o.minUsd,
                    max: max(maxUsd, o.minUsd + 0.01),
                    onChanged: maxUsd > o.minUsd ? (v) => setState(() => _usd = (v * 100).roundToDouble() / 100) : null,
                  ),
                ),
                Row(
                  children: [
                    for (final f in const [0.25, 0.5, 1.0])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(f == 1 ? 'All' : '${(f * 100).round()}%'),
                          selected: (usd - max(o.minUsd, maxUsd * f)).abs() < 0.01,
                          showCheckmark: false,
                          selectedColor: AppColors.brandBlue,
                          labelStyle: TextStyle(fontSize: 12, color: (usd - max(o.minUsd, maxUsd * f)).abs() < 0.01 ? Colors.white : context.textPrimary),
                          onSelected: (_) => setState(() => _usd = (max(o.minUsd, maxUsd * f) * 100).floorToDouble() / 100),
                        ),
                      ),
                  ],
                ),
                Divider(height: 22, color: context.border),
                _row('Amount', money(usd, 'USD')),
                _row('Transfer fee', '− ${money(fee, 'USD')}'),
                _row('You receive', localCurrency == 'USD' || rate == 0 ? money(net, 'USD') : money(net * rate, localCurrency), bold: true),
                if (localCurrency != 'USD' && rate > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Rate 1 USD = ${rate.toStringAsFixed(rate >= 100 ? 0 : 2)} $localCurrency. The final amount uses the rate at sending time.',
                        style: TextStyle(fontSize: 10.5, color: context.textMuted)),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: PrimaryButton(
              label: 'Withdraw ${money(usd, 'USD')}',
              icon: Icons.north_east_rounded,
              busy: _sending,
              onPressed: () => _confirm(method, usd, fee, net, rate, localCurrency),
            ),
          ),
        ],
      ],
    );
  }

  Widget _row(String a, String b, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(a, style: TextStyle(fontSize: 12.5, color: context.textSecondary))),
            Text(b, style: TextStyle(fontSize: bold ? 14 : 12.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: context.textPrimary)),
          ],
        ),
      );

  Future<void> _addMethod(PayoutOptions o) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (_) => _AddMethodSheet(options: o, holder: ref.read(kycProvider).value?.verifiedName ?? ''),
    );
    if (id != null && mounted) setState(() => _methodId = id);
  }

  Future<void> _confirm(PayoutMethod m, double usd, double fee, double net, double rate, String currency) async {
    final key = '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Confirm withdrawal', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: context.textPrimary)),
              const SizedBox(height: 14),
              _row('To', '${m.label} ••${m.last4}'),
              _row('Name', m.holderName),
              _row('Amount', money(usd, 'USD')),
              _row('Fee', money(fee, 'USD')),
              _row('You receive', currency == 'USD' || rate == 0 ? money(net, 'USD') : '≈ ${money(net * rate, currency)}', bold: true),
              const SizedBox(height: 16),
              PrimaryButton(label: 'Confirm and send', icon: Icons.fingerprint_rounded, onPressed: () => Navigator.pop(ctx, true)),
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;

    // Device lock (fingerprint, face or PIN) when the phone has one.
    final auth = LocalAuthentication();
    try {
      if (await auth.isDeviceSupported()) {
        final passed = await auth.authenticate(localizedReason: 'Confirm your withdrawal of ${money(usd, 'USD')}', biometricOnly: false, persistAcrossBackgrounding: true);
        if (!passed) return;
      }
    } on PlatformException catch (e) {
      debugPrint('[Withdraw] device auth: ${e.code}');
    }

    setState(() => _sending = true);
    try {
      final r = await ref.read(moneyServiceProvider).requestWithdrawal(
            diamonds: (usd / diamondUsd).floor(),
            methodId: m.id,
            idempotencyKey: key,
          );
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _result = {...r, 'methodLabel': '${m.label} ••${m.last4}'});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(moneyError(e)), behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

class _Detecting extends StatelessWidget {
  const _Detecting();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.5), width: 1.5)),
                  )
                      .animate(onPlay: (c) => c.repeat(), delay: (i * 500).ms)
                      .scaleXY(begin: 0.2, end: 1, duration: 1500.ms, curve: Curves.easeOut)
                      .fadeOut(duration: 1500.ms),
                Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.premiumGradient),
                  child: const Icon(Icons.my_location_rounded, color: Colors.white, size: 22),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('Finding the best way to pay you…', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.textPrimary)),
          const SizedBox(height: 4),
          Text('We use your location to show local options.', style: TextStyle(fontSize: 12, color: context.textSecondary)),
        ],
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off_rounded, size: 40, color: context.textMuted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: context.textSecondary)),
            const SizedBox(height: 16),
            SizedBox(width: 180, child: PrimaryButton(label: 'Try again', onPressed: onRetry)),
          ],
        ),
      ),
    );
  }
}

class _CountryCard extends StatelessWidget {
  const _CountryCard({required this.o, required this.onRedetect});
  final PayoutOptions o;
  final VoidCallback onRedetect;

  @override
  Widget build(BuildContext context) {
    final from = switch (o.source) {
      'location' => 'your location',
      'sim' => 'your SIM card',
      'phone' => 'your phone number',
      'id' => 'your ID',
      _ => 'your phone’s language',
    };
    final flag = o.country.length == 2 ? String.fromCharCodes(o.country.codeUnits.map((c) => 0x1F1E6 + c - 65)) : '🌍';
    return MoneyCard(
      child: Row(
        children: [
          Text(flag, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Paying out in ${o.countryName ?? o.country}', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
                Text('Found from $from · ${o.africa ? 'local mobile money & banks' : 'bank or card via Stripe'}',
                    style: TextStyle(fontSize: 11.5, color: context.textSecondary)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Detect again',
            icon: const Icon(Icons.my_location_rounded, size: 19, color: AppColors.brandBlue),
            onPressed: onRedetect,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms);
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({required this.m, required this.selected, required this.onTap, required this.onDelete});
  final PayoutMethod m;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final icon = switch (m.rail) {
      'mobile_money' => Icons.phone_android_rounded,
      'bank' => Icons.account_balance_rounded,
      _ => Icons.credit_card_rounded,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.brandBlue.withValues(alpha: 0.08) : context.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: selected ? AppColors.brandBlue : context.border, width: selected ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: selected ? AppColors.brandBlue : context.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${m.label} ••${m.last4}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.textPrimary)),
                    Text(m.holderName, style: TextStyle(fontSize: 11, color: context.textMuted)),
                  ],
                ),
              ),
              Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, size: 18, color: selected ? AppColors.brandBlue : context.textMuted),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, size: 18, color: context.textMuted),
                onSelected: (_) => onDelete(),
                itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Remove'))],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddMethodSheet extends ConsumerStatefulWidget {
  const _AddMethodSheet({required this.options, required this.holder});
  final PayoutOptions options;
  final String holder;

  @override
  ConsumerState<_AddMethodSheet> createState() => _AddMethodSheetState();
}

class _AddMethodSheetState extends ConsumerState<_AddMethodSheet> with WidgetsBindingObserver {
  late RailOption _rail = widget.options.rails.first;
  String? _network;
  final _phone = TextEditingController();
  final _account = TextEditingController();
  ({String code, String name})? _bank;
  Future<List<({String code, String name})>>? _banks;
  bool _busy = false;
  bool _waitingForStripe = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _phone.dispose();
    _account.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Stripe onboarding: save the method if payouts are on.
    if (state == AppLifecycleState.resumed && _waitingForStripe) {
      _waitingForStripe = false;
      _save();
    }
  }

  InputDecoration _dec(String hint, {String? prefix}) => InputDecoration(
        isDense: true,
        hintText: hint,
        prefixText: prefix,
        hintStyle: TextStyle(fontSize: 12.5, color: context.textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border)),
      );

  Future<void> _save() async {
    final svc = ref.read(moneyServiceProvider);
    setState(() => _busy = true);
    try {
      if (_rail.rail == 'stripe') {
        final enabled = await svc.refreshStripe().catchError((_) => false);
        if (!enabled) {
          final url = await svc.stripeOnboardingUrl(widget.options.country);
          _waitingForStripe = true;
          await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
          return;
        }
      }
      final id = await svc.savePayoutMethod({
        'rail': _rail.rail,
        'country': widget.options.country,
        if (_rail.rail == 'mobile_money') 'network': _network,
        if (_rail.rail == 'mobile_money') 'msisdn': _phone.text,
        if (_rail.rail == 'bank') 'bankCode': _bank?.code,
        if (_rail.rail == 'bank') 'bankName': _bank?.name,
        if (_rail.rail == 'bank') 'accountNumber': _account.text,
      });
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(moneyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rails = widget.options.rails;
    final canSave = switch (_rail.rail) {
      'mobile_money' => _network != null && _phone.text.replaceAll(RegExp(r'\D'), '').length >= 7,
      'bank' => _bank != null && _account.text.trim().length >= 6,
      _ => true,
    };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add where to get paid', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: context.textPrimary)),
              const SizedBox(height: 12),
              if (rails.length > 1)
                Wrap(
                  spacing: 6,
                  children: [
                    for (final r in rails)
                      ChoiceChip(
                        label: Text(r.label),
                        selected: _rail == r,
                        showCheckmark: false,
                        selectedColor: AppColors.brandBlue,
                        labelStyle: TextStyle(fontSize: 12, color: _rail == r ? Colors.white : context.textPrimary),
                        onSelected: (_) => setState(() => _rail = r),
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              if (_rail.rail == 'mobile_money') ...[
                Text('Network', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.textSecondary)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final n in _rail.networks)
                      ChoiceChip(
                        label: Text(n.label),
                        selected: _network == n.id,
                        showCheckmark: false,
                        selectedColor: AppColors.brandPink,
                        labelStyle: TextStyle(fontSize: 12, color: _network == n.id ? Colors.white : context.textPrimary),
                        onSelected: (_) => setState(() => _network = n.id),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(fontSize: 13, color: context.textPrimary),
                  decoration: _dec('Mobile money number'),
                ),
              ] else if (_rail.rail == 'bank') ...[
                FutureBuilder<List<({String code, String name})>>(
                  future: _banks ??= ref.read(moneyServiceProvider).banks(widget.options.country),
                  builder: (context, snap) {
                    final banks = snap.data ?? const [];
                    if (!snap.hasData) return const LinearProgressIndicator(color: AppColors.brandBlue);
                    if (banks.isEmpty) return Text('Banks are not available right now.', style: TextStyle(fontSize: 12, color: context.textSecondary));
                    return DropdownMenu<({String code, String name})>(
                      expandedInsets: EdgeInsets.zero,
                      enableFilter: true,
                      requestFocusOnTap: true,
                      hintText: 'Search your bank',
                      textStyle: TextStyle(fontSize: 13, color: context.textPrimary),
                      menuHeight: 300,
                      onSelected: (b) => setState(() => _bank = b),
                      dropdownMenuEntries: [for (final b in banks) DropdownMenuEntry(value: b, label: b.name)],
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _account,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(fontSize: 13, color: context.textPrimary),
                  decoration: _dec('Account number'),
                ),
              ] else
                Text(
                  'Stripe pays out to your bank account or debit card in your country. You’ll add the details on Stripe’s secure page, then come back here.',
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: context.textSecondary),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.verified_user_rounded, size: 15, color: AppColors.brandBlue),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.holder.isEmpty ? 'Paid to the name on your verified ID.' : 'Paid to ${widget.holder}, the name on your verified ID.',
                      style: TextStyle(fontSize: 11.5, color: context.textSecondary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: _rail.rail == 'stripe' ? 'Continue with Stripe' : 'Save',
                busy: _busy,
                onPressed: canSave ? _save : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerifyGate extends StatelessWidget {
  const _VerifyGate({required this.wallet, required this.kyc});
  final CreatorWallet wallet;
  final KycState kyc;

  @override
  Widget build(BuildContext context) {
    final inReview = kyc.status == 'processing';
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 32),
      children: [
        Center(
          child: Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.premiumGradient),
            child: Icon(inReview ? Icons.hourglass_top_rounded : Icons.verified_user_rounded, color: Colors.white, size: 36),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(begin: 1, end: 1.06, duration: 1200.ms),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            inReview ? 'Checking your ID…' : 'One quick step to get paid',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: context.textPrimary),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            inReview
                ? 'This usually takes a few minutes. We’ll notify you the moment you’re verified.'
                : 'To keep your money safe, we verify who you are once before your first withdrawal${wallet.availableUsd > 0 ? '. ${money(wallet.availableUsd, 'USD')} is waiting for you' : ''}.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.4, color: context.textSecondary),
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: PrimaryButton(
            label: inReview ? 'See status' : 'Verify my identity',
            icon: Icons.badge_rounded,
            onPressed: () => context.push('/wallet/verify'),
          ),
        ),
      ],
    );
  }
}

class _Success extends StatelessWidget {
  const _Success({required this.result});
  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final review = result['review'] == true;
    final failed = result['status'] == 'failed';
    final amount = money((result['localAmount'] as num?)?.toDouble() ?? 0, '${result['currency'] ?? 'USD'}');
    const cheers = [
      'Look at you go! Your creativity just paid off.',
      'Earned by you, sent to you. Keep creating!',
      'Your fans made this happen. Go make more magic.',
    ];
    return Scaffold(
      backgroundColor: context.bg,
      body: Stack(
        children: [
          if (!failed) const Positioned.fill(child: ConfettiBurst()),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SuccessMark(icon: failed ? Icons.undo_rounded : review ? Icons.shield_rounded : Icons.check_rounded),
                    const SizedBox(height: 20),
                    Text(
                      failed ? 'It didn’t go through' : review ? 'Request received' : 'Money on the way! 🎉',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: context.textPrimary),
                    ).animate().fadeIn(delay: 200.ms),
                    const SizedBox(height: 8),
                    Text(
                      failed
                          ? 'Your Diamonds are back in your wallet. Check the details and try again.'
                          : review
                              ? 'We’re double-checking $amount to ${result['methodLabel']} for your safety. It usually takes less than a day.'
                              : '$amount is heading to ${result['methodLabel']}.\n${cheers[DateTime.now().second % cheers.length]}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13.5, height: 1.45, color: context.textSecondary),
                    ).animate().fadeIn(delay: 350.ms),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: 220,
                      child: PrimaryButton(
                        label: 'Track it',
                        onPressed: () => context.pushReplacement('/wallet/withdrawals/${result['id']}'),
                      ),
                    ),
                    TextButton(onPressed: () => context.pop(), child: const Text('Back to wallet')),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
