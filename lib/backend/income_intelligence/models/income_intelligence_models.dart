import 'package:flutter/material.dart';

/// Models the core metrics for subscription / recurring income channels
/// Formula: ARR = MRR * 12
class ArrMrrModel {
  final double mrr;
  final double arpu;
  final double churnRate;
  final double monthlyBurn;
  final int payingSubscribers;

  const ArrMrrModel({
    required this.mrr,
    this.arpu = 29.99,
    this.churnRate = 0.035,
    this.monthlyBurn = 35000.0,
    this.payingSubscribers = 8336,
  });

  /// Annual Recurring Revenue: MRR * 12
  double get arr => mrr * 12.0;

  /// Customer Lifetime Value: ARPU / Churn Rate
  double get lifetimeValue => churnRate > 0 ? arpu / churnRate : 0.0;

  /// Net Monthly Cashflow
  double get netMonthlyCashflow => mrr - monthlyBurn;

  /// Estimated Runway in Months
  double get runwayMonths => monthlyBurn > mrr && monthlyBurn > 0 ? (mrr * 6) / (monthlyBurn - mrr) : double.infinity;

  ArrMrrModel copyWith({
    double? mrr,
    double? arpu,
    double? churnRate,
    double? monthlyBurn,
    int? payingSubscribers,
  }) {
    return ArrMrrModel(
      mrr: mrr ?? this.mrr,
      arpu: arpu ?? this.arpu,
      churnRate: churnRate ?? this.churnRate,
      monthlyBurn: monthlyBurn ?? this.monthlyBurn,
      payingSubscribers: payingSubscribers ?? this.payingSubscribers,
    );
  }
}

/// Represents an equity stakeholder in the company cap table
class CapTableShareholder {
  final String id;
  final String name;
  final String role; // 'You', 'Co-founder', 'Investor', 'Option Pool'
  final double shareCount;
  final Color badgeColor;

  const CapTableShareholder({
    required this.id,
    required this.name,
    required this.role,
    required this.shareCount,
    required this.badgeColor,
  });
}

/// Models cap table equity distribution and dilution
class CapTableEquityModel {
  final List<CapTableShareholder> shareholders;
  final double totalShares;
  final int vestingDurationYears;
  final int cliffDurationYears;

  const CapTableEquityModel({
    required this.shareholders,
    required this.totalShares,
    this.vestingDurationYears = 4,
    this.cliffDurationYears = 1,
  });

  double getPercentage(double shareCount) {
    if (totalShares <= 0) return 0.0;
    return (shareCount / totalShares) * 100.0;
  }
}

/// Models liquidation preference outcomes on company sale/exit
/// Compares Founder-Friendly (1x Non-Participating) vs Watch-Out (Participating)
class LiquidationPreferenceModel {
  final double raisedAmount; // e.g. $10,000,000
  final double exitValuation; // e.g. $30,000,000
  final double investorEquityPercentage; // e.g. 0.40 (40%)
  final double liquidationMultiple; // e.g. 1.0x

  const LiquidationPreferenceModel({
    required this.raisedAmount,
    required this.exitValuation,
    this.investorEquityPercentage = 0.40,
    this.liquidationMultiple = 1.0,
  });

  /// 1. 1x Non-Participating (Founder-Friendly):
  /// Investor receives the HIGHER of:
  ///   a) 1x Liquidation preference ($10M)
  ///   b) Common share pro-rata percentage (e.g. 40% of $30M = $12M)
  /// If preference taken, Founder keeps the entire remainder ($20M).
  double get nonParticipatingInvestorPayout {
    final prefPayout = (raisedAmount * liquidationMultiple).clamp(0.0, exitValuation);
    final proRataPayout = exitValuation * investorEquityPercentage;
    // In market practice, investor takes max of preference or pro-rata
    return prefPayout > proRataPayout ? prefPayout : proRataPayout;
  }

  double get nonParticipatingFounderPayout {
    return (exitValuation - nonParticipatingInvestorPayout).clamp(0.0, exitValuation);
  }

  /// 2. Participating (Double-Dipping / Watch Out):
  /// Investor gets preference FIRST ($10M), AND THEN takes their equity cut (40%)
  /// of whatever is left ($20M * 40% = $8M), for total $18M!
  /// Founder only receives the remainder ($12M).
  double get participatingInvestorPreferenceReturn {
    return (raisedAmount * liquidationMultiple).clamp(0.0, exitValuation);
  }

  double get participatingInvestorRemainderCut {
    final remainingAfterPref = (exitValuation - participatingInvestorPreferenceReturn).clamp(0.0, exitValuation);
    return remainingAfterPref * investorEquityPercentage;
  }

  double get participatingInvestorTotalPayout {
    return (participatingInvestorPreferenceReturn + participatingInvestorRemainderCut).clamp(0.0, exitValuation);
  }

  double get participatingFounderPayout {
    return (exitValuation - participatingInvestorTotalPayout).clamp(0.0, exitValuation);
  }

  /// Amount founder loses due to participating structure
  double get founderLossToParticipating {
    return (nonParticipatingFounderPayout - participatingFounderPayout).clamp(0.0, exitValuation);
  }
}

/// Represents an investor protective provision (veto right)
class ProtectiveProvisionItem {
  final String id;
  final String title;
  final IconData icon;
  final String shortDescription;
  final String explanation;
  final String founderRiskLevel; // 'High', 'Critical', 'Moderate'
  final String founderFriendlyCarveOut;

  const ProtectiveProvisionItem({
    required this.id,
    required this.title,
    required this.icon,
    required this.shortDescription,
    required this.explanation,
    required this.founderRiskLevel,
    required this.founderFriendlyCarveOut,
  });
}

