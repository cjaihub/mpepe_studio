import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../backend/money/insights_logic.dart';
import '../../backend/money/money_models.dart';
import '../../backend/money/money_service.dart';
import '../../shared/theme/app_theme.dart';
import 'money_widgets.dart';

/// Identity check before payouts (`/wallet/verify`), on Stripe Identity's
/// secure page. Oneova keeps only the result, never the photos.
class KycScreen extends ConsumerStatefulWidget {
  const KycScreen({super.key});

  @override
  ConsumerState<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends ConsumerState<KycScreen> with WidgetsBindingObserver {
  bool _busy = false;
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _opened) {
      _opened = false;
      ref.read(moneyServiceProvider).refreshKyc().catchError((_) => '');
    }
  }

  Future<void> _start() async {
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    try {
      final url = await ref.read(moneyServiceProvider).startKyc();
      if (url != null) {
        _opened = true;
        await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(moneyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final kyc = ref.watch(kycProvider).value ?? const KycState();
    final (icon, title, body) = switch (kyc.status) {
      'verified' => (Icons.verified_rounded, 'You’re verified', 'Thanks${kyc.verifiedName != null ? ', ${kyc.verifiedName!.split(' ').first}' : ''}! You can withdraw your earnings any time.'),
      'processing' => (Icons.hourglass_top_rounded, 'Checking your ID', 'This usually takes a few minutes. We’ll notify you when it’s done.'),
      'requires_input' when kyc.lastError != null => (Icons.refresh_rounded, 'Let’s try that again', _errorText(kyc.lastError!)),
      _ => (Icons.badge_rounded, 'Verify your identity', 'A one-time check that keeps your earnings safe and makes sure only you can withdraw them.'),
    };
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
          if (!kyc.verified) ...[
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
                label: kyc.status == 'processing' ? 'Refresh status' : kyc.status == 'requires_input' ? 'Continue verification' : 'Start verification',
                icon: Icons.verified_user_rounded,
                busy: _busy,
                onPressed: kyc.status == 'processing' ? () => ref.read(moneyServiceProvider).refreshKyc() : _start,
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: PrimaryButton(label: 'Withdraw now', icon: Icons.north_east_rounded, onPressed: () => context.pushReplacement('/wallet/withdraw')),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_rounded, size: 14, color: context.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'The check runs on Stripe’s secure page. Oneova never sees or stores your ID photos or selfie; we keep only your verified name, country and the result.',
                    style: TextStyle(fontSize: 11, height: 1.4, color: context.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _errorText(String code) => switch (code) {
        'document_expired' => 'That ID has expired. Please use a valid one.',
        'document_unverified_other' || 'document_type_not_supported' => 'We couldn’t read that ID. Try another document in good light.',
        'selfie_face_mismatch' => 'The selfie didn’t match the ID photo. Try again in good light, without glasses or a hat.',
        'consent_declined' => 'Verification needs your consent to continue.',
        _ => 'Something didn’t work. Please try again in good light.',
      };
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
