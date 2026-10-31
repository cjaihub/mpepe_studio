import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/money/insights_logic.dart';
import 'package:oneova/backend/money/money_models.dart';
import 'package:oneova/backend/money/money_service.dart';
import 'package:oneova/looks/marketplace/ui/oneova_wallet_screen.dart';

ClipStat clip(String id, {int views = 0, int? durationMs, DateTime? at, int plays = 0, int completes = 0, int shares = 0}) => ClipStat(
      id: id,
      caption: 'clip $id',
      createdAt: at ?? DateTime(2026, 10, 1, 20),
      durationMs: durationMs,
      views: views,
      plays: plays,
      completes: completes,
      shares: shares,
    );

void main() {
  group('insights wording', () {
    test('short clips tip names the multiple', () {
      final clips = [
        clip('a', views: 400, durationMs: 12000),
        clip('b', views: 380, durationMs: 15000),
        clip('c', views: 100, durationMs: 45000),
        clip('d', views: 90, durationMs: 50000),
      ];
      final tips = creatorTips(clips, now: DateTime(2026, 10, 3));
      expect(tips.first, 'Your clips under 20s get 4.1x more views. Make more of them.');
    });

    test('no tip when groups are close', () {
      final clips = [
        clip('a', views: 100, durationMs: 12000),
        clip('b', views: 100, durationMs: 15000),
        clip('c', views: 95, durationMs: 45000),
        clip('d', views: 90, durationMs: 50000),
      ];
      expect(creatorTips(clips, now: DateTime(2026, 10, 3)).where((t) => t.contains('under 20s')), isEmpty);
    });

    test('headline cheers growth', () {
      final h = headline(const PeriodTotals(views: 150), const PeriodTotals(views: 100), 7);
      expect(h.title, "You're growing! 🚀");
      expect(h.body, contains('50%'));
    });

    test('empty creator gets a starting line', () {
      expect(headline(const PeriodTotals(), const PeriodTotals(), 28).title, 'Your story starts here');
    });

    test('milestones and earnings cheer', () {
      expect(nextMilestone(312), 500);
      expect(earningsCheer(const CreatorWallet(availableDiamonds: 300, pendingDiamonds: 200)), contains('on the way'));
      expect(earningsCheer(const CreatorWallet(availableDiamonds: 2000)), contains('withdraw'));
    });

    test('fee matches the server', () {
      expect(PayoutOptions.feeFor('mobile_money', 10), 0.2);
      expect(PayoutOptions.feeFor('stripe', 100), 0.5);
    });
  });

  testWidgets('wallet shows coins and Diamonds from the wallet doc', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        creatorWalletProvider.overrideWith((ref) => Stream.value(const CreatorWallet(coins: 720, availableDiamonds: 1500, pendingDiamonds: 300))),
        planStateProvider.overrideWith((ref) => Stream.value(const PlanState())),
        withdrawalsProvider.overrideWith((ref) => Stream.value(const <Withdrawal>[])),
        walletLedgerProvider.overrideWith((ref) => Stream.value(const <LedgerItem>[])),
      ],
      child: const MaterialApp(home: OneovaWalletScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Wallet'), findsOneWidget);
    expect(find.text(r'$15.00'), findsOneWidget);
    expect(find.text('720 coins'), findsOneWidget);
    expect(find.text('Withdraw'), findsOneWidget);
  });
}
