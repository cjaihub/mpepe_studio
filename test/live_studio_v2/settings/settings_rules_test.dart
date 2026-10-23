import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/backend/live_studio/settings/settings_rules.dart';

void main() {
  const dark = StudioSettings();

  test('keys match the contract wire shape', () {
    expect(StudioSettingsKeys.all.toSet(), dark.toJson().keys.toSet());
  });

  test('frameWidth rounds and clamps to 0–12', () {
    expect(clampFrameWidth(40), 12);
    expect(clampFrameWidth(-2), 0);
    expect(clampFrameWidth(6.6), 7);
  });

  test('studioDim clamps to 0–0.6 and snaps to 0.05', () {
    expect(clampStudioDim(2), 0.6);
    expect(clampStudioDim(-1), 0);
    expect(clampStudioDim(0.33), 0.35);
    expect(clampStudioDim(0.1 + 0.05), 0.15);
  });

  test('theme switch maps frame color by index', () {
    for (var i = 0; i < 4; i++) {
      final s = applySettingsPatch(
          dark.copyWith(frameColor: kFrameColorOptions[StudioTheme.dark]![i]), {'theme': 'light'});
      expect(s.theme, StudioTheme.light);
      expect(s.frameColor, kFrameColorOptions[StudioTheme.light]![i]);
    }
    expect(mapFrameColor('#000000', StudioTheme.dark, StudioTheme.light), '#3B4763');
  });

  test('explicit frame color validates against the resulting theme', () {
    expect(applySettingsPatch(dark, {'theme': 'light', 'frameColor': '#8c97ae'}).frameColor, '#8C97AE');
    expect(applySettingsPatch(dark, {'frameColor': '#123456'}).frameColor, dark.frameColor);
  });

  test('invalid enum values are ignored in the preview', () {
    final s = applySettingsPatch(dark, {
      'guestSize': 'xl',
      'speakerMode': 'auto',
      'theme': 'sepia',
      'showNames': 'no',
      'frameWidth': double.nan,
    });
    expect(s, dark);
  });

  test('every field applies', () {
    final s = applySettingsPatch(dark, {
      'studioId': 'x',
      'frameWidth': 9,
      'guestSize': 'l',
      'showNames': false,
      'studioDim': 0.4,
      'speakerMode': 'manual',
    });
    expect(s.studioId, 'x');
    expect(s.frameWidth, 9);
    expect(s.guestSize, GuestSize.l);
    expect(s.showNames, false);
    expect(s.studioDim, 0.4);
    expect(s.speakerMode, SpeakerMode.manual);
  });

  test('sanitizeSettings repairs a frame color from the wrong theme', () {
    final s = sanitizeSettings(StudioSettings.fromJson({'theme': 'light', 'frameColor': '#15151B'}));
    expect(s.frameColor, '#3B4763');
    expect(sanitizeSettings(dark.copyWith(frameColor: '#2f7bff')).frameColor, '#2F7BFF');
  });
}
