import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../backend/money/money_models.dart';
import '../../backend/money/money_service.dart';
import '../../backend/money/plan_store_service.dart';
import '../../shared/theme/app_theme.dart';
import 'money_widgets.dart';

class _PlanInfo {
  final OneovaPlan plan;
  final String name;
  final String tagline;
  final IconData icon;
  final List<String> perks;
  const _PlanInfo(this.plan, this.name, this.tagline, this.icon, this.perks);
}

const _plans = [
  _PlanInfo(OneovaPlan.free, 'Free', 'Everything you need to start', Icons.bolt_rounded, [
    'Post clips, go live, chat and call',
    'Receive gifts and withdraw earnings',
    'Basic insights for 28 days',
  ]),
  _PlanInfo(OneovaPlan.plus, 'Plus', 'For people who create every week', Icons.add_circle_rounded, [
    'Plus badge on your profile',
    '2× daily Ova AI requests',
    'Insights for 90 days',
    'Priority support',
  ]),
  _PlanInfo(OneovaPlan.pro, 'Pro', 'For creators growing an audience', Icons.workspace_premium_rounded, [
    'Everything in Plus',
    'Pro badge and 5× Ova AI requests',
    'Per-clip insights with tips',
    'Early access to new Studio effects',
  ]),
  _PlanInfo(OneovaPlan.biz, 'Biz', 'For shops and brands on Oneova Biz', Icons.storefront_rounded, [
    'Everything in Pro',
    'Verified business badge',
    'Biz storefront tools and order insights',
    'Team access for your shop',
  ]),
];

/// Oneova plans (`/wallet/plans`), sold as Google Play subscriptions.
class PlansScreen extends ConsumerStatefulWidget {
  const PlansScreen({super.key});

  @override
  ConsumerState<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends ConsumerState<PlansScreen> {
  late Future<List<PlanOffer>> _offers = ref.read(planStoreServiceProvider).loadOffers();
  StreamSubscription<({bool ok, String message})>? _events;
  bool _yearly = false;
  OneovaPlan _pick = OneovaPlan.pro;
  bool _busy = false;
  bool _welcome = false;

  @override
  void initState() {
    super.initState();
    _events = ref.read(planStoreServiceProvider).events.listen((e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.ok && e.message.startsWith('Welcome')) {
        HapticFeedback.heavyImpact();
        setState(() => _welcome = true);
      } else if (e.message.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), behavior: SnackBarBehavior.floating));
      }
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  PlanOffer? _offer(List<PlanOffer> offers, OneovaPlan plan) =>
      offers.where((o) => o.plan == plan && o.yearly == _yearly).firstOrNull ?? offers.where((o) => o.plan == plan).firstOrNull;

  /// "Save 17%" on yearly, from the real Play prices.
  int? _yearlySaving(List<PlanOffer> offers, OneovaPlan plan) {
    final m = offers.where((o) => o.plan == plan && !o.yearly).firstOrNull;
    final y = offers.where((o) => o.plan == plan && o.yearly).firstOrNull;
    if (m == null || y == null || m.rawPrice <= 0) return null;
    final s = (1 - y.rawPrice / (m.rawPrice * 12)) * 100;
    return s >= 1 ? s.round() : null;
  }

