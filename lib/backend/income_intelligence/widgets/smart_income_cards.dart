import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../shared/theme/app_theme.dart';
import '../services/income_intelligence_service.dart';

/// Formatter helper
final _currencyFormatter = NumberFormat.compactCurrency(symbol: '\$', decimalDigits: 1);
final _exactCurrencyFormatter = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

/// 1. ARR = MRR x 12 Intelligence Card
/// Replicates the aesthetic of: $3M ARR = MRR x 12
class ArrMrrIntelligenceCard extends ConsumerWidget {
  const ArrMrrIntelligenceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(arrMrrStateProvider);
    final isDark = context.isDark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121417) : context.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isDark ? const Color(0xFF262A30) : context.border,
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.trending_up_rounded, color: Color(0xFF10B981), size: 16),
              ),
              const SizedBox(width: 8),
              Text(
                'RECURRING INCOME ENGINE',
                style: GoogleFonts.inter(
                  color: const Color(0xFF10B981),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Central Hero Math Equation: $3M ARR = MRR x 12
          Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${_currencyFormatter.format(model.arr)} ARR = MRR × 12',
                style: GoogleFonts.inter(
                  color: const Color(0xFF10B981),
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Monthly Recurring: ${_exactCurrencyFormatter.format(model.mrr)}/mo · ${_currencyFormatter.format(model.arr)}/yr Run-Rate',
              style: GoogleFonts.inter(
                color: context.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Interactive MRR Slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF10B981),
              inactiveTrackColor: isDark ? const Color(0xFF2D333B) : const Color(0xFFE2E8F0),
              thumbColor: const Color(0xFF10B981),
              overlayColor: const Color(0xFF10B981).withValues(alpha: 0.2),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              trackHeight: 3.5,
            ),
            child: Slider(
              value: model.mrr.clamp(10000.0, 1000000.0),
              min: 10000.0,
              max: 1000000.0,
              divisions: 99,
              onChanged: (newMrr) {
                HapticFeedback.selectionClick();
                ref.read(arrMrrStateProvider.notifier).state = ref
                    .read(incomeIntelligenceServiceProvider)
                    .calculateArrMrr(mrr: newMrr, arpu: model.arpu, churnRate: model.churnRate);
              },
            ),
          ),

          // Metric Stats Grid
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  context,
                  label: 'Subscribers',
                  value: NumberFormat.compact().format(model.payingSubscribers),
                  sub: '@ \$${model.arpu.toStringAsFixed(0)}/mo',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  context,
                  label: 'Churn Rate',
                  value: '${(model.churnRate * 100).toStringAsFixed(1)}%',
                  sub: 'Monthly rate',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  context,
                  label: 'LTV Value',
                  value: _currencyFormatter.format(model.lifetimeValue),
                  sub: 'Lifetime value',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(BuildContext context, {required String label, required String value, required String sub}) {
    final isDark = context.isDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171B20) : context.surfaceMid,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: context.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(color: context.textMuted, fontSize: 10, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(value, style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
          Text(sub, style: GoogleFonts.inter(color: context.textSecondary, fontSize: 9)),
        ],
      ),
    );
  }
}

/// 2. Cap Table & Equity Split Modeling Card
/// Replicates the diagram:
/// You (-50) & Co-founder (-50) -> Company (-100) / Dilution (-120, Investor -7)
class CapTableEquityDiagramCard extends ConsumerStatefulWidget {
  const CapTableEquityDiagramCard({super.key});

  @override
  ConsumerState<CapTableEquityDiagramCard> createState() => _CapTableEquityDiagramCardState();
}

class _CapTableEquityDiagramCardState extends ConsumerState<CapTableEquityDiagramCard> {
  bool _includeInvestorRound = false;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;

    // Calculate displayed counts based on toggle
    final youShares = 50.0;
    final cofounderShares = 50.0;
    final investorShares = _includeInvestorRound ? 20.0 : 0.0;
    final totalShares = youShares + cofounderShares + investorShares;

