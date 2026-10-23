import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../backend/finance/models/ledger_models.dart';
import '../../backend/finance/services/ledger_service.dart';
import '../../shared/theme/app_theme.dart';

/// A payout the creator asked for, in `ledgers/{uid}/payout_requests`.
class PayoutRequest {
  final String id;
  final double amount;
  final String currency;
  final String status; // requested | processing | paid | rejected
  final DateTime createdAt;

  const PayoutRequest({
    required this.id,
    required this.amount,
    required this.currency,
    required this.status,
    required this.createdAt,
  });

  factory PayoutRequest.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return PayoutRequest(
      id: doc.id,
      amount: (d['amount'] as num?)?.toDouble() ?? 0,
      currency: (d['currency'] ?? 'USD') as String,
      status: (d['status'] ?? 'requested') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  bool get isOpen => status == 'requested' || status == 'processing';
}

final _payoutRequestsProvider = StreamProvider.autoDispose<List<PayoutRequest>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(const []);
  return FirebaseFirestore.instance
      .collection('ledgers')
      .doc(uid)
      .collection('payout_requests')
      .orderBy('createdAt', descending: true)
      .limit(20)
      .snapshots()
      .map((s) => s.docs.map(PayoutRequest.fromFirestore).toList());
});

/// Totals derived from the ledger. Every number comes from real entries.
class _EarningsSummary {
  final double available;
  final double pending;
  final double lifetime;
  final double inPeriod;
  final double previousPeriod;
  final Map<String, double> bySource;
  final List<double> daily; // oldest → newest, one per day in the period
  final String currency;

  const _EarningsSummary({
    required this.available,
    required this.pending,
    required this.lifetime,
    required this.inPeriod,
    required this.previousPeriod,
    required this.bySource,
    required this.daily,
    required this.currency,
  });

  static _EarningsSummary from(List<LedgerEntry> entries, List<PayoutRequest> payouts, int days) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(Duration(days: days - 1));
    final prevStart = start.subtract(Duration(days: days));
    var available = 0.0, pending = 0.0, lifetime = 0.0, inPeriod = 0.0, prev = 0.0;
    final bySource = <String, double>{};
    final daily = List<double>.filled(days, 0);

    for (final e in entries) {
      if (e.refundState == RefundState.full) continue;
      if (e.status == TransactionStatus.failed || e.status == TransactionStatus.voided) continue;
      final settled = e.status == TransactionStatus.settled;
      final credit = e.type == TransactionType.credit;
      if (!settled) {
        if (credit) pending += e.amount;
        continue;
      }
      available += credit ? e.amount : -e.amount;
      if (!credit) continue;
      lifetime += e.amount;
      final day = DateTime(e.createdAt.year, e.createdAt.month, e.createdAt.day);
      if (!day.isBefore(start)) {
        inPeriod += e.amount;
        final key = e.source.isEmpty ? 'other' : e.source;
        bySource[key] = (bySource[key] ?? 0) + e.amount;
        final i = day.difference(start).inDays;
        if (i >= 0 && i < days) daily[i] += e.amount;
      } else if (!day.isBefore(prevStart)) {
        prev += e.amount;
      }
    }
    // Money already asked for can't be requested twice.
    for (final p in payouts.where((p) => p.isOpen)) {
      available -= p.amount;
    }
    return _EarningsSummary(
      available: available < 0 ? 0 : available,
      pending: pending,
      lifetime: lifetime,
      inPeriod: inPeriod,
      previousPeriod: prev,
      bySource: bySource,
      daily: daily,
      currency: entries.isNotEmpty ? entries.first.currency : 'USD',
    );
  }
}

/// Owner-only earnings dashboard at `/profile/earnings`, built on the
/// creator's ledger (`ledgers/{uid}/entries`). Entries are written by the
/// payment backend (gifts, tips, subscriptions, …); this screen only reads
/// them and lets the creator request a payout.
class EarningsScreen extends ConsumerStatefulWidget {
  const EarningsScreen({super.key});

