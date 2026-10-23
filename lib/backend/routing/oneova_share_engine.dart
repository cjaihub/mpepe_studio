import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../social/models/content.dart';

final oneovaShareEngineProvider = Provider<OneovaShareEngine>((ref) {
  return OneovaShareEngine();
});

/// OpenGraph and Twitter card metadata for Oneova shareable media cards
class OpenGraphMetadata {
  final String contentId;
  final String title;
  final String author;
  final String thumbnailUrl;
  final String playUrl;
  final String webUrl;
  final String deepLinkUrl;
  final String description;
  final Duration? duration;

  const OpenGraphMetadata({
    required this.contentId,
    required this.title,
    required this.author,
    required this.thumbnailUrl,
    required this.playUrl,
    required this.webUrl,
    required this.deepLinkUrl,
    required this.description,
    this.duration,
  });

  Map<String, dynamic> toMap() {
    return {
      'contentId': contentId,
      'title': title,
      'author': author,
      'thumbnailUrl': thumbnailUrl,
      'playUrl': playUrl,
      'webUrl': webUrl,
      'deepLinkUrl': deepLinkUrl,
      'description': description,
      'durationMs': duration?.inMilliseconds,
    };
  }
}

/// Detailed outcome of resolving an incoming link
class ShareLinkResolution {
  final bool isValid;
  final String? contentId;
  final String? route;
  final bool isSignatureVerified;
  final String? referrerId;
  final String? errorReason;

  const ShareLinkResolution({
    required this.isValid,
    this.contentId,
    this.route,
    this.isSignatureVerified = false,
    this.referrerId,
    this.errorReason,
  });
}

/// Oneova Cryptographic Deep Link Generator & Resolver
///
/// Powers rich, tamper-evident link sharing and universal deep-linking:
/// 1. Generates universal web links: `https://oneova.app/p/{contentId}`
/// 2. Generates native app scheme URIs: `oneova://content/{contentId}`
/// 3. Generates and verifies HMAC-SHA256 cryptographic signatures.
/// 4. Generates OpenGraph rich preview tags for social platforms (iMessage, WhatsApp, Twitter).
/// 5. Safely resolves links into `/hub/home?v={contentId}` for auto-play in the main feed
///    without requiring guest authentication.
class OneovaShareEngine {
  static const String webDomain = 'oneova.app';
  static const String customScheme = 'oneova';
  static const String _defaultHmacKey = 'oneova_secure_link_secret_2026';

  final String _signingSecret;

  OneovaShareEngine({String? signingSecret})
      : _signingSecret = signingSecret ?? _defaultHmacKey;

  /// Generates a standard shareable web link: `https://oneova.app/p/{contentId}`
  String generateWebShareUrl(String contentId, {String? referrerId}) {
    final cleanId = contentId.trim();
    if (referrerId != null && referrerId.isNotEmpty) {
      return 'https://$webDomain/p/$cleanId?ref=${Uri.encodeComponent(referrerId)}';
    }
    return 'https://$webDomain/p/$cleanId';
  }

  /// Generates a native deep link URI: `oneova://content/{contentId}`
  String generateDeepLinkUri(String contentId) {
    final cleanId = contentId.trim();
    return '$customScheme://content/$cleanId';
  }

  /// Generates a cryptographically signed web link with HMAC-SHA256 verification and TTL
  String generateCryptographicShareUrl(
    String contentId, {
    Duration ttl = const Duration(days: 30),
    String? referrerId,
  }) {
    final cleanId = contentId.trim();
    final expiresAt = DateTime.now().add(ttl).millisecondsSinceEpoch;
    final ref = referrerId ?? '';

    final payload = '$cleanId:$expiresAt:$ref';
    final signature = _computeHmacSha256(payload, _signingSecret);

    final queryParams = {
      'exp': expiresAt.toString(),
      'sig': signature,
      if (ref.isNotEmpty) 'ref': ref,
    };

    final uri = Uri(
      scheme: 'https',
      host: webDomain,
      path: '/p/$cleanId',
      queryParameters: queryParams,
    );

    return uri.toString();
  }

