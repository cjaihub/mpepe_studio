import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/shops3d/data/shop3d_repository.dart';
import 'package:oneova/shops3d/models/shop_models.dart';
import 'package:oneova/shops3d/widgets/shop_stage_view.dart';

class _NoAuth extends Fake implements FirebaseAuth {
  @override
  User? get currentUser => null;
}

class _NoStorage extends Fake implements FirebaseStorage {}

Future<void> _pump(WidgetTester tester, {required Brightness brightness, ShopLive? live}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  const shop = Shop3D(id: 'u1', ownerId: 'u1', name: 'Kiko Sneakers', tagline: 'Handmade in Nairobi');
  const product = ShopProduct(id: 'p1', ownerId: 'u1', name: 'Runner', price: 80);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      shop3dRepositoryProvider.overrideWithValue(
        Shop3DRepository(db: FakeFirebaseFirestore(), storage: _NoStorage(), auth: _NoAuth()),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: ShopStageView(shop: shop, live: live, active: false, preview: true, productsOverride: const [product], onClose: () {}),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('the stage sits in a 25 px frame under a what\'s-on header', (tester) async {
    await _pump(tester, brightness: Brightness.dark);
    expect(find.byType(StageFrame), findsOneWidget);
    expect(find.byType(StageFrameBackdrop), findsOneWidget);
    expect(find.text('Handmade in Nairobi'), findsOneWidget);
    expect(find.text('Kiko Sneakers'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    // The header sits above the frame.
    final header = tester.getRect(find.text('Handmade in Nairobi'));
    final frame = tester.getRect(find.byType(StageFrame));
    expect(header.bottom, lessThan(frame.top));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a live shows its title, the LIVE badge and viewers at the top', (tester) async {
    await _pump(
      tester,
      brightness: Brightness.light,
      live: const ShopLive(streamId: 's1', title: 'Friday sneaker drop', viewerCount: 1250),
    );
    expect(find.text('Friday sneaker drop'), findsWidgets);
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('1.3K'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
