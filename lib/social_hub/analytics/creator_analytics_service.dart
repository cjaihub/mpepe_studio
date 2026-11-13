import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../backend/connections/linked_accounts.dart';
import '../../youtube_manager/services/youtube_account_store.dart';

/// Where a report comes from. Oneova is always there for a signed-in person;
/// the rest need a linked account (Connected accounts).
enum AnalyticsSource {
  oneova('Oneova', Icons.play_circle_fill_rounded, null),
  youtube('YouTube', Icons.smart_display_rounded, LinkedPlatform.youtube),
  tiktok('TikTok', Icons.music_note_rounded, LinkedPlatform.tiktok),
  instagram('Instagram', Icons.camera_alt_rounded, LinkedPlatform.instagram),
  facebook('Facebook', Icons.facebook_rounded, LinkedPlatform.facebook);

  const AnalyticsSource(this.label, this.icon, this.platform);
  final String label;
  final IconData icon;
  final LinkedPlatform? platform;

  static AnalyticsSource? of(LinkedPlatform p) {
    for (final s in values) {
      if (s.platform == p) return s;
    }
    return null;
  }
}

/// Every platform the Analytics screen lists, in display order. Add a row
/// here when a new integration lands: give it a [source] once its stats can
/// be fetched, a [platform] once it can be linked.
class AnalyticsPlatformInfo {
  final String label;
  final IconData icon;

  /// Linkable in Connected accounts today.
  final LinkedPlatform? platform;

  /// Stats this screen can load. Null: shown as "coming soon".
  final AnalyticsSource? source;

  /// Shown when [source] is null.
  final String note;

  const AnalyticsPlatformInfo(this.label, this.icon, {this.platform, this.source, this.note = ''});

  bool get hasAnalytics => source != null;
}

final analyticsPlatforms = <AnalyticsPlatformInfo>[
  const AnalyticsPlatformInfo('YouTube', Icons.smart_display_rounded,
      platform: LinkedPlatform.youtube, source: AnalyticsSource.youtube),
  const AnalyticsPlatformInfo('TikTok', Icons.music_note_rounded,
      platform: LinkedPlatform.tiktok, source: AnalyticsSource.tiktok),
  const AnalyticsPlatformInfo('Instagram', Icons.camera_alt_rounded,
      platform: LinkedPlatform.instagram, source: AnalyticsSource.instagram),
  const AnalyticsPlatformInfo('Facebook', Icons.facebook_rounded,
      platform: LinkedPlatform.facebook, source: AnalyticsSource.facebook),
  const AnalyticsPlatformInfo('WhatsApp Business', Icons.chat_rounded,
      platform: LinkedPlatform.whatsapp,
      note: 'Message analytics need your WhatsApp Business account, coming soon.'),
  const AnalyticsPlatformInfo('Telegram', Icons.send_rounded, note: 'Telegram isn\'t connected to Oneova yet. Coming soon.'),
];

enum SourceState { ready, needsReconnect, error }

/// The period being looked at, ending today, plus the one before it for
/// change badges.
class AnalyticsWindow {
  AnalyticsWindow(this.days, {DateTime? now}) {
    final n = now ?? DateTime.now();
    end = DateTime(n.year, n.month, n.day);
    start = end.subtract(Duration(days: days - 1));
    prevEnd = start.subtract(const Duration(days: 1));
    prevStart = prevEnd.subtract(Duration(days: days - 1));
  }

  final int days;
  late final DateTime start, end, prevStart, prevEnd;

  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end.add(const Duration(days: 1)));
  bool inPrevious(DateTime t) => !t.isBefore(prevStart) && t.isBefore(start);

  List<DateTime> get daysList => [for (var i = 0; i < days; i++) start.add(Duration(days: i))];

  static DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);
}

class AudienceSlice {
  final String label;

  /// Percent of the audience, 0–100.
  final double share;
  const AudienceSlice(this.label, this.share);
}

/// One post or video with its lifetime counts (YouTube: counts inside the
/// period). Null means the platform doesn't report that number.
class ContentStat {
  final AnalyticsSource source;
  final String id;
  final String title;
  final String thumbnailUrl;
  final DateTime? publishedAt;
  final int? views;
  final int likes;
  final int comments;
  final int shares;
  final double? watchHours;

  /// In-app route (Oneova posts) or external link.
  final String? route;
  final String? url;

