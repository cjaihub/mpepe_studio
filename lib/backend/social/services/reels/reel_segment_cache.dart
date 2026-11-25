import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Shared disk cache for reel HLS files, served to the players through a
/// tiny HTTP proxy on 127.0.0.1.
///
/// Why a proxy: media_kit (mpv) has no cache shared between players or
/// across app runs. Routing playback through this proxy means:
///  * segments prefetched for the next videos are read from disk at swipe
///    time, so playback starts instantly;
///  * swiping back, or replaying, costs no download (and no CDN egress);
///  * one LRU limit covers everything.
///
/// URL shape: `http://127.0.0.1:<port>/h/<host>/<path>` maps to
/// `https://<host>/<path>`. Keeping the path means relative URIs inside
/// playlists resolve back through the proxy on their own.
///
/// Transcoded reels never change once written, so files are cached forever
/// until evicted by size.
class ReelSegmentCache {
  ReelSegmentCache({required this.maxBytes, Directory? directory, this.originScheme = 'https'})
      : _injectedDir = directory;

  int maxBytes;

  /// Scheme of the CDN. Always https in the app; tests use a local http server.
  final String originScheme;
  final Directory? _injectedDir;
  late final Directory _dir;
  HttpServer? _server;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..idleTimeout = const Duration(seconds: 30);

  final Map<String, Future<File?>> _inFlight = {};
  int _totalBytes = 0;
  bool _trimming = false;

  /// Smoothed download speed seen by the cache, in kbit/s. 0 when unknown.
  double estimatedKbps = 0;

