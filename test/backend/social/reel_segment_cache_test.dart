import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mpepe_studio/backend/social/services/reels/reel_segment_cache.dart';

/// Fake CDN serving a 2-rung HLS reel, counting requests per path.
class _FakeCdn {
  late HttpServer server;
  final Map<String, int> hits = {};
  final Map<String, List<int>> files = {
    '/reels/r1/master.m3u8': '#EXTM3U\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=600000,RESOLUTION=360x640\nv0/index.m3u8\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=1400000,RESOLUTION=540x960\nv1/index.m3u8\n'
        .codeUnits,
    for (final v in ['v0', 'v1'])
      '/reels/r1/$v/index.m3u8': '#EXTM3U\n#EXT-X-TARGETDURATION:2\n'
              '#EXTINF:2.0,\nseg_000.ts\n#EXTINF:2.0,\nseg_001.ts\n#EXTINF:2.0,\nseg_002.ts\n'
              '#EXT-X-ENDLIST\n'
          .codeUnits,
    for (final v in ['v0', 'v1'])
      for (var i = 0; i < 3; i++)
        '/reels/r1/$v/seg_00$i.ts': List<int>.generate(40000, (b) => (b + i) % 256),
  };

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      hits.update(req.uri.path, (n) => n + 1, ifAbsent: () => 1);
      final body = files[req.uri.path];
      if (body == null) {
        req.response.statusCode = 404;
      } else {
        req.response.add(body);
      }
      await req.response.close();
    });
  }

  String get master => 'http://127.0.0.1:${server.port}/reels/r1/master.m3u8';
}

