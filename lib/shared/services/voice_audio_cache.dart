import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Result of translating a voice note into the listener's language while
/// matching the speaker's vocal profile (timbre, pitch, and speaking rate).
class VoiceTranslationResult {
  final String transcript;
  final String translated;
  final String source;
  final String target;
  final bool same;

  /// Synthesized voice-matched audio file on local disk, if cloud neural TTS
  /// succeeded. When null, the player falls back to on-device TTS tuned with
  /// [pitch] and [rate].
  final String? localAudioPath;
  final String voiceName;
  final double pitch;
  final double rate;

  const VoiceTranslationResult({
    required this.transcript,
    required this.translated,
    required this.source,
    required this.target,
    required this.same,
    this.localAudioPath,
    this.voiceName = 'Aoede',
    this.pitch = 1.0,
    this.rate = 1.0,
  });
}

/// Zero-duplicate local disk cache and translation event bus for chat voice
/// notes so playback starts in <15ms and translated audio is synthesized at
/// most once per message/language pair.
class VoiceAudioDiskCache {
  VoiceAudioDiskCache._();

  static final Map<String, String> _urlToLocalPath = <String, String>{};
  static final Map<String, Future<String>> _inflightDownloads = <String, Future<String>>{};
  static final Map<String, VoiceTranslationResult> _translationCache = <String, VoiceTranslationResult>{};
  static final Map<String, Future<VoiceTranslationResult>> _inflightTranslations =
      <String, Future<VoiceTranslationResult>>{};
  static final StreamController<String> _translateRequests = StreamController<String>.broadcast();

  /// Stream of messageIds for which the user requested voice-note translation
  /// from an external action sheet.
  static Stream<String> get translateRequests => _translateRequests.stream;

  static void requestTranslate(String messageId) {
    if (messageId.isNotEmpty) {
      _translateRequests.add(messageId);
    }
  }

  /// Associates a remote download URL with an existing local recording file so
  /// playing your own sent voice note never re-downloads from cloud storage.
  static void seedLocalFile(String remoteUrl, String localPath) {
    if (remoteUrl.isEmpty || localPath.isEmpty) return;
    _urlToLocalPath[remoteUrl] = localPath;
  }

  static bool _isRemoteUrl(String v) => v.startsWith('http://') || v.startsWith('https://');

  static String _hashKey(String input) => sha1.convert(utf8.encode(input)).toString().substring(0, 20);

  static String _inferExtension(String urlOrMime) {
    final lower = urlOrMime.toLowerCase();
    if (lower.contains('.wav') || lower.contains('audio/wav')) return '.wav';
    if (lower.contains('.mp3') || lower.contains('audio/mpeg')) return '.mp3';
    if (lower.contains('.ogg') || lower.contains('audio/ogg')) return '.ogg';
    if (lower.contains('.aac') || lower.contains('audio/aac')) return '.aac';
    return '.m4a';
  }

  static String inferMimeType(String pathOrUrl) {
    final lower = pathOrUrl.toLowerCase();
    if (lower.contains('.wav')) return 'audio/wav';
    if (lower.contains('.mp3')) return 'audio/mpeg';
    if (lower.contains('.ogg')) return 'audio/ogg';
    if (lower.contains('.aac')) return 'audio/aac';
    return 'audio/mp4';
  }

  /// Resolves [pathOrUrl] to a verified local file path for instant playback,
  /// downloading once if needed. Falls back to [pathOrUrl] if offline.
  static Future<String> resolvePlayablePath(String pathOrUrl) async {
    if (pathOrUrl.isEmpty || !_isRemoteUrl(pathOrUrl)) {
      return pathOrUrl;
    }

    final seeded = _urlToLocalPath[pathOrUrl];
    if (seeded != null) {
      final f = File(seeded);
      if (await f.exists() && await f.length() > 0) {
        return seeded;
      }
      _urlToLocalPath.remove(pathOrUrl);
    }

    final inflight = _inflightDownloads[pathOrUrl];
    if (inflight != null) return inflight;

    final future = _downloadToTemp(pathOrUrl);
    _inflightDownloads[pathOrUrl] = future;
    try {
      return await future;
    } finally {
      _inflightDownloads.remove(pathOrUrl);
    }
  }

  static Future<String> _downloadToTemp(String url) async {
    try {
      final dir = await getTemporaryDirectory();
      final ext = _inferExtension(url);
      final targetPath = File.fromUri(dir.uri.resolve('oneova_vn_${_hashKey(url)}$ext')).path;
      final file = File(targetPath);
      if (await file.exists() && await file.length() > 0) {
        _urlToLocalPath[url] = targetPath;
        return targetPath;
      }

      final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(resp.bodyBytes, flush: true);
        _urlToLocalPath[url] = targetPath;
        return targetPath;
      }
    } catch (_) {
      // Fall back to direct URL streaming if local caching fails.
    }
    return url;
  }

  /// Reads raw audio bytes from [pathOrUrl], reusing any locally cached file.
  static Future<Uint8List> readAudioBytes(String pathOrUrl) async {
    final resolved = await resolvePlayablePath(pathOrUrl);
    if (!_isRemoteUrl(resolved)) {
      final f = File(resolved);
      if (await f.exists()) {
        return f.readAsBytes();
      }
    }
    final resp = await http.get(Uri.parse(pathOrUrl)).timeout(const Duration(seconds: 25));
    if (resp.statusCode < 200 || resp.statusCode >= 300 || resp.bodyBytes.isEmpty) {
      throw const SocketException('Could not load voice note audio.');
    }
    return resp.bodyBytes;
  }

  /// Writes synthesized base64 audio bytes to local temp cache for playback.
  static Future<String?> saveSynthesizedAudio({
    required String cacheKey,
    required String base64Audio,
    String mimeType = 'audio/wav',
  }) async {
    if (base64Audio.isEmpty) return null;
    final dir = await getTemporaryDirectory();
    final ext = _inferExtension(mimeType);
    final file = File.fromUri(dir.uri.resolve('oneova_vn_tts_${_hashKey(cacheKey)}$ext'));
    if (await file.exists() && await file.length() > 0) {
      return file.path;
    }
    final bytes = base64Decode(base64Audio);
    if (bytes.isEmpty) return null;
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static VoiceTranslationResult? getCachedTranslation(String fullKey) {
    final hit = _translationCache[fullKey];
    if (hit == null) return null;
    if (hit.localAudioPath != null && !File(hit.localAudioPath!).existsSync()) {
      _translationCache.remove(fullKey);
      return null;
    }
    return hit;
  }

  static Future<VoiceTranslationResult> runDeduplicatedTranslation(
    String fullKey,
    Future<VoiceTranslationResult> Function() loader,
  ) async {
    final cached = getCachedTranslation(fullKey);
    if (cached != null) return cached;

    final inflight = _inflightTranslations[fullKey];
    if (inflight != null) return inflight;

    final future = loader();
    _inflightTranslations[fullKey] = future;
    try {
      final res = await future;
      _translationCache[fullKey] = res;
      return res;
    } finally {
      _inflightTranslations.remove(fullKey);
    }
  }
}
