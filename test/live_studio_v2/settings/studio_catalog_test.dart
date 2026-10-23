import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/settings/studio_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses ids and labels, falling back to the id', () {
    final c = parseStudioCatalog('{"studios":{"a":{"label":"A studio"},"b":{}}}');
    expect(c, const [
      StudioCatalogEntry(id: 'a', label: 'A studio'),
      StudioCatalogEntry(id: 'b', label: 'b'),
    ]);
  });

  test('malformed documents yield an empty list', () {
    expect(parseStudioCatalog('nope'), isEmpty);
    expect(parseStudioCatalog('[]'), isEmpty);
    expect(parseStudioCatalog('{"studios":3}'), isEmpty);
  });

  test('the bundled geometry asset lists the default studio', () async {
    final c = await AssetStudioCatalog().load();
    expect(c.map((e) => e.id), contains('broadcast_curved_wall'));
    expect(c.every((e) => e.label.isNotEmpty), isTrue);
  });
}
