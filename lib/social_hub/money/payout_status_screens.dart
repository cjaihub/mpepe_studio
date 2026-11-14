import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../../backend/money/insights_logic.dart';
import '../../backend/money/money_models.dart';
import '../../backend/money/money_service.dart';
import '../../shared/theme/app_theme.dart';
import 'money_widgets.dart';
import '../../identity/id_guide.dart';
import '../../identity/id_photo_check.dart';
import '../../identity/liveness/live_face_check_screen.dart';
import 'package:local_auth/local_auth.dart';
import '../../identity/widgets/id_country_picker.dart';
import '../../shared/location/country_detector.dart';
import '../../shared/widgets/compact/compact.dart';

/// Identity check before payouts (`/wallet/verify`): your ID and a selfie,
/// uploaded to a private folder only Oneova's review team can open, then
/// checked by a person (an automatic pre-check helps them). Payouts go only
/// to the name on the verified ID.
class KycScreen extends ConsumerStatefulWidget {
  const KycScreen({super.key});

  @override
  ConsumerState<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends ConsumerState<KycScreen> {
  bool _busy = false;
  bool _capturing = false;
  final _name = TextEditingController();
  String _country = '';
  bool _countryTouched = false;
  bool _detecting = false;
  CountryDetection? _detected;
  String _docType = 'id_card';
  File? _front;
  File? _back;
  File? _selfie;
  LivenessResult? _live;
  final _photoFacts = <String, Object?>{};

  static const _docTypes = {'id_card': 'National ID', 'passport': 'Passport', 'driving_license': 'Driving licence'};

  @override
  void initState() {
    super.initState();
    _country = guessHomeCountry();
    _detect(ask: false);
  }

  /// Fills the country from where the phone is (location only if allowed).
  Future<void> _detect({required bool ask}) async {
    setState(() => _detecting = true);
    final d = await CountryDetector.detect(askLocation: ask);
    if (!mounted) return;
    setState(() {
      _detecting = false;
      _detected = d;
      if (!_countryTouched && d.code != null) _country = d.code!;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _shoot(String which) async {
    HapticFeedback.selectionClick();
    // The selfie is a live face check (mesh, guide, random actions), never a gallery photo.
    if (which == 'selfie') {
      final r = await LiveFaceCheckScreen.open(context);
      if (r == null || !mounted) return;
      setState(() {
        _live = r;
        _selfie = r.selfie;
      });
      return;
    }
    // ID photos: camera or a photo/scan already on the device.
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: context.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take a photo'), onTap: () => Navigator.pop(c, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.upload_file_rounded), title: const Text('Upload from device'), onTap: () => Navigator.pop(c, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null || !mounted) return;
    final x = await ImagePicker().pickImage(
      source: source,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: 85,
      maxWidth: 1800,
    );
    if (x == null || !mounted) return;
    final check = await IdPhotoCheck.check(File(x.path), face: which == 'selfie' ? 'selfie' : (which == 'front' ? 'document' : 'none'));
    _photoFacts.addAll(check.asGuideFacts(which));
    if (!mounted || !await IdPhotoCheck.review(context, check)) return;
    setState(() {
      final f = File(x.path);
      if (which == 'front') _front = f;
      if (which == 'back') _back = f;
      if (which == 'selfie') _selfie = f;
    });
  }

  bool get _ready => _name.text.trim().length >= 3 && RegExp(r'^[A-Z]{2}$').hasMatch(_country) && _front != null && _selfie != null;

  Future<void> _submit() async {
    if (!_ready || _busy) return;
    HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    try {
      // Confirm on the phone with fingerprint or face (never leaves the phone).
      var biometric = false;
      try {
        final auth = LocalAuthentication();
        if (await auth.isDeviceSupported()) {
          biometric = await auth.authenticate(localizedReason: 'Confirm it’s you to send your ID for checking', biometricOnly: true);
          if (!biometric) return;
        }
      } catch (_) {}
      final svc = ref.read(moneyServiceProvider);
      final s = await svc.startKyc();
      if (s == null) return; // already in review or verified
      final store = FirebaseStorage.instance;
      final meta = SettableMetadata(contentType: 'image/jpeg');
      await Future.wait([
        store.ref('${s.path}/id_front.jpg').putFile(_front!, meta),
        store.ref('${s.path}/selfie.jpg').putFile(_selfie!, meta),
        if (_back != null) store.ref('${s.path}/id_back.jpg').putFile(_back!, meta),
        if (_live?.left != null) store.ref('${s.path}/live_left.jpg').putFile(_live!.left!, meta),
        if (_live?.right != null) store.ref('${s.path}/live_right.jpg').putFile(_live!.right!, meta),
      ]);
      final res = await svc.submitKyc(
        sessionId: s.sessionId,
        fullName: _name.text.trim(),
        country: _country,
        documentType: _docType,
        countrySignals: _detected?.signals ?? const {},
        liveness: _live?.toMap(biometric: biometric),
      );
      if (res['duplicate'] == true && mounted) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('This ID is already in use'),
            content: Text('${res['message'] ?? 'This ID is already verified on another Oneova account.'}'),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
          ),
        );
      }
      if (mounted) setState(() => _capturing = false);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(moneyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kyc = ref.watch(kycProvider).value ?? const KycState();
    if (_capturing) return _captureForm();
    final (icon, title, body) = switch (kyc.status) {
      'verified' => (Icons.verified_rounded, 'You’re verified', 'Thanks${kyc.verifiedName != null ? ', ${kyc.verifiedName!.split(' ').first}' : ''}! You can withdraw your earnings any time.'),
      'review' => (Icons.hourglass_top_rounded, 'Checking your ID', 'Our team is reviewing it — usually within a day. We’ll notify you when it’s done.'),
      'rejected' => (Icons.refresh_rounded, 'Let’s try that again', kyc.lastError ?? 'We couldn’t confirm your ID. Try again with clear photos in good light.'),
      _ => (Icons.badge_rounded, 'Verify your identity', 'A one-time check that keeps your earnings safe and makes sure only you can withdraw them.'),
    };
    final canStart = !kyc.verified && kyc.status != 'review';
    return MoneyScaffold(
      title: 'Identity',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 20, 0, 32),
        children: [
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.premiumGradient),
              child: Icon(icon, color: Colors.white, size: 38),
            ).animate(key: ValueKey(kyc.status)).scale(begin: const Offset(0.6, 0.6), end: const Offset(1, 1), duration: 450.ms, curve: Curves.easeOutBack),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: context.textPrimary)),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 6, 32, 20),
            child: Text(body, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, height: 1.4, color: context.textSecondary)),
          ),
          if (canStart) ...[
            MoneyCard(
              child: Column(
                children: [
                  for (final (i, (ic, t, s)) in [
                    (Icons.credit_card_rounded, 'Your ID', 'Passport, national ID card or driving licence'),
                    (Icons.face_rounded, 'A quick selfie', 'To match you with your ID'),
                    (Icons.timer_rounded, 'About 2 minutes', 'Done once, then you’re set'),
                  ].indexed) ...[
                    if (i > 0) const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(ic, size: 20, color: AppColors.brandBlue),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.textPrimary)),
                              Text(s, style: TextStyle(fontSize: 11.5, color: context.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: PrimaryButton(
                label: kyc.status == 'rejected' ? 'Try again' : 'Start verification',
                icon: Icons.verified_user_rounded,
                onPressed: () => setState(() => _capturing = true),
              ),
            ),
          ] else if (kyc.verified)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: PrimaryButton(label: 'Withdraw now', icon: Icons.north_east_rounded, onPressed: () => context.pushReplacement('/wallet/withdraw')),
            ),
          _privacy(),
        ],
      ),
    );
  }

  Widget _privacy() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_rounded, size: 14, color: context.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Your photos go to a private, encrypted folder that only Oneova’s review team can open. They’re used only to confirm it’s you.',
                style: TextStyle(fontSize: 11, height: 1.4, color: context.textMuted),
              ),
            ),
          ],
        ),
      );

  /// "Detected from your location" with a way to use location, and a calm
  /// note when the ID country differs from where the phone is.
  Widget _countryHint() {
    final d = _detected;
    final detectedName = d?.code == null ? null : kIdCountries[d!.code];
    final differs = d?.code != null && d!.code != _country;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        Icon(_detecting ? Icons.my_location_rounded : Icons.place_outlined, size: 14, color: context.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            _detecting
                ? 'Finding your country…'
                : detectedName == null
                    ? 'Pick the country on your ID.'
                    : differs
                        ? 'You seem to be in $detectedName. That’s fine if your ID is from somewhere else.'
                        : 'Detected $detectedName ${d!.sourceLabel}.',
            style: TextStyle(fontSize: 11.5, color: context.textSecondary),
          ),
        ),
        if (!_detecting && d?.source != CountrySource.location)
          TextButton(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
            onPressed: () {
              _countryTouched = false;
              _detect(ask: true);
            },
            child: const Text('Use my location', style: TextStyle(fontSize: 12)),
          ),
      ]),
    );
  }

  Widget _shot(String which, String label, IconData icon, File? file) => Expanded(
        child: GestureDetector(
          onTap: _busy ? null : () => _shoot(which),
          child: AspectRatio(
            aspectRatio: 0.82,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: context.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: file != null ? AppColors.brandBlue : context.border, width: file != null ? 2 : 1),
              ),
              child: file != null
                  ? Image.file(file, fit: BoxFit.cover)
                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(icon, color: AppColors.brandBlue, size: 28),
                      const SizedBox(height: 6),
                      Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
                    ]),
            ),
          ),
        ),
      );

  Widget _captureForm() {
    return MoneyScaffold(
      title: 'Verify identity',
      actions: [Padding(padding: const EdgeInsets.only(right: 8), child: IdGuideButton(guideContext: IdGuideContext(screen: 'verify_id', extra: _photoFacts)))],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text('Name exactly as on your ID', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.textPrimary)),
          const SizedBox(height: 6),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Full name',
              prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
          ),
          const CompactSectionHeader('ID type'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in _docTypes.entries)
              CompactChip(
                label: e.value,
                icon: switch (e.key) { 'passport' => Icons.menu_book_rounded, 'driving_license' => Icons.directions_car_rounded, _ => Icons.badge_outlined },
                selected: _docType == e.key,
                onTap: () => setState(() => _docType = e.key),
              ),
          ]),
          const SizedBox(height: 14),
          IdCountryField(
            value: _country,
            label: 'Country that issued your ID',
            onChanged: (v) => setState(() {
              _country = v;
              _countryTouched = true;
            }),
          ),
          _countryHint(),
          const SizedBox(height: 18),
          Text('Photos', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.textPrimary)),
          const SizedBox(height: 4),
          Text('Flat surface, good light, all four corners visible.', style: TextStyle(fontSize: 11.5, color: context.textSecondary)),
          const SizedBox(height: 10),
          Row(children: [
            _shot('front', 'ID front', Icons.badge_outlined, _front),
            const SizedBox(width: 10),
            _shot('back', 'ID back\n(if any)', Icons.flip_rounded, _back),
            const SizedBox(width: 10),
            _shot('selfie', _live != null ? 'Live check ✓' : 'Live face\ncheck', Icons.face_retouching_natural_rounded, _selfie),
          ]),
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'Send for review',
            icon: Icons.verified_user_rounded,
            busy: _busy,
            onPressed: _ready ? _submit : null,
          ),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _capturing = false),
            child: Text('Cancel', style: TextStyle(color: context.textSecondary)),
          ),
          _privacy(),
        ],
      ),
    );
  }
}

