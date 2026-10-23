import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/feed/widgets/circle_gesture_detector.dart';

List<Offset> arc(double fromDeg, double toDeg, {double r = 90, Offset c = const Offset(200, 400), int n = 40, double sx = 1}) {
  return List.generate(n, (i) {
    final a = (fromDeg + (toDeg - fromDeg) * i / (n - 1)) * math.pi / 180;
    return c + Offset(math.cos(a) * r * sx, math.sin(a) * r);
  });
}

void main() {
  test('closed round loop is a circle (either direction)', () {
    expect(OneovaCircleGesture.isCircle(arc(0, 350)), isTrue);
    expect(OneovaCircleGesture.isCircle(arc(0, -350)), isTrue);
  });

  test('slightly oval loop still counts', () {
    expect(OneovaCircleGesture.isCircle(arc(30, 400, sx: 1.4)), isTrue);
  });

  test('vertical swipe, half circle and tiny loop do not count', () {
    final swipe = List.generate(30, (i) => Offset(200, 900 - i * 25.0));
    expect(OneovaCircleGesture.isCircle(swipe), isFalse);
    expect(OneovaCircleGesture.isCircle(arc(0, 180)), isFalse);
    expect(OneovaCircleGesture.isCircle(arc(0, 350, r: 15)), isFalse);
  });

  test('open spiral that does not close is rejected', () {
    final pts = arc(0, 340);
    expect(OneovaCircleGesture.isCircle([...pts.take(30)]), isFalse);
  });
}
