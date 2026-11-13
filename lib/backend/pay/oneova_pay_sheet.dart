import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/theme/app_theme.dart';
import 'oneova_pay_service.dart';

/// Opens Oneova Pay for one payment and resolves with the finished pay-in
/// (status `succeeded`), or null when the payer closed it.
///
///   purpose `order`  [refId] = order id (the server prices it)
///   purpose `topup`  [topupAmount] in major units of the payer's currency
///
/// [amountMinor] / [currency] are only shown; the server's price wins.
Future<PayIntent?> showOneovaPaySheet(
  BuildContext context, {
  required String purpose,
  String? refId,
  required int amountMinor,
  required String currency,
  required String title,
  String? subtitle,
  num? topupAmount,
}) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet<PayIntent>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => OneovaPaySheet(
      purpose: purpose,
      refId: refId,
      amountMinor: amountMinor,
      currency: currency,
      title: title,
      subtitle: subtitle,
      topupAmount: topupAmount,
    ),
  );
}

enum _Stage { loading, choose, starting, waiting, done, failed }

class OneovaPaySheet extends ConsumerStatefulWidget {
  const OneovaPaySheet({
    super.key,
    required this.purpose,
    this.refId,
    required this.amountMinor,
    required this.currency,
    required this.title,
    this.subtitle,
    this.topupAmount,
  });

  final String purpose;
  final String? refId;
  final int amountMinor;
  final String currency;
  final String title;
  final String? subtitle;
  final num? topupAmount;

  @override
  ConsumerState<OneovaPaySheet> createState() => _OneovaPaySheetState();
}

class _OneovaPaySheetState extends ConsumerState<OneovaPaySheet> with WidgetsBindingObserver {
  _Stage _stage = _Stage.loading;
  PayOptions? _options;
  PayMethod? _method;
  PayIntent? _intent;
  String? _error;
  final _phone = TextEditingController();
  StreamSubscription<PayIntent?>? _sub;
  Timer? _poll;

  OneovaPayService get _svc => ref.read(oneovaPayServiceProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final p = FirebaseAuth.instance.currentUser?.phoneNumber;
    if (p != null && p.isNotEmpty) _phone.text = p;
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _poll?.cancel();
    _phone.dispose();
    super.dispose();
  }

