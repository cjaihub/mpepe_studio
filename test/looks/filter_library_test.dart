import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/looks/filters/oneova_filter_library.dart';
import 'package:oneova/looks/filters/oneova_presets.dart';

void main() {
  test('library has 1000+ unique, searchable filters', () {
    final all = OneovaFilterLibrary.all;
    expect(all.length, greaterThan(1000));
    expect(all.map((f) => f.id).toSet().length, all.length);
    expect(OneovaFilterLibrary.search('lagoon warm').map((f) => f.id), contains('ov_lagoon_warm'));
    expect(OneovaFilterLibrary.search('black and white'), isNotEmpty);
    final ink = OneovaFilterLibrary.search('ink');
    expect(ink.first.name, 'Ink');
    expect(ink.any((f) => f.base == 'Rosewater'), isFalse);
  });

  test('every built-in preset uses a real filter', () {
    for (final p in OneovaPresets.builtIns) {
      expect(OneovaFilterLibrary.byId(p.filterId), isNotNull, reason: p.id);
    }
  });
}
