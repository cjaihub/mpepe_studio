import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/social/models/audio_track.dart';
import 'package:oneova/backend/social/services/audio_service.dart';

void main() {
  late AudioService audioService;

  setUp(() {
    audioService = AudioService();
  });

  test('Ingest original sound succeeds', () async {
    final track = await audioService.ingestSound(
      title: 'My Voice',
      ownerId: 'user_1',
      ownerName: 'Alice',
      type: AudioType.originalSound,
      licenseType: AudioLicenseType.nonCommercial,
      contentUrl: 'https://test.com/audio.mp3',
    );
    expect(track.title, 'My Voice');
    expect(track.type, AudioType.originalSound);
  });

  test('Ingest licensed commercial sound without clearance throws Exception', () async {
    expect(
      () => audioService.ingestSound(
        title: 'Top 40 Hit',
        ownerId: 'user_1',
        ownerName: 'Alice',
        type: AudioType.licensedMusic,
        licenseType: AudioLicenseType.commercial,
        contentUrl: 'https://test.com/hit.mp3',
        hasCopyrightClearance: false,
      ),
      throwsA(isA<CopyrightException>()),
    );
  });
  
  test('Ingest licensed commercial sound with clearance succeeds', () async {
    final track = await audioService.ingestSound(
      title: 'Top 40 Hit',
      ownerId: 'user_1',
      ownerName: 'Alice',
      type: AudioType.licensedMusic,
      licenseType: AudioLicenseType.commercial,
      contentUrl: 'https://test.com/hit.mp3',
      hasCopyrightClearance: true,
    );
    expect(track.title, 'Top 40 Hit');
  });

  test('Search sounds returns results', () async {
    final results = await audioService.searchSounds('Dance');
    expect(results.length, 1);
    expect(results.first.title.contains('Dance'), true);
  });
  
  test('View videos for sound returns list', () async {
    final videos = await audioService.watchVideosForSound('sound_123').first;
    expect(videos, isNotNull);
  });
}
