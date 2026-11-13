import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr/qr.dart';
import 'package:share_plus/share_plus.dart';

import '../../backend/pay/oneova_pay_service.dart';
import '../../backend/pay/oneova_pay_sheet.dart';
import '../../shared/theme/app_theme.dart';

/// Scan to pay and receive (functions/src/pay/merchantQr.ts). The app only
/// reads codes and shows what the server says; prices and money stay there.
const _payPrefix = 'https://oneova.web.app/p/';
final _codePattern = RegExp(r'^[A-Za-z0-9_-]{22}$');

bool _isPayCode(String s) {
  final t = s.trim();
  final code = t.startsWith(_payPrefix) ? t.substring(_payPrefix.length).split(RegExp(r'[?#/]')).first : t;
  return _codePattern.hasMatch(code);
}

String _money(num amount, String currency) {
  final whole = amount == amount.roundToDouble();
  return '$currency ${whole ? amount.toInt().toString() : amount.toStringAsFixed(2)}';
}

String _errorText(Object e, String fallback) => e is FirebaseFunctionsException ? payErrorText(e, fallback: fallback) : fallback;

// ─────────────────────────────── Scan ───────────────────────────────

class ScanToPayScreen extends ConsumerStatefulWidget {
  const ScanToPayScreen({super.key});

  @override
  ConsumerState<ScanToPayScreen> createState() => _ScanToPayScreenState();
}

class _ScanToPayScreenState extends ConsumerState<ScanToPayScreen> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates, facing: CameraFacing.back);
  bool _busy = false;
  String? _hint;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final raw = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue?.trim();
    if (raw == null || raw.isEmpty) return;
    if (!_isPayCode(raw)) {
      setState(() => _hint = 'That isn’t an Oneova Pay code.');
      return;
    }
    setState(() {
      _busy = true;
      _hint = null;
    });
    HapticFeedback.mediumImpact();
    await _controller.stop();
    try {
      final code = await ref.read(oneovaPayServiceProvider).resolveQr(raw);
      if (!mounted) return;
      final paid = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _ConfirmPaySheet(code: code),
      );
      if (!mounted) return;
      if (paid == true) {
        context.pop();
        return;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _hint = _errorText(e, 'Couldn’t read this code. Try again.'));
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.brandBlue, width: 3),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.canPop() ? context.pop() : context.go('/hub/home'),
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  ),
                  const Expanded(
                    child: Text('Scan to pay', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    onPressed: () => _controller.toggleTorch(),
                    icon: const Icon(Icons.flash_on_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: MediaQuery.of(context).padding.bottom + 32,
            child: Column(
              children: [
                if (_busy) const CircularProgressIndicator(color: Colors.white),
                if (_hint != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(AppRadius.sm)),
                    child: Text(_hint!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 13.5)),
                  ),
                const SizedBox(height: 12),
                const Text('Point at a shop’s Oneova Pay code', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => context.push('/wallet/receive'),
                  icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                  label: const Text('My code to receive'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmPaySheet extends ConsumerStatefulWidget {
  const _ConfirmPaySheet({required this.code});
  final MerchantCode code;

  @override
  ConsumerState<_ConfirmPaySheet> createState() => _ConfirmPaySheetState();
}

class _ConfirmPaySheetState extends ConsumerState<_ConfirmPaySheet> {
  final _amount = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<bool> _confirmWithDevice(String what) async {
    final auth = LocalAuthentication();
    try {
      if (!await auth.isDeviceSupported()) return true; // no lock screen set: the server still checks everything
      return await auth.authenticate(localizedReason: 'Confirm payment of $what', biometricOnly: false, persistAcrossBackgrounding: true);
    } catch (_) {
      return false;
    }
  }

  Future<void> _pay() async {
    final c = widget.code;
    num? typed;
    if (!c.fixedAmount) {
      typed = num.tryParse(_amount.text.replaceAll(',', '').trim());
      if (typed == null || typed <= 0) {
        setState(() => _error = 'Enter the amount to pay.');
        return;
      }
    }
    final amount = c.fixedAmount ? c.amount! : typed!;
    final label = _money(amount, c.currency);
    if (!await _confirmWithDevice(label)) {
      setState(() => _error = 'Payment not confirmed.');
      return;
    }
    if (!mounted) return;
    final exp = c.currency == 'UGX' || c.currency == 'RWF' || c.currency == 'XOF' || c.currency == 'XAF' ? 1 : 100;
    final intent = await showOneovaPaySheet(
      context,
      purpose: 'merchant',
      refId: c.code,
      amountMinor: c.amountMinor ?? (amount * exp).round(),
      currency: c.currency,
      title: 'Pay ${c.name}',
      subtitle: c.label,
      topupAmount: c.fixedAmount ? null : typed,
      country: c.country,
    );
    if (!mounted) return;
    if (intent != null && intent.status == 'succeeded') {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Paid $label to ${c.name}'), backgroundColor: AppColors.brandBlue));
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.code;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(color: context.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: context.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 18),
          CircleAvatar(
            radius: 30,
            backgroundColor: AppColors.brandBlue.withValues(alpha: 0.12),
            backgroundImage: c.avatarUrl != null ? NetworkImage(c.avatarUrl!) : null,
            child: c.avatarUrl == null ? const Icon(Icons.storefront_rounded, color: AppColors.brandBlue, size: 28) : null,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(c.name, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.w800))),
              if (c.verified) ...[const SizedBox(width: 6), const Icon(Icons.verified_rounded, color: AppColors.brandBlue, size: 18)],
            ],
          ),
          if (c.label != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(c.label!, style: TextStyle(color: context.textSecondary))),
          if (!c.verified)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('This merchant hasn’t verified their identity.', style: TextStyle(color: AppColors.brandPink, fontSize: 12.5)),
            ),
          const SizedBox(height: 18),
          if (c.fixedAmount)
            Text(_money(c.amount!, c.currency), style: TextStyle(color: context.textPrimary, fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1))
          else
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textPrimary, fontSize: 30, fontWeight: FontWeight.w900),
              decoration: InputDecoration(prefixText: '${c.currency} ', hintText: '0', border: InputBorder.none),
            ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: AppColors.brandPink))),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _pay,
              icon: const Icon(Icons.lock_rounded, size: 18),
              label: const Text('Pay', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue, minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md))),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────── Receive ───────────────────────────────

