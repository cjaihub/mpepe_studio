import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/looks/camera/services/camera_voice_command_parser.dart';

void main() {
  group('CameraVoiceCommandParser Tests', () {
    const parser = CameraVoiceCommandParser();

    test('Photo capture commands parsed with or without timer', () {
      final snapNow = parser.parse('take a picture');
      expect(snapNow, isA<CapturePhotoIntent>());
      expect((snapNow as CapturePhotoIntent).timerSeconds, 0);

      final snapTimer = parser.parse('snap photo in 3 seconds');
      expect(snapTimer, isA<CapturePhotoIntent>());
      expect((snapTimer as CapturePhotoIntent).timerSeconds, 3);

      final cheese = parser.parse('cheese');
      expect(cheese, isA<CapturePhotoIntent>());

      final selfie = parser.parse('take selfie');
      expect(selfie, isA<CapturePhotoIntent>());
    });

    test('Video recording start and stop commands parsed', () {
      final start = parser.parse('start recording');
      expect(start, isA<StartRecordingIntent>());

      final shoot = parser.parse('shoot video');
      expect(shoot, isA<StartRecordingIntent>());

      final stop = parser.parse('stop recording');
      expect(stop, isA<StopRecordingIntent>());

      final cut = parser.parse('cut');
      expect(cut, isA<StopRecordingIntent>());
    });

    test('Switch camera commands parsed accurately', () {
      final front = parser.parse('switch to front camera');
      expect(front, isA<SwitchCameraIntent>());
      expect((front as SwitchCameraIntent).front, true);

      final back = parser.parse('switch to rear camera');
      expect(back, isA<SwitchCameraIntent>());
      expect((back as SwitchCameraIntent).front, false);

      final toggle = parser.parse('flip camera');
      expect(toggle, isA<SwitchCameraIntent>());
      expect((toggle as SwitchCameraIntent).front, isNull);
    });

    test('Smart lock toggle commands parsed', () {
      final lock = parser.parse('lock exposure');
      expect(lock, isA<ToggleSmartLockIntent>());
      expect((lock as ToggleSmartLockIntent).enable, true);

      final unlock = parser.parse('unlock focus');
      expect(unlock, isA<ToggleSmartLockIntent>());
      expect((unlock as ToggleSmartLockIntent).enable, false);
    });

    test('Boost Beauty intensity adjustments parsed', () {
      final beauty80 = parser.parse('set beauty to 80%');
      expect(beauty80, isA<SetBeautyIntent>());
      expect((beauty80 as SetBeautyIntent).intensity, closeTo(0.8, 0.01));

      final beautyOff = parser.parse('turn off beauty');
      expect(beautyOff, isA<SetBeautyIntent>());
      expect((beautyOff as SetBeautyIntent).intensity, 0.0);
    });

    test('Exposure EV bias adjustments parsed', () {
      final brighter = parser.parse('brighter');
      expect(brighter, isA<SetExposureIntent>());
      expect((brighter as SetExposureIntent).evBias, 1.0);

      final darker = parser.parse('darker');
      expect(darker, isA<SetExposureIntent>());
      expect((darker as SetExposureIntent).evBias, -1.0);

      final customEv = parser.parse('exposure +1.5');
      expect(customEv, isA<SetExposureIntent>());
      expect((customEv as SetExposureIntent).evBias, 1.5);
    });

    test('Apply look and filter commands parsed', () {
      final look = parser.parse('apply cinematic look');
      expect(look, isA<ApplyLookIntent>());
      expect((look as ApplyLookIntent).lookQuery, 'cinematic');

      final filter = parser.parse('set filter noir');
      expect(filter, isA<ApplyLookIntent>());
      expect((filter as ApplyLookIntent).lookQuery, 'noir');
    });
  });
}