  /// Verifies the cryptographic HMAC signature of a share link
  bool verifySignature(Uri uri) {
    final contentId = _extractContentId(uri);
    final expStr = uri.queryParameters['exp'];
    final sig = uri.queryParameters['sig'];
    final ref = uri.queryParameters['ref'] ?? '';

    if (contentId == null || expStr == null || sig == null) {
      return false;
    }

    final expiresAt = int.tryParse(expStr);
    if (expiresAt == null) return false;

    // Check expiration timestamp
    if (DateTime.now().millisecondsSinceEpoch > expiresAt) {
      return false; // Token expired
    }

    final payload = '$contentId:$expiresAt:$ref';
    final expectedSig = _computeHmacSha256(payload, _signingSecret);

    return _constantTimeEquals(sig, expectedSig);
  }

  /// Generates OpenGraph metadata for rich preview presentation
  OpenGraphMetadata generateOpenGraphMetadata({
    required String contentId,
    required String title,
    required String author,
    required String thumbnailUrl,
    required String playUrl,
    String? description,
    Duration? duration,
  }) {
    final webUrl = generateWebShareUrl(contentId);
    final deepLink = generateDeepLinkUri(contentId);
    final resolvedDesc = description ?? 'Watch $author on Oneova';

    return OpenGraphMetadata(
      contentId: contentId,
      title: title,
      author: author,
      thumbnailUrl: thumbnailUrl,
      playUrl: playUrl,
      webUrl: webUrl,
      deepLinkUrl: deepLink,
      description: resolvedDesc,
      duration: duration,
    );
  }

  /// Generates OpenGraph metadata directly from a Content model
  OpenGraphMetadata fromContent(Content content, {String authorName = 'Oneova Creator'}) {
    final title = content.description.isNotEmpty
        ? (content.description.length > 60
            ? '${content.description.substring(0, 57)}...'
            : content.description)
        : '$authorName on Oneova';

    final thumb = content.mediaMetadata.thumbnailUrl ??
        content.mediaMetadata.posterFrameUrl ??
        'https://$webDomain/assets/oneova_poster_default.jpg';

    return generateOpenGraphMetadata(
      contentId: content.id,
      title: title,
      author: authorName,
      thumbnailUrl: thumb,
      playUrl: content.mediaUrl,
      description: content.description,
      duration: content.mediaMetadata.duration,
    );
  }

  /// Generates clean HTML `<head>` meta tags for social crawlers (OpenGraph / Twitter Card)
  String generateOpenGraphHtml(OpenGraphMetadata metadata) {
    final buffer = StringBuffer();
    buffer.writeln('<!-- Oneova Rich Card OpenGraph Metadata -->');
    buffer.writeln('<meta property="og:site_name" content="Oneova" />');
    buffer.writeln('<meta property="og:type" content="video.other" />');
    buffer.writeln('<meta property="og:title" content="${_escapeHtml(metadata.title)}" />');
    buffer.writeln('<meta property="og:description" content="${_escapeHtml(metadata.description)}" />');
    buffer.writeln('<meta property="og:url" content="${metadata.webUrl}" />');
    buffer.writeln('<meta property="og:image" content="${metadata.thumbnailUrl}" />');
    buffer.writeln('<meta property="og:video" content="${metadata.playUrl}" />');
    buffer.writeln('<meta property="og:video:type" content="video/mp4" />');
    if (metadata.duration != null) {
      buffer.writeln('<meta property="video:duration" content="${metadata.duration!.inSeconds}" />');
    }
    buffer.writeln('<meta name="twitter:card" content="player" />');
    buffer.writeln('<meta name="twitter:title" content="${_escapeHtml(metadata.title)}" />');
    buffer.writeln('<meta name="twitter:description" content="${_escapeHtml(metadata.description)}" />');
    buffer.writeln('<meta name="twitter:image" content="${metadata.thumbnailUrl}" />');
    buffer.writeln('<meta name="twitter:player" content="${metadata.playUrl}" />');
    buffer.writeln('<meta name="al:ios:url" content="${metadata.deepLinkUrl}" />');
    buffer.writeln('<meta name="al:ios:app_name" content="Oneova" />');
    buffer.writeln('<meta name="al:android:url" content="${metadata.deepLinkUrl}" />');
    buffer.writeln('<meta name="al:android:app_name" content="Oneova" />');
    buffer.writeln('<meta name="al:web:url" content="${metadata.webUrl}" />');

    return buffer.toString();
  }

