import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/looks/marketplace/controllers/looks_marketplace_controller.dart';
import 'package:oneova/looks/marketplace/controllers/wallet_controller.dart';
import 'package:oneova/looks/marketplace/models/looks_pack_models.dart';
import 'package:oneova/looks/marketplace/models/wallet_models.dart';
import 'package:oneova/looks/marketplace/services/looks_pack_service.dart';
import 'package:oneova/looks/marketplace/services/wallet_service.dart';
import 'package:oneova/looks/marketplace/ui/looks_catalog_screen.dart';
import 'package:oneova/looks/marketplace/ui/looks_pack_details_screen.dart';
import 'package:oneova/looks/marketplace/ui/oneova_wallet_screen.dart';
import 'package:oneova/looks/marketplace/widgets/buy_pack_dialog.dart';
import 'package:oneova/looks/models/oneova_look.dart';
import 'package:oneova/shared/theme/app_theme.dart';

Widget buildTestHost({
  required Widget child,
  Brightness brightness = Brightness.dark,
}) {
  return ProviderScope(
    child: MaterialApp(
      theme: ThemeData(
        brightness: brightness,
        scaffoldBackgroundColor:
            brightness == Brightness.dark ? AppColors.darkBackground : AppColors.lightBackground,
      ),
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OneovaLookPack Models & Packaging Tests', () {
    test('OneovaLookPack serializes to JSON and deserializes accurately', () {
      final pack = OneovaLookPack(
        id: 'pack_test_01',
        title: 'Cyberpunk Neon Nights',
        description: 'Futuristic sci-fi look pack',
        creatorId: 'creator_01',
        creatorName: 'Neon Director',
        creatorAvatarUrl: 'assets/avatar.jpg',
        priceCoins: 120,
        priceFiat: 3.99,
        previewVideoUrl: 'https://cdn.example.com/showcase.mp4',
        thumbnailUrl: 'assets/thumb.jpg',
        beforeAfterStills: const [
          BeforeAfterStillPair(
            beforeUrl: 'assets/b.jpg',
            afterUrl: 'assets/a.jpg',
            lookTitle: 'Neon Teal',
          ),
        ],
        looks: const [
          OneovaLook(id: 'look_test', name: 'Neon Teal', categories: ['Cinematic']),
        ],
        publishedAt: DateTime.now(),
      );

      final json = pack.toJson();
      expect(json['id'], 'pack_test_01');
      expect(json['price_coins'], 120);

      final deserialized = OneovaLookPack.fromJson(json);
      expect(deserialized.id, pack.id);
      expect(deserialized.beforeAfterStills.length, 1);
      expect(deserialized.beforeAfterStills.first.lookTitle, 'Neon Teal');
      expect(deserialized.looks.length, 1);
    });

    test('exportPackBundle packages looks into .oneovapack structure', () {
      final walletService = WalletService();
      final packService = LooksPackService(walletService: walletService);

      final bundle = packService.exportPackBundle(
        title: 'Anamorphic Flare Pack',
        description: 'Hollywood blue flares',
        creatorId: 'creator_dop',
        creatorName: 'DOP Mike',
        priceCoins: 80,
        priceFiat: 2.50,
        looks: const [
          OneovaLook(id: 'look_test', name: 'Neon Teal', categories: ['Cinematic']),
        ],
        stills: const [],
      );

      expect(bundle['format'], 'oneovapack_v1');
      expect(bundle['manifest'], isNotNull);
      expect((bundle['manifest'] as Map<String, dynamic>)['title'], 'Anamorphic Flare Pack');
    });
  });

  group('WalletService & Double-Entry Ledger Tests', () {
    late WalletService walletService;

    setUp(() {
      walletService = WalletService();
    });

    test('Initializes wallet with starting balance', () {
      final wallet = walletService.getWallet('user_test');
      expect(wallet.coinBalance, 100);
      expect(wallet.fiatBalance, 0.0);
    });

    test('topUpCoins adds coins and creates ledger entry for M-Pesa', () async {
      final entry = await walletService.topUpCoins(
        userId: 'user_test',
        coins: 500,
        fiatAmount: 9.99,
        provider: PaymentProvider.flutterwaveMpesa,
        currency: 'KES',
      );

      expect(entry.type, LedgerTransactionType.coinPurchase);
      expect(entry.coinsDelta, 500);

      final wallet = walletService.getWallet('user_test');
      expect(wallet.coinBalance, 600); // 100 + 500
      expect(wallet.transactions.length, 1);
    });

    test('deductCoins throws when balance is insufficient', () async {
      expect(
        () => walletService.deductCoins(
          userId: 'user_test',
          amountCoins: 9999,
          description: 'Buy premium look',
          referenceId: 'ref_fail',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('withdrawEarnings deducts fiat when KYC is verified and balance is sufficient', () async {
      final entry = await walletService.withdrawEarnings(
        const WithdrawalRequest(
          userId: 'user_studio_pro',
          amount: 15.0,
          currency: 'USD',
          provider: PaymentProvider.flutterwaveMpesa,
          destinationAccountOrPhone: '+254712345678',
          accountHolderName: 'Verified Creator',
        ),
      );

      expect(entry.type, LedgerTransactionType.withdrawal);
      expect(entry.fiatDelta, -15.0);

      final wallet = walletService.getWallet('user_studio_pro');
      expect(wallet.fiatBalance, 9.50); // 24.50 - 15.0
    });
  });

  group('LooksPackService Purchase & Entitlements Tests', () {
    late WalletService walletService;
    late LooksPackService packService;

    setUp(() {
      walletService = WalletService();
      packService = LooksPackService(walletService: walletService);
    });

    test('purchasePackWithCoins unlocks pack, deducts coins and credits creator', () async {
      final pack = OneovaLookPack.starterPacks.firstWhere((p) => p.priceCoins > 0);
      final initialBalance = walletService.getWallet('user_studio_pro').coinBalance;

      final entitlement = await packService.purchasePackWithCoins(
        userId: 'user_studio_pro',
        packId: pack.id,
      );

      expect(entitlement.packId, pack.id);
      expect(packService.hasUserUnlockedPack('user_studio_pro', pack.id), isTrue);

      final updatedBalance = walletService.getWallet('user_studio_pro').coinBalance;
      expect(updatedBalance, initialBalance - pack.priceCoins);
    });

    test('purchasePackWithCoins throws when pack is already unlocked', () async {
      final pack = OneovaLookPack.starterPacks.firstWhere((p) => p.priceCoins > 0);

      await packService.purchasePackWithCoins(userId: 'user_studio_pro', packId: pack.id);

      expect(
        () => packService.purchasePackWithCoins(userId: 'user_studio_pro', packId: pack.id),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('Marketplace & Wallet UI Widget Tests', () {
    testWidgets('BuyPackDialog renders pack info and price', (tester) async {
      final pack = OneovaLookPack.starterPacks.first;

      await tester.pumpWidget(
        buildTestHost(
          child: Scaffold(
            body: BuyPackDialog(pack: pack),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Unlock Look Pack'), findsOneWidget);
      expect(find.text(pack.title), findsOneWidget);
      expect(find.text('Pack Price:'), findsOneWidget);
    });

    testWidgets('LooksPackDetailsScreen renders showcase video and included looks', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final pack = OneovaLookPack.starterPacks.first;

      await tester.pumpWidget(
        buildTestHost(
          child: LooksPackDetailsScreen(pack: pack),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(pack.title), findsNWidgets(2)); // app bar and header
      expect(find.text('SHOWCASE'), findsOneWidget);
      expect(find.text('Play Showcase Video'), findsOneWidget);
      expect(find.text('Included Pro Looks (${pack.looks.length})'), findsOneWidget);
    });

    testWidgets('OneovaWalletScreen renders balance card and transaction ledger', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestHost(
          child: const OneovaWalletScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Oneova Wallet & Coins'), findsOneWidget);
      expect(find.text('KYC Verified'), findsOneWidget);
      expect(find.text('Total Creator Balance'), findsOneWidget);
      expect(find.text('500 Coins'), findsOneWidget);
      expect(find.text('Top Up Coins'), findsOneWidget);
      expect(find.text('Withdraw'), findsOneWidget);
      expect(find.text('Ledger Transactions'), findsOneWidget);
    });

    testWidgets('LooksCatalogScreen renders categories, search, and looks grid', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestHost(
          child: const LooksCatalogScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('100+ Looks & Marketplace'), findsOneWidget);
      expect(find.text('Cinematic'), findsAtLeastNWidgets(1));
      expect(find.text('Film Stocks'), findsAtLeastNWidgets(1));
      expect(find.text('Clean Commercial'), findsAtLeastNWidgets(1));
      expect(find.text('Biz Marketplace Look Packs'), findsOneWidget);
      expect(find.text('View Pack →'), findsOneWidget);
    });
  });
}