  // Back from the partner's secure page: ask for the result at once.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _stage == _Stage.waiting) _check();
  }

  Future<void> _load() async {
    setState(() {
      _stage = _Stage.loading;
      _error = null;
    });
    try {
      final o = await _svc.options();
      if (!mounted) return;
      setState(() {
        _options = o;
        _method = o.methods.isEmpty ? null : o.methods.first;
        _stage = _Stage.choose;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _message(e, 'Couldn’t load ways to pay. Check your connection.');
        _stage = _Stage.failed;
      });
    }
  }

  String _message(Object e, String fallback) =>
      e is FirebaseFunctionsException && (e.message ?? '').isNotEmpty ? e.message! : fallback;

  Future<void> _pay() async {
    final m = _method;
    if (m == null) return;
    if (m.needsPhone && _phone.text.replaceAll(RegExp(r'[^0-9]'), '').length < 9) {
      setState(() => _error = 'Enter your ${m.label} number.');
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _stage = _Stage.starting;
      _error = null;
    });
    try {
      final i = await _svc.create(
        purpose: widget.purpose,
        refId: widget.refId,
        methodId: m.id,
        msisdn: m.needsPhone ? _phone.text : null,
        amount: widget.topupAmount,
        country: _options?.country,
      );
      if (!mounted) return;
      _follow(i);
      if (i.redirectUrl != null && i.isOpen) await _openPage(i.redirectUrl!);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _message(e, 'The payment could not start. Please try again.');
        _stage = _Stage.choose;
      });
    }
  }

  Future<void> _openPage(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && mounted) setState(() => _error = 'Couldn’t open the secure payment page.');
  }

  /// Live status from the intent doc, plus a gentle status check every few
  /// seconds (it asks the partner when no callback has come yet).
  void _follow(PayIntent i) {
    _apply(i);
    _sub?.cancel();
    _sub = _svc.watch(i.id).listen((x) {
      if (x != null) _apply(x);
    });
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _check());
  }

  Future<void> _check() async {
    final id = _intent?.id;
    if (id == null || !(_intent?.isOpen ?? false)) return;
    try {
      _apply(await _svc.status(id));
    } catch (_) {/* the stream keeps us posted */}
  }

  void _apply(PayIntent i) {
    if (!mounted) return;
    setState(() {
      _intent = i;
      if (i.succeeded) {
        _stage = _Stage.done;
        _poll?.cancel();
        HapticFeedback.heavyImpact();
      } else if (i.isOpen) {
        _stage = _Stage.waiting;
      } else if (i.status == 'review') {
        _stage = _Stage.failed;
        _error = 'We’re checking this payment. You won’t be charged twice — we’ll let you know shortly.';
        _poll?.cancel();
      } else if (i.failed) {
        _stage = _Stage.failed;
        _error = i.failureReason ?? (i.status == 'expired' ? 'The payment timed out. Nothing was charged.' : 'The payment didn’t go through.');
        _poll?.cancel();
      }
    });
  }

  Future<void> _cancelWaiting() async {
    final id = _intent?.id;
    _poll?.cancel();
    if (id != null) await _svc.cancel(id).catchError((_) {});
    if (mounted) Navigator.pop(context);
  }

  // ─── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.9;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0E1630), Color(0xFF07090F)],
          ),
          border: Border(top: BorderSide(color: Color(0x332D7BFF))),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(
                child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4))),
              ),
              const SizedBox(height: 14),
              _header(),
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                child: KeyedSubtree(key: ValueKey(_stage), child: _body()),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final amount = formatMinor(_intent?.amountMinor ?? widget.amountMinor, _intent?.currency ?? widget.currency);
    return Row(children: [
      Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [AppColors.brandBlue, AppColors.brandPink]),
        ),
        child: const Icon(Icons.lock_rounded, color: Colors.white, size: 19),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Oneova Pay', style: GoogleFonts.inter(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
          Text(widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
        ]),
      ),
      Text(amount, style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
    ]);
  }

  Widget _body() {
    switch (_stage) {
      case _Stage.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator(color: AppColors.brandPink, strokeWidth: 2.4)),
        );
      case _Stage.choose:
      case _Stage.starting:
        return _chooser();
      case _Stage.waiting:
        return _waiting();
      case _Stage.done:
        return _done();
      case _Stage.failed:
        return _failed();
    }
  }

  Widget _chooser() {
    final o = _options!;
    final starting = _stage == _Stage.starting;
    if (o.methods.isEmpty) {
      return _note(Icons.hourglass_top_rounded,
          'Payments in ${o.countryName ?? o.country} are opening soon. You haven’t been charged.');
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.subtitle != null) ...[
        Text(widget.subtitle!, style: GoogleFonts.inter(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 14),
      ],
      if (o.sandbox && !o.live) ...[
        _note(Icons.science_outlined, 'Test mode: no real money moves.'),
        const SizedBox(height: 12),
      ],
      Text('Pay with', style: GoogleFonts.inter(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
      const SizedBox(height: 8),
      for (final m in o.methods) _methodTile(m, o),
      AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: (_method?.needsPhone ?? false)
            ? Padding(
                padding: const EdgeInsets.only(top: 6),
                child: TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  enabled: !starting,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    labelText: '${_method!.label} number',
                    labelStyle: GoogleFonts.inter(color: Colors.white54),
                    prefixIcon: const Icon(Icons.phone_iphone_rounded, color: Colors.white54),
                    prefixText: o.dial == null ? null : '+${o.dial} ',
                    prefixStyle: GoogleFonts.inter(color: Colors.white54, fontSize: 16),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
              )
            : const SizedBox(width: double.infinity),
      ),
      if (_error != null) ...[
        const SizedBox(height: 10),
        Text(_error!, style: GoogleFonts.inter(color: AppColors.brandPink, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
      const SizedBox(height: 16),
      _primary(
        starting ? 'Starting…' : _payLabel(),
        starting || _method == null ? null : _pay,
        busy: starting,
      ),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.verified_user_outlined, size: 14, color: Colors.white38),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            widget.purpose == 'order' ? 'Held safely until you confirm delivery.' : 'Encrypted and protected by Oneova.',
            style: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
          ),
        ),
      ]),
    ]);
  }

  String _payLabel() {
    final m = _method;
    if (m == null) return 'Pay';
    return switch (m.kind) {
      'prompt' => 'Send ${m.label} request',
      'hosted' => 'Continue to secure page',
      _ => 'Pay ${formatMinor(widget.amountMinor, widget.currency)}',
    };
  }

  IconData _icon(PayMethod m) => switch (m.rail) {
        'mobile_money' => Icons.phone_android_rounded,
        'card' => Icons.credit_card_rounded,
        'bank' => Icons.account_balance_rounded,
        _ => Icons.account_balance_wallet_rounded,
      };

  Widget _methodTile(PayMethod m, PayOptions o) {
    final on = _method?.id == m.id;
    final subtitle = switch (m.kind) {
      'prompt' => 'Approve with your PIN on your phone',
      'hosted' => 'Finish on the partner’s secure page',
      _ => o.balanceMinor == null ? 'Instant' : 'Available ${formatMinor(o.balanceMinor!, o.currency)}',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        selected: on,
        label: m.label,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: _stage == _Stage.starting
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _method = m;
                    _error = null;
                  });
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: on ? AppColors.brandBlue.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: on ? AppColors.brandBlue : Colors.white12, width: on ? 1.6 : 1),
            ),
            child: Row(children: [
              Icon(_icon(m), color: on ? Colors.white : Colors.white70, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.label, style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: GoogleFonts.inter(color: Colors.white54, fontSize: 12)),
                ]),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? AppColors.brandPink : Colors.transparent,
                  border: Border.all(color: on ? AppColors.brandPink : Colors.white30, width: 2),
                ),
                child: on ? const Icon(Icons.check_rounded, size: 13, color: Colors.white) : null,
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _waiting() {
    final hosted = _intent?.methodKind == 'hosted';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 8),
      const _Pulse(),
      const SizedBox(height: 18),
      Text(
        hosted ? 'Finish on the secure page' : 'Check your phone',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 6),
      Text(
        hosted
            ? 'Complete the payment there, then come back. We’ll confirm it here automatically.'
            : 'Enter your PIN on the ${_intent?.methodLabel ?? 'payment'} prompt to approve. This screen updates on its own.',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(color: Colors.white60, fontSize: 13, height: 1.4),
      ),
      if (_intent?.sandbox == true) ...[
        const SizedBox(height: 10),
        Text('Test mode — approving automatically in a few seconds.',
            textAlign: TextAlign.center, style: GoogleFonts.inter(color: Colors.white38, fontSize: 12)),
      ],
      const SizedBox(height: 18),
      if (hosted && _intent?.redirectUrl != null) ...[
        _primary('Open the payment page again', () => _openPage(_intent!.redirectUrl!)),
        const SizedBox(height: 8),
      ],
      TextButton(
        onPressed: _cancelWaiting,
        child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white54, fontWeight: FontWeight.w700)),
      ),
    ]);
  }

  Widget _done() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 10),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [AppColors.brandBlue, AppColors.brandPink]),
            ),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
          ),
        ),
        const SizedBox(height: 16),
        Text('Payment received', textAlign: TextAlign.center, style: GoogleFonts.inter(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(
          widget.purpose == 'order' ? 'The shop is getting your order ready.' : 'Your balance is updated.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(color: Colors.white60, fontSize: 13),
        ),
        const SizedBox(height: 20),
        _primary('Done', () => Navigator.pop(context, _intent)),
      ]);

  Widget _failed() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 6),
        _note(Icons.info_outline_rounded, _error ?? 'The payment didn’t go through.'),
        const SizedBox(height: 16),
        _primary('Try again', _options == null ? _load : () => setState(() {
              _stage = _Stage.choose;
              _intent = null;
              _error = null;
            })),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close', style: GoogleFonts.inter(color: Colors.white54, fontWeight: FontWeight.w700)),
        ),
      ]);

  Widget _note(IconData icon, String text) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: GoogleFonts.inter(color: Colors.white, fontSize: 13.5, height: 1.4))),
        ]),
      );

  Widget _primary(String label, VoidCallback? onTap, {bool busy = false}) => Opacity(
        opacity: onTap == null && !busy ? 0.5 : 1,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.brandBlue, AppColors.brandPink]),
              borderRadius: BorderRadius.circular(AppRadius.full),
              boxShadow: [BoxShadow(color: AppColors.brandPink.withValues(alpha: 0.28), blurRadius: 18, offset: const Offset(0, 6))],
            ),
            child: busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4))
                : Text(label, style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ),
      );
}

/// Soft pulsing phone while the payer approves.
class _Pulse extends StatefulWidget {
  const _Pulse();

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 110,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => Stack(alignment: Alignment.center, children: [
            for (final d in [0.0, 0.5])
              Opacity(
                opacity: (1 - ((_c.value + d) % 1)).clamp(0.0, 1.0) * 0.5,
                child: Container(
                  width: 60 + 50 * ((_c.value + d) % 1),
                  height: 60 + 50 * ((_c.value + d) % 1),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.brandBlue, width: 2)),
                ),
              ),
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [AppColors.brandBlue, AppColors.brandPink]),
              ),
              child: const Icon(Icons.phone_android_rounded, color: Colors.white, size: 28),
            ),
          ]),
        ),
      );
}
