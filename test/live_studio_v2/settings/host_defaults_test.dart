import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/backend/live_studio/settings/studio_settings_controller.dart';

void main() {
  late FakeFirebaseFirestore db;
  late ProviderContainer c;

  setUp(() {
    db = FakeFirebaseFirestore();
    c = ProviderContainer(overrides: [
      hostSettingsStoreProvider.overrideWithValue(FirestoreHostSettingsStore(db)),
    ]);
  });
  tearDown(() => c.dispose());

  test('no saved doc → contract defaults', () async {
    expect(await c.read(hostDefaultsProvider('h1').future), const StudioSettings());
  });

  test('round-trips the saved doc at users/{uid}/live_studio/settings', () async {
    final saved = const StudioSettings(
      theme: StudioTheme.light,
      frameColor: '#8C97AE',
      frameWidth: 9,
      guestSize: GuestSize.l,
      showNames: false,
      studioDim: 0.3,
      speakerMode: SpeakerMode.manual,
    );
    await db.doc(StudioPaths.hostSettings('h1')).set({...saved.toJson(), 'updatedAt': 1});
    expect(await c.read(hostDefaultsProvider('h1').future), saved);
  });

  test('bad stored values are clamped and repaired', () async {
    await db.doc(StudioPaths.hostSettings('h2')).set(
        {'theme': 'light', 'frameColor': '#15151B', 'frameWidth': 50, 'studioDim': 3});
    final s = await c.read(hostDefaultsProvider('h2').future);
    expect(s.frameColor, '#3B4763');
    expect(s.frameWidth, 12);
    expect(s.studioDim, 0.6);
  });
}
