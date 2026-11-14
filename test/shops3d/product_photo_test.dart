import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:oneova/shops3d/data/product_photo.dart';

img.Image _cut(int w, int h, bool Function(int x, int y) solid) {
  final image = img.Image(width: w, height: h, numChannels: 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      image.setPixelRgba(x, y, 200, 120, 40, solid(x, y) ? 255 : 0);
    }
  }
  return image;
}

void main() {
  test('a product in the middle of the photo is a usable cut-out', () {
    expect(cutoutCoverageOk(_cut(200, 200, (x, y) => x > 50 && x < 150 && y > 40 && y < 170)), isTrue);
  });

  test('an empty mask (nothing found) is rejected', () {
    expect(cutoutCoverageOk(_cut(200, 200, (_, _) => false)), isFalse);
  });

  test('a mask that kept the whole photo is rejected', () {
    expect(cutoutCoverageOk(_cut(200, 200, (_, _) => true)), isFalse);
  });
}
