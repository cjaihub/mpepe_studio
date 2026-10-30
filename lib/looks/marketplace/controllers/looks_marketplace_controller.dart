import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/looks_pack_models.dart';
import '../services/looks_pack_service.dart';
import '../services/wallet_service.dart';

@immutable
class LooksMarketplaceState {
  final List<OneovaLookPack> packs;
  final String? activeTag;
  final bool isLoading;
  final OneovaLookPack? selectedPack;
  final bool isPurchasing;
  final String? errorMessage;
  final String? successMessage;

  const LooksMarketplaceState({
    this.packs = const [],
    this.activeTag,
    this.isLoading = false,
    this.selectedPack,
    this.isPurchasing = false,
    this.errorMessage,
    this.successMessage,
  });

  LooksMarketplaceState copyWith({
    List<OneovaLookPack>? packs,
    String? Function()? activeTag,
    bool? isLoading,
    OneovaLookPack? Function()? selectedPack,
    bool? isPurchasing,
    String? errorMessage,
    String? successMessage,
  }) {
    return LooksMarketplaceState(
      packs: packs ?? this.packs,
      activeTag: activeTag != null ? activeTag() : this.activeTag,
      isLoading: isLoading ?? this.isLoading,
      selectedPack: selectedPack != null ? selectedPack() : this.selectedPack,
      isPurchasing: isPurchasing ?? this.isPurchasing,
      errorMessage: errorMessage,
      successMessage: successMessage,
    );
  }
}

final walletServiceProvider = Provider<WalletService>((ref) {
  return WalletService();
});

final looksPackServiceProvider = Provider<LooksPackService>((ref) {
  final wallet = ref.read(walletServiceProvider);
  return LooksPackService(walletService: wallet);
});

class LooksMarketplaceController extends Notifier<LooksMarketplaceState> {
  late final LooksPackService _packService;

  @override
  LooksMarketplaceState build() {
    _packService = ref.read(looksPackServiceProvider);
    return LooksMarketplaceState(
      packs: OneovaLookPack.starterPacks,
      isLoading: false,
    );
  }

  Future<void> _loadPacks([String? tag]) async {
    final search = tag ?? state.activeTag;
    final packs = await _packService.getMarketplacePacks(searchTag: search);
    state = state.copyWith(packs: packs, isLoading: false);
  }

  void selectTag(String? tag) {
    state = state.copyWith(activeTag: () => tag);
    _loadPacks(tag);
  }

  void selectPack(OneovaLookPack pack) {
    state = state.copyWith(selectedPack: () => pack);
  }

  Future<bool> purchasePack({
    required String userId,
    required String packId,
  }) async {
    state = state.copyWith(isPurchasing: true, errorMessage: null, successMessage: null);

    try {
      await _packService.purchasePackWithCoins(userId: userId, packId: packId);
      state = state.copyWith(
        isPurchasing: false,
        successMessage: 'Pack successfully unlocked! Added to your Looks Studio.',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isPurchasing: false,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
      return false;
    }
  }

  bool isPackUnlocked(String userId, String packId) {
    return _packService.hasUserUnlockedPack(userId, packId);
  }
}

final looksMarketplaceControllerProvider =
    NotifierProvider<LooksMarketplaceController, LooksMarketplaceState>(() {
  return LooksMarketplaceController();
});
