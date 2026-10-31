import 'package:cloud_firestore/cloud_firestore.dart';

/// What 1 Diamond (an earned coin) pays out, in USD. Same as DIAMOND_USD in
/// functions/src/creator/payoutLogic.ts.
const diamondUsd = 0.01;
const minWithdrawUsd = 10.0;
const holdDays = 7;

int _i(Object? v) => (v as num?)?.toInt() ?? 0;
double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
DateTime? _t(Object? v) => v is Timestamp ? v.toDate() : null;

/// `wallets/{uid}`: purchased coins (spend only) and earned Diamonds.
class CreatorWallet {
  final int coins;
  final int pendingDiamonds;
  final int availableDiamonds;
  final int lockedDiamonds;
  final int withdrawnDiamonds;
  final int releasedDiamonds;

  const CreatorWallet({
    this.coins = 0,
    this.pendingDiamonds = 0,
    this.availableDiamonds = 0,
    this.lockedDiamonds = 0,
    this.withdrawnDiamonds = 0,
    this.releasedDiamonds = 0,
  });

  factory CreatorWallet.fromMap(Map<String, dynamic>? m) => CreatorWallet(
        coins: _i(m?['balanceCoins']),
        pendingDiamonds: _i(m?['pendingCoins']),
        availableDiamonds: _i(m?['availableCoins']),
        lockedDiamonds: _i(m?['lockedCoins']),
        withdrawnDiamonds: _i(m?['withdrawnCoins']),
        releasedDiamonds: _i(m?['lifetimeEarnedCoins']),
      );

  /// Everything ever earned, held or not.
  int get lifetimeDiamonds {
    final released = availableDiamonds + lockedDiamonds + withdrawnDiamonds;
    return (releasedDiamonds > released ? releasedDiamonds : released) + pendingDiamonds;
  }
  double get availableUsd => availableDiamonds * diamondUsd;
  double get pendingUsd => pendingDiamonds * diamondUsd;
  double get lockedUsd => lockedDiamonds * diamondUsd;
  double get lifetimeUsd => lifetimeDiamonds * diamondUsd;
  double get withdrawnUsd => withdrawnDiamonds * diamondUsd;
  bool get canWithdraw => availableUsd >= minWithdrawUsd;
}

class LedgerItem {
  final String id;
  final int amount;
  final String type;
  final String status;
  final String? giftId;
  final int qty;
  final DateTime? createdAt;

  const LedgerItem({required this.id, required this.amount, required this.type, required this.status, this.giftId, this.qty = 1, this.createdAt});

  factory LedgerItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    return LedgerItem(
      id: d.id,
      amount: _i(m['amount']),
      type: (m['type'] as String?) ?? '',
      status: (m['status'] as String?) ?? 'completed',
      giftId: m['giftId'] as String?,
      qty: _i(m['qty']) == 0 ? 1 : _i(m['qty']),
      createdAt: _t(m['createdAt']),
    );
  }

  /// Diamonds (earnings) vs coins (purchased credit).
  bool get isDiamonds => const {'live_gift_received', 'user_gift_received', 'withdrawal', 'withdrawal_returned'}.contains(type);
  bool get isWithdrawal => type == 'withdrawal' || type == 'withdrawal_returned';

  String get title => switch (type) {
        'coin_purchase' => 'Coins bought',
        'live_gift_sent' => 'Gift sent in a live',
        'user_gift_sent' => 'Gift sent',
        'live_gift_received' => 'Gift received in your live',
        'user_gift_received' => 'Gift received',
        'withdrawal' => 'Withdrawal',
        'withdrawal_returned' => 'Withdrawal returned',
        _ => 'Wallet activity',
      };
}

class Withdrawal {
  final String id;
  final String status;
  final int diamonds;
  final double amountUsd;
  final double feeUsd;
  final double netUsd;
  final String currency;
  final double localAmount;
  final String methodLabel;
  final String rail;
  final bool review;
  final String? failureReason;
  final DateTime? createdAt;
  final List<({String status, DateTime at})> timeline;

  const Withdrawal({
    required this.id,
    required this.status,
    required this.diamonds,
    required this.amountUsd,
    required this.feeUsd,
    required this.netUsd,
    required this.currency,
    required this.localAmount,
    required this.methodLabel,
    required this.rail,
    required this.review,
    this.failureReason,
    this.createdAt,
    this.timeline = const [],
  });

