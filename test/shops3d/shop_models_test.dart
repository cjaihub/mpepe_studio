import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/shops3d/models/shop_models.dart';

void main() {
  ShopProduct product({
    num price = 80,
    num? compareAt,
    int? stock,
    bool inStock = true,
    bool active = true,
    String imageUrl = '',
    List<String> images = const [],
    String? model,
    List<ProductVariant> variants = const [],
  }) =>
      ShopProduct(
        id: 'p1',
        ownerId: 'u1',
        name: 'Runner',
        price: price,
        compareAtPrice: compareAt,
        stock: stock,
        inStock: inStock,
        active: active,
        imageUrl: imageUrl,
        imageUrls: images,
        model3dUrl: model,
        variants: variants,
      );

  group('ShopProduct', () {
    test('discount only when compare-at is higher than the price', () {
      expect(product(price: 80, compareAt: 100).discountPercent, 20);
      expect(product(price: 100, compareAt: 100).discountPercent, isNull);
      expect(product(price: 100, compareAt: 90).discountPercent, isNull);
      expect(product(price: 100).discountPercent, isNull);
    });

    test('gallery puts the cover first, drops duplicates and non-http links', () {
      final p = product(imageUrl: 'https://a/1.jpg', images: ['https://a/1.jpg', 'file:///x.jpg', 'https://a/2.jpg']);
      expect(p.gallery, ['https://a/1.jpg', 'https://a/2.jpg']);
    });

    test('only https models count as 3D', () {
      expect(product(model: 'https://cdn/x.glb').has3d, isTrue);
      expect(product(model: 'http://cdn/x.glb').has3d, isFalse);
      expect(product().has3d, isFalse);
    });

    test('sold out and sellable', () {
      expect(product(stock: 0).soldOut, isTrue);
      expect(product(inStock: false).soldOut, isTrue);
      expect(product(stock: 3).sellable, isTrue);
      expect(product(price: 0).sellable, isFalse);
      expect(product(active: false).sellable, isFalse);
    });
  });

  group('ProductVariant', () {
    test('parses swatch colours and ignores bad hex', () {
      expect(const ProductVariant(id: 'a', name: 'Blue', colorHex: '#0C4FA8').swatch?.toARGB32(), 0xFF0C4FA8);
      expect(const ProductVariant(id: 'a', name: 'Bad', colorHex: '#12').swatch, isNull);
      expect(const ProductVariant(id: 'a', name: 'None').swatch, isNull);
    });

    test('round-trips through a map without empty fields', () {
      const v = ProductVariant(id: 'blue-1a2b', name: 'Blue', colorHex: '#0C4FA8', stock: 4, modelVariant: '');
      final m = v.toMap();
      expect(m.containsKey('modelVariant'), isFalse);
      final back = ProductVariant.fromMap(m);
      expect(back.id, 'blue-1a2b');
      expect(back.stock, 4);
      expect(const ProductVariant(id: 'x', name: 'x', stock: 0).soldOut, isTrue);
    });
  });

  group('StageConfig', () {
    test('unknown values fall back to defaults', () {
      final s = StageConfig.fromMap({'backdrop': 'neon', 'accent': 'red', 'card': 'top'});
      expect(s.backdrop, StageBackdrop.studio);
      expect(s.accent, StageAccent.blue);
      expect(s.card, CardPlacement.right);
      expect(s.autoRotate, isTrue);
    });

    test('round-trips', () {
      const s = StageConfig(backdrop: StageBackdrop.midnight, accent: StageAccent.pink, card: CardPlacement.left, autoRotate: false);
      final back = StageConfig.fromMap(s.toMap());
      expect(back.backdrop, StageBackdrop.midnight);
      expect(back.accent, StageAccent.pink);
      expect(back.card, CardPlacement.left);
      expect(back.autoRotate, isFalse);
    });
  });
}
