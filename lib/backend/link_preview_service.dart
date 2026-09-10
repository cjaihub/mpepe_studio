import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;

class LinkMetadata {
  final String? title;
  final String? description;
  final String? imageUrl;
  final String platform;

  LinkMetadata({
    this.title,
    this.description,
    this.imageUrl,
    required this.platform,
  });
}

class LinkPreviewService {
  static Future<LinkMetadata?> fetchMetadata(String urlString) async {
    if (urlString.isEmpty) return null;
    
    // Add protocol if missing
    if (!urlString.startsWith('http')) {
      urlString = 'https://$urlString';
    }

    try {
      final uri = Uri.parse(urlString);
      final host = uri.host.toLowerCase();

      // YouTube oEmbed
      if (host.contains('youtube.com') || host.contains('youtu.be')) {
        return await _fetchYouTubeOEmbed(urlString);
      }
      
      // TikTok oEmbed
      if (host.contains('tiktok.com')) {
        return await _fetchTikTokOEmbed(urlString);
      }

      // Generic OpenGraph parse (including Instagram/Facebook fallback)
      return await _fetchGenericOGTags(urlString, host);

    } catch (e) {
      debugPrint('Error fetching metadata: $e');
      return null;
    }
  }

  static Future<LinkMetadata?> _fetchYouTubeOEmbed(String url) async {
    final oembedUrl = 'https://www.youtube.com/oembed?url=${Uri.encodeComponent(url)}&format=json';
    try {
      final response = await http.get(Uri.parse(oembedUrl)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return LinkMetadata(
          title: data['title'],
          description: data['author_name'],
          imageUrl: data['thumbnail_url'],
          platform: 'YouTube',
        );
      }
    } catch (_) {}
    return _fetchGenericOGTags(url, 'youtube.com');
  }

  static Future<LinkMetadata?> _fetchTikTokOEmbed(String url) async {
    final oembedUrl = 'https://www.tiktok.com/oembed?url=${Uri.encodeComponent(url)}';
    try {
      final response = await http.get(Uri.parse(oembedUrl)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return LinkMetadata(
          title: data['title'],
          description: data['author_name'],
          imageUrl: data['thumbnail_url'],
          platform: 'TikTok',
        );
      }
    } catch (_) {}
    return _fetchGenericOGTags(url, 'tiktok.com');
  }

  static Future<LinkMetadata?> _fetchGenericOGTags(String url, String host) async {
    String platform = 'Link';
    if (host.contains('instagram.com')) platform = 'Instagram';
    if (host.contains('facebook.com')) platform = 'Facebook';
    if (host.contains('twitter.com') || host.contains('x.com')) platform = 'Twitter';
    if (host.contains('whatsapp.com') || host.contains('wa.me')) platform = 'WhatsApp';

    try {
      // Mimic WhatsApp bot for better OG tag responses
      final response = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'WhatsApp/2.21.12.21 A',
      }).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final document = parser.parse(response.body);
        
        String? title;
        String? description;
        String? imageUrl;

        // Extract OG tags
        final metaTags = document.getElementsByTagName('meta');
        for (var meta in metaTags) {
          final property = meta.attributes['property'];
          final name = meta.attributes['name'];
          final content = meta.attributes['content'];

          if (property == 'og:title' || name == 'twitter:title') {
            title ??= content;
          } else if (property == 'og:description' || name == 'twitter:description' || name == 'description') {
            description ??= content;
          } else if (property == 'og:image' || name == 'twitter:image') {
            imageUrl ??= content;
          }
        }

        // Fallback title
        if (title == null) {
          final titleElements = document.getElementsByTagName('title');
          if (titleElements.isNotEmpty) {
            title = titleElements.first.text;
          }
        }

        return LinkMetadata(
          title: title,
          description: description,
          imageUrl: imageUrl,
          platform: platform,
        );
      }
    } catch (_) {}
    return null;
  }
}