    final youPct = (youShares / totalShares) * 100;
    final cofounderPct = (cofounderShares / totalShares) * 100;
    final investorPct = (investorShares / totalShares) * 100;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121417) : context.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isDark ? const Color(0xFF262A30) : context.border,
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0C4FA8).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.pie_chart_outline_rounded, color: AppColors.brandBlue, size: 16),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'CAP TABLE & DILUTION',
                    style: GoogleFonts.inter(
                      color: context.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              // Round Toggle
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _includeInvestorRound = !_includeInvestorRound);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _includeInvestorRound
                        ? AppColors.brandBlue.withValues(alpha: 0.15)
                        : context.surfaceMid,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(
                      color: _includeInvestorRound ? AppColors.brandBlue : context.border,
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _includeInvestorRound ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                        size: 13,
                        color: _includeInvestorRound ? AppColors.brandBlue : context.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _includeInvestorRound ? 'Seed Round Added' : 'Simulate Round',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: _includeInvestorRound ? AppColors.brandBlue : context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Diagram Representation ──
          // Top Row: Founders
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildFounderNode(
                context,
                title: 'You',
                sharesText: '- 50',
                percentageText: '${youPct.toStringAsFixed(1)}%',
                iconColor: const Color(0xFF10B981),
              ),
              const SizedBox(width: 40),
              _buildFounderNode(
                context,
                title: 'Co-founder',
                sharesText: '- 50',
                percentageText: '${cofounderPct.toStringAsFixed(1)}%',
                iconColor: const Color(0xFF10B981),
              ),
            ],
          ),

          // Connecting Arrow Down
          const SizedBox(height: 12),
          Center(
            child: Icon(Icons.arrow_downward_rounded, size: 22, color: context.textMuted),
          ),
          const SizedBox(height: 12),

          // Middle Box: Company
          Center(
            child: Container(
              width: 110,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1F26) : context.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.5), width: 1.2),
              ),
              child: Column(
                children: [
                  const Icon(Icons.business_rounded, color: Color(0xFF38BDF8), size: 28),
                  const SizedBox(height: 6),
                  Text(
                    '- ${totalShares.toInt()}',
                    style: GoogleFonts.inter(
                      color: const Color(0xFF38BDF8),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Company Pool',
                    style: GoogleFonts.inter(color: context.textSecondary, fontSize: 9.5),
                  ),
                ],
              ),
            ),
          ),

          // Optional Investor Node below (Image 3)
          if (_includeInvestorRound) ...[
            const SizedBox(height: 12),
            Center(
              child: Icon(Icons.arrow_downward_rounded, size: 22, color: context.textMuted),
            ),
            const SizedBox(height: 12),
            Center(
              child: _buildFounderNode(
                context,
                title: 'Investor',
                sharesText: '- ${investorShares.toInt()}',
                percentageText: '${investorPct.toStringAsFixed(1)}%',
                iconColor: const Color(0xFF38BDF8),
              ),
            ),
          ],

          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F1216) : context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: context.border, width: 0.8),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_user_outlined, size: 16, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Standard 4-Year Vesting with 1-Year Cliff applies to preserve founder equity alignment.',
                    style: GoogleFonts.inter(color: context.textSecondary, fontSize: 11, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFounderNode(
    BuildContext context, {
    required String title,
    required String sharesText,
    required String percentageText,
    required Color iconColor,
  }) {
    return Column(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: iconColor.withValues(alpha: 0.5), width: 1.5),
          ),
          child: Icon(Icons.person_rounded, color: iconColor, size: 28),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: GoogleFonts.inter(color: context.textPrimary, fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 7, height: 7, color: iconColor),
            const SizedBox(width: 4),
            Text(
              sharesText,
              style: GoogleFonts.inter(color: context.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            Text(
              '($percentageText)',
              style: GoogleFonts.inter(color: iconColor, fontSize: 10, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ],
    );
  }
}

/// 3. Liquidation Preference Waterfall Comparison Card
/// Exact replica of Image 4:
/// "Liquidation preference - Who gets paid first when the company sells"
/// Raised -> $10M | Sold for -> $30M
/// FOUNDER-FRIENDLY (1x non-participating) vs WATCH OUT FOR (Participating)
class LiquidationPreferenceWaterfallCard extends ConsumerWidget {
  const LiquidationPreferenceWaterfallCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(liquidationPreferenceStateProvider);
    final isDark = context.isDark;

    final raisedFormatted = _currencyFormatter.format(model.raisedAmount);
    final exitFormatted = _currencyFormatter.format(model.exitValuation);

    // Non-participating payouts
    final nonPartInvestor = model.nonParticipatingInvestorPayout;
    final nonPartFounder = model.nonParticipatingFounderPayout;

    // Participating payouts
    final partPrefReturn = model.participatingInvestorPreferenceReturn;
    final partRemainderCut = model.participatingInvestorRemainderCut;
    final partFounder = model.participatingFounderPayout;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131518) : context.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isDark ? const Color(0xFF262A30) : context.border,
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with Raised & Sold for stats
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(Icons.star_rounded, color: Color(0xFF10B981), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Liquidation preference',
                      style: GoogleFonts.inter(
                        color: context.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Who gets paid first when the company sells',
                      style: GoogleFonts.inter(
                        color: context.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              // Raised & Sold for Pills
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Raised → ', style: GoogleFonts.inter(color: context.textMuted, fontSize: 12)),
                      Text(
                        raisedFormatted,
                        style: GoogleFonts.inter(color: const Color(0xFF38BDF8), fontSize: 13, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Sold for → ', style: GoogleFonts.inter(color: context.textMuted, fontSize: 12)),
                      Text(
                        exitFormatted,
                        style: GoogleFonts.inter(color: const Color(0xFF10B981), fontSize: 14, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Two-Column Comparison View (Founder-Friendly vs Watch Out For)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Column 1: FOUNDER-FRIENDLY ──
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF181C20) : const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.35),
                      width: 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FOUNDER-FRIENDLY',
                        style: GoogleFonts.inter(
                          color: const Color(0xFF10B981),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '1× non-participating',
                        style: GoogleFonts.inter(
                          color: context.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Investors get their money back.',
                        style: GoogleFonts.inter(
                          color: context.textSecondary,
                          fontSize: 10.5,
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Segmented Bar: $10M (Investor) | $20M (Founder)
                      Row(
                        children: [
                          Expanded(
                            flex: (nonPartInvestor / model.exitValuation * 100).round(),
                            child: _buildBarSegment(
                              color: const Color(0xFF2DD4BF), // Light teal
                              amountText: _currencyFormatter.format(nonPartInvestor),
                              subText: 'Investor\ngets back',
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            flex: (nonPartFounder / model.exitValuation * 100).round(),
                            child: _buildBarSegment(
                              color: const Color(0xFF059669), // Dark emerald
                              amountText: _currencyFormatter.format(nonPartFounder),
                              subText: 'Founder\nkeeps',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // ── Column 2: WATCH OUT FOR ──
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1F1819) : const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: const Color(0xFFF43F5E).withValues(alpha: 0.35),
                      width: 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WATCH OUT FOR',
                        style: GoogleFonts.inter(
                          color: const Color(0xFFF43F5E),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Participating',
                        style: GoogleFonts.inter(
                          color: context.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Investors get money back + a cut of what\'s left.',
                        style: GoogleFonts.inter(
                          color: context.textSecondary,
                          fontSize: 10.5,
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Segmented Bar: $10M (Investor) | +$8M (Cut) | $12M (Founder)
                      Row(
                        children: [
                          Expanded(
                            flex: (partPrefReturn / model.exitValuation * 100).round(),
                            child: _buildBarSegment(
                              color: const Color(0xFF2DD4BF),
                              amountText: _currencyFormatter.format(partPrefReturn),
                              subText: 'Investor\ngets back',
                            ),
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            flex: (partRemainderCut / model.exitValuation * 100).round(),
                            child: _buildBarSegment(
                              color: const Color(0xFFF43F5E), // Red highlight
                              amountText: '+${_currencyFormatter.format(partRemainderCut)}',
                              subText: 'Investor\ncut',
                            ),
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            flex: (partFounder / model.exitValuation * 100).round(),
                            child: _buildBarSegment(
                              color: const Color(0xFF059669),
                              amountText: _currencyFormatter.format(partFounder),
                              subText: 'Founder\nkeeps',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          // Interactive Exit Simulator Sliders
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Simulate Exit Valuation: ${_currencyFormatter.format(model.exitValuation)}',
                style: GoogleFonts.inter(color: context.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
              ),
              Text(
                'Founder Difference: -${_currencyFormatter.format(model.founderLossToParticipating)}',
                style: GoogleFonts.inter(color: const Color(0xFFF43F5E), fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF10B981),
              inactiveTrackColor: isDark ? const Color(0xFF262A30) : const Color(0xFFE2E8F0),
              thumbColor: const Color(0xFF10B981),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              trackHeight: 3.0,
            ),
            child: Slider(
              value: model.exitValuation.clamp(10000000.0, 100000000.0),
              min: 10000000.0,
              max: 100000000.0,
              divisions: 18,
              onChanged: (newExit) {
                HapticFeedback.selectionClick();
                ref.read(liquidationPreferenceStateProvider.notifier).state = ref
                    .read(incomeIntelligenceServiceProvider)
                    .calculateLiquidationWaterfall(
                      raisedAmount: model.raisedAmount,
                      exitValuation: newExit,
                      investorEquityPercentage: model.investorEquityPercentage,
                    );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarSegment({required Color color, required String amountText, required String subText}) {
    return Column(
      children: [
        Container(
          height: 24,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
          alignment: Alignment.center,
          child: Text(
            amountText,
            style: GoogleFonts.inter(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subText,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 8.5, height: 1.1),
        ),
      ],
    );
  }
}

/// 4. Protective Provisions Guard Card
/// Exact replica of Image 5:
/// Shield icon: "Protective provisions - Investor veto power over big decisions"
/// Sub: "The founder is still CEO — but can't do any of these without investor approval:"
/// Horizontal chips: [ Sell the company | Raise another round | Change the budget | Issue new shares | Take on debt ]
class ProtectiveProvisionsGuardCard extends ConsumerStatefulWidget {
  const ProtectiveProvisionsGuardCard({super.key});

  @override
  ConsumerState<ProtectiveProvisionsGuardCard> createState() => _ProtectiveProvisionsGuardCardState();
}

class _ProtectiveProvisionsGuardCardState extends ConsumerState<ProtectiveProvisionsGuardCard> {
  String? _selectedProvisionId;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDark;
    final provisions = ref.read(incomeIntelligenceServiceProvider).getStandardProtectiveProvisions();
    final selectedItem = provisions.firstWhere(
      (p) => p.id == (_selectedProvisionId ?? 'sell_company'),
      orElse: () => provisions.first,
    );

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131518) : context.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isDark ? const Color(0xFF262A30) : context.border,
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A1F26) : context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: const Icon(Icons.shield_outlined, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Protective provisions',
                      style: GoogleFonts.inter(
                        color: context.textPrimary,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Investor veto power over big decisions',
                      style: GoogleFonts.inter(
                        color: context.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'The founder is still CEO — but can\'t do any of these without investor approval:',
            style: GoogleFonts.inter(
              color: isDark ? Colors.grey.shade300 : context.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),

          // 5 Horizontal Pills matching Image 5
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: provisions.map((p) {
                final isSelected = p.id == (_selectedProvisionId ?? 'sell_company');
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedProvisionId = p.id);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF1D283A)
                            : (isDark ? const Color(0xFF181C20) : context.surfaceMid),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF38BDF8) : context.border,
                          width: 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            p.icon,
                            size: 16,
                            color: isSelected ? const Color(0xFF38BDF8) : context.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            p.title,
                            style: GoogleFonts.inter(
                              color: isSelected ? Colors.white : context.textSecondary,
                              fontSize: 11.5,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Detailed Explanation and Founder Carve-out for selected provision
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F1216) : context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.border, width: 0.8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Clause: ${selectedItem.title}',
                      style: GoogleFonts.inter(color: context.textPrimary, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: selectedItem.founderRiskLevel == 'Critical'
                            ? const Color(0xFFF43F5E).withValues(alpha: 0.2)
                            : const Color(0xFFF59E0B).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text(
                        '${selectedItem.founderRiskLevel} Risk',
                        style: GoogleFonts.inter(
                          color: selectedItem.founderRiskLevel == 'Critical'
                              ? const Color(0xFFF43F5E)
                              : const Color(0xFFF59E0B),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  selectedItem.explanation,
                  style: GoogleFonts.inter(color: context.textSecondary, fontSize: 11, height: 1.3),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lightbulb_outline_rounded, size: 14, color: Color(0xFF10B981)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Founder-Friendly Solution: ${selectedItem.founderFriendlyCarveOut}',
                        style: GoogleFonts.inter(
                          color: const Color(0xFF10B981),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

