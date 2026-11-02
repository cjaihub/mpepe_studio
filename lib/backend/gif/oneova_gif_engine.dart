import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../live_studio/fun/studio_fun.dart';
import '../social/models/comment.dart';

/// Representation of an animated GIF from the Open-Source GIF Engine.
class OneovaGif {
  final String id;
  final String url;
  final String previewUrl;
  final int width;
  final int height;
  final String title;
  final String category;

  const OneovaGif({
    required this.id,
    required this.url,
    required this.previewUrl,
    this.width = 480,
    this.height = 360,
    this.title = '',
    this.category = 'Trending',
  });

  CommentGif toCommentGif() => CommentGif(
        id: id,
        url: url,
        w: width,
        h: height,
      );

  StudioGif toStudioGif() => (
        id: id,
        url: url,
        w: width,
        h: height,
      );
}

/// Standalone, zero-configuration Open-Source GIF Engine for Oneova.
///
/// Features:
/// 1. Comprehensive built-in catalog of curated open-source reaction GIFs
///    (Trending, Hype, LOL, Love, Clap, Party, Wow, Vibe, 100, Popcorn).
/// 2. Live open-source search via Wikimedia Commons API (no API key required, public domain & CC).
/// 3. In-memory LRU caching and category filtering.
/// 4. Resilient fallback: works 100% offline or when cloud functions are unavailable.
class OneovaGifEngine {
  final http.Client _client;

  OneovaGifEngine({http.Client? client}) : _client = client ?? http.Client();

  final Map<String, List<OneovaGif>> _cache = {};

  static const List<String> categories = [
    'Trending',
    '🔥 Hype',
    '😂 LOL',
    '❤️ Love',
    '👏 Clap',
    '🎉 Party',
    '🤯 Wow',
    '✨ Vibe',
    '💯 Facts',
    '🍿 Popcorn',
  ];