class ReceivePayScreen extends ConsumerStatefulWidget {
  const ReceivePayScreen({super.key});

  @override
  ConsumerState<ReceivePayScreen> createState() => _ReceivePayScreenState();
}

class _ReceivePayScreenState extends ConsumerState<ReceivePayScreen> {
  MerchantCode? _shown;
  List<MerchantCode> _codes = const [];
  bool _loading = true;
  String? _error;
  bool _needsKyc = false;
  final _amount = TextEditingController();

  OneovaPayService get _svc => ref.read(oneovaPayServiceProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var codes = await _svc.myQrCodes();
      var shop = codes.where((c) => !c.oneTime && c.active).firstOrNull;
      if (shop == null) {
        shop = await _svc.createQr(label: 'Shop code');
        codes = [shop, ...codes];
      }
      if (!mounted) return;
      setState(() {
        _codes = codes;
        _shown = shop;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _needsKyc = e is FirebaseFunctionsException && (e.message ?? '').contains('Verify your identity');
        _error = _errorText(e, 'Couldn’t load your code. Check your connection.');
        _loading = false;
      });
    }
  }

  Future<void> _request() async {
    final amount = num.tryParse(_amount.text.replaceAll(',', '').trim());
    if (amount == null || amount <= 0) return;
    FocusScope.of(context).unfocus();
    try {
      final code = await _svc.createQr(amount: amount, label: 'One-time');
      if (!mounted) return;
      setState(() {
        _shown = code;
        _codes = [code, ..._codes];
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_errorText(e, 'Couldn’t make the code.'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        title: Text('Receive with Oneova Pay', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w800, fontSize: 17)),
        leading: IconButton(icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary), onPressed: () => context.canPop() ? context.pop() : context.go('/wallet')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.brandBlue))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_needsKyc ? Icons.badge_rounded : Icons.error_outline_rounded, color: AppColors.brandBlue, size: 44),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: context.textPrimary)),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _needsKyc ? () => context.push('/wallet/verify') : _load,
                          style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue),
                          child: Text(_needsKyc ? 'Verify my identity' : 'Try again'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (_shown != null) _QrCard(code: _shown!),
                    const SizedBox(height: 20),
                    Text('Ask for an exact amount', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _amount,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              hintText: 'Amount',
                              prefixText: _shown != null ? '${_shown!.currency} ' : null,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: _request,
                          style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue, minimumSize: const Size(0, 46)),
                          child: const Text('Make code'),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('A one-time code works for 15 minutes and is paid once.', style: TextStyle(color: context.textSecondary, fontSize: 12)),
                    ),
                    const SizedBox(height: 22),
                    Text('Your codes', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w800)),
                    for (final c in _codes)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        onTap: () => setState(() => _shown = c),
                        leading: Icon(c.oneTime ? Icons.timer_rounded : Icons.storefront_rounded, color: c.active ? AppColors.brandBlue : context.textMuted),
                        title: Text(c.fixedAmount ? _money(c.amount!, c.currency) : (c.label ?? 'Shop code'), style: TextStyle(color: context.textPrimary)),
                        subtitle: Text(
                          '${c.paidCount} paid · ${c.currency} ${(c.receivedMinor / (c.currency == 'UGX' || c.currency == 'RWF' || c.currency == 'XOF' || c.currency == 'XAF' ? 1 : 100)).toStringAsFixed(0)} received${c.active ? '' : ' · closed'}',
                          style: TextStyle(color: context.textSecondary, fontSize: 12),
                        ),
                        trailing: c.active
                            ? IconButton(
                                icon: Icon(Icons.block_rounded, color: context.textMuted),
                                tooltip: 'Turn off',
                                onPressed: () async {
                                  await _svc.disableQr(c.code);
                                  _load();
                                },
                              )
                            : null,
                      ),
                  ],
                ),
    );
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard({required this.code});
  final MerchantCode code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.brandBlue,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.qr_code_2_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(code.name, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16))),
              if (code.verified) const Icon(Icons.verified_rounded, color: Colors.white, size: 18),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: SizedBox(width: 210, height: 210, child: CustomPaint(painter: _QrPainter(code.qr))),
          ),
          const SizedBox(height: 14),
          Text(
            code.fixedAmount ? _money(code.amount!, code.currency) : 'Payer types the amount',
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
          ),
          if (code.oneTime) const Text('One-time · 15 minutes', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () => SharePlus.instance.share(ShareParams(text: 'Pay ${code.name} with Oneova Pay: ${code.qr}')),
            icon: const Icon(Icons.ios_share_rounded, color: Colors.white, size: 18),
            label: const Text('Share link', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.data);
  final String data;

  @override
  void paint(Canvas canvas, Size size) {
    final image = QrImage(QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M));
    final n = image.moduleCount;
    final cell = size.width / n;
    final dark = Paint()..color = AppColors.brandBlue;
    for (var x = 0; x < n; x++) {
      for (var y = 0; y < n; y++) {
        if (image.isDark(y, x)) canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell + 0.3, cell + 0.3), dark);
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.data != data;
}