  Future<void> _subscribe(PlanOffer offer, OneovaPlan current) async {
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    try {
      await ref.read(planStoreServiceProvider).buy(offer, currentPlan: current);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(moneyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(planStateProvider).value ?? const PlanState();
    return Stack(
      children: [
        MoneyScaffold(
          title: 'Plans',
          actions: [
            TextButton(
              onPressed: () => ref.read(planStoreServiceProvider).restore(),
              child: const Text('Restore', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.brandBlue)),
            ),
          ],
          body: FutureBuilder<List<PlanOffer>>(
            future: _offers,
            builder: (context, snap) {
              final offers = snap.data ?? const <PlanOffer>[];
              return ListView(
                padding: const EdgeInsets.only(bottom: 120),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Text('Grow faster with Oneova', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: context.textPrimary)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Text(
                      state.active
                          ? 'You’re on ${_plans[state.plan.index].name}${state.expiresAt != null ? ' · ${state.autoRenewing ? 'renews' : 'ends'} ${DateFormat('d MMM y').format(state.expiresAt!)}' : ''}.'
                          : 'Pick what fits you. Cancel any time in Google Play.',
                      style: TextStyle(fontSize: 12.5, color: context.textSecondary),
                    ),
                  ),
                  _periodToggle(offers),
                  const SizedBox(height: 12),
                  if (snap.hasError)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: MoneyCard(
                        margin: EdgeInsets.zero,
                        child: Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 18, color: context.textSecondary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(snap.error is StateError ? (snap.error as StateError).message : 'Plans are not available right now.',
                                  style: TextStyle(fontSize: 12, color: context.textSecondary)),
                            ),
                            TextButton(onPressed: () => setState(() => _offers = ref.read(planStoreServiceProvider).loadOffers()), child: const Text('Retry')),
                          ],
                        ),
                      ),
                    ),
                  for (final (i, info) in _plans.indexed)
                    _PlanCard(
                      info: info,
                      offer: info.plan == OneovaPlan.free ? null : _offer(offers, info.plan),
                      saving: _yearly ? _yearlySaving(offers, info.plan) : null,
                      selected: _pick == info.plan,
                      current: state.plan == info.plan,
                      recommended: info.plan == OneovaPlan.pro,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _pick = info.plan);
                      },
                    ).animate(delay: (60 * i).ms).fadeIn(duration: 260.ms).slideY(begin: 0.06, end: 0),
                  if (state.active)
                    Center(
                      child: TextButton.icon(
                        onPressed: () => launchUrl(
                          Uri.parse('https://play.google.com/store/account/subscriptions?package=com.oneova.app'),
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.open_in_new_rounded, size: 15),
                        label: const Text('Manage or cancel in Google Play'),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      'Billed by Google Play to your Google account. Renews automatically until you cancel. Prices include local taxes where they apply.',
                      style: TextStyle(fontSize: 11, height: 1.4, color: context.textMuted),
                    ),
                  ),
                ],
              );
            },
          ),
          bottom: FutureBuilder<List<PlanOffer>>(
            future: _offers,
            builder: (context, snap) {
              final offer = _pick == OneovaPlan.free ? null : _offer(snap.data ?? const [], _pick);
              final isCurrent = state.plan == _pick;
              final label = _pick == OneovaPlan.free
                  ? (state.active ? 'Cancel in Google Play' : 'You’re on Free')
                  : isCurrent
                      ? 'Your current plan'
                      : '${state.active ? 'Switch to' : 'Get'} ${_plans[_pick.index].name}${offer != null ? ' · ${offer.price}/${offer.yearly ? 'yr' : 'mo'}' : ''}';
              return SafeArea(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  decoration: BoxDecoration(color: context.surface, border: Border(top: BorderSide(color: context.border))),
                  child: PrimaryButton(
                    label: label,
                    busy: _busy,
                    icon: Icons.workspace_premium_rounded,
                    onPressed: _pick == OneovaPlan.free && state.active
                        ? () => launchUrl(Uri.parse('https://play.google.com/store/account/subscriptions?package=com.oneova.app'), mode: LaunchMode.externalApplication)
                        : offer == null || isCurrent
                            ? null
                            : () => _subscribe(offer, state.plan),
                  ),
                ),
              );
            },
          ),
        ),
        if (_welcome)
          Positioned.fill(
            child: Material(
              color: context.bg.withValues(alpha: 0.94),
              child: Stack(
                children: [
                  const Positioned.fill(child: ConfettiBurst()),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SuccessMark(icon: _plans[_pick.index].icon),
                        const SizedBox(height: 18),
                        Text('Welcome to ${_plans[_pick.index].name}!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: context.textPrimary)),
                        const SizedBox(height: 6),
                        Text('Your new perks are on. Let’s grow!', style: TextStyle(fontSize: 13, color: context.textSecondary)),
                        const SizedBox(height: 20),
                        SizedBox(width: 200, child: PrimaryButton(label: 'Let’s go', onPressed: () => setState(() => _welcome = false))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _periodToggle(List<PlanOffer> offers) {
    final hasYearly = offers.any((o) => o.yearly);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: context.surfaceMid, borderRadius: BorderRadius.circular(AppRadius.full)),
        child: Row(
          children: [
            for (final yearly in [false, true])
              Expanded(
                child: GestureDetector(
                  onTap: yearly && !hasYearly ? null : () => setState(() => _yearly = yearly),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _yearly == yearly ? context.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      border: _yearly == yearly ? Border.all(color: context.border) : null,
                    ),
                    child: Text(
                      yearly ? 'Yearly · save more' : 'Monthly',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: _yearly == yearly ? context.textPrimary : context.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.info,
    required this.offer,
    required this.saving,
    required this.selected,
    required this.current,
    required this.recommended,
    required this.onTap,
  });
  final _PlanInfo info;
  final PlanOffer? offer;
  final int? saving;
  final bool selected;
  final bool current;
  final bool recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final price = info.plan == OneovaPlan.free ? 'Free' : offer == null ? '—' : '${offer!.price}/${offer!.yearly ? 'yr' : 'mo'}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedScale(
          scale: selected ? 1 : 0.985,
          duration: const Duration(milliseconds: 150),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected ? AppColors.brandBlue.withValues(alpha: context.isDark ? 0.14 : 0.06) : context.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: selected ? AppColors.brandBlue : context.border, width: selected ? 1.5 : 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: info.plan == OneovaPlan.free ? null : AppColors.premiumGradient,
                        color: info.plan == OneovaPlan.free ? context.surfaceMid : null,
                      ),
                      child: Icon(info.icon, size: 17, color: info.plan == OneovaPlan.free ? context.textSecondary : Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(info.name, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: context.textPrimary)),
                              if (recommended) ...[const SizedBox(width: 6), _tag('MOST LOVED', AppColors.brandPink)],
                              if (current) ...[const SizedBox(width: 6), _tag('CURRENT', AppColors.brandBlue)],
                            ],
                          ),
                          Text(info.tagline, style: TextStyle(fontSize: 11.5, color: context.textSecondary)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(price, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: context.textPrimary)),
                        if (saving != null) Text('Save $saving%', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.brandPink)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final p in info.perks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_rounded, size: 14, color: selected ? AppColors.brandBlue : context.textMuted),
                        const SizedBox(width: 6),
                        Expanded(child: Text(p, style: TextStyle(fontSize: 12.5, color: context.textPrimary))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tag(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(AppRadius.xs)),
        child: Text(t, style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: 0.5, color: Colors.white)),
      );
}
