import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr/qr.dart';
import 'package:share_plus/share_plus.dart';

import '../../auth/services/oneova_biometrics_service.dart';
import '../../shared/theme/app_theme.dart';
import '../identity_service.dart';

/// Pick what to reveal and for how long → a QR code anyone can check at
/// oneova.web.app/verify. Approving a share asks for biometrics.
class IdShareSheet extends ConsumerStatefulWidget {
  const IdShareSheet({super.key, required this.kind});
  final String kind; // person | business

  static Future<void> show(BuildContext context, {String kind = 'person'}) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: context.bg,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
        builder: (_) => IdShareSheet(kind: kind),
      );

  @override
  ConsumerState<IdShareSheet> createState() => _IdShareSheetState();
}

class _IdShareSheetState extends ConsumerState<IdShareSheet> {
  static const _personFields = {'name': 'Full name', 'country': 'Country', 'document': 'Document type', 'since': 'Verified since', 'handle': 'Oneova username'};
  static const _bizFields = {'name': 'Legal name', 'country': 'Country', 'type': 'Business type', 'registration': 'Registration number', 'since': 'Verified since'};
  static const _durations = {10: '10 min', 60: '1 hour', 1440: '1 day', 10080: '7 days'};

  late final Set<String> _picked = widget.kind == 'person' ? {'name', 'country'} : {'name', 'country', 'registration'};
  int _minutes = 10;
  bool _busy = false;
  IdShareLink? _result;
  Timer? _tick;

  Map<String, String> get _fields => widget.kind == 'person' ? _personFields : _bizFields;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final bio = OneovaBiometricsService();
      if (await bio.isDeviceSupported() && !await bio.authenticate(reason: 'Confirm sharing your Oneova ID')) return;
      final r = await ref.read(identityServiceProvider).share(kind: widget.kind, fields: _picked.toList(), minutes: _minutes);
      HapticFeedback.mediumImpact();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(identityError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: context.border, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          Text(_result == null ? 'Share your verified ${widget.kind == 'person' ? 'identity' : 'business'}' : 'Show this code',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: context.textPrimary)),
          const SizedBox(height: 4),
          Text(
            _result == null
                ? 'They’ll see “Verified” plus only what you pick. Nothing else.'
                : 'Anyone can scan it to check it’s genuine. It stops working when the timer ends or when you stop it.',
            style: TextStyle(fontSize: 13, color: context.textSecondary, height: 1.35),
          ),
          const SizedBox(height: 14),
          if (_result == null) ..._picker() else ..._code(_result!),
        ]),
      ),
    );
  }

  List<Widget> _picker() => [
        ..._fields.entries.map((e) => CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _picked.contains(e.key),
              activeColor: AppColors.brandBlue,
              title: Text(e.value, style: TextStyle(color: context.textPrimary)),
              onChanged: (v) => setState(() => v == true ? _picked.add(e.key) : _picked.remove(e.key)),
            )),
        const SizedBox(height: 8),
        Text('Valid for', style: TextStyle(fontWeight: FontWeight.w700, color: context.textPrimary)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: _durations.entries
              .map((d) => ChoiceChip(
                    label: Text(d.value),
                    selected: _minutes == d.key,
                    selectedColor: AppColors.brandBlue.withValues(alpha: 0.22),
                    checkmarkColor: AppColors.brandBlue,
                    labelStyle: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600),
                    onSelected: (_) => setState(() => _minutes = d.key),
                  ))
              .toList(),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _busy ? null : _create,
          style: FilledButton.styleFrom(foregroundColor: Colors.white, backgroundColor: AppColors.brandBlue, minimumSize: const Size.fromHeight(48)),
          icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.qr_code_2_rounded),
          label: const Text('Create code'),
        ),
      ];

  List<Widget> _code(IdShareLink r) {
    final left = r.expiresAt.difference(DateTime.now());
    final expired = left.isNegative;
    String fmt(Duration d) => d.inHours >= 24
        ? '${d.inDays}d ${d.inHours % 24}h'
        : d.inMinutes >= 60
            ? '${d.inHours}h ${d.inMinutes % 60}m'
            : '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    return [
      Center(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.lg)),
          child: Opacity(
            opacity: expired ? 0.15 : 1,
            child: CustomPaint(size: const Size.square(240), painter: IdQrPainter(r.url)),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Center(
        child: Text(expired ? 'Expired' : 'Expires in ${fmt(left)}',
            style: TextStyle(fontWeight: FontWeight.w700, color: expired ? AppColors.brandPink : context.textPrimary)),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: expired ? null : () => SharePlus.instance.share(ShareParams(text: r.url)),
            icon: const Icon(Icons.ios_share_rounded, size: 18),
            label: const Text('Send link'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              await ref.read(identityServiceProvider).stopShare(r.shareId);
              if (mounted) Navigator.pop(context);
            },
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.brandPink),
            icon: const Icon(Icons.block_rounded, size: 18),
            label: const Text('Stop sharing'),
          ),
        ),
      ]),
    ];
  }
}

class IdQrPainter extends CustomPainter {
  IdQrPainter(this.data);
  final String data;

  @override
  void paint(Canvas canvas, Size size) {
    final qr = QrImage(QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.L));
    final n = qr.moduleCount;
    final m = size.width / n;
    final fg = Paint()..color = const Color(0xFF0B1220);
    final accent = Paint()..color = AppColors.brandBlue;
    for (var x = 0; x < n; x++) {
      for (var y = 0; y < n; y++) {
        if (!qr.isDark(y, x)) continue;
        final corner = (x < 7 && y < 7) || (x < 7 && y >= n - 7) || (x >= n - 7 && y < 7);
        canvas.drawRect(Rect.fromLTWH(x * m, y * m, m + 0.3, m + 0.3), corner ? accent : fg);
      }
    }
  }

  @override
  bool shouldRepaint(covariant IdQrPainter old) => old.data != data;
}