  const ContentStat({
    required this.source,
    required this.id,
    required this.title,
    this.thumbnailUrl = '',
    this.publishedAt,
    this.views,
    this.likes = 0,
    this.comments = 0,
    this.shares = 0,
    this.watchHours,
    this.route,
    this.url,
  });

  int get engagement => likes + comments + shares;
}

/// Everything one account reports for an [AnalyticsWindow].
class SourceReport {
  final AnalyticsSource source;
  final String accountId;
  final SourceState state;
  final String message;
  final String accountName;
  final String avatarUrl;

  final int? followers;
  final int? followersGained;

  /// Views (or reach, see [viewsLabel]) in the period. For platforms that only
  /// give lifetime counts per post this is the total for posts published in
  /// the period ([activityTrend] false).
  final int? views;
  final int? prevViews;
  final String viewsLabel;
  final int? likes;
  final int? comments;
  final int? shares;
  final int? prevEngagement;
  final int? posts;
  final double? watchHours;
  final double? revenue;
  final String currency;

  final Map<DateTime, int> dailyViews;
  final Map<DateTime, int> dailyEngagement;

  /// True when the daily series is activity on that day; false when it is
  /// totals of posts published that day.
  final bool activityTrend;

  final List<ContentStat> content;
  final List<AudienceSlice> ages;
  final List<AudienceSlice> genders;
  final List<AudienceSlice> countries;
  final String audienceNote;
  final DateTime fetchedAt;

  SourceReport({
    required this.source,
    required this.accountId,
    this.state = SourceState.ready,
    this.message = '',
    this.accountName = '',
    this.avatarUrl = '',
    this.followers,
    this.followersGained,
    this.views,
    this.prevViews,
    this.viewsLabel = 'Views',
    this.likes,
    this.comments,
    this.shares,
    this.prevEngagement,
    this.posts,
    this.watchHours,
    this.revenue,
    this.currency = 'USD',
    this.dailyViews = const {},
    this.dailyEngagement = const {},
    this.activityTrend = false,
    this.content = const [],
    this.ages = const [],
    this.genders = const [],
    this.countries = const [],
    this.audienceNote = '',
    DateTime? fetchedAt,
  }) : fetchedAt = fetchedAt ?? DateTime.now();

  factory SourceReport.failed(AnalyticsSource source, String accountId, SourceState state, String message,
          {String accountName = ''}) =>
      SourceReport(source: source, accountId: accountId, state: state, message: message, accountName: accountName);

  bool get isReady => state == SourceState.ready;

  int? get engagement {
    if (likes == null && comments == null && shares == null) return null;
    return (likes ?? 0) + (comments ?? 0) + (shares ?? 0);
  }
}

/// What to fetch: one account of one platform for a number of days. A record
/// so the family caches per account and refetches only when the link changes.
typedef AnalyticsQuery = ({AnalyticsSource source, String accountId, int days});

class AnalyticsAuthException implements Exception {
  final String message;
  const AnalyticsAuthException(this.message);
  @override
  String toString() => message;
}

final creatorAnalyticsProvider = FutureProvider.autoDispose.family<SourceReport, AnalyticsQuery>((ref, q) async {
  // Keep results while the screen is open and for a short while after, so
  // switching filters back and forth doesn't call the APIs again.
  final link = ref.keepAlive();
  Future<void>.delayed(const Duration(minutes: 10), link.close);
  final w = AnalyticsWindow(q.days);
  try {
    switch (q.source) {
      case AnalyticsSource.oneova:
        return await CreatorAnalyticsService.oneova(w);
      case AnalyticsSource.youtube:
        return await CreatorAnalyticsService.youtube(
            w, q.accountId, ref.read(ytAccountStoreProvider.notifier).getAuthClientForAccount);
      case AnalyticsSource.tiktok:
        return await CreatorAnalyticsService.tiktok(w, q.accountId);
      case AnalyticsSource.instagram:
        return await CreatorAnalyticsService.instagram(w, q.accountId);
      case AnalyticsSource.facebook:
        return await CreatorAnalyticsService.facebook(w, q.accountId);
    }
  } on AnalyticsAuthException catch (e) {
    return SourceReport.failed(q.source, q.accountId, SourceState.needsReconnect, e.message);
  } catch (e) {
    debugPrint('[analytics] ${q.source.name}: $e');
    return SourceReport.failed(q.source, q.accountId, SourceState.error, _friendly(e));
  }
});

