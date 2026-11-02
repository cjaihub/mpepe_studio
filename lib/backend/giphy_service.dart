import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'gif/oneova_gif_engine.dart';

class GiphyGif {
  final String id;
  final String previewUrl;
  final String fullUrl;

  GiphyGif({
    required this.id,
    required this.previewUrl,
    required this.fullUrl,
  });

  factory GiphyGif.fromJson(Map<String, dynamic> json) {
    return GiphyGif(
      id: json['id'] ?? '',
      previewUrl: json['images']?['fixed_height']?['url'] ?? json['url'] ?? '',
      fullUrl: json['images']?['original']?['url'] ?? json['url'] ?? '',
    );
  }
}

class GiphyService {
  final OneovaGifEngine _engine;

  GiphyService({OneovaGifEngine? engine}) : _engine = engine ?? OneovaGifEngine();

  Future<List<GiphyGif>> fetchTrending() => search('');

  Future<List<GiphyGif>> search(String query) async {
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('lsGifSearch')
          .call({'q': query.trim()});
      final data = res.data;
      if (data is Map && data['gifs'] is List) {
        final List items = data['gifs'];
        final list = items.map((e) {
          final id = e['id']?.toString() ?? '';
          final url = e['url']?.toString() ?? '';
          return GiphyGif(id: id, previewUrl: url, fullUrl: url);
        }).toList();
        if (list.isNotEmpty) return list;
      }
    } catch (_) {}

    // Resilient fallback to Open-Source GIF Engine
    try {
      final openGifs = await _engine.search(query);
      return openGifs
          .map((g) => GiphyGif(id: g.id, previewUrl: g.previewUrl, fullUrl: g.url))
          .toList();
    } catch (_) {
      return [];
    }
  }
}

final giphyServiceProvider = Provider<GiphyService>((ref) {
  final engine = ref.watch(oneovaGifEngineProvider);
  return GiphyService(engine: engine);
});