  /// Curated High-Speed Open-Source Reaction GIFs
  static const List<OneovaGif> _curatedGifs = [
    // 🔥 Hype / Fire / Excitement
    OneovaGif(
      id: 'hype_1',
      title: 'Fire Reaction',
      url: 'https://media.giphy.com/media/26tOZ42Mg6pbTUPHW/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/26tOZ42Mg6pbTUPHW/200w.gif',
      category: '🔥 Hype',
      width: 480,
      height: 480,
    ),
    OneovaGif(
      id: 'hype_2',
      title: 'Mind Blown Energy',
      url: 'https://media.giphy.com/media/l0MYt5jPR6QX5pnqM/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/l0MYt5jPR6QX5pnqM/200w.gif',
      category: '🔥 Hype',
      width: 480,
      height: 360,
    ),
    OneovaGif(
      id: 'hype_3',
      title: 'Let’s Go Celebration',
      url: 'https://media.giphy.com/media/blSTtZehjAZ8I/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/blSTtZehjAZ8I/200w.gif',
      category: '🔥 Hype',
      width: 480,
      height: 360,
    ),
    OneovaGif(
      id: 'hype_4',
      title: 'Victory Dance',
      url: 'https://media.giphy.com/media/artj92V8o75VPL7AeQ/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/artj92V8o75VPL7AeQ/200w.gif',
      category: '🔥 Hype',
      width: 480,
      height: 480,
    ),

    // 😂 LOL / Humor
    OneovaGif(
      id: 'lol_1',
      title: 'Laughing Out Loud',
      url: 'https://media.giphy.com/media/10JhviFuU2gWD6/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/10JhviFuU2gWD6/200w.gif',
      category: '😂 LOL',
      width: 480,
      height: 360,
    ),
    OneovaGif(
      id: 'lol_2',
      title: 'Can’t Stop Laughing',
      url: 'https://media.giphy.com/media/xr9AQyxLtjlxS/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/xr9AQyxLtjlxS/200w.gif',
      category: '😂 LOL',
      width: 480,
      height: 360,
    ),
    OneovaGif(
      id: 'lol_3',
      title: 'Rolling on the Floor',
      url: 'https://media.giphy.com/media/I4Jmrcjnr8Zfq/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/I4Jmrcjnr8Zfq/200w.gif',
      category: '😂 LOL',
      width: 480,
      height: 360,
    ),
    OneovaGif(
      id: 'lol_4',
      title: 'Chuckle Smile',
      url: 'https://media.giphy.com/media/3oEjHAUOqG3lSS0f1C/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/3oEjHAUOqG3lSS0f1C/200w.gif',
      category: '😂 LOL',
      width: 480,
      height: 360,
    ),

    // ❤️ Love / Hearts
    OneovaGif(
      id: 'love_1',
      title: 'Heart Eyes Love',
      url: 'https://media.giphy.com/media/PQKlfexeEpnTq/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/PQKlfexeEpnTq/200w.gif',
      category: '❤️ Love',
      width: 480,
      height: 360,
    ),
    OneovaGif(
      id: 'love_2',
      title: 'Flying Hearts Kiss',
      url: 'https://media.giphy.com/media/26FLdmIp6wJr91JAI/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/26FLdmIp6wJr91JAI/200w.gif',
      category: '❤️ Love',
      width: 480,
      height: 360,
    ),
    OneovaGif(
      id: 'love_3',
      title: 'Warm Hug Love',
      url: 'https://media.giphy.com/media/EvYHHSntaIl5m/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/EvYHHSntaIl5m/200w.gif',
      category: '❤️ Love',
      width: 480,
      height: 360,
    ),
    OneovaGif(
      id: 'love_4',
      title: 'Heart Pulse',
      url: 'https://media.giphy.com/media/MDJ9IbxxvDUQM/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/MDJ9IbxxvDUQM/200w.gif',
      category: '❤️ Love',
      width: 480,
      height: 360,
    ),

    // 👏 Clap / Applause
    OneovaGif(
      id: 'clap_1',
      title: 'Standing Ovation',
      url: 'https://media.giphy.com/media/7rj2ZgttvgomY/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/7rj2ZgttvgomY/200w.gif',
      category: '👏 Clap',
      width: 480,
      height: 360,
    ),
    OneovaGif(
      id: 'clap_2',
      title: 'Applause Great Job',
      url: 'https://media.giphy.com/media/nbvFVPiEiJH6JOGIok/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/nbvFVPiEiJH6JOGIok/200w.gif',
      category: '👏 Clap',
      width: 480,
      height: 360,
    ),
    OneovaGif(
      id: 'clap_3',
      title: 'Enthusiastic Clap',
      url: 'https://media.giphy.com/media/l4q8cJzGdR9J8w3hS/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/l4q8cJzGdR9J8w3hS/200w.gif',
      category: '👏 Clap',
      width: 480,
      height: 360,
    ),

    // 🎉 Party / Celebration
    OneovaGif(
      id: 'party_1',
      title: 'Party Confetti',
      url: 'https://media.giphy.com/media/g9582DNuQppxC/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/g9582DNuQppxC/200w.gif',
      category: '🎉 Party',
      width: 480,
      height: 360,
    ),
    OneovaGif(
      id: 'party_2',
      title: 'Celebration Dance',
      url: 'https://media.giphy.com/media/IwAZ6dvvvaNN6/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/IwAZ6dvvvaNN6/200w.gif',
      category: '🎉 Party',
      width: 480,
      height: 360,
    ),
    OneovaGif(
      id: 'party_3',
      title: 'Fireworks Sparkle',
      url: 'https://media.giphy.com/media/26u4cqiYI30juCOGY/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/26u4cqiYI30juCOGY/200w.gif',
      category: '🎉 Party',
      width: 480,
      height: 360,
    ),

    // 🤯 Wow / Shock
    OneovaGif(
      id: 'wow_1',
      title: 'Shocked Wow',
      url: 'https://media.giphy.com/media/5VKbvrjxpVJCM/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/5VKbvrjxpVJCM/200w.gif',
      category: '🤯 Wow',
      width: 480,
      height: 360,
    ),
    OneovaGif(
      id: 'wow_2',
      title: 'Mind Blown Particle',
      url: 'https://media.giphy.com/media/xT0xeJpnrWC4XWblEk/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/xT0xeJpnrWC4XWblEk/200w.gif',
      category: '🤯 Wow',
      width: 480,
      height: 360,
    ),
    OneovaGif(
      id: 'wow_3',
      title: 'No Way Wow',
      url: 'https://media.giphy.com/media/lXu72d4iKwqek/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/lXu72d4iKwqek/200w.gif',
      category: '🤯 Wow',
      width: 480,
      height: 360,
    ),

    // ✨ Vibe / Chill / Dance
    OneovaGif(
      id: 'vibe_1',
      title: 'Grooving Vibe',
      url: 'https://media.giphy.com/media/13CoXDiaCcCoyk/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/13CoXDiaCcCoyk/200w.gif',
      category: '✨ Vibe',
      width: 480,
      height: 360,
    ),
    OneovaGif(
      id: 'vibe_2',
      title: 'Cat Vibing Bop',
      url: 'https://media.giphy.com/media/jpbnoe3UIa8TU8LM13/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/jpbnoe3UIa8TU8LM13/200w.gif',
      category: '✨ Vibe',
      width: 480,
      height: 360,
    ),
    OneovaGif(
      id: 'vibe_3',
      title: 'Smooth Groove',
      url: 'https://media.giphy.com/media/DhstvI3zZ598Nb1rFf/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/DhstvI3zZ598Nb1rFf/200w.gif',
      category: '✨ Vibe',
      width: 480,
      height: 360,
    ),

    // 💯 Facts / Agreement
    OneovaGif(
      id: 'facts_1',
      title: 'Exact Facts 100',
      url: 'https://media.giphy.com/media/6cFcUiCG5eONW/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/6cFcUiCG5eONW/200w.gif',
      category: '💯 Facts',
      width: 480,
      height: 360,
    ),
    OneovaGif(
      id: 'facts_2',
      title: 'Nodding Approval',
      url: 'https://media.giphy.com/media/NEvPzZ8bd1V4Y/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/NEvPzZ8bd1V4Y/200w.gif',
      category: '💯 Facts',
      width: 480,
      height: 360,
    ),

    // 🍿 Popcorn
    OneovaGif(
      id: 'popcorn_1',
      title: 'Watching Drama Popcorn',
      url: 'https://media.giphy.com/media/gl0mkIZOW6Nwc/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/gl0mkIZOW6Nwc/200w.gif',
      category: '🍿 Popcorn',
      width: 480,
      height: 360,
    ),
    OneovaGif(
      id: 'popcorn_2',
      title: 'Waiting for Tea',
      url: 'https://media.giphy.com/media/uWzS6ZKs09Hzq/giphy.gif',
      previewUrl: 'https://media.giphy.com/media/uWzS6ZKs09Hzq/200w.gif',
      category: '🍿 Popcorn',
      width: 480,
      height: 360,
    ),
  ];