String _friendly(Object e) {
  if (e is FirebaseFunctionsException) return e.message ?? 'Couldn\'t load right now. Pull to retry.';
  final s = e.toString();
  if (s.contains('SocketException') || s.contains('Failed host lookup')) return 'You\'re offline. Pull to retry.';
  return s.replaceFirst('Exception: ', '');
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

DateTime? _time(Object? v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v)?.toLocal();
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  return null;
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _firstLine(String s, String fallback) {
  final t = s.trim().split('\n').first.trim();
  if (t.isEmpty) return fallback;
  return t.length > 90 ? '${t.substring(0, 90)}…' : t;
}

/// Totals for posts published in the window and the one before, plus a per
/// publish-day series. Used where platforms only give lifetime counts.
class _PublishTotals {
  int views = 0, likes = 0, comments = 0, shares = 0, posts = 0;
  int prevViews = 0, prevEng = 0;
  bool anyViews = false;
  final dailyViews = <DateTime, int>{};
  final dailyEng = <DateTime, int>{};
  final inRange = <ContentStat>[];

  void add(ContentStat c, AnalyticsWindow w) {
    final t = c.publishedAt;
    if (t == null) return;
    if (w.contains(t)) {
      posts++;
      likes += c.likes;
      comments += c.comments;
      shares += c.shares;
      if (c.views != null) {
        anyViews = true;
        views += c.views!;
      }
      final d = AnalyticsWindow.dayOf(t);
      dailyViews[d] = (dailyViews[d] ?? 0) + (c.views ?? 0);
      dailyEng[d] = (dailyEng[d] ?? 0) + c.engagement;
      inRange.add(c);
    } else if (w.inPrevious(t)) {
      prevViews += c.views ?? 0;
      prevEng += c.engagement;
    }
  }
}

class CreatorAnalyticsService {
  CreatorAnalyticsService._();

  static final _db = FirebaseFirestore.instance;
  static const _graph = 'https://graph.facebook.com/v22.0';

  static String get _uid {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw const AnalyticsAuthException('Sign in to see your analytics.');
    return uid;
  }

  // ── Oneova ──────────────────────────────────────────────────────────────

  static Future<SourceReport> oneova(AnalyticsWindow w) async {
    final uid = _uid;
    final results = await Future.wait([
      _db.collection('users').doc(uid).get(),
      _db.collection('content').where('authorId', isEqualTo: uid).limit(500).get(),
    ]);
    final user = (results[0] as DocumentSnapshot<Map<String, dynamic>>).data() ?? const {};
    final docs = (results[1] as QuerySnapshot<Map<String, dynamic>>).docs;

    int pick(Map<String, dynamic> d, List<String> keys) {
      for (final k in keys) {
        if (d[k] is num) return (d[k] as num).toInt();
      }
      return 0;
    }

    final totals = _PublishTotals();
    for (final doc in docs) {
      final d = doc.data();
      final meta = d['mediaMetadata'] is Map ? Map<String, dynamic>.from(d['mediaMetadata'] as Map) : const {};
      final type = (d['type'] ?? '').toString();
      final thumb = (meta['thumbnailUrl'] ?? d['thumbnailUrl'] ?? (type == 'photo' ? d['mediaUrl'] : '') ?? '').toString();
      totals.add(
        ContentStat(
          source: AnalyticsSource.oneova,
          id: doc.id,
          title: _firstLine((d['description'] ?? d['caption'] ?? d['title'] ?? '').toString(), 'Untitled post'),
          thumbnailUrl: thumb,
          publishedAt: _time(d['createdAt']),
          views: pick(d, const ['viewCount', 'views']),
          likes: pick(d, const ['likeCount', 'likesCount']),
          comments: pick(d, const ['commentCount', 'commentsCount']),
          shares: pick(d, const ['shareCount']) + pick(d, const ['repostCount']),
          route: '/post/${doc.id}',
        ),
        w,
      );
    }

    return SourceReport(
      source: AnalyticsSource.oneova,
      accountId: uid,
      accountName: (user['displayName'] ?? user['username'] ?? 'You').toString(),
      avatarUrl: (user['photoUrl'] ?? user['avatarUrl'] ?? user['profileImageUrl'] ?? '').toString(),
      followers: pick(user, const ['followers', 'followersCount', 'followerCount']),
      views: totals.views,
      prevViews: totals.prevViews,
      likes: totals.likes,
      comments: totals.comments,
      shares: totals.shares,
      prevEngagement: totals.prevEng,
      posts: totals.posts,
      dailyViews: totals.dailyViews,
      dailyEngagement: totals.dailyEng,
      content: totals.inRange,
      audienceNote: 'Oneova doesn\'t break down your audience yet.',
    );
  }

  // ── YouTube (Analytics API v2 + Data API v3) ────────────────────────────

  static Future<SourceReport> youtube(
    AnalyticsWindow w,
    String googleId,
    Future<http.Client?> Function(String googleId) clientFor,
  ) async {
    final uid = _uid;
    final client = await clientFor(googleId);
    if (client == null) {
      throw const AnalyticsAuthException('Reconnect YouTube to load your channel stats.');
    }
    try {
      final acct = (await _db.collection('users').doc(uid).collection('youtube_accounts').doc(googleId).get()).data();
      final channels = (acct?['channels'] as List? ?? const []).whereType<Map>().toList();
      final ch = channels.where((c) => c['isActive'] == true).firstOrNull ?? channels.firstOrNull;
      final channelId = (ch?['id'] ?? '').toString();
      final ids = channelId.isEmpty ? 'channel==MINE' : 'channel==$channelId';

      Future<List<Map<String, dynamic>>> report(Map<String, String> p, {DateTime? from, DateTime? to}) =>
          _ytReport(client, {'ids': ids, 'startDate': _ymd(from ?? w.start), 'endDate': _ymd(to ?? w.end), ...p});

      const core = 'views,estimatedMinutesWatched,likes,comments,shares,subscribersGained,subscribersLost';
      final f = await Future.wait<Object?>([
        report({'metrics': core, 'dimensions': 'day', 'sort': 'day'}),
        report({'metrics': 'views,likes,comments,shares'}, from: w.prevStart, to: w.prevEnd),
        report({
          'metrics': 'views,likes,comments,shares,estimatedMinutesWatched',
          'dimensions': 'video',
          'sort': '-views',
          'maxResults': '20',
        }),
        report({'metrics': 'viewerPercentage', 'dimensions': 'ageGroup,gender'}).catchError((Object _) => <Map<String, dynamic>>[]),
        report({'metrics': 'views', 'dimensions': 'country', 'sort': '-views', 'maxResults': '8'})
            .catchError((Object _) => <Map<String, dynamic>>[]),
        // Only monetized channels with the monetary scope get this.
        report({'metrics': 'estimatedRevenue'}).then<Object?>((r) => r).catchError((Object _) => null),
        _getJson(client, Uri.https('www.googleapis.com', '/youtube/v3/channels', {
          'part': 'snippet,statistics',
          if (channelId.isEmpty) 'mine': 'true' else 'id': channelId,
        })),
      ]);

      final daily = f[0] as List<Map<String, dynamic>>;
      final prev = f[1] as List<Map<String, dynamic>>;
      final top = f[2] as List<Map<String, dynamic>>;
      final ageGender = f[3] as List<Map<String, dynamic>>;
      final countries = f[4] as List<Map<String, dynamic>>;
      final revenueRows = f[5] as List<Map<String, dynamic>>?;
      final chItem = ((f[6] as Map<String, dynamic>)['items'] as List? ?? const []).whereType<Map>().firstOrNull;

      var views = 0, minutes = 0, likes = 0, comments = 0, shares = 0, gained = 0, lost = 0;
      final dv = <DateTime, int>{}, de = <DateTime, int>{};
      for (final r in daily) {
        final day = DateTime.tryParse('${r['day']}');
        final v = _int(r['views']);
        final e = _int(r['likes']) + _int(r['comments']) + _int(r['shares']);
        views += v;
        minutes += _int(r['estimatedMinutesWatched']);
        likes += _int(r['likes']);
        comments += _int(r['comments']);
        shares += _int(r['shares']);
        gained += _int(r['subscribersGained']);
        lost += _int(r['subscribersLost']);
        if (day != null) {
          dv[day] = v;
          de[day] = e;
        }
      }
      final p = prev.firstOrNull ?? const {};

      // Titles and thumbnails for the top videos.
      final videoIds = [for (final r in top) '${r['video']}'];
      final snippets = <String, Map>{};
      if (videoIds.isNotEmpty) {
        final v = await _getJson(client, Uri.https('www.googleapis.com', '/youtube/v3/videos', {
          'part': 'snippet',
          'id': videoIds.join(','),
          'maxResults': '50',
        }));
        for (final it in (v['items'] as List? ?? const []).whereType<Map>()) {
          snippets['${it['id']}'] = (it['snippet'] as Map?) ?? const {};
        }
      }
      final content = [
        for (final r in top)
          ContentStat(
            source: AnalyticsSource.youtube,
            id: '${r['video']}',
            title: _firstLine('${snippets['${r['video']}']?['title'] ?? ''}', 'YouTube video'),
            thumbnailUrl: '${(snippets['${r['video']}']?['thumbnails'] as Map?)?['medium']?['url'] ?? ''}',
            publishedAt: _time(snippets['${r['video']}']?['publishedAt']),
            views: _int(r['views']),
            likes: _int(r['likes']),
            comments: _int(r['comments']),
            shares: _int(r['shares']),
            watchHours: _int(r['estimatedMinutesWatched']) / 60,
            url: 'https://youtu.be/${r['video']}',
          ),
      ];

      final ages = <String, double>{}, genders = <String, double>{};
      for (final r in ageGender) {
        final pct = (r['viewerPercentage'] as num?)?.toDouble() ?? 0;
        final a = '${r['ageGroup']}'.replaceFirst('age', '').replaceAll('-', '–');
        final g = switch ('${r['gender']}') { 'female' => 'Female', 'male' => 'Male', _ => 'Other' };
        ages[a] = (ages[a] ?? 0) + pct;
        genders[g] = (genders[g] ?? 0) + pct;
      }
      final countryViews = countries.fold<int>(0, (s, r) => s + _int(r['views']));
      final snippet = (chItem?['snippet'] as Map?) ?? const {};
      final stats = (chItem?['statistics'] as Map?) ?? const {};
      final revenue = revenueRows?.firstOrNull?['estimatedRevenue'];

      return SourceReport(
        source: AnalyticsSource.youtube,
        accountId: googleId,
        accountName: '${snippet['title'] ?? ch?['title'] ?? 'YouTube channel'}',
        avatarUrl: '${(snippet['thumbnails'] as Map?)?['default']?['url'] ?? ch?['thumbnailUrl'] ?? ''}',
        followers: stats['hiddenSubscriberCount'] == true ? null : _int(stats['subscriberCount']),
        followersGained: gained - lost,
        views: views,
        prevViews: p.isEmpty ? null : _int(p['views']),
        likes: likes,
        comments: comments,
        shares: shares,
        prevEngagement: p.isEmpty ? null : _int(p['likes']) + _int(p['comments']) + _int(p['shares']),
        watchHours: minutes / 60,
        revenue: revenue is num ? revenue.toDouble() : null,
        dailyViews: dv,
        dailyEngagement: de,
        activityTrend: true,
        content: content,
        ages: _sorted(ages, byLabel: true),
        genders: _sorted(genders),
        countries: [
          if (countryViews > 0)
            for (final r in countries) AudienceSlice(_flag('${r['country']}'), _int(r['views']) * 100 / (views == 0 ? countryViews : views)),
        ],
        audienceNote: ages.isEmpty ? 'YouTube shares age and gender once a channel has enough views.' : '',
      );
    } finally {
      client.close();
    }
  }

  static Future<List<Map<String, dynamic>>> _ytReport(http.Client c, Map<String, String> params) async {
    final body = await _getJson(c, Uri.https('youtubeanalytics.googleapis.com', '/v2/reports', params));
    final cols = [for (final h in (body['columnHeaders'] as List? ?? const []).whereType<Map>()) '${h['name']}'];
    return [
      for (final row in (body['rows'] as List? ?? const []).whereType<List>())
        {for (var i = 0; i < cols.length && i < row.length; i++) cols[i]: row[i]},
    ];
  }

  static Future<Map<String, dynamic>> _getJson(http.Client c, Uri uri) async {
    final res = await c.get(uri);
    final Object? decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    final body = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    if (res.statusCode == 200) return body;
    final msg = '${(body['error'] as Map?)?['message'] ?? 'HTTP ${res.statusCode}'}';
    if (res.statusCode == 401 || (res.statusCode == 403 && msg.toLowerCase().contains('insufficient'))) {
      throw const AnalyticsAuthException('Reconnect YouTube and allow channel analytics.');
    }
    throw Exception(msg);
  }

  // ── TikTok (server callables, tokens stay on the server) ────────────────

  static Future<SourceReport> tiktok(AnalyticsWindow w, String openId) async {
    final fn = FirebaseFunctions.instance;
    try {
      final profile = Map<String, dynamic>.from(
          ((await fn.httpsCallable('tiktokProfile').call()).data as Map?)?['account'] as Map? ?? const {});
      final totals = _PublishTotals();
      Object? cursor;
      for (var page = 0; page < 5; page++) {
        final r = Map<String, dynamic>.from(
            (await fn.httpsCallable('tiktokVideos').call({'cursor': ?cursor})).data as Map? ?? const {});
        final videos = (r['videos'] as List? ?? const []).whereType<Map>().toList();
        DateTime? oldest;
        for (final v in videos) {
          final t = DateTime.fromMillisecondsSinceEpoch(_int(v['create_time']) * 1000);
          oldest = t;
          totals.add(
            ContentStat(
              source: AnalyticsSource.tiktok,
              id: '${v['id']}',
              title: _firstLine('${v['title'] ?? ''}'.isNotEmpty ? '${v['title']}' : '${v['video_description'] ?? ''}',
                  'TikTok video'),
              thumbnailUrl: '${v['cover_image_url'] ?? ''}',
              publishedAt: t,
              views: _int(v['view_count']),
              likes: _int(v['like_count']),
              comments: _int(v['comment_count']),
              shares: _int(v['share_count']),
              url: '${v['share_url'] ?? ''}'.isEmpty ? null : '${v['share_url']}',
            ),
            w,
          );
        }
        cursor = r['cursor'];
        if (r['hasMore'] != true || cursor == null || (oldest != null && oldest.isBefore(w.prevStart))) break;
      }
      return SourceReport(
        source: AnalyticsSource.tiktok,
        accountId: openId,
        accountName: '${profile['displayName'] ?? profile['username'] ?? 'TikTok'}',
        avatarUrl: '${profile['avatarUrl'] ?? ''}',
        followers: _int(profile['followerCount']),
        views: totals.views,
        prevViews: totals.prevViews,
        likes: totals.likes,
        comments: totals.comments,
        shares: totals.shares,
        prevEngagement: totals.prevEng,
        posts: totals.posts,
        dailyViews: totals.dailyViews,
        dailyEngagement: totals.dailyEng,
        content: totals.inRange,
        audienceNote: 'TikTok doesn\'t share audience details with other apps.',
      );
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unauthenticated' || e.code == 'failed-precondition' || e.code == 'permission-denied') {
        throw AnalyticsAuthException(e.message ?? 'Reconnect TikTok to load your stats.');
      }
      rethrow;
    }
  }

  // ── Meta (Graph API with the Page token kept on this phone) ─────────────

  static Future<(String id, String token)> _metaAuth(String platform, String accountId) async {
    final doc = await _db.collection('users').doc(_uid).collection('social_connections').doc(platform).get();
    final d = doc.data() ?? const {};
    final key = d['tokenKey'] as String?;
    final id = '${d['pageId'] ?? accountId}';
    final token = key == null ? null : await const FlutterSecureStorage().read(key: key);
    if (token == null || token.isEmpty) {
      throw AnalyticsAuthException(
          'Reconnect ${platform == 'instagram' ? 'Instagram' : 'Facebook'} on this phone to load its stats.');
    }
    return (id, token);
  }

  static Future<Map<String, dynamic>> _graphGet(String pathOrUrl, Map<String, String> q, String token) async {
    final uri = pathOrUrl.startsWith('http')
        ? Uri.parse(pathOrUrl)
        : Uri.parse('$_graph/$pathOrUrl').replace(queryParameters: {...q, 'access_token': token});
    final res = await http.get(uri);
    final Object? decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    final body = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    if (res.statusCode == 200) return body;
    final err = (body['error'] as Map?) ?? const {};
    if (err['code'] == 190) throw const AnalyticsAuthException('Your Meta login expired. Reconnect to load stats.');
    throw Exception('${err['message'] ?? 'Meta returned ${res.statusCode}'}');
  }

  /// Follows `paging.next` until posts are older than the previous window.
  static Future<List<Map>> _graphPages(String path, Map<String, String> q, String token, AnalyticsWindow w,
      String timeField) async {
    final out = <Map>[];
    String? next;
    for (var page = 0; page < 4; page++) {
      final r = await _graphGet(next ?? path, q, token);
      final items = (r['data'] as List? ?? const []).whereType<Map>().toList();
      out.addAll(items);
      final oldest = items.isEmpty ? null : _time(items.last[timeField]);
      next = (r['paging'] as Map?)?['next'] as String?;
      if (next == null || oldest == null || oldest.isBefore(w.prevStart)) break;
    }
    return out;
  }

  static Future<SourceReport> instagram(AnalyticsWindow w, String accountId) async {
    final (ig, token) = await _metaAuth('instagram', accountId);
    final profileF = _graphGet(ig, {'fields': 'username,name,profile_picture_url,followers_count,media_count'}, token);
    final mediaF = _graphPages(
        '$ig/media',
        {
          'fields': 'id,caption,media_type,thumbnail_url,media_url,permalink,timestamp,like_count,comments_count',
          'limit': '50',
        },
        token,
        w,
        'timestamp');
    final reachF = _igDaily(ig, token, 'reach', w.start, w.end).catchError((Object _) => <DateTime, int>{});
    final prevReachF = _igDaily(ig, token, 'reach', w.prevStart, w.prevEnd).catchError((Object _) => <DateTime, int>{});
    final ageF = _igDemographics(ig, token, 'age');
    final genderF = _igDemographics(ig, token, 'gender');
    final countryF = _igDemographics(ig, token, 'country');

    final profile = await profileF;
    final totals = _PublishTotals();
    for (final m in await mediaF) {
      final video = m['media_type'] == 'VIDEO';
      totals.add(
        ContentStat(
          source: AnalyticsSource.instagram,
          id: '${m['id']}',
          title: _firstLine('${m['caption'] ?? ''}', 'Instagram post'),
          thumbnailUrl: '${(video ? m['thumbnail_url'] : m['media_url']) ?? m['media_url'] ?? ''}',
          publishedAt: _time(m['timestamp']),
          likes: _int(m['like_count']),
          comments: _int(m['comments_count']),
          url: m['permalink'] as String?,
        ),
        w,
      );
    }
    final reach = await reachF;
    final prevReach = await prevReachF;
    final ages = await ageF, genders = await genderF, countries = await countryF;

    return SourceReport(
      source: AnalyticsSource.instagram,
      accountId: ig,
      accountName: '${profile['username'] ?? profile['name'] ?? 'Instagram'}',
      avatarUrl: '${profile['profile_picture_url'] ?? ''}',
      followers: _int(profile['followers_count']),
      views: reach.isEmpty ? null : reach.values.fold<int>(0, (a, b) => a + b),
      prevViews: prevReach.isEmpty ? null : prevReach.values.fold<int>(0, (a, b) => a + b),
      viewsLabel: 'Reach',
      likes: totals.likes,
      comments: totals.comments,
      prevEngagement: totals.prevEng,
      posts: totals.posts,
      dailyViews: reach,
      dailyEngagement: totals.dailyEng,
      activityTrend: reach.isNotEmpty,
      content: totals.inRange,
      ages: ages,
      genders: genders.map((s) => AudienceSlice(switch (s.label) { 'F' => 'Female', 'M' => 'Male', _ => 'Other' }, s.share)).toList(),
      countries: countries.map((s) => AudienceSlice(_flag(s.label), s.share)).toList(),
      audienceNote: ages.isEmpty ? 'Instagram shares follower details once an account has 100+ followers.' : '',
    );
  }

  /// Daily values of an account metric; Meta allows at most 30 days per call.
  static Future<Map<DateTime, int>> _igDaily(String ig, String token, String metric, DateTime from, DateTime to) async {
    final out = <DateTime, int>{};
    final calls = <Future<Map<String, dynamic>>>[];
    for (var s = from; !s.isAfter(to); s = s.add(const Duration(days: 30))) {
      var e = s.add(const Duration(days: 30));
      final cap = to.add(const Duration(days: 1));
      if (e.isAfter(cap)) e = cap;
      calls.add(_graphGet('$ig/insights', {
        'metric': metric,
        'period': 'day',
        'since': '${s.millisecondsSinceEpoch ~/ 1000}',
        'until': '${e.millisecondsSinceEpoch ~/ 1000}',
      }, token));
    }
    for (final r in await Future.wait(calls)) {
      final series = (r['data'] as List? ?? const []).whereType<Map>().firstOrNull;
      for (final v in (series?['values'] as List? ?? const []).whereType<Map>()) {
        final t = _time(v['end_time']);
        if (t == null) continue;
        // end_time marks the end of the day the value covers.
        out[AnalyticsWindow.dayOf(t.subtract(const Duration(hours: 12)))] = _int(v['value']);
      }
    }
    return out;
  }

  static Future<List<AudienceSlice>> _igDemographics(String ig, String token, String breakdown) async {
    try {
      final r = await _graphGet('$ig/insights', {
        'metric': 'follower_demographics',
        'period': 'lifetime',
        'metric_type': 'total_value',
        'breakdown': breakdown,
      }, token);
      final series = (r['data'] as List? ?? const []).whereType<Map>().firstOrNull;
      final bd = ((series?['total_value'] as Map?)?['breakdowns'] as List? ?? const []).whereType<Map>().firstOrNull;
      final counts = <String, double>{};
      for (final x in (bd?['results'] as List? ?? const []).whereType<Map>()) {
        final label = '${(x['dimension_values'] as List? ?? const []).firstOrNull ?? ''}';
        if (label.isEmpty) continue;
        counts[label] = (counts[label] ?? 0) + _int(x['value']);
      }
      final total = counts.values.fold<double>(0, (a, b) => a + b);
      if (total <= 0) return const [];
      final pct = {for (final e in counts.entries) e.key.replaceAll('-', '–'): e.value * 100 / total};
      final list = _sorted(pct, byLabel: breakdown == 'age');
      return breakdown == 'country' ? list.take(8).toList() : list;
    } catch (e) {
      return const [];
    }
  }

  static Future<SourceReport> facebook(AnalyticsWindow w, String accountId) async {
    final (page, token) = await _metaAuth('facebook', accountId);
    final infoF = _graphGet(page, {'fields': 'name,fan_count,followers_count,picture{url}'}, token);
    final posts = await _graphPages(
        '$page/posts',
        {
          'fields': 'id,message,created_time,full_picture,permalink_url,shares,'
              'reactions.summary(total_count).limit(0),comments.summary(total_count).limit(0)',
          'limit': '50',
        },
        token,
        w,
        'created_time');
    final info = await infoF;
    final totals = _PublishTotals();
    for (final p in posts) {
      totals.add(
        ContentStat(
          source: AnalyticsSource.facebook,
          id: '${p['id']}',
          title: _firstLine('${p['message'] ?? ''}', 'Facebook post'),
          thumbnailUrl: '${p['full_picture'] ?? ''}',
          publishedAt: _time(p['created_time']),
          likes: _int(((p['reactions'] as Map?)?['summary'] as Map?)?['total_count']),
          comments: _int(((p['comments'] as Map?)?['summary'] as Map?)?['total_count']),
          shares: _int((p['shares'] as Map?)?['count']),
          url: p['permalink_url'] as String?,
        ),
        w,
      );
    }
    return SourceReport(
      source: AnalyticsSource.facebook,
      accountId: page,
      accountName: '${info['name'] ?? 'Facebook Page'}',
      avatarUrl: '${((info['picture'] as Map?)?['data'] as Map?)?['url'] ?? ''}',
      followers: info['followers_count'] is num ? _int(info['followers_count']) : _int(info['fan_count']),
      likes: totals.likes,
      comments: totals.comments,
      shares: totals.shares,
      prevEngagement: totals.prevEng,
      posts: totals.posts,
      dailyEngagement: totals.dailyEng,
      content: totals.inRange,
      audienceNote: 'Facebook Page reach and audience need Page insights access, which Oneova doesn\'t ask for yet.',
    );
  }

  // ── helpers ─────────────────────────────────────────────────────────────

  static List<AudienceSlice> _sorted(Map<String, double> m, {bool byLabel = false}) {
    final list = [for (final e in m.entries) AudienceSlice(e.key, e.value)];
    list.sort(byLabel ? (a, b) => a.label.compareTo(b.label) : (a, b) => b.share.compareTo(a.share));
    return list;
  }

  /// "US" → "🇺🇸 US".
  static String _flag(String code) {
    final c = code.toUpperCase();
    if (c.length != 2 || !RegExp(r'^[A-Z]{2}$').hasMatch(c)) return c;
    final flag = String.fromCharCodes(c.codeUnits.map((u) => 0x1F1E6 + u - 65));
    return '$flag $c';
  }
}
