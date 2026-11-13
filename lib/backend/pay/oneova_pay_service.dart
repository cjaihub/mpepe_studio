import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One way to pay, as offered by the server for the payer's country
/// (`payMethods`). The app never decides which partner is used.
class PayMethod {
  final String id;
  final String rail; // mobile_money | card | bank | balance
  final String provider;
  final String kind; // prompt | hosted | instant
  final String label;
  final String? network;
  final bool needsPhone;
  final bool sandbox;

  const PayMethod({
    required this.id,
    required this.rail,
    required this.provider,
    required this.kind,
    required this.label,
    this.network,
    this.needsPhone = false,
    this.sandbox = false,
  });

  factory PayMethod.fromMap(Map m) => PayMethod(
        id: '${m['id']}',
        rail: '${m['rail']}',
        provider: '${m['provider']}',
        kind: '${m['kind']}',
        label: '${m['label']}',
        network: m['network'] as String?,
        needsPhone: m['needsPhone'] == true,
        sandbox: m['sandbox'] == true,
      );
}

class PayOptions {
  final String country;
  final String? countryName;
  final String currency;
  final String? dial;
  final List<PayMethod> methods;
  final bool sandbox;
  final bool walletEnabled;
  final int? balanceMinor;

  /// At least one licensed partner has keys (false = sandbox / not open yet).
  final bool live;

  const PayOptions({
    required this.country,
    this.countryName,
    required this.currency,
    this.dial,
    required this.methods,
    this.sandbox = false,
    this.walletEnabled = false,
    this.balanceMinor,
    this.live = false,
  });
}

/// A pay-in as the server reports it (`pay_intents/{id}`).
class PayIntent {
  final String id;
  final String status; // created | pending_payer | succeeded | failed | expired | cancelled | refunded | review
  final int amountMinor;
  final String currency;
  final String? redirectUrl;
  final String? failureReason;
  final String methodLabel;
  final String methodKind;
  final bool sandbox;

  const PayIntent({
    required this.id,
    required this.status,
    required this.amountMinor,
    required this.currency,
    this.redirectUrl,
    this.failureReason,
    this.methodLabel = '',
    this.methodKind = 'prompt',
    this.sandbox = false,
  });

  bool get isOpen => status == 'created' || status == 'pending_payer';
  bool get succeeded => status == 'succeeded';
  bool get failed => status == 'failed' || status == 'expired' || status == 'cancelled';

  factory PayIntent.fromMap(String id, Map m) {
    final method = (m['method'] as Map?) ?? const {};
    return PayIntent(
      id: id,
      status: '${m['status'] ?? 'created'}',
      amountMinor: (m['amountMinor'] as num?)?.toInt() ?? 0,
      currency: '${m['currency'] ?? ''}',
      redirectUrl: m['redirectUrl'] as String?,
      failureReason: m['failureReason'] as String?,
      methodLabel: '${method['label'] ?? ''}',
      methodKind: '${method['kind'] ?? 'prompt'}',
      sandbox: m['sandbox'] == true,
    );
  }
}

/// Balances per currency (minor units) and whether payouts can be received.
class PayoutStatus {
  final String kycStatus; // none | collecting | review | verified | rejected
  final int methods;
  final bool payoutsEnabled;
  /// Personal balance per currency (top-ups, deliveries, refunds).
  final Map<String, ({int available, int pending, int locked})> balances;

  /// Business balance per currency (shop sales, scan to pay).
  final Map<String, ({int available, int pending, int locked})> businessBalances;

  const PayoutStatus({
    this.kycStatus = 'none',
    this.methods = 0,
    this.payoutsEnabled = false,
    this.balances = const {},
    this.businessBalances = const {},
  });

  bool get verified => kycStatus == 'verified';
  bool get hasMethod => methods > 0;
}

/// The signed-in account's payment country and currency, as Oneova Pay
/// decides them on the server (payout profile → verified ID → profile).
/// One source of truth for shop prices, checkout and the wallet. Filled by
/// [OneovaPayService.options]; null until the first call.
class PayAccount {
  PayAccount._();
  static String? country;
  static String? currency;
}

/// "KES 1,250" / "USD 12.50" from a decimal amount, rounded like the server.
String formatMajor(num amount, String currency) => formatMinor((amount * (currencyExponent(currency) == 0 ? 1 : 100)).round(), currency);