  /// Resolves an incoming link (web or custom deep link) and returns the destination
  /// route `/hub/home?v={contentId}` for auto-play in the main feed without requiring guest authentication.
  ///
  /// Supported formats:
  /// - `https://oneova.app/p/{contentId}`
  /// - `https://oneova.app/content/{contentId}`
  /// - `https://oneova.app/hub/home?v={contentId}`
  /// - `oneova://content/{contentId}`
  /// - `oneova://p/{contentId}`
  /// - `oneova:///p/{contentId}`
  /// - Any URI having query parameter `v` or `contentId`
  String? resolveShareLink(Uri uri) {
    final contentId = _extractContentId(uri);
    if (contentId == null || contentId.isEmpty) {
      return null;
    }
    return '/hub/home?v=$contentId';
  }

  /// Full resolution breakdown including validation, signature status, and referrer
  ShareLinkResolution resolveShareLinkDetails(Uri uri) {
    final contentId = _extractContentId(uri);
    if (contentId == null || contentId.isEmpty) {
      return const ShareLinkResolution(
        isValid: false,
        errorReason: 'No valid contentId found in URI',
      );
    }

    final hasSignature = uri.queryParameters.containsKey('sig');
    final isSigValid = hasSignature ? verifySignature(uri) : false;
    final referrer = uri.queryParameters['ref'];

    return ShareLinkResolution(
      isValid: true,
      contentId: contentId,
      route: '/hub/home?v=$contentId',
      isSignatureVerified: isSigValid,
      referrerId: referrer,
    );
  }

  /// Internal parser that extracts the contentId safely from varying URI patterns
  String? _extractContentId(Uri uri) {
    // 1. Direct query parameters ?v= or ?contentId=
    if (uri.queryParameters.containsKey('v')) {
      final v = uri.queryParameters['v']?.trim();
      if (v != null && v.isNotEmpty && _isValidIdFormat(v)) return v;
    }
    if (uri.queryParameters.containsKey('contentId')) {
      final c = uri.queryParameters['contentId']?.trim();
      if (c != null && c.isNotEmpty && _isValidIdFormat(c)) return c;
    }

    // 2. Custom native scheme: oneova://content/{id} or oneova://p/{id}
    if (uri.scheme == customScheme) {
      // e.g. oneova://content/xyz -> host: 'content', pathSegments: ['xyz']
      if (uri.host == 'content' || uri.host == 'p') {
        if (uri.pathSegments.isNotEmpty) {
          final id = uri.pathSegments.first.trim();
          if (_isValidIdFormat(id)) return id;
        }
      }
      // e.g. oneova:///content/xyz -> host: '', pathSegments: ['content', 'xyz']
      if (uri.pathSegments.length >= 2) {
        final prefix = uri.pathSegments[0];
        if (prefix == 'content' || prefix == 'p') {
          final id = uri.pathSegments[1].trim();
          if (_isValidIdFormat(id)) return id;
        }
      }
      if (uri.pathSegments.length == 1 && _isValidIdFormat(uri.pathSegments[0])) {
        return uri.pathSegments[0].trim();
      }
    }

    // 3. Web URL: https://oneova.app/p/{id} or /content/{id}
    final segments = uri.pathSegments;
    if (segments.length >= 2) {
      final prefix = segments[0];
      if (prefix == 'p' || prefix == 'content' || prefix == 'v') {
        final id = segments[1].trim();
        if (_isValidIdFormat(id)) return id;
      }
    }

    return null;
  }

  /// Validates ID contains safe characters (alphanumeric, underscores, hyphens)
  static bool _isValidIdFormat(String id) {
    if (id.isEmpty || id.length > 128) return false;
    return RegExp(r'^[a-zA-Z0-9_\-]+$').hasMatch(id);
  }

  static String _computeHmacSha256(String data, String key) {
    final hmac = Hmac(sha256, utf8.encode(key));
    return hmac.convert(utf8.encode(data)).toString();
  }

  /// Constant-time string equality check to mitigate timing attacks
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#039;');
  }
}
