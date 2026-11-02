import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/income_intelligence_models.dart';

final incomeIntelligenceServiceProvider = Provider<IncomeIntelligenceService>((ref) {
  return IncomeIntelligenceService();
});

/// Current ARR/MRR state provider for interactive simulation
class ArrMrrNotifier extends Notifier<ArrMrrModel> {
  @override
  ArrMrrModel build() => const ArrMrrModel(
        mrr: 250000.0,
        arpu: 29.99,
        churnRate: 0.035,
        monthlyBurn: 45000.0,
        payingSubscribers: 8336,
      );

  @override
  set state(ArrMrrModel val) => super.state = val;
}

final arrMrrStateProvider =
    NotifierProvider<ArrMrrNotifier, ArrMrrModel>(ArrMrrNotifier.new);

/// Current Liquidation Preference state provider for interactive exit modeling
class LiquidationPreferenceNotifier extends Notifier<LiquidationPreferenceModel> {
  @override
  LiquidationPreferenceModel build() => const LiquidationPreferenceModel(
        raisedAmount: 10000000.0,
        exitValuation: 30000000.0,
        investorEquityPercentage: 0.40,
        liquidationMultiple: 1.0,
      );

  @override
  set state(LiquidationPreferenceModel val) => super.state = val;
}

final liquidationPreferenceStateProvider =
    NotifierProvider<LiquidationPreferenceNotifier, LiquidationPreferenceModel>(
        LiquidationPreferenceNotifier.new);

/// Current Cap Table state provider
class CapTableNotifier extends Notifier<CapTableEquityModel> {
  @override
  CapTableEquityModel build() => const CapTableEquityModel(
        shareholders: [
          CapTableShareholder(
            id: 'you',
            name: 'You (CEO)',
            role: 'Founder',
            shareCount: 50.0,
            badgeColor: Color(0xFF10B981), // Emerald green
          ),
          CapTableShareholder(
            id: 'cofounder',
            name: 'Co-founder (CTO)',
            role: 'Co-founder',
            shareCount: 50.0,
            badgeColor: Color(0xFF059669), // Dark emerald green
          ),
        ],
        totalShares: 100.0,
      );

  @override
  set state(CapTableEquityModel val) => super.state = val;
}

final capTableStateProvider =
    NotifierProvider<CapTableNotifier, CapTableEquityModel>(CapTableNotifier.new);

/// Income Intelligence Service
/// Powers smart income channel financial mechanics, cap table modeling,
/// liquidation waterfalls, and protective provision term sheet analysis.
class IncomeIntelligenceService {
  /// Computes ARR/MRR metrics with full financial indicators
  ArrMrrModel calculateArrMrr({
    required double mrr,
    double arpu = 29.99,
    double churnRate = 0.035,
    double monthlyBurn = 45000.0,
  }) {
    final subscribers = arpu > 0 ? (mrr / arpu).round() : 0;
    return ArrMrrModel(
      mrr: mrr,
      arpu: arpu,
      churnRate: churnRate,
      monthlyBurn: monthlyBurn,
      payingSubscribers: subscribers,
    );
  }

  /// Calculates exit proceeds for Founder vs Investor under both liquidation preference regimes
  LiquidationPreferenceModel calculateLiquidationWaterfall({
    required double raisedAmount,
    required double exitValuation,
    double investorEquityPercentage = 0.40,
    double liquidationMultiple = 1.0,
  }) {
    return LiquidationPreferenceModel(
      raisedAmount: raisedAmount,
      exitValuation: exitValuation,
      investorEquityPercentage: investorEquityPercentage,
      liquidationMultiple: liquidationMultiple,
    );
  }