/// Plain-language text for a payment error (never a raw code).
String payErrorText(Object e, {String fallback = 'Something went wrong. Please try again.'}) {
  final msg = (e as dynamic).message;
  final code = (e as dynamic).code;
  if (code is String) {
    switch (code) {
      case 'unavailable':
      case 'deadline-exceeded':
        return 'The payment partner is taking longer than usual. We’ll update you as soon as it answers.';
      case 'resource-exhausted':
        return 'Too many tries in a short time. Wait a few minutes and try again.';
      case 'unauthenticated':
        return 'Please sign in again to continue.';
      case 'internal':
        return fallback;
    }
  }
  return msg is String && msg.trim().isNotEmpty && !msg.contains('Exception') ? msg : fallback;
}

/// Digits per currency the way the server counts minor units.
int currencyExponent(String currency) => const {
      'UGX': 0, 'RWF': 0, 'XAF': 0, 'XOF': 0, 'BIF': 0, 'GNF': 0, 'KMF': 0, 'DJF': 0, 'JPY': 0, 'KRW': 0,
      'VND': 0, 'CLP': 0, 'PYG': 0,
    }[currency.toUpperCase()] ??
    2;

/// "KES 1,250" / "USD 12.50" from minor units.
String formatMinor(int minor, String currency) {
  final e = currencyExponent(currency);
  final major = minor / _pow10(e);
  final fixed = major.toStringAsFixed(major == major.roundToDouble() ? 0 : e);
  final parts = fixed.split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '${currency.toUpperCase()} $whole${parts.length > 1 ? '.${parts[1]}' : ''}';
}

int _pow10(int e) => e == 0 ? 1 : (e == 1 ? 10 : 100);

final oneovaPayServiceProvider = Provider<OneovaPayService>((ref) => OneovaPayService());

/// Oneova Pay on the app side (see functions/src/pay/). Prices, partners and
/// the ledger all live on the server; the app shows choices and status.
class OneovaPayService {
  final FirebaseFunctions _fn = FirebaseFunctions.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<Map<String, dynamic>> _call(String name, [Map<String, dynamic>? data]) async {
    final res = await _fn
        .httpsCallable(name, options: HttpsCallableOptions(timeout: const Duration(seconds: 60)))
        .call<Map<String, dynamic>>(data ?? const {});
    return Map<String, dynamic>.from(res.data);
  }

  Future<PayOptions> options({String? country}) async {
    final r = await _call('payMethods', {'country': ?country});
    if (country == null) {
      PayAccount.country = '${r['country']}';
      PayAccount.currency = '${r['currency']}';
    }
    return PayOptions(
      country: '${r['country']}',
      countryName: r['countryName'] as String?,
      currency: '${r['currency']}',
      dial: r['dial'] as String?,
      methods: [for (final m in (r['methods'] as List? ?? const [])) PayMethod.fromMap(m as Map)],
      sandbox: r['sandbox'] == true,
      walletEnabled: r['walletEnabled'] == true,
      balanceMinor: (r['balanceMinor'] as num?)?.toInt(),
      live: r['live'] == true,
    );
  }

  /// Starts a pay-in. [purpose] is `order` (refId = order id) or `topup`
  /// (with [amount] in major units of the payer's currency).
  Future<PayIntent> create({
    required String purpose,
    required String methodId,
    String? refId,
    String? msisdn,
    num? amount,
    String? country,
  }) async {
    final r = await _call('payCreate', {
      'purpose': purpose,
      'methodId': methodId,
      'refId': ?refId,
      'msisdn': ?msisdn,
      'amount': ?amount,
      'country': ?country,
    });
    return PayIntent.fromMap('${r['intentId']}', r);
  }

  // ── Scan to pay (functions/src/pay/merchantQr.ts) ──

  /// Who a scanned code pays and how much. Throws when it isn't payable.
  Future<MerchantCode> resolveQr(String scanned) async => MerchantCode.fromMap(await _call('payQrResolve', {'qr': scanned}));

  /// A code to receive money: a shop code ([amount] null) or a one-time code for [amount].
  Future<MerchantCode> createQr({num? amount, String? label}) async =>
      MerchantCode.fromMap(await _call('payQrCreate', {'amount': ?amount, 'label': ?label}));

  Future<List<MerchantCode>> myQrCodes() async {
    final r = await _call('payQrList');
    return [for (final c in (r['codes'] as List? ?? const [])) MerchantCode.fromMap(Map<String, dynamic>.from(c as Map))];
  }

  Future<void> disableQr(String code) => _call('payQrDisable', {'code': code});

  Future<PayIntent> status(String intentId) async {
    final r = await _call('payStatus', {'intentId': intentId});
    return PayIntent.fromMap(intentId, r);
  }

  Future<void> cancel(String intentId) => _call('payCancel', {'intentId': intentId});

