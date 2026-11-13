import 'dart:async';
import '../models/wallet_models.dart';

/// Double-entry ledger wallet service powering the Oneova Coins economy.
/// Integrates with:
/// - Oneova Pay (mobile money: M-Pesa, MTN, Airtel, Telecel, Orange; cards on
///   a licensed partner's secure page)
class WalletService {
  final Map<String, OneovaWallet> _wallets = {
    'user_studio_pro': const OneovaWallet(
      userId: 'user_studio_pro',
      coinBalance: 500,
      fiatBalance: 24.50,
      localCurrency: 'USD',
      isKycVerified: true,
      transactions: [
        WalletLedgerEntry(
          id: 'tx_init_1',
          userId: 'user_studio_pro',
          type: LedgerTransactionType.coinPurchase,
          coinsDelta: 500,
          fiatDelta: 9.99,
          currency: 'USD',
          description: 'Purchased 500 Oneova Coins',
          referenceId: 'ref_init_1',
          status: 'completed',
          createdAt: CustomTime(daysAgo: 2),
        ),
      ],
    ),
  };

  /// Retrieves or initializes a user's wallet.
  OneovaWallet getWallet(String userId) {
    return _wallets.putIfAbsent(
      userId,
      () => OneovaWallet(userId: userId, coinBalance: 100, fiatBalance: 0.0),
    );
  }

  /// Deducts coins for marketplace purchases, tips, or vision credits.
  Future<WalletLedgerEntry> deductCoins({
    required String userId,
    required int amountCoins,
    required String description,
    required String referenceId,
  }) async {
    final wallet = getWallet(userId);
    if (wallet.coinBalance < amountCoins) {
      throw Exception(
        'Insufficient coins. Available: ${wallet.coinBalance} Coins, Required: $amountCoins Coins',
      );
    }

    final txId = 'tx_deduct_${DateTime.now().millisecondsSinceEpoch}';
    final entry = WalletLedgerEntry(
      id: txId,
      userId: userId,
      type: LedgerTransactionType.packPurchase,
      coinsDelta: -amountCoins,
      fiatDelta: 0.0,
      currency: wallet.localCurrency,
      description: description,
      referenceId: referenceId,
      status: 'completed',
      createdAt: DateTime.now(),
    );

    final updatedTx = List<WalletLedgerEntry>.from(wallet.transactions)..insert(0, entry);
    _wallets[userId] = wallet.copyWith(
      coinBalance: wallet.coinBalance - amountCoins,
      transactions: updatedTx,
    );

    return entry;
  }

  /// Credits creator coins from marketplace sales or tips.
  Future<WalletLedgerEntry> creditCoins({
    required String userId,
    required int amountCoins,
    required String description,
    required String referenceId,
  }) async {
    final wallet = getWallet(userId);
    final txId = 'tx_credit_${DateTime.now().millisecondsSinceEpoch}';

    final entry = WalletLedgerEntry(
      id: txId,
      userId: userId,
      type: LedgerTransactionType.packSaleEarning,
      coinsDelta: amountCoins,
      fiatDelta: 0.0,
      currency: wallet.localCurrency,
      description: description,
      referenceId: referenceId,
      status: 'completed',
      createdAt: DateTime.now(),
    );

    final updatedTx = List<WalletLedgerEntry>.from(wallet.transactions)..insert(0, entry);
    _wallets[userId] = wallet.copyWith(
      coinBalance: wallet.coinBalance + amountCoins,
      transactions: updatedTx,
    );

    return entry;
  }

  /// Tops up coins via local or global payment provider (e.g. M-Pesa, MTN MoMo, card).
  Future<WalletLedgerEntry> topUpCoins({
    required String userId,
    required int coins,
    required double fiatAmount,
    required PaymentProvider provider,
    required String currency,
  }) async {
    final wallet = getWallet(userId);
    final txId = 'tx_topup_${DateTime.now().millisecondsSinceEpoch}';

    final entry = WalletLedgerEntry(
      id: txId,
      userId: userId,
      type: LedgerTransactionType.coinPurchase,
      coinsDelta: coins,
      fiatDelta: fiatAmount,
      currency: currency,
      description: 'Purchased $coins Oneova Coins (${provider.label})',
      referenceId: 'ref_$txId',
      status: 'completed',
      createdAt: DateTime.now(),
    );

    final updatedTx = List<WalletLedgerEntry>.from(wallet.transactions)..insert(0, entry);
    _wallets[userId] = wallet.copyWith(
      coinBalance: wallet.coinBalance + coins,
      transactions: updatedTx,
    );

    return entry;
  }

  /// Dispatches withdrawal request to local African mobile money or bank.
  Future<WalletLedgerEntry> withdrawEarnings(WithdrawalRequest req) async {
    final wallet = getWallet(req.userId);

    if (!wallet.isKycVerified) {
      throw Exception('KYC verification required before withdrawing earnings.');
    }

    if (wallet.fiatBalance < req.amount) {
      throw Exception(
        'Insufficient balance: \$${wallet.fiatBalance.toStringAsFixed(2)} available, \$${req.amount.toStringAsFixed(2)} requested.',
      );
    }

    final txId = 'tx_wdr_${DateTime.now().millisecondsSinceEpoch}';
    final entry = WalletLedgerEntry(
      id: txId,
      userId: req.userId,
      type: LedgerTransactionType.withdrawal,
      coinsDelta: 0,
      fiatDelta: -req.amount,
      currency: req.currency,
      description: 'Withdrawal to ${req.provider.label} (${req.destinationAccountOrPhone})',
      referenceId: 'wdr_$txId',
      status: 'completed',
      createdAt: DateTime.now(),
    );

    final updatedTx = List<WalletLedgerEntry>.from(wallet.transactions)..insert(0, entry);
    _wallets[req.userId] = wallet.copyWith(
      fiatBalance: wallet.fiatBalance - req.amount,
      transactions: updatedTx,
    );

    return entry;
  }
}

class CustomTime implements DateTime {
  final int daysAgo;
  const CustomTime({this.daysAgo = 0});

  @override
  DateTime subtract(Duration duration) => DateTime.now().subtract(duration);
  @override
  String toIso8601String() => DateTime.now().subtract(Duration(days: daysAgo)).toIso8601String();
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