/// Every withdrawal (`/wallet/withdrawals`).
class WithdrawalsScreen extends ConsumerWidget {
  const WithdrawalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(withdrawalsProvider);
    final list = async.value ?? const <Withdrawal>[];
    final paid = list.where((w) => w.status == 'paid').fold<double>(0, (s, w) => s + w.netUsd);
    return MoneyScaffold(
      title: 'Withdrawals',
      body: async.isLoading && list.isEmpty
          ? const Center(child: CircularProgressIndicator(color: AppColors.brandBlue))
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                if (paid > 0) ...[
                  const SizedBox(height: 4),
                  GrowthBanner(title: '${money(paid, 'USD')} paid out', body: 'That’s money you made from what you love. Keep going!', icon: Icons.savings_rounded),
                ],
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('No withdrawals yet. When you withdraw, you can follow each one here.',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: context.textSecondary)),
                  ),
                const SizedBox(height: 8),
                for (final w in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: MoneyCard(
                      onTap: () => context.push('/wallet/withdrawals/${w.id}'),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(money(w.localAmount, w.currency), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: context.textPrimary)),
                                Text(
                                  [w.methodLabel, if (w.createdAt != null) DateFormat('d MMM y').format(w.createdAt!)].join(' · '),
                                  style: TextStyle(fontSize: 11.5, color: context.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          StatusPill(w.status, review: w.review),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// One withdrawal with its live timeline (`/wallet/withdrawals/:id`).
class WithdrawalDetailScreen extends ConsumerWidget {
  const WithdrawalDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(withdrawalProvider(id)).value;
    if (w == null) {
      return const MoneyScaffold(title: 'Withdrawal', body: Center(child: CircularProgressIndicator(color: AppColors.brandBlue)));
    }
    final steps = [
      ('pending', w.review ? 'Safety check' : 'Requested', w.review ? 'We’re double-checking this request for you.' : 'We got your request.'),
      ('processing', 'Sending', 'On its way to ${w.methodLabel}.'),
      ('paid', 'Paid', 'The money has arrived. Well earned!'),
    ];
    final reached = <String, DateTime>{for (final t in w.timeline) t.status: t.at};
    final failed = w.status == 'failed' || w.status == 'cancelled';
    final order = ['pending', 'processing', 'paid'];
    final current = failed ? -1 : order.indexOf(w.status);
    final fmt = DateFormat('d MMM · HH:mm');

    return MoneyScaffold(
      title: 'Withdrawal',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const SizedBox(height: 4),
          MoneyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(money(w.localAmount, w.currency), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: context.textPrimary))),
                    StatusPill(w.status, review: w.review),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${money(w.amountUsd, 'USD')} − ${money(w.feeUsd, 'USD')} fee · ${compact(w.diamonds)} Diamonds',
                    style: TextStyle(fontSize: 12, color: context.textSecondary)),
              ],
            ),
          ),
          const SectionTitle('Progress'),
          MoneyCard(
            child: failed
                ? Row(
                    children: [
                      const Icon(Icons.undo_rounded, color: AppColors.brandPink),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          w.status == 'cancelled' ? 'You cancelled this. Your Diamonds are back in your wallet.' : '${w.failureReason ?? 'It didn’t go through.'} Your Diamonds are back in your wallet.',
                          style: TextStyle(fontSize: 12.5, height: 1.4, color: context.textPrimary),
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      for (final (i, (key, title, sub)) in steps.indexed)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: i <= current ? AppColors.brandBlue : context.surfaceMid,
                                    border: Border.all(color: i <= current ? AppColors.brandBlue : context.border),
                                  ),
                                  child: i < current || (i == current && key == 'paid')
                                      ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                                      : i == current
                                          ? const Padding(padding: EdgeInsets.all(5), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                          : null,
                                ),
                                if (i < steps.length - 1) Container(width: 2, height: 30, color: i < current ? AppColors.brandBlue : context.border),
                              ],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: i <= current ? context.textPrimary : context.textMuted)),
                                    Text(
                                      reached[key] != null ? '$sub · ${fmt.format(reached[key]!)}' : sub,
                                      style: TextStyle(fontSize: 11.5, color: context.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
          ),
          if (w.status == 'paid') ...[
            const SizedBox(height: 12),
            const GrowthBanner(title: 'You did it! 🎉', body: 'Every clip and every live brought you here. Ready for the next one?', icon: Icons.celebration_rounded),
          ],
          if (w.status == 'pending')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: OutlinedButton(
                onPressed: () async {
                  try {
                    await ref.read(moneyServiceProvider).cancelWithdrawal(w.id);
                  } catch (e) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(moneyError(e))));
                  }
                },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(40),
                  side: BorderSide(color: context.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                ),
                child: Text('Cancel withdrawal', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.textPrimary)),
              ),
            ),
        ],
      ),
    );
  }
}
