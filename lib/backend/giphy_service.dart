import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

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
      previewUrl: json['images']['fixed_height']['url'] ?? '',
      fullUrl: json['images']['original']['url'] ?? '',
    );
  }
}

class GiphyService {
  static const _kGiphyApiKey = 'YOUR_GIPHY_BETA_KEY'; // Placeholder for beta key
  
  Future<List<GiphyGif>> fetchTrending() async {
    try {
      final url = Uri.parse('https://api.giphy.com/v1/gifs/trending?api_key=$_kGiphyApiKey&limit=24&rating=g');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List items = data['data'] ?? [];
        return items.map((e) => GiphyGif.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<GiphyGif>> search(String query) async {
    if (query.trim().isEmpty) return fetchTrending();
    try {
      final url = Uri.parse('https://api.giphy.com/v1/gifs/search?api_key=$_kGiphyApiKey&q=${Uri.encodeComponent(query)}&limit=24&rating=g');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List items = data['data'] ?? [];
        return items.map((e) => GiphyGif.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}

final giphyServiceProvider = Provider<GiphyService>((ref) => GiphyService());