  factory Withdrawal.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    return Withdrawal(
      id: d.id,
      status: (m['status'] as String?) ?? 'pending',
      diamonds: _i(m['diamonds']),
      amountUsd: _d(m['amountUsd']),
      feeUsd: _d(m['feeUsd']),
      netUsd: _d(m['netUsd']),
      currency: (m['currency'] as String?) ?? 'USD',
      localAmount: _d(m['localAmount']),
      methodLabel: (m['methodLabel'] as String?) ?? '',
      rail: (m['rail'] as String?) ?? '',
      review: m['review'] == true,
      failureReason: m['failureReason'] as String?,
      createdAt: _t(m['createdAt']),
      timeline: [
        for (final e in (m['timeline'] as List?) ?? const [])
          if (e is Map && e['at'] is Timestamp) (status: '${e['status']}', at: (e['at'] as Timestamp).toDate()),
      ],
    );
  }

  bool get isOpen => status == 'pending' || status == 'processing';
}

class KycState {
  final String status; // none | requires_input | processing | verified | canceled
  final String? verifiedName;
  final String? country;
  final String? lastError;
  const KycState({this.status = 'none', this.verifiedName, this.country, this.lastError});

  factory KycState.fromMap(Map<String, dynamic>? m) => KycState(
        status: (m?['status'] as String?) ?? 'none',
        verifiedName: m?['verifiedName'] as String?,
        country: m?['country'] as String?,
        lastError: m?['lastError'] as String?,
      );

  bool get verified => status == 'verified';
}

class PayoutMethod {
  final String id;
  final String rail;
  final String provider;
  final String country;
  final String currency;
  final String label;
  final String last4;
  final String holderName;

  const PayoutMethod({
    required this.id,
    required this.rail,
    required this.provider,
    required this.country,
    required this.currency,
    required this.label,
    required this.last4,
    required this.holderName,
  });

  factory PayoutMethod.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    return PayoutMethod(
      id: d.id,
      rail: (m['rail'] as String?) ?? '',
      provider: (m['provider'] as String?) ?? '',
      country: (m['country'] as String?) ?? '',
      currency: (m['currency'] as String?) ?? 'USD',
      label: (m['label'] as String?) ?? '',
      last4: (m['last4'] as String?) ?? '',
      holderName: (m['holderName'] as String?) ?? '',
    );
  }
}

class RailOption {
  final String rail;
  final String provider;
  final String label;
  final List<({String id, String label})> networks;
  const RailOption({required this.rail, required this.provider, required this.label, this.networks = const []});
}

/// Result of `payoutOptions`: where the person is and how they can be paid.
class PayoutOptions {
  final String country;
  final String? countryName;
  final String source; // location | sim | phone | locale | id
  final bool africa;
  final String currency;
  final double? usdRate;
  final List<RailOption> rails;
  final double minUsd;
  final double maxUsd;
  final Map<String, String> fees;
  final String kycStatus;
  final bool stripeConnected;
  final bool stripePayoutsEnabled;

  const PayoutOptions({
    required this.country,
    this.countryName,
    required this.source,
    required this.africa,
    required this.currency,
    this.usdRate,
    required this.rails,
    required this.minUsd,
    required this.maxUsd,
    required this.fees,
    required this.kycStatus,
    required this.stripeConnected,
    required this.stripePayoutsEnabled,
  });