void main() {
  late _FakeCdn cdn;
  late Directory dir;
  late ReelSegmentCache cache;
  final client = HttpClient();

  setUp(() async {
    cdn = _FakeCdn();
    await cdn.start();
    dir = await Directory.systemTemp.createTemp('reel_cache_test');
    cache = ReelSegmentCache(maxBytes: 10 * 1024 * 1024, directory: dir, originScheme: 'http');
    await cache.start();
  });

  tearDown(() async {
    await cache.stop();
    await cdn.server.close(force: true);
    await dir.delete(recursive: true);
  });

  Future<(int, List<int>)> get(String url, {String? range}) async {
    final req = await client.getUrl(Uri.parse(url));
    if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
    final res = await req.close();
    final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
    return (res.statusCode, bytes);
  }

  test('prefetch downloads only the first segments of the chosen rung', () async {
    final variant = await cache.prefetch(cdn.master, 1, 1);
    expect(variant, endsWith('/reels/r1/v1/index.m3u8'));
    expect(cdn.hits['/reels/r1/v1/seg_000.ts'], 1);
    expect(cdn.hits.containsKey('/reels/r1/v1/seg_001.ts'), isFalse);
    expect(cdn.hits.containsKey('/reels/r1/v0/seg_000.ts'), isFalse);
  });

  test('rung index is clamped to the rungs that exist', () async {
    final variant = await cache.resolveVariant(cdn.master, 5);
    expect(variant, endsWith('/v1/index.m3u8'));
  });

  test('player reads prefetched segments from disk, relative URIs work', () async {
    await cache.prefetch(cdn.master, 0, 2);
    final variant = (await cache.resolveVariant(cdn.master, 0))!;
    final proxied = cache.playbackUrl(variant);
    expect(proxied, startsWith('http://127.0.0.1:'));

    // Player fetches the playlist, then a segment by relative path.
    final (status, playlist) = await get(proxied);
    expect(status, 200);
    expect(String.fromCharCodes(playlist), contains('seg_000.ts'));
    final segUrl = Uri.parse(proxied).resolve('seg_000.ts').toString();
    final (segStatus, seg) = await get(segUrl);
    expect(segStatus, 200);
    expect(seg, cdn.files['/reels/r1/v0/seg_000.ts']);

    // Served from disk: the CDN saw each file exactly once.
    expect(cdn.hits['/reels/r1/v0/seg_000.ts'], 1);
    expect(cdn.hits['/reels/r1/v0/index.m3u8'], 1);
    expect(cache.hitBytes, greaterThan(0));

    // Not prefetched: fetched through on demand, then cached.
    final seg2 = Uri.parse(proxied).resolve('seg_002.ts').toString();
    expect((await get(seg2)).$1, 200);
    expect((await get(seg2)).$1, 200);
    expect(cdn.hits['/reels/r1/v0/seg_002.ts'], 1);
  });

  test('range requests return the right slice', () async {
    final variant = (await cache.resolveVariant(cdn.master, 0))!;
    final segUrl = Uri.parse(cache.playbackUrl(variant)).resolve('seg_001.ts').toString();
    final (status, bytes) = await get(segUrl, range: 'bytes=100-199');
    expect(status, 206);
    expect(bytes, cdn.files['/reels/r1/v0/seg_001.ts']!.sublist(100, 200));
  });

  test('missing origin file gives 502, not a hang', () async {
    final url = cache.playbackUrl('http://127.0.0.1:${cdn.server.port}/reels/nope/master.m3u8');
    expect((await get(url)).$1, 502);
  });

  test('LRU trim keeps the cache under its limit', () async {
    await cache.stop();
    cache = ReelSegmentCache(maxBytes: 100000, directory: dir, originScheme: 'http');
    await cache.start();
    await cache.prefetch(cdn.master, 0, 3); // ~120 KB of segments
    await cache.prefetch(cdn.master, 1, 3); // ~120 KB more
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final total = dir
        .listSync()
        .whereType<File>()
        .fold<int>(0, (s, f) => s + f.lengthSync());
    expect(total, lessThanOrEqualTo(100000));
  });

  test('real HLS ladder plays through the proxy (ffmpeg)', () async {
    final hls = await Directory.systemTemp.createTemp('reel_hls');
    // Same ladder code the Cloud Run worker uses.
    final node = await Process.run('node', [
      '-e',
      '''
const {execFileSync}=require("child_process");
const L=require(process.argv[1]+"/reels_worker/ladder.js");
const out=process.argv[2]; const input=out+"/in.mp4";
execFileSync("ffmpeg",["-loglevel","error","-y","-f","lavfi","-i","testsrc2=size=720x1280:rate=30:duration=6","-f","lavfi","-i","sine=duration=6","-shortest",input]);
execFileSync("ffmpeg",["-loglevel","error",...L.buildHlsArgs(input,out,L.chooseRungs(720,1280),true,30)]);
''',
      Directory.current.path,
      hls.path,
    ]);
    if (node.exitCode != 0) {
      markTestSkipped('node/ffmpeg unavailable: ${node.stderr}');
      return;
    }
    final static = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var cdnRequests = 0;
    static.listen((req) async {
      cdnRequests++;
      final f = File('${hls.path}${req.uri.path}');
      if (f.existsSync()) {
        await req.response.addStream(f.openRead());
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
    final master = 'http://127.0.0.1:${static.port}/master.m3u8';
    await cache.prefetch(master, 0, 1);
    final variant = (await cache.resolveVariant(master, 0))!;

    Future<ProcessResult> play() => Process.run('ffmpeg', [
          '-v', 'error', '-i', cache.playbackUrl(variant), '-f', 'null', '-',
        ]);
    final first = await play();
    expect(first.exitCode, 0, reason: '${first.stderr}');
    final afterFirst = cdnRequests;
    // Second play is fully served from disk: no new CDN requests.
    final second = await play();
    expect(second.exitCode, 0, reason: '${second.stderr}');
    expect(cdnRequests, afterFirst);

    await static.close(force: true);
    await hls.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('non-matching URLs are passed through untouched', () {
    const signed = 'http://example.com/a.m3u8?token=abc';
    expect(cache.playbackUrl(signed), signed);
    expect(cache.playbackUrl('https://example.com/a.m3u8'), 'https://example.com/a.m3u8');
  });
}