  /// Bytes served from disk vs fetched from the network, for metrics.
  int hitBytes = 0;
  int missBytes = 0;

  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    _dir = _injectedDir ??
        Directory('${(await getApplicationCacheDirectory()).path}/reels_hls');
    await _dir.create(recursive: true);
    await for (final f in _dir.list()) {
      if (f is File) {
        if (f.path.endsWith('.part')) {
          await f.delete().catchError((_) => f);
        } else {
          _totalBytes += await f.length();
        }
      }
    }
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle, onError: (Object e) => debugPrint('ReelSegmentCache: $e'));
    unawaited(_trim());
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// Returns a URL the player should open. Falls back to [url] when it
  /// cannot be proxied (proxy down, not https, or signed with a query).
  String playbackUrl(String url) {
    final server = _server;
    final uri = Uri.tryParse(url);
    if (server == null || uri == null || uri.scheme != originScheme || uri.hasQuery) {
      return url;
    }
    return 'http://127.0.0.1:${server.port}/h/${uri.authority}${uri.path}';
  }

  /// Downloads (or reuses) the playlist chain and the first [segments]
  /// segments of rung [rungIndex], so playback can start from disk.
  /// Returns the variant playlist URL (origin form), or null on failure.
  Future<String?> prefetch(String masterUrl, int rungIndex, int segments,
      {bool Function()? cancelled}) async {
    final variant = await resolveVariant(masterUrl, rungIndex);
    if (variant == null || segments <= 0) return variant;
    final playlist = await _textOf(variant);
    if (playlist == null) return variant;
    final base = Uri.parse(variant);
    final segs = playlist
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('#'))
        .take(segments);
    for (final s in segs) {
      if (cancelled?.call() ?? false) break;
      await _ensureCached(base.resolve(s).toString());
    }
    return variant;
  }

  /// URL of the variant playlist for [rungIndex] (0 = lowest), clamped to
  /// the rungs that exist. Variants are listed lowest first by the worker.
  Future<String?> resolveVariant(String masterUrl, int rungIndex) async {
    final master = await _textOf(masterUrl);
    if (master == null) return null;
    final lines = master.split('\n').map((l) => l.trim()).toList();
    final variants = <String>[];
    for (var i = 0; i < lines.length - 1; i++) {
      if (lines[i].startsWith('#EXT-X-STREAM-INF')) variants.add(lines[i + 1]);
    }
    if (variants.isEmpty) return masterUrl; // Already a media playlist.
    final pick = variants[rungIndex.clamp(0, variants.length - 1)];
    return Uri.parse(masterUrl).resolve(pick).toString();
  }

  Future<String?> _textOf(String url) async {
    final f = await _ensureCached(url);
    if (f == null) return null;
    try {
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }

  File _fileFor(String origin) {
    final key = sha1.convert(utf8.encode(origin)).toString();
    return File('${_dir.path}/$key');
  }

  /// Makes sure [origin] is on disk. Concurrent callers share one download.
  Future<File?> _ensureCached(String origin) {
    final file = _fileFor(origin);
    if (file.existsSync()) {
      // Touch for LRU. Failure here is harmless.
      file.setLastModified(DateTime.now()).ignore();
      return Future.value(file);
    }
    return _inFlight.putIfAbsent(origin, () async {
      try {
        return await _download(origin, file);
      } finally {
        _inFlight.remove(origin);
      }
    });
  }

  Future<File?> _download(String origin, File file) async {
    final part = File('${file.path}.part');
    final watch = Stopwatch()..start();
    try {
      final req = await _client.getUrl(Uri.parse(origin));
      final res = await req.close();
      if (res.statusCode != HttpStatus.ok) {
        await res.drain<void>();
        return null;
      }
      final sink = part.openWrite();
      var bytes = 0;
      await for (final chunk in res) {
        bytes += chunk.length;
        sink.add(chunk);
      }
      await sink.close();
      await part.rename(file.path);
      missBytes += bytes;
      _recordSpeed(bytes, watch.elapsedMicroseconds);
      _totalBytes += bytes;
      if (_totalBytes > maxBytes) unawaited(_trim());
      return file;
    } catch (e) {
      debugPrint('ReelSegmentCache: download failed $origin ($e)');
      if (part.existsSync()) await part.delete().catchError((_) => part);
      return null;
    }
  }

  void _recordSpeed(int bytes, int micros) {
    // Tiny files (playlists) say more about latency than bandwidth.
    if (bytes < 32 * 1024 || micros <= 0) return;
    final kbps = bytes * 8 / 1000 / (micros / 1e6);
    estimatedKbps = estimatedKbps == 0 ? kbps : estimatedKbps * 0.7 + kbps * 0.3;
  }

  Future<void> _trim() async {
    if (_trimming || _totalBytes <= maxBytes) return;
    _trimming = true;
    try {
      final files = <File>[];
      await for (final f in _dir.list()) {
        if (f is File && !f.path.endsWith('.part')) files.add(f);
      }
      final stats = <File, FileStat>{for (final f in files) f: await f.stat()};
      files.sort((a, b) => stats[a]!.modified.compareTo(stats[b]!.modified));
      // Trim to 90% so we do not trim again on the very next write.
      final target = (maxBytes * 0.9).round();
      var total = stats.values.fold<int>(0, (s, st) => s + st.size);
      for (final f in files) {
        if (total <= target) break;
        total -= stats[f]!.size;
        await f.delete().catchError((_) => f);
      }
      _totalBytes = total;
    } finally {
      _trimming = false;
    }
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final segs = req.uri.pathSegments;
      final isRead = req.method == 'GET' || req.method == 'HEAD';
      if (!isRead || segs.length < 3 || segs[0] != 'h') {
        res.statusCode = HttpStatus.notFound;
        await res.close();
        return;
      }
      final origin = '$originScheme://${segs[1]}/${segs.skip(2).join('/')}';
      final wasCached = _fileFor(origin).existsSync();
      final file = await _ensureCached(origin);
      if (file == null) {
        res.statusCode = HttpStatus.badGateway;
        await res.close();
        return;
      }
      final length = await file.length();
      if (wasCached) hitBytes += length;
      res.headers.contentType = _typeFor(origin);
      res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');

      var start = 0, end = length - 1;
      final range = req.headers.value(HttpHeaders.rangeHeader);
      final m = range == null ? null : RegExp(r'bytes=(\d*)-(\d*)').firstMatch(range);
      if (m != null) {
        if (m[1]!.isNotEmpty) start = int.parse(m[1]!);
        if (m[2]!.isNotEmpty) end = int.parse(m[2]!).clamp(0, length - 1);
        if (m[1]!.isEmpty && m[2]!.isNotEmpty) {
          start = (length - int.parse(m[2]!)).clamp(0, length);
          end = length - 1;
        }
        if (start > end || start >= length) {
          res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
          await res.close();
          return;
        }
        res.statusCode = HttpStatus.partialContent;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$length');
      }
      res.contentLength = end - start + 1;
      if (req.method == 'HEAD') {
        await res.close();
        return;
      }
      await res.addStream(file.openRead(start, end + 1));
      await res.close();
    } catch (e) {
      // Player closed the connection mid-file (normal on fast swipes).
      try {
        await res.close();
      } catch (_) {}
    }
  }

  ContentType _typeFor(String path) {
    if (path.endsWith('.m3u8')) return ContentType('application', 'vnd.apple.mpegurl');
    if (path.endsWith('.ts')) return ContentType('video', 'mp2t');
    if (path.endsWith('.jpg')) return ContentType('image', 'jpeg');
    return ContentType.binary;
  }
}