  /// Live updates of one pay-in (owner-readable).
  Stream<PayIntent?> watch(String intentId) => _db
      .collection('pay_intents')
      .doc(intentId)
      .snapshots()
      .map((d) => d.data() == null ? null : PayIntent.fromMap(d.id, d.data()!));

  Future<PayoutStatus> payoutStatus() async {
    final r = await _call('payPayoutStatus');
    Map<String, ({int available, int pending, int locked})> read(Object? raw) {
      final out = <String, ({int available, int pending, int locked})>{};
      (raw as Map? ?? const {}).forEach((k, v) {
        final m = v as Map;
        out['$k'] = (
          available: (m['available'] as num?)?.toInt() ?? 0,
          pending: (m['pending'] as num?)?.toInt() ?? 0,
          locked: (m['locked'] as num?)?.toInt() ?? 0,
        );
      });
      return out;
    }

    return PayoutStatus(
      kycStatus: '${r['kycStatus'] ?? 'none'}',
      methods: (r['methods'] as num?)?.toInt() ?? 0,
      payoutsEnabled: r['payoutsEnabled'] == true,
      balances: read(r['balances']),
      businessBalances: read(r['businessBalances']),
    );
  }

  /// Sends [amountMinor] of the personal or business ([balance]) balance to a saved payout method.
  Future<Map<String, dynamic>> withdraw({
    required String methodId,
    required int amountMinor,
    required String currency,
    required String idempotencyKey,
    String balance = 'personal',
  }) =>
      _call('payWithdraw', {
        'methodId': methodId,
        'amountMinor': amountMinor,
        'currency': currency,
        'idempotencyKey': idempotencyKey,
        'balance': balance,
      });

  /// Moves money from the business balance to the personal one (instant).
  Future<void> moveToPersonal({required int amountMinor, required String currency, required String idempotencyKey}) =>
      _call('payMoveToPersonal', {'amountMinor': amountMinor, 'currency': currency, 'idempotencyKey': idempotencyKey});

  /// Live personal ('personal') or business ('business') balances: currency → (available, pending, locked).
  Stream<Map<String, ({int available, int pending, int locked})>> watchBalances(String kind) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(const {});
    return _db.doc('${kind == 'business' ? 'pay_business_balances' : 'pay_balances'}/$uid').snapshots().map((d) {
      final out = <String, ({int available, int pending, int locked})>{};
      (d.data() ?? const {}).forEach((k, v) {
        if (v is! Map || !RegExp(r'^[A-Z]{3}$').hasMatch(k)) return;
        out[k] = (
          available: (v['available'] as num?)?.toInt() ?? 0,
          pending: (v['pending'] as num?)?.toInt() ?? 0,
          locked: (v['locked'] as num?)?.toInt() ?? 0,
        );
      });
      return out;
    });
  }
}


/// A merchant's Oneova Pay code, as the server describes it.
class MerchantCode {
  final String code;
  final String qr;
  final String merchantUid;
  final String name;
  final String? avatarUrl;
  final bool verified;
  final String? label;
  final String country;
  final String currency;
  final int? amountMinor;
  final num? amount;
  final bool oneTime;
  final bool active;
  final int paidCount;
  final int receivedMinor;

  const MerchantCode({
    required this.code,
    required this.qr,
    required this.merchantUid,
    required this.name,
    this.avatarUrl,
    required this.verified,
    this.label,
    required this.country,
    required this.currency,
    this.amountMinor,
    this.amount,
    required this.oneTime,
    required this.active,
    this.paidCount = 0,
    this.receivedMinor = 0,
  });

  /// The merchant set the amount (one-time code); otherwise the payer types it.
  bool get fixedAmount => amountMinor != null;

  factory MerchantCode.fromMap(Map<String, dynamic> m) => MerchantCode(
        code: '${m['code']}',
        qr: '${m['qr'] ?? 'https://oneova.web.app/p/${m['code']}'}',
        merchantUid: '${m['merchantUid']}',
        name: '${m['name'] ?? 'Oneova merchant'}',
        avatarUrl: m['avatarUrl'] as String?,
        verified: m['verified'] == true,
        label: m['label'] as String?,
        country: '${m['country']}',
        currency: '${m['currency']}',
        amountMinor: (m['amountMinor'] as num?)?.toInt(),
        amount: m['amount'] as num?,
        oneTime: m['oneTime'] == true,
        active: m['active'] != false,
        paidCount: (m['paidCount'] as num?)?.toInt() ?? 0,
        receivedMinor: (m['receivedMinor'] as num?)?.toInt() ?? 0,
      );
}
