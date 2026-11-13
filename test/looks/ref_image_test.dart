import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/looks/filters/filter_reference_image.dart';

void main() {
  testWidgets('reference image draws', (tester) async {
    final img = await tester.runAsync(() => FilterReferenceImage.load());
    expect(img!.width, 240);
  });
}
