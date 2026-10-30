import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/backend/live_studio/media/studio_media_api.dart';
import 'package:oneova/backend/live_studio/settings/settings_rules.dart';

import '../session/fakes/fake_studio.dart';

void main() {
  test('start sends kind gaming and the trimmed game title', () async {
    final call = FakeCallPort()
      ..on(StudioCallables.start, (_) => {'streamId': 's1', 'token': 't', 'url': 'wss://x'});
    final api = StudioMediaApi(call);
    final r = await api.start('My run', gaming: true, gameTitle: '  Free Fire ');
    expect(r.streamId, 's1');
    expect(call.calls.single.$2, {'title': 'My run', 'kind': 'gaming', 'gameTitle': 'Free Fire'});
  });

  test('studio start sends no gaming fields; empty title is omitted', () async {
    final call = FakeCallPort();
    final api = StudioMediaApi(call);
    await api.start('Show');
    await api.start('Game', gaming: true, gameTitle: '   ');
    expect(call.calls[0].$2, {'title': 'Show'});
    expect(call.calls[1].$2, {'title': 'Game', 'kind': 'gaming'});
  });

  test('settings rules accept layoutPreset and ignore unknown presets', () {
    const base = StudioSettings();
    expect(applySettingsPatch(base, {'layoutPreset': 'gaming'}).layoutPreset, LayoutPreset.gaming);
    expect(applySettingsPatch(base, {'layoutPreset': 'arena'}).layoutPreset, LayoutPreset.studio);
    expect(StudioSettingsKeys.all, contains('layoutPreset'));
  });
}
