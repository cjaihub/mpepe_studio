import 'package:flutter/foundation.dart';

/// Supported payment providers across global card networks and African mobile money.
enum PaymentProvider {
  flutterwaveMpesa('M-Pesa (Kenya/Tanzania)', '🇰🇪 🇹🇿', 'mobile_money'),
  flutterwaveMtn('MTN Mobile Money (Uganda/Ghana/Nigeria)', '🇺🇬 🇬🇭 🇳🇬', 'mobile_money'),
  flutterwaveAirtel('Airtel Money (Kenya/Uganda/Nigeria)', '🇰🇪 🇺🇬 🇳🇬', 'mobile_money'),
  flutterwaveVodafone('Telecel / Vodafone Cash (Ghana)', '🇬🇭', 'mobile_money'),
  flutterwaveOrange('Orange Money (Francophone Africa)', '🇨🇲 🇸🇳 🇨🇮', 'mobile_money'),
  stripeCard('Global Credit / Debit Card', '💳', 'card'),
  stripeApplePay('Apple Pay', '', 'digital_wallet'),
  stripeGooglePay('Google Pay', 'G', 'digital_wallet');

  final String label;
  final String icon;
  final String category;
  const PaymentProvider(this.label, this.icon, this.category);

  bool get isMobileMoney => category == 'mobile_money';
}

/// Double-entry ledger transaction types for the Oneova Coins economy.
enum LedgerTransactionType {
  deposit('Deposit Funds', true),
  withdrawal('Withdrawal to Provider', false),
  coinPurchase('Coins Purchase', true),
  packPurchase('Look Pack Purchase', false),
  packSaleEarning('Marketplace Sale Payout', true),
  creatorTip('Live Creator Tip', false),
  cloudVisionCredit('Cloud Vision GPU Credits', false);

  final String label;
  final bool isCredit;
  const LedgerTransactionType(this.label, this.isCredit);
}

/// Individual immutable double-entry ledger entry.
@immutable
class WalletLedgerEntry {
  final String id;
  final String userId;
  final LedgerTransactionType type;
  final int coinsDelta;
  final double fiatDelta;
  final String currency;
  final String description;
  final String referenceId;
  final String status; // 'completed' | 'pending' | 'failed'
  final DateTime createdAt;

  const WalletLedgerEntry({
    required this.id,
    required this.userId,
    required this.type,
    required this.coinsDelta,
    required this.fiatDelta,
    this.currency = 'USD',
    required this.description,
    required this.referenceId,
    this.status = 'completed',
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'type': type.name,
        'coins_delta': coinsDelta,
        'fiat_delta': fiatDelta,
        'currency': currency,
        'description': description,
        'reference_id': referenceId,
        'status': status,
        'created_at': createdAt.toIso8601String(),
      };

  factory WalletLedgerEntry.fromJson(Map<String, dynamic> json) {
    return WalletLedgerEntry(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      type: LedgerTransactionType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => LedgerTransactionType.coinPurchase,
      ),
      coinsDelta: (json['coins_delta'] as num?)?.toInt() ?? 0,
      fiatDelta: (json['fiat_delta'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'USD',
      description: json['description'] as String? ?? '',
      referenceId: json['reference_id'] as String? ?? '',
      status: json['status'] as String? ?? 'completed',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }
}

/// User's real-time wallet account state.
@immutable
class OneovaWallet {
  final String userId;
  final int coinBalance;
  final double fiatBalance;
  final String localCurrency;
  final bool isKycVerified;
  final List<WalletLedgerEntry> transactions;

  const OneovaWallet({
    required this.userId,
    this.coinBalance = 250,
    this.fiatBalance = 7.50,
    this.localCurrency = 'USD',
    this.isKycVerified = true,
    this.transactions = const [],
  });

  OneovaWallet copyWith({
    String? userId,
    int? coinBalance,
    double? fiatBalance,
    String? localCurrency,
    bool? isKycVerified,
    List<WalletLedgerEntry>? transactions,
  }) {
    return OneovaWallet(
      userId: userId ?? this.userId,
      coinBalance: coinBalance ?? this.coinBalance,
      fiatBalance: fiatBalance ?? this.fiatBalance,
      localCurrency: localCurrency ?? this.localCurrency,
      isKycVerified: isKycVerified ?? this.isKycVerified,
      transactions: transactions ?? this.transactions,
    );
  }
}

/// Request to withdraw earnings to mobile money or bank account.
@immutable
class WithdrawalRequest {
  final String userId;
  final double amount;
  final String currency;
  final PaymentProvider provider;
  final String destinationAccountOrPhone;
  final String accountHolderName;

  const WithdrawalRequest({
    required this.userId,
    required this.amount,
    required this.currency,
    required this.provider,
    required this.destinationAccountOrPhone,
    required this.accountHolderName,
  });
}