  /// Simulates a new financing round and computes new cap table dilution
  CapTableEquityModel simulateRound({
    required CapTableEquityModel currentCapTable,
    required double investmentAmount,
    required double preMoneyValuation,
    double optionPoolPercentage = 0.10,
  }) {
    final postMoney = preMoneyValuation + investmentAmount;
    final investorEquityPct = investmentAmount / postMoney;
    
    // Total current shares (e.g. 100)
    final existingShares = currentCapTable.totalShares;
    
    // Target post-round total shares to grant investor their exact percentage
    final newTotalShares = existingShares / (1.0 - investorEquityPct - optionPoolPercentage);
    final investorShares = newTotalShares * investorEquityPct;
    final optionPoolShares = newTotalShares * optionPoolPercentage;

    final updatedShareholders = [
      ...currentCapTable.shareholders,
      CapTableShareholder(
        id: 'option_pool',
        name: 'Unallocated Option Pool',
        role: 'ESOP',
        shareCount: double.parse(optionPoolShares.toStringAsFixed(1)),
        badgeColor: const Color(0xFF6B7280), // Muted slate
      ),
      CapTableShareholder(
        id: 'investor_series_a',
        name: 'Lead Investor',
        role: 'Preferred Investor',
        shareCount: double.parse(investorShares.toStringAsFixed(1)),
        badgeColor: const Color(0xFF38BDF8), // Cyan / light teal
      ),
    ];

    return CapTableEquityModel(
      shareholders: updatedShareholders,
      totalShares: double.parse(newTotalShares.toStringAsFixed(1)),
      vestingDurationYears: currentCapTable.vestingDurationYears,
      cliffDurationYears: currentCapTable.cliffDurationYears,
    );
  }

  /// Standard market protective provisions evaluated against founder risk
  List<ProtectiveProvisionItem> getStandardProtectiveProvisions() {
    return const [
      ProtectiveProvisionItem(
        id: 'sell_company',
        title: 'Sell the company',
        icon: Icons.storefront_rounded,
        shortDescription: 'M&A and company sale veto',
        explanation: 'Investors can block an acquisition even if the founder and common shareholders want to sell.',
        founderRiskLevel: 'Critical',
        founderFriendlyCarveOut: 'Include a "Drag-Along" clause requiring 51%+ of common stock consent, or stipulate that preferred veto falls away if exit proceeds exceed a designated return threshold (e.g. 3x-5x preference).',
      ),
      ProtectiveProvisionItem(
        id: 'raise_round',
        title: 'Raise another round',
        icon: Icons.bar_chart_rounded,
        shortDescription: 'Future financing authorization veto',
        explanation: 'Investors can block future rounds of funding if they disagree with valuation or dilution terms.',
        founderRiskLevel: 'High',
        founderFriendlyCarveOut: 'Specify that consent cannot be unreasonably withheld, and permit standard unpriced SAFEs or convertible notes up to a qualified aggregate cap without separate preferred approvals.',
      ),
      ProtectiveProvisionItem(
        id: 'change_budget',
        title: 'Change the budget',
        icon: Icons.account_balance_wallet_rounded,
        shortDescription: 'Annual budget and major expenditure veto',
        explanation: 'Requires board or preferred approval to alter the operating plan or exceed budget lines.',
        founderRiskLevel: 'Moderate',
        founderFriendlyCarveOut: 'Allow the CEO/Management a standard 15% to 20% variance allowance per budget line item before triggering board approval.',
      ),
      ProtectiveProvisionItem(
        id: 'issue_shares',
        title: 'Issue new shares',
        icon: Icons.share_rounded,
        shortDescription: 'Equity pool and option grant veto',
        explanation: 'Prevents the CEO from granting equity to key hires or creating employee stock option pools without consent.',
        founderRiskLevel: 'High',
        founderFriendlyCarveOut: 'Carve out pre-approved Board-approved ESOP pools (typically 10-15%) so the CEO can issue routine employee grants without preferred stockholder votes.',
      ),
      ProtectiveProvisionItem(
        id: 'take_debt',
        title: 'Take on debt',
        icon: Icons.credit_card_rounded,
        shortDescription: 'Indebtedness and venture debt veto',
        explanation: 'Blocks borrowing money or taking credit lines that could introduce senior debt liens on company assets.',
        founderRiskLevel: 'Moderate',
        founderFriendlyCarveOut: 'Permit ordinary course trade credit, equipment leasing, and standard operating credit facilities up to a defined ceiling (e.g. \$250,000 to \$500,000) without investor sign-off.',
      ),
    ];
  }
}