  @override
  ConsumerState<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends ConsumerState<EarningsScreen> {
  static const _periods = {7: '7 days', 30: '30 days', 90: '90 days'};
  static const double _minPayout = 10;
  int _days = 30;

  String _money(double v, String currency) {
    final symbol = switch (currency.toUpperCase()) {
      'USD' => '\$',
      'EUR' => '€',
      'GBP' => '£',
      _ => '$currency ',
    };
    return '$symbol${v.toStringAsFixed(2)}';
  }

  static String _sourceLabel(String s) {
    switch (s) {
      case 'gift':
      case 'gifts':
        return 'Gifts';
      case 'tip':
      case 'tips':
        return 'Tips';
      case 'subscription':
      case 'subscriptions':
        return 'Subscriptions';
      case 'premium_series':
      case 'premiumSeries':
        return 'Premium series';
      case 'creatorRewards':
      case 'creator_rewards':
        return 'Creator rewards';
      case 'affiliate':
      case 'affiliateLinks':
        return 'Affiliate';
      case 'digitalProducts':
      case 'digital_product':
        return 'Digital products';
      case 'payout':
        return 'Payout';
      default:
        if (s.isEmpty) return 'Other';
        return s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ');
    }
  }

  static IconData _sourceIcon(String s) {
    if (s.startsWith('gift')) return Icons.card_giftcard_rounded;
    if (s.startsWith('tip')) return Icons.volunteer_activism_rounded;
    if (s.startsWith('sub')) return Icons.workspace_premium_rounded;
    if (s.startsWith('premium')) return Icons.lock_open_rounded;
    if (s.startsWith('affiliate')) return Icons.link_rounded;
    if (s.startsWith('payout')) return Icons.account_balance_rounded;
    return Icons.payments_rounded;
  }

  Future<void> _requestPayout(_EarningsSummary sum) async {
    HapticFeedback.lightImpact();
    if (sum.available < _minPayout) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.brandBlue,
        content: Text('You can withdraw once you have ${_money(_minPayout, sum.currency)} available.'),
      ));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        title: Text('Request payout',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
        content: Text(
          'Withdraw ${_money(sum.available, sum.currency)} to your payout method on file. '
          'Requests are reviewed and usually paid within 3–5 business days.',
          style: GoogleFonts.inter(fontSize: 12.5, color: ctx.textSecondary, height: 1.35),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('ledgers').doc(uid).collection('payout_requests').add({
        'userId': uid,
        'amount': double.parse(sum.available.toStringAsFixed(2)),
        'currency': sum.currency,
        'status': 'requested',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.brandBlue,
        content: Text('Payout requested'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.brandPink,
        content: Text('Could not request payout: $e'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(ledgerHistoryProvider);
    final payouts = ref.watch(_payoutRequestsProvider).value ?? const <PayoutRequest>[];

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.topBarBg,
        toolbarHeight: 50,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.topBarFg),
          onPressed: () => context.canPop() ? context.pop() : context.go('/profile/me'),
        ),
        title: Text('Earnings',
            style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: context.topBarFg)),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Monetization tools',
            icon: Icon(Icons.tune_rounded, color: context.topBarFg),
            onPressed: () => context.push('/profile/monetization'),
          ),
        ],
      ),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandBlue)),
        error: (e, _) => _message(Icons.error_outline_rounded, 'Could not load earnings', '$e'),
        data: (entries) {
          final sum = _EarningsSummary.from(entries, payouts, _days);
          return RefreshIndicator(
            color: AppColors.brandBlue,
            onRefresh: () async => ref.invalidate(ledgerHistoryProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
              children: [
                _hero(sum, payouts),
                const SizedBox(height: 14),
                _periodChips(),
                const SizedBox(height: 10),
                _chartCard(sum),
                const SizedBox(height: 14),
                _breakdown(sum),
                if (payouts.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _payouts(payouts),
                ],
                const SizedBox(height: 14),
                _transactions(entries),
              ].animate(interval: 40.ms).fadeIn(duration: 250.ms).slideY(begin: 0.04, end: 0),
            ),
          );
        },
      ),
    );
  }

  Widget _hero(_EarningsSummary sum, List<PayoutRequest> payouts) {
    final change = sum.previousPeriod == 0
        ? null
        : ((sum.inPeriod - sum.previousPeriod) / sum.previousPeriod * 100);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brandBlue, AppColors.brandBlue.withValues(alpha: 0.78)],
        ),
        boxShadow: AppShadows.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('AVAILABLE BALANCE',
              style: GoogleFonts.inter(
                  fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.9, color: AppColors.brandWhite.withValues(alpha: 0.75))),
          const SizedBox(height: 6),
          Text(_money(sum.available, sum.currency),
              style: GoogleFonts.inter(
                  fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: AppColors.brandWhite)),
          if (change != null) ...[
            const SizedBox(height: 4),
            Text(
              '${change >= 0 ? '▲' : '▼'} ${change.abs().toStringAsFixed(0)}% vs previous ${_periods[_days]}',
              style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.brandWhite.withValues(alpha: 0.85)),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              _heroStat('Pending', _money(sum.pending, sum.currency)),
              _heroStat('Lifetime', _money(sum.lifetime, sum.currency)),
              _heroStat(_periods[_days]!, _money(sum.inPeriod, sum.currency)),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandWhite,
                foregroundColor: AppColors.brandBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
              onPressed: payouts.any((p) => p.isOpen) ? null : () => _requestPayout(sum),
              icon: const Icon(Icons.account_balance_wallet_rounded, size: 18),
              label: Text(payouts.any((p) => p.isOpen) ? 'Payout in progress' : 'Withdraw',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.brandWhite.withValues(alpha: 0.75))),
            const SizedBox(height: 2),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.brandWhite)),
          ],
        ),
      );

  Widget _periodChips() {
    return Row(
      children: [
        for (final e in _periods.entries)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(e.value),
              selected: _days == e.key,
              showCheckmark: false,
              labelStyle: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _days == e.key ? AppColors.brandWhite : context.textPrimary,
              ),
              selectedColor: AppColors.brandBlue,
              backgroundColor: context.surface,
              side: BorderSide(color: _days == e.key ? AppColors.brandBlue : context.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
              onSelected: (_) {
                HapticFeedback.selectionClick();
                setState(() => _days = e.key);
              },
            ),
          ),
      ],
    );
  }

  Widget _card({required String title, required Widget child, Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: context.textPrimary)),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _chartCard(_EarningsSummary sum) {
    final max = sum.daily.fold<double>(0, (m, v) => v > m ? v : m);
    return _card(
      title: 'Daily earnings',
      trailing: Text(_money(sum.inPeriod, sum.currency),
          style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.brandBlue)),
      child: SizedBox(
        height: 120,
        child: max == 0
            ? Center(
                child: Text('No earnings in this period yet',
                    style: GoogleFonts.inter(fontSize: 12, color: context.textMuted)),
              )
            : BarChart(
                BarChartData(
                  maxY: max * 1.15,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => context.surfaceMid,
                      getTooltipItem: (g, _, rod, _) => BarTooltipItem(
                        _money(rod.toY, sum.currency),
                        GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: context.textPrimary),
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < sum.daily.length; i++)
                      BarChartGroupData(x: i, barRods: [
                        BarChartRodData(
                          toY: sum.daily[i],
                          width: _days <= 7 ? 18 : (_days <= 30 ? 5 : 2),
                          color: i == sum.daily.length - 1 ? AppColors.brandPink : AppColors.brandBlue,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ]),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _breakdown(_EarningsSummary sum) {
    final items = sum.bySource.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return _card(
      title: 'Where it comes from',
      child: items.isEmpty
          ? Text('Gifts, tips and subscriptions you receive will show up here.',
              style: GoogleFonts.inter(fontSize: 12, color: context.textMuted))
          : Column(
              children: [
                for (final e in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(_sourceIcon(e.key), size: 18, color: AppColors.brandBlue),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(_sourceLabel(e.key),
                                        style: GoogleFonts.inter(fontSize: 12.5, color: context.textPrimary)),
                                  ),
                                  Text(_money(e.value, sum.currency),
                                      style: GoogleFonts.inter(
                                          fontSize: 12.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
                                ],
                              ),
                              const SizedBox(height: 5),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(AppRadius.full),
                                child: LinearProgressIndicator(
                                  value: sum.inPeriod == 0 ? 0 : e.value / sum.inPeriod,
                                  minHeight: 4,
                                  color: AppColors.brandBlue,
                                  backgroundColor: context.surfaceMid,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _payouts(List<PayoutRequest> payouts) {
    return _card(
      title: 'Payouts',
      child: Column(
        children: [
          for (final p in payouts.take(5))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.account_balance_rounded, color: AppColors.brandBlue, size: 20),
              title: Text(_money(p.amount, p.currency),
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary)),
              subtitle: Text(_date(p.createdAt), style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary)),
              trailing: _statusPill(p.status),
            ),
        ],
      ),
    );
  }

  Widget _statusPill(String status) {
    final color = status == 'paid'
        ? AppColors.brandBlue
        : status == 'rejected'
            ? AppColors.brandPink
            : context.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(status.toUpperCase(),
          style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: color)),
    );
  }

  Widget _transactions(List<LedgerEntry> entries) {
    return _card(
      title: 'Activity',
      child: entries.isEmpty
          ? Text('No transactions yet. Turn on gifts, tips or subscriptions in Monetization tools to start earning.',
              style: GoogleFonts.inter(fontSize: 12, color: context.textMuted, height: 1.35))
          : Column(
              children: [
                for (final e in entries.take(30))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.brandBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Icon(_sourceIcon(e.source), color: AppColors.brandBlue, size: 18),
                    ),
                    title: Text(_sourceLabel(e.source),
                        style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary)),
                    subtitle: Text(
                      '${_date(e.createdAt)} · ${e.status.name}',
                      style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary),
                    ),
                    trailing: Text(
                      '${e.type == TransactionType.credit ? '+' : '−'}${_money(e.amount, e.currency)}',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: e.type == TransactionType.credit ? AppColors.brandBlue : context.textPrimary,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  static String _date(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }

  Widget _message(IconData icon, String title, String body) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: context.textMuted),
              const SizedBox(height: 10),
              Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: context.textPrimary)),
              const SizedBox(height: 4),
              Text(body, textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary)),
            ],
          ),
        ),
      );
}