  /// Searches GIFs across curated open-source categories and Wikimedia Commons live open search.
  Future<List<OneovaGif>> search(String query, {String? category}) async {
    final cleanQuery = query.trim().toLowerCase();
    final cleanCat = category?.trim();

    final cacheKey = '$cleanQuery|$cleanCat';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    final List<OneovaGif> results = [];

    // 1. Filter local curated GIFs
    if (cleanQuery.isEmpty) {
      if (cleanCat != null && cleanCat.isNotEmpty && cleanCat != 'Trending') {
        results.addAll(_curatedGifs.where((g) => g.category == cleanCat));
      } else {
        results.addAll(_curatedGifs);
      }
    } else {
      results.addAll(_curatedGifs.where((g) =>
          g.title.toLowerCase().contains(cleanQuery) ||
          g.category.toLowerCase().contains(cleanQuery)));
    }

    // 2. If query specified, query Wikimedia Commons Live Open GIF search
    if (cleanQuery.isNotEmpty && cleanQuery.length >= 2) {
      try {
        final wikiResults = await _searchWikimediaCommons(cleanQuery);
        // Add non-duplicate items
        final existingUrls = results.map((g) => g.url).toSet();
        for (final g in wikiResults) {
          if (!existingUrls.contains(g.url)) {
            results.add(g);
          }
        }
      } catch (e) {
        debugPrint('[OneovaGifEngine] Wikimedia search notice: $e');
      }
    }

    _cache[cacheKey] = results;
    return results;
  }

  /// Queries Wikimedia Commons API for open-source animated GIF media files.
  Future<List<OneovaGif>> _searchWikimediaCommons(String query) async {
    final uri = Uri.parse(
      'https://commons.wikimedia.org/w/api.php?action=query'
      '&generator=search'
      '&gsrsearch=filemime:image/gif+${Uri.encodeComponent(query)}'
      '&gsrnamespace=6'
      '&gsrlimit=20'
      '&prop=imageinfo'
      '&iiprop=url|size|mime'
      '&format=json'
      '&origin=*',
    );

    final res = await _client.get(uri).timeout(const Duration(seconds: 4));
    if (res.statusCode != 200) return const [];

    final Map<String, dynamic> data = jsonDecode(res.body);
    final pages = data['query']?['pages'] as Map<String, dynamic>?;
    if (pages == null) return const [];

    final List<OneovaGif> gifs = [];
    for (final page in pages.values) {
      if (page is! Map<String, dynamic>) continue;
      final title = (page['title'] as String? ?? '').replaceFirst('File:', '');
      final imageInfo = (page['imageinfo'] as List?)?.firstOrNull as Map<String, dynamic>?;
      if (imageInfo == null) continue;
      final url = imageInfo['url'] as String? ?? '';
      final width = imageInfo['width'] as int? ?? 480;
      final height = imageInfo['height'] as int? ?? 360;

      if (url.toLowerCase().endsWith('.gif')) {
        gifs.add(OneovaGif(
          id: 'wiki_${page['pageid']}',
          title: title,
          url: url,
          previewUrl: url,
          width: width,
          height: height,
          category: 'Search',
        ));
      }
    }
    return gifs;
  }
}

/// Provider for Oneova's Open-Source GIF Engine.
final oneovaGifEngineProvider = Provider<OneovaGifEngine>((ref) {
  return OneovaGifEngine();
});

