import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/wallet_models.dart';
import '../services/wallet_service.dart';
import 'looks_marketplace_controller.dart';

@immutable
class WalletState {
  final OneovaWallet wallet;
  final bool isProcessing;
  final String? errorMessage;
  final String? successMessage;

  const WalletState({
    required this.wallet,
    this.isProcessing = false,
    this.errorMessage,
    this.successMessage,
  });

  WalletState copyWith({
    OneovaWallet? wallet,
    bool? isProcessing,
    String? errorMessage,
    String? successMessage,
  }) {
    return WalletState(
      wallet: wallet ?? this.wallet,
      isProcessing: isProcessing ?? this.isProcessing,
      errorMessage: errorMessage,
      successMessage: successMessage,
    );
  }
}

class WalletController extends Notifier<WalletState> {
  late final WalletService _walletService;

  @override
  WalletState build() {
    _walletService = ref.read(walletServiceProvider);
    final initial = _walletService.getWallet('user_studio_pro');
    return WalletState(wallet: initial);
  }

  void refreshWallet(String userId) {
    final updated = _walletService.getWallet(userId);
    state = state.copyWith(wallet: updated);
  }

  Future<bool> withdrawEarnings({
    required String userId,
    required double amount,
    required PaymentProvider provider,
    required String destinationAccountOrPhone,
    required String accountHolderName,
    String currency = 'USD',
  }) async {
    state = state.copyWith(isProcessing: true, errorMessage: null, successMessage: null);

    try {
      await _walletService.withdrawEarnings(
        WithdrawalRequest(
          userId: userId,
          amount: amount,
          currency: currency,
          provider: provider,
          destinationAccountOrPhone: destinationAccountOrPhone,
          accountHolderName: accountHolderName,
        ),
      );

      final updated = _walletService.getWallet(userId);
      state = state.copyWith(
        wallet: updated,
        isProcessing: false,
        successMessage: 'Withdrawal of \$$amount to ${provider.label} submitted successfully!',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isProcessing: false,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
      return false;
    }
  }
}

final walletControllerProvider = NotifierProvider<WalletController, WalletState>(() {
  return WalletController();
});