  factory PayoutOptions.fromMap(Map<String, dynamic> m) {
    final stripe = (m['stripe'] as Map?) ?? const {};
    return PayoutOptions(
      country: '${m['country']}',
      countryName: m['countryName'] as String?,
      source: '${m['source']}',
      africa: m['africa'] == true,
      currency: (m['currency'] as String?) ?? 'USD',
      usdRate: (m['usdRate'] as num?)?.toDouble(),
      rails: [
        for (final r in (m['rails'] as List?) ?? const [])
          RailOption(
            rail: '${r['rail']}',
            provider: '${r['provider']}',
            label: '${r['label']}',
            networks: [for (final n in (r['networks'] as List?) ?? const []) (id: '${n['id']}', label: '${n['label']}')],
          ),
      ],
      minUsd: _d(m['minUsd']) == 0 ? minWithdrawUsd : _d(m['minUsd']),
      maxUsd: _d(m['maxUsd']),
      fees: {for (final e in ((m['fees'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
      kycStatus: (m['kycStatus'] as String?) ?? 'none',
      stripeConnected: stripe['connected'] == true,
      stripePayoutsEnabled: stripe['payoutsEnabled'] == true,
    );
  }

  /// Fee for [usd] on [rail]; same formula as payoutFeeUsd on the server.
  static double feeFor(String rail, double usd) {
    final fee = switch (rail) {
      'mobile_money' => (usd * 0.015) < 0.2 ? 0.2 : usd * 0.015,
      'bank' => (usd * 0.01) < 0.5 ? 0.5 : usd * 0.01,
      _ => 0.25 + usd * 0.0025,
    };
    return (fee * 100).round() / 100;
  }
}

enum OneovaPlan { free, plus, pro, biz }

class PlanState {
  final OneovaPlan plan;
  final bool active;
  final bool autoRenewing;
  final String? basePlanId;
  final DateTime? expiresAt;
  const PlanState({this.plan = OneovaPlan.free, this.active = false, this.autoRenewing = false, this.basePlanId, this.expiresAt});

  factory PlanState.fromMap(Map<String, dynamic>? m) {
    final active = m?['active'] == true && (_t(m?['expiresAt'])?.isAfter(DateTime.now()) ?? false);
    return PlanState(
      plan: active ? OneovaPlan.values.firstWhere((p) => p.name == m?['plan'], orElse: () => OneovaPlan.free) : OneovaPlan.free,
      active: active,
      autoRenewing: m?['autoRenewing'] == true,
      basePlanId: m?['basePlanId'] as String?,
      expiresAt: _t(m?['expiresAt']),
    );
  }
}

/// One day of `creator_daily/{uid}/days/{date}`.
class DayStat {
  final DateTime date;
  final int views;
  final int plays;
  final int watchMs;
  final int completes;
  final int likes;
  final int comments;
  final int shares;
  final int followsGained;
  final int followsLost;
  final int giftDiamonds;

  const DayStat({
    required this.date,
    this.views = 0,
    this.plays = 0,
    this.watchMs = 0,
    this.completes = 0,
    this.likes = 0,
    this.comments = 0,
    this.shares = 0,
    this.followsGained = 0,
    this.followsLost = 0,
    this.giftDiamonds = 0,
  });

  factory DayStat.fromMap(DateTime date, Map<String, dynamic> m) => DayStat(
        date: date,
        views: _i(m['views']),
        plays: _i(m['plays']),
        watchMs: _i(m['watchMs']),
        completes: _i(m['completes']),
        likes: _i(m['likes']),
        comments: _i(m['comments']),
        shares: _i(m['shares']),
        followsGained: _i(m['followsGained']),
        followsLost: _i(m['followsLost']),
        giftDiamonds: _i(m['giftDiamonds']),
      );

  int get netFollows => followsGained - followsLost;
}

/// A clip with the numbers the insights screens use (`content/{id}`).
class ClipStat {
  final String id;
  final String caption;
  final String? thumbnailUrl;
  final DateTime createdAt;
  final int? durationMs;
  final int views;
  final int plays;
  final int watchMs;
  final int completes;
  final int likes;
  final int comments;
  final int shares;
  final int saves;
  final int giftDiamonds;

  const ClipStat({
    required this.id,
    required this.caption,
    this.thumbnailUrl,
    required this.createdAt,
    this.durationMs,
    this.views = 0,
    this.plays = 0,
    this.watchMs = 0,
    this.completes = 0,
    this.likes = 0,
    this.comments = 0,
    this.shares = 0,
    this.saves = 0,
    this.giftDiamonds = 0,
  });

  factory ClipStat.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    final media = (m['mediaMetadata'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ClipStat(
      id: d.id,
      caption: (m['description'] as String?) ?? '',
      thumbnailUrl: (media['thumbnailUrl'] ?? media['posterFrameUrl'] ?? m['thumbnailUrl']) as String?,
      createdAt: _t(m['createdAt']) ?? DateTime.now(),
      durationMs: (media['durationMs'] as num?)?.toInt(),
      views: _i(m['viewCount']),
      plays: _i(m['playCount']),
      watchMs: _i(m['watchTimeMs']),
      completes: _i(m['completionCount']),
      likes: _i(m['likeCount']),
      comments: _i(m['commentCount']),
      shares: _i(m['shareCount']),
      saves: _i(m['saveCount']),
      giftDiamonds: _i(m['giftDiamonds']),
    );
  }

  /// Share of plays watched to the end (0–1), or null before any plays.
  double? get completionRate => plays == 0 ? null : (completes / plays).clamp(0, 1).toDouble();
  double get avgWatchSec => plays == 0 ? 0 : watchMs / plays / 1000;
  int get engagements => likes + comments + shares + saves;
  double get engagementRate => views == 0 ? 0 : engagements / views;
}
