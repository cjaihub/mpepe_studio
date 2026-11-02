import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oneova/backend/gif/oneova_gif_engine.dart';
import 'package:oneova/feed/providers/oneova_focus_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(const {});

  group('OneovaGifEngine Open-Source GIF Engine', () {
    test('provides comprehensive curated open-source reaction categories and GIFs', () async {
      final engine = OneovaGifEngine();

      expect(OneovaGifEngine.categories, contains('Trending'));
      expect(OneovaGifEngine.categories, contains('🔥 Hype'));
      expect(OneovaGifEngine.categories, contains('😂 LOL'));
      expect(OneovaGifEngine.categories, contains('❤️ Love'));
      expect(OneovaGifEngine.categories, contains('👏 Clap'));

      // Trending search
      final trending = await engine.search('');
      expect(trending, isNotEmpty);
      expect(trending.first.url, startsWith('http'));
      expect(trending.first.previewUrl, startsWith('http'));

      // Category filtering
      final lolGifs = await engine.search('', category: '😂 LOL');
      expect(lolGifs, isNotEmpty);
      expect(lolGifs.every((g) => g.category == '😂 LOL'), isTrue);

      // Model conversion
      final commentGif = trending.first.toCommentGif();
      expect(commentGif.url, trending.first.url);
      expect(commentGif.id, trending.first.id);

      final studioGif = trending.first.toStudioGif();
      expect(studioGif.url, trending.first.url);
    });

    test('searches Wikimedia Commons open-source animated GIF API with fallback', () async {
      final mockClient = MockClient((req) async {
        if (req.url.host.contains('wikimedia.org')) {
          return http.Response(
            jsonEncode({
              'query': {
                'pages': {
                  '12345': {
                    'pageid': 12345,
                    'title': 'File:Dancing_cat.gif',
                    'imageinfo': [
                      {
                        'url': 'https://upload.wikimedia.org/wikipedia/commons/dancing_cat.gif',
                        'width': 480,
                        'height': 360,
                        'mime': 'image/gif',
                      }
                    ]
                  }
                }
              }
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final engine = OneovaGifEngine(client: mockClient);
      final searchResults = await engine.search('dancing cat');

      expect(searchResults, isNotEmpty);
      final wikiGif = searchResults.firstWhere((g) => g.id == 'wiki_12345');
      expect(wikiGif.url, contains('dancing_cat.gif'));
      expect(wikiGif.title, 'Dancing_cat.gif');
    });
  });

  group('Oneova Focus Mode (Clear Display) Provider', () {
    test('toggles and sets focus state seamlessly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(oneovaFocusModeProvider), isFalse);

      container.read(oneovaFocusModeProvider.notifier).set(true);
      expect(container.read(oneovaFocusModeProvider), isTrue);

      container.read(oneovaFocusModeProvider.notifier).toggle();
      expect(container.read(oneovaFocusModeProvider), isFalse);
    });
  });
}
