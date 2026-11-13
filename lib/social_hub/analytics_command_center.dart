import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';

import '../backend/connections/linked_accounts.dart';
import '../shared/audio/mic_coordinator.dart';
import '../shared/audio/speech_hub.dart';
import '../shared/theme/app_theme.dart';
import 'analytics/creator_analytics_service.dart';

/// Analytics for the person's Oneova posts and their linked accounts, in one
/// scrollable view: KPIs, trend, platform comparison, top content, audience.
/// Every number comes from Firestore or the platform's own API.
class AnalyticsCommandCenter extends ConsumerStatefulWidget {
  const AnalyticsCommandCenter({super.key});

  @override
  ConsumerState<AnalyticsCommandCenter> createState() => _AnalyticsCommandCenterState();
}

enum _Sort { views, engagement, likes, comments, newest }

enum _TrendMetric { views, engagement }

const _ranges = [(7, '7D'), (28, '28D'), (90, '90D'), (365, '1Y')];

class _AnalyticsCommandCenterState extends ConsumerState<AnalyticsCommandCenter> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  int _days = 28;
  final Set<AnalyticsSource> _only = {};
  _TrendMetric _trend = _TrendMetric.views;
  _Sort _sort = _Sort.views;
  bool _allContent = false;
  bool _listening = false;
  MicLease? _micLease;

  String get _q => _search.text.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    unawaited(SpeechHub.instance.cancel(this));
    unawaited(_micLease?.release());
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── Voice search ────────────────────────────────────────────────────────

  Future<void> _toggleVoice() async {
    if (_listening) return _stopVoice();
    HapticFeedback.lightImpact();
    PermissionStatus? mic;
    try {
      mic = await Permission.microphone.request();
    } catch (_) {}
    if (!mounted) return;
    if (mic != null && !mic.isGranted) {
      _snack(
        mic.isPermanentlyDenied ? 'Microphone is off for Oneova. Turn it on in Settings.' : 'Allow the microphone to search by voice.',
        action: mic.isPermanentlyDenied ? SnackBarAction(label: 'Settings', onPressed: openAppSettings) : null,
      );
      return;
    }
    final got = await MicCoordinator.instance.acquire(
      MicUser.voiceTyping,
      onPreempted: () async {
        _micLease = null;
        await _stopVoice(release: false);
      },
    );
    if (!mounted) {
      if (got is MicLease) await got.release();
      return;
    }
    if (got is MicBusy) return _snack(got.message);
    _micLease = got as MicLease;
    setState(() => _listening = true);
    final ok = await SpeechHub.instance.listen(
      owner: this,
      options: stt.SpeechListenOptions(partialResults: true, cancelOnError: true, listenMode: stt.ListenMode.search),
      onStatus: (s) {
        if (s == 'done' || s == 'notListening' || s == 'preempted') unawaited(_stopVoice());
      },
      onError: (_) => unawaited(_stopVoice()),
      onResult: (r) {
        if (!mounted || !_listening) return;
        _search.text = r.recognizedWords;
        _search.selection = TextSelection.collapsed(offset: _search.text.length);
        if (r.finalResult) unawaited(_stopVoice());
      },
    );
    if (!ok && mounted) {
      await _stopVoice();
      _snack('Voice search isn\'t available on this device.');
    }
  }

  Future<void> _stopVoice({bool release = true}) async {
    await SpeechHub.instance.cancel(this);
    if (release) {
      final l = _micLease;
      _micLease = null;
      await l?.release();
    }
    if (mounted && _listening) setState(() => _listening = false);
  }

  void _snack(String msg, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), action: action));
  }

  // ── Data ────────────────────────────────────────────────────────────────

  /// One query per account that can report, plus links that need fixing.
  (List<AnalyticsQuery>, List<LinkedAccount> broken, List<(AnalyticsPlatformInfo, bool linked)> more) _plan(
      List<LinkedAccount> accounts) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final queries = <AnalyticsQuery>[
      if (uid.isNotEmpty) (source: AnalyticsSource.oneova, accountId: uid, days: _days),
    ];
    final broken = <LinkedAccount>[];
    for (final a in accounts) {
      final s = AnalyticsSource.of(a.platform);
      if (s == null) continue;
      if (a.isUsable) {
        queries.add((source: s, accountId: a.accountId, days: _days));
      } else {
        broken.add(a);
      }
    }
    // Platforms with no stats here yet: not linked, or linked but no
    // analytics integration (WhatsApp), or not linkable at all (Telegram).
    final more = <(AnalyticsPlatformInfo, bool)>[
      for (final p in analyticsPlatforms)
        if (p.platform == null || !p.hasAnalytics || !accounts.any((a) => a.platform == p.platform))
          (p, p.platform != null && accounts.any((a) => a.platform == p.platform)),
    ];
    return (queries, broken, more);
  }

  Future<void> _refresh(List<AnalyticsQuery> queries) async {
    await Future.wait([
      for (final q in queries) ref.refresh(creatorAnalyticsProvider(q).future).then<void>((_) {}, onError: (_) {}),
    ]);
  }

  void _connect(LinkedPlatform p) {
    if (p == LinkedPlatform.youtube) {
      context.push('/social_hub/google');
      return;
    }
    final route = LinkedAccountsController.wizardRoute(p);
    context.push(route ?? '/social_hub');
  }

  Future<void> _open(ContentStat c) async {
    if (c.route != null) {
      context.push(c.route!);
    } else if (c.url != null) {
      final ok = await launchUrl(Uri.parse(c.url!), mode: LaunchMode.externalApplication);
      if (!ok && mounted) _snack('Couldn\'t open this ${c.source.label} link.');
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final linked = ref.watch(linkedAccountsProvider);
    final (queries, broken, more) = _plan(linked.value ?? const []);
    final results = [for (final q in queries) (q, ref.watch(creatorAnalyticsProvider(q)))];
    final loading = linked.isLoading || results.any((r) => r.$2.isLoading);
    final reports = [for (final r in results) ?r.$2.value];
    final ready = reports.where((r) => r.isReady).toList();
    final failed = reports.where((r) => !r.isReady).toList();
    // A picked platform that isn't loaded (yet) doesn't hide everything else.
    final active = _only.intersection({for (final r in ready) r.source});
    final shown = ready.where((r) => active.isEmpty || active.contains(r.source)).toList();
    final w = AnalyticsWindow(_days);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: _topBar(context, queries),
      body: RefreshIndicator(
        color: AppColors.brandBlue,
        onRefresh: () => _refresh(queries),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _FilterHeader(
                child: _filters(context, ready, active, loading, w),
                color: context.bg,
              ),
            ),
            if (FirebaseAuth.instance.currentUser == null)
              SliverFillRemaining(hasScrollBody: false, child: _empty(context, 'Sign in to see your analytics.'))
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 32),
                sliver: SliverList.list(children: _sections(context, shown, failed, broken, more, loading, w)),
              ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _topBar(BuildContext context, List<AnalyticsQuery> queries) {
    final fg = context.topBarFg;
    return AppBar(
      backgroundColor: context.topBarBg,
      foregroundColor: fg,
      toolbarHeight: 52,
      elevation: 0,
      titleSpacing: 0,
      leading: IconButton(
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => context.canPop() ? context.pop() : context.go('/social_hub'),
      ),
      title: SizedBox(
        height: 36,
        child: TextField(
          controller: _search,
          focusNode: _searchFocus,
          textInputAction: TextInputAction.search,
          cursorColor: fg,
          style: TextStyle(color: fg, fontSize: 13.5, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: fg.withValues(alpha: 0.14),
            hintText: _listening ? 'Listening…' : 'Search posts or metrics',
            hintStyle: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 13.5),
            prefixIcon: Icon(Icons.search_rounded, size: 19, color: fg.withValues(alpha: 0.85)),
            prefixIconConstraints: const BoxConstraints(minWidth: 36),
            suffixIcon: _search.text.isNotEmpty && !_listening
                ? IconButton(
                    tooltip: 'Clear',
                    icon: Icon(Icons.close_rounded, size: 18, color: fg),
                    onPressed: _search.clear,
                  )
                : IconButton(
                    tooltip: _listening ? 'Stop' : 'Search by voice',
                    icon: Icon(_listening ? Icons.graphic_eq_rounded : Icons.mic_rounded,
                        size: 19, color: _listening ? AppColors.brandPink : fg),
                    onPressed: _toggleVoice,
                  ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.full), borderSide: BorderSide.none),
          ),
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => _refresh(queries),
        ),
      ],
    );
  }

  Widget _filters(BuildContext context, List<SourceReport> ready, Set<AnalyticsSource> active, bool loading, AnalyticsWindow w) {
    final sources = {for (final r in ready) r.source}.toList()..sort((a, b) => a.index.compareTo(b.index));
    final df = DateFormat('MMM d');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: Row(
            children: [
              for (final (d, label) in _ranges)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _Pill(
                    label: label,
                    selected: _days == d,
                    onTap: () => setState(() {
                      _days = d;
                      _allContent = false;
                    }),
                  ),
                ),
              const Spacer(),
              Text('${df.format(w.start)} – ${df.format(w.end)}',
                  style: TextStyle(fontSize: 11, color: context.textMuted, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
            children: [
              _Pill(label: 'All', selected: active.isEmpty, onTap: () => setState(_only.clear)),
              for (final s in sources)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: _Pill(
                    label: s.label,
                    icon: s.icon,
                    dot: _sourceColor(context, s),
                    selected: active.contains(s),
                    onTap: () => setState(() => _only.contains(s) ? _only.remove(s) : _only.add(s)),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 2,
          child: loading
              ? const LinearProgressIndicator(minHeight: 2, color: AppColors.brandBlue, backgroundColor: Colors.transparent)
              : null,
        ),
      ],
    );
  }

  List<Widget> _sections(
    BuildContext context,
    List<SourceReport> shown,
    List<SourceReport> failed,
    List<LinkedAccount> broken,
    List<(AnalyticsPlatformInfo, bool)> more,
    bool loading,
    AnalyticsWindow w,
  ) {
    final q = _q;
    final kpis = _kpis(shown);
    final content = _content(shown, q);
    bool section(List<String> words) => q.isEmpty || words.any((k) => k.contains(q) || q.contains(k));

    final matchedKpis = q.isEmpty ? kpis : kpis.where((k) => k.matches(q)).toList();
    final showTrend = section(const ['trend', 'over time', 'growth', 'chart', 'daily', 'views', 'reach', 'engagement']);
    final showCompare = section(['compare', 'platform', 'comparison', for (final r in shown) r.source.label.toLowerCase()]);
    final showAudience = section(const ['audience', 'age', 'gender', 'country', 'countries', 'demographic', 'viewers', 'followers']);
    final showContent = q.isEmpty || content.isNotEmpty;

    final out = <Widget>[
      if (failed.isNotEmpty || broken.isNotEmpty) _issues(context, failed, broken),
    ];
    if (shown.isEmpty) {
      out.add(loading ? _skeleton(context) : _empty(context, 'Nothing to show for this period yet.'));
    } else {
      if (matchedKpis.isNotEmpty) out.add(_kpiGrid(context, matchedKpis));
      if (showTrend) out.add(_trendCard(context, shown, w));
      if (showCompare && shown.length > 1) out.add(_compareCard(context, shown));
      if (showContent) out.add(_contentCard(context, content, q));
      if (showAudience) out.add(_audienceCard(context, shown));
      if (q.isNotEmpty && matchedKpis.isEmpty && !showTrend && !showCompare && !showAudience && content.isEmpty) {
        out.add(_empty(context, 'No posts or metrics match "${_search.text.trim()}".'));
      }
    }
    if (more.isNotEmpty && q.isEmpty) out.add(_connectCard(context, more));
    return [
      for (final wd in out) Padding(padding: const EdgeInsets.only(top: 12), child: wd),
    ];
  }

  // ── KPIs ────────────────────────────────────────────────────────────────

  List<_Kpi> _kpis(List<SourceReport> rs) {
    int? sum(int? Function(SourceReport) f) {
      final v = [for (final r in rs) ?f(r)];
      return v.isEmpty ? null : v.fold<int>(0, (a, b) => a + b);
    }

    double? change(int? Function(SourceReport) cur, int? Function(SourceReport) prev) {
      var c = 0, p = 0, any = false;
      for (final r in rs) {
        final a = cur(r), b = prev(r);
        if (a == null || b == null) continue;
        any = true;
        c += a;
        p += b;
      }
      if (!any) return null;
      if (p == 0) return c == 0 ? 0 : double.infinity;
      return (c - p) * 100 / p;
    }

    int? viewsOf(SourceReport r) => r.viewsLabel == 'Views' ? r.views : null;
    int? prevViewsOf(SourceReport r) => r.viewsLabel == 'Views' ? r.prevViews : null;
    int? reachOf(SourceReport r) => r.viewsLabel == 'Reach' ? r.views : null;

    final followers = sum((r) => r.followers);
    final gained = sum((r) => r.followersGained);
    final views = sum(viewsOf);
    final reach = sum(reachOf);
    final eng = sum((r) => r.engagement);
    // Rate only from accounts that report both numbers.
    final rateViews = sum((r) => r.engagement == null ? null : viewsOf(r));
    final rateEng = sum((r) => viewsOf(r) == null ? null : r.engagement);
    final watch = rs.where((r) => r.watchHours != null).fold<double?>(null, (a, r) => (a ?? 0) + r.watchHours!);
    final revenue = rs.where((r) => r.revenue != null).fold<double?>(null, (a, r) => (a ?? 0) + r.revenue!);
    final posts = sum((r) => r.posts);
    final youtubeOnly = rs.every((r) => r.source == AnalyticsSource.youtube);

    return [
      if (followers != null)
        _Kpi('Followers', _compact(followers), Icons.people_alt_rounded,
            note: gained == null ? null : '${gained >= 0 ? '+' : ''}${_compact(gained)} subs', keys: const ['subscribers', 'fans']),
      if (views != null)
        _Kpi('Views', _compact(views), Icons.visibility_rounded,
            change: change(viewsOf, prevViewsOf), keys: const ['plays', 'watch']),
      if (reach != null)
        _Kpi('Reach', _compact(reach), Icons.radar_rounded,
            change: change(reachOf, (r) => r.viewsLabel == 'Reach' ? r.prevViews : null), keys: const ['instagram', 'accounts reached']),
      if (eng != null)
        _Kpi('Engagement', _compact(eng), Icons.favorite_rounded,
            change: change((r) => r.engagement, (r) => r.prevEngagement), keys: const ['likes', 'comments', 'shares', 'interactions']),
      if (rateViews != null && rateViews > 0 && rateEng != null)
        _Kpi('Engagement rate', '${(rateEng * 100 / rateViews).toStringAsFixed(1)}%', Icons.percent_rounded,
            keys: const ['rate', 'ratio']),
      if (watch != null) _Kpi('Watch time', '${_compact(watch.round())} h', Icons.schedule_rounded, keys: const ['hours', 'minutes', 'youtube']),
      if (posts != null && !youtubeOnly) _Kpi('Posts', _compact(posts), Icons.grid_view_rounded, keys: const ['published', 'uploads', 'videos']),
      if (revenue != null)
        _Kpi('Est. revenue', NumberFormat.simpleCurrency(name: rs.firstWhere((r) => r.revenue != null).currency).format(revenue),
            Icons.payments_rounded, keys: const ['money', 'earnings', 'income', 'monetization']),
    ];
  }

  Widget _kpiGrid(BuildContext context, List<_Kpi> kpis) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 600 ? 4 : 2;
      final tileW = (c.maxWidth - 8 * (cols - 1)) / cols;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final k in kpis) SizedBox(width: tileW, child: _KpiTile(k))],
      );
    });
  }

  // ── Trend ───────────────────────────────────────────────────────────────

  Widget _trendCard(BuildContext context, List<SourceReport> rs, AnalyticsWindow w) {
    final metric = _trend;
    final days = w.daysList;
    final bucket = w.days > 90 ? 7 : 1;
    final buckets = <DateTime>[for (var i = 0; i < days.length; i += bucket) days[i]];

    final series = <(SourceReport, List<double>)>[];
    for (final r in rs) {
      final m = metric == _TrendMetric.views ? r.dailyViews : r.dailyEngagement;
      if (m.isEmpty) continue;
      final vals = <double>[];
      for (var i = 0; i < days.length; i += bucket) {
        var s = 0;
        for (var j = i; j < math.min(i + bucket, days.length); j++) {
          s += m[days[j]] ?? 0;
        }
        vals.add(s.toDouble());
      }
      series.add((r, vals));
    }
    final maxY = series.fold<double>(0, (a, s) => math.max(a, s.$2.fold<double>(0, math.max)));
    final byPublish = {
      for (final s in series)
        if (!s.$1.activityTrend) s.$1.source.label,
    };
    final df = DateFormat(w.days > 90 ? 'MMM' : 'MMM d');
    final labelEvery = math.max(1, (buckets.length / 4).ceil());

    return _Card(
      title: 'Trend',
      trailing: _Segmented<_TrendMetric>(
        value: metric,
        options: const [(_TrendMetric.views, 'Views'), (_TrendMetric.engagement, 'Engagement')],
        onChanged: (v) => setState(() => _trend = v),
      ),
      child: series.isEmpty || maxY == 0
          ? _note(context,
              metric == _TrendMetric.views ? 'No views recorded in this period.' : 'No likes, comments or shares in this period.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 180,
                  child: LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: math.max(1, buckets.length - 1).toDouble(),
                      minY: 0,
                      maxY: maxY * 1.15,
                      clipData: const FlClipData.all(),
                      borderData: FlBorderData(show: false),
                      gridData: FlGridData(
                        drawVerticalLine: false,
                        horizontalInterval: math.max(1, maxY / 3),
                        getDrawingHorizontalLine: (_) => FlLine(color: context.border, strokeWidth: 1),
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 36,
                            interval: math.max(1, maxY / 3),
                            getTitlesWidget: (v, meta) => v == meta.max
                                ? const SizedBox.shrink()
                                : Text(_compact(v.round()), style: TextStyle(fontSize: 10, color: context.textMuted)),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 22,
                            interval: 1,
                            getTitlesWidget: (v, meta) {
                              final i = v.round();
                              if (i < 0 || i >= buckets.length || i % labelEvery != 0) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(df.format(buckets[i]), style: TextStyle(fontSize: 10, color: context.textMuted)),
                              );
                            },
                          ),
                        ),
                      ),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipColor: (_) => context.surfaceMid,
                          fitInsideHorizontally: true,
                          getTooltipItems: (spots) => [
                            for (final s in spots)
                              LineTooltipItem(
                                '${s == spots.first ? '${DateFormat('MMM d').format(buckets[s.x.round()])}\n' : ''}'
                                '${series[s.barIndex].$1.source.label}: ${_compact(s.y.round())}',
                                TextStyle(
                                  color: _sourceColor(context, series[s.barIndex].$1.source),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ),
                      lineBarsData: [
                        for (final (r, vals) in series)
                          LineChartBarData(
                            spots: [for (var i = 0; i < vals.length; i++) FlSpot(i.toDouble(), vals[i])],
                            isCurved: true,
                            preventCurveOverShooting: true,
                            color: _sourceColor(context, r.source),
                            barWidth: 2,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: series.length == 1,
                              color: _sourceColor(context, r.source).withValues(alpha: 0.12),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    for (final (r, _) in series)
                      _Legend(
                        color: _sourceColor(context, r.source),
                        label: metric == _TrendMetric.views && r.viewsLabel != 'Views'
                            ? '${r.source.label} ${r.viewsLabel.toLowerCase()}'
                            : r.source.label,
                      ),
                  ],
                ),
                if (byPublish.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _note(context, '${byPublish.join(', ')}: totals for posts published each ${bucket == 7 ? 'week' : 'day'}.'),
                ],
              ],
            ),
    );
  }

  // ── Platform comparison ─────────────────────────────────────────────────

  Widget _compareCard(BuildContext context, List<SourceReport> rs) {
    final totalEng = rs.fold<int>(0, (a, r) => a + (r.engagement ?? 0));
    return _Card(
      title: 'Platforms',
      child: Column(
        children: [
          for (final r in rs) ...[
            Row(
              children: [
                _Avatar(url: r.avatarUrl, icon: r.source.icon, color: _sourceColor(context, r.source)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.accountName.isEmpty ? r.source.label : r.accountName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.textPrimary)),
                      Text(r.source.label, style: TextStyle(fontSize: 11, color: context.textMuted)),
                    ],
                  ),
                ),
                _MiniStat(label: 'Followers', value: r.followers == null ? '—' : _compact(r.followers!)),
                _MiniStat(label: r.viewsLabel, value: r.views == null ? '—' : _compact(r.views!)),
                _MiniStat(label: 'Engaged', value: r.engagement == null ? '—' : _compact(r.engagement!)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.full),
              child: LinearProgressIndicator(
                minHeight: 4,
                value: totalEng == 0 ? 0 : (r.engagement ?? 0) / totalEng,
                color: _sourceColor(context, r.source),
                backgroundColor: context.surfaceMid,
              ),
            ),
            if (r != rs.last) const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: _note(context, 'Bar: share of all engagement in this period.')),
        ],
      ),
    );
  }

  // ── Top content ─────────────────────────────────────────────────────────

  List<ContentStat> _content(List<SourceReport> rs, String q) {
    final all = [
      for (final r in rs)
        for (final c in r.content)
          if (q.isEmpty ||
              c.title.toLowerCase().contains(q) ||
              c.source.label.toLowerCase().contains(q) ||
              r.accountName.toLowerCase().contains(q))
            c,
    ];
    int key(ContentStat c) => switch (_sort) {
          _Sort.views => c.views ?? -1,
          _Sort.engagement => c.engagement,
          _Sort.likes => c.likes,
          _Sort.comments => c.comments,
          _Sort.newest => c.publishedAt?.millisecondsSinceEpoch ?? 0,
        };
    all.sort((a, b) => key(b).compareTo(key(a)));
    return all;
  }

  Widget _contentCard(BuildContext context, List<ContentStat> items, String q) {
    final limit = _allContent ? items.length : math.min(items.length, 8);
    final df = DateFormat('MMM d, y');
    return _Card(
      title: q.isEmpty ? 'Top content' : 'Matching content',
      trailing: PopupMenuButton<_Sort>(
        tooltip: 'Sort',
        initialValue: _sort,
        onSelected: (s) => setState(() => _sort = s),
        itemBuilder: (_) => const [
          PopupMenuItem(value: _Sort.views, child: Text('Most views')),
          PopupMenuItem(value: _Sort.engagement, child: Text('Most engagement')),
          PopupMenuItem(value: _Sort.likes, child: Text('Most likes')),
          PopupMenuItem(value: _Sort.comments, child: Text('Most comments')),
          PopupMenuItem(value: _Sort.newest, child: Text('Newest')),
        ],
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(switch (_sort) {
              _Sort.views => 'Views',
              _Sort.engagement => 'Engagement',
              _Sort.likes => 'Likes',
              _Sort.comments => 'Comments',
              _Sort.newest => 'Newest',
            }, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brandBlue)),
            const Icon(Icons.unfold_more_rounded, size: 16, color: AppColors.brandBlue),
          ],
        ),
      ),
      child: items.isEmpty
          ? _note(context, 'No posts published in this period.')
          : Column(
              children: [
                for (final c in items.take(limit))
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    onTap: c.route == null && c.url == null ? null : () => _open(c),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          _Thumb(url: c.thumbnailUrl, icon: c.source.icon),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 12.5, height: 1.3, fontWeight: FontWeight.w600, color: context.textPrimary)),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Icon(c.source.icon, size: 12, color: _sourceColor(context, c.source)),
                                    const SizedBox(width: 4),
                                    Text(
                                      [c.source.label, if (c.publishedAt != null) df.format(c.publishedAt!)].join(' · '),
                                      style: TextStyle(fontSize: 10.5, color: context.textMuted),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Wrap(
                                  spacing: 10,
                                  children: [
                                    if (c.views != null) _Metric(Icons.visibility_rounded, c.views!),
                                    _Metric(Icons.favorite_rounded, c.likes),
                                    _Metric(Icons.chat_bubble_rounded, c.comments),
                                    if (c.shares > 0) _Metric(Icons.reply_rounded, c.shares),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (c.route != null || c.url != null)
                            Icon(c.route != null ? Icons.chevron_right_rounded : Icons.open_in_new_rounded,
                                size: 16, color: context.textMuted),
                        ],
                      ),
                    ),
                  ),
                if (items.length > 8)
                  TextButton(
                    onPressed: () => setState(() => _allContent = !_allContent),
                    child: Text(_allContent ? 'Show less' : 'Show all ${items.length}',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.brandBlue)),
                  ),
              ],
            ),
    );
  }

  // ── Audience ────────────────────────────────────────────────────────────

  Widget _audienceCard(BuildContext context, List<SourceReport> rs) {
    final withData = rs.where((r) => r.ages.isNotEmpty || r.genders.isNotEmpty || r.countries.isNotEmpty).toList();
    final notes = rs.where((r) => r.audienceNote.isNotEmpty && !withData.contains(r)).toList();
    return _Card(
      title: 'Audience',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in withData) ...[
            Row(
              children: [
                Icon(r.source.icon, size: 14, color: _sourceColor(context, r.source)),
                const SizedBox(width: 6),
                Text(r.source == AnalyticsSource.youtube ? 'YouTube viewers' : '${r.source.label} followers',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
              ],
            ),
            const SizedBox(height: 8),
            if (r.genders.isNotEmpty) ...[
              _GenderBar(slices: r.genders),
              const SizedBox(height: 10),
            ],
            if (r.ages.isNotEmpty) ...[
              for (final a in r.ages) _ShareRow(label: a.label, share: a.share, color: _sourceColor(context, r.source)),
              const SizedBox(height: 8),
            ],
            if (r.countries.isNotEmpty) ...[
              Text('Top countries', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.textSecondary)),
              const SizedBox(height: 4),
              for (final c in r.countries) _ShareRow(label: c.label, share: c.share, color: _sourceColor(context, r.source)),
            ],
            const SizedBox(height: 12),
          ],
          if (withData.isEmpty && notes.isEmpty) _note(context, 'No audience details yet.'),
          for (final r in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(r.source.icon, size: 13, color: context.textMuted),
                  const SizedBox(width: 6),
                  Expanded(child: _note(context, r.audienceNote)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Issues, connect, empty ──────────────────────────────────────────────

  Widget _issues(BuildContext context, List<SourceReport> failed, List<LinkedAccount> broken) {
    final rows = <(IconData, String, String, VoidCallback)>[
      for (final a in broken)
        (
          a.platform.icon,
          '${a.platform.label}: ${a.status == LinkStatus.expired ? 'login expired' : 'needs reconnecting'}',
          'Reconnect',
          () => _connect(a.platform),
        ),
      for (final r in failed)
        (
          r.source.icon,
          '${r.source.label}: ${r.message}',
          r.state == SourceState.needsReconnect ? 'Reconnect' : 'Retry',
          r.state == SourceState.needsReconnect && r.source.platform != null
              ? () => _connect(r.source.platform!)
              : () => ref.invalidate(creatorAnalyticsProvider((source: r.source, accountId: r.accountId, days: _days))),
        ),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.brandPink.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          for (final (icon, text, label, onTap) in rows)
            Row(
              children: [
                Icon(icon, size: 16, color: AppColors.brandPink),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: context.textPrimary, height: 1.3)),
                ),
                TextButton(
                  onPressed: onTap,
                  child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brandBlue)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _connectCard(BuildContext context, List<(AnalyticsPlatformInfo, bool linked)> more) {
    final connectable = [for (final (p, linked) in more) if (p.hasAnalytics && !linked) p];
    final later = [for (final (p, linked) in more) if (!p.hasAnalytics) (p, linked)];
    return _Card(
      title: 'More platforms',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (connectable.isNotEmpty) ...[
            _note(context, 'Connect an account to see its stats here next to your Oneova posts.'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in connectable)
                  ActionChip(
                    avatar: Icon(p.icon, size: 16, color: AppColors.brandBlue),
                    label: Text('Connect ${p.label}'),
                    labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: context.textPrimary),
                    backgroundColor: context.surfaceMid,
                    side: BorderSide(color: context.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
                    onPressed: () => _connect(p.platform!),
                  ),
              ],
            ),
          ],
          if (connectable.isNotEmpty && later.isNotEmpty) const SizedBox(height: 12),
          for (final (p, linked) in later)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(p.icon, size: 18, color: context.textMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
                        _note(context, p.note),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (linked ? AppColors.brandBlue : AppColors.brandPink).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Text(linked ? 'LINKED' : 'SOON',
                        style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: linked ? AppColors.brandBlue : AppColors.brandPink)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insights_rounded, size: 36, color: context.textMuted),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: context.textSecondary)),
          ],
        ),
      );

  Widget _skeleton(BuildContext context) => Column(
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              height: i == 0 ? 120 : 180,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: context.surface, borderRadius: BorderRadius.circular(AppRadius.md)),
            ),
        ],
      );
}

// ── Helpers ────────────────────────────────────────────────────────────────

String _compact(int n) => NumberFormat.compact().format(n);

Color _sourceColor(BuildContext context, AnalyticsSource s) => switch (s) {
      AnalyticsSource.oneova => AppColors.brandBlue,
      AnalyticsSource.youtube => AppColors.brandPink,
      AnalyticsSource.tiktok => context.textPrimary,
      AnalyticsSource.instagram => AppColors.brandPink.withValues(alpha: 0.55),
      AnalyticsSource.facebook => AppColors.brandBlue.withValues(alpha: 0.5),
    };

Widget _note(BuildContext context, String text) =>
    Text(text, style: TextStyle(fontSize: 11, height: 1.35, color: context.textMuted));

class _Kpi {
  final String label;
  final String value;
  final IconData icon;
  final double? change;
  final String? note;
  final List<String> keys;
  const _Kpi(this.label, this.value, this.icon, {this.change, this.note, this.keys = const []});

  bool matches(String q) => label.toLowerCase().contains(q) || keys.any((k) => k.contains(q) || q.contains(k));
}

class _KpiTile extends StatelessWidget {
  const _KpiTile(this.k);
  final _Kpi k;

  @override
  Widget build(BuildContext context) {
    final c = k.change;
    final up = c == null || c >= 0;
    final changeText = c == null
        ? null
        : c.isInfinite
            ? 'new'
            : '${c >= 0 ? '+' : ''}${c.abs() >= 100 ? c.toStringAsFixed(0) : c.toStringAsFixed(1)}%';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(k.icon, size: 14, color: AppColors.brandBlue),
              const SizedBox(width: 6),
              Expanded(
                child: Text(k.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(k.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: context.textPrimary)),
          const SizedBox(height: 2),
          SizedBox(
            height: 15,
            child: changeText != null
                ? Row(
                    children: [
                      Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                          size: 12, color: up ? AppColors.brandBlue : AppColors.brandPink),
                      const SizedBox(width: 2),
                      Text('$changeText vs previous',
                          style: TextStyle(
                              fontSize: 10.5, fontWeight: FontWeight.w600, color: up ? AppColors.brandBlue : AppColors.brandPink)),
                    ],
                  )
                : Text(k.note ?? '', style: TextStyle(fontSize: 10.5, color: context.textMuted)),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: context.textPrimary)),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.onTap, this.icon, this.dot});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : context.textSecondary;
    return Material(
      color: selected ? AppColors.brandBlue : context.surface,
      shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.brandBlue : context.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: selected ? Colors.white : dot ?? fg),
                const SizedBox(width: 5),
              ],
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Segmented<T> extends StatelessWidget {
  const _Segmented({required this.value, required this.options, required this.onChanged});
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: context.surfaceMid, borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (v, label) in options)
            GestureDetector(
              onTap: () => onChanged(v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: v == value ? AppColors.brandBlue : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700, color: v == value ? Colors.white : context.textSecondary)),
              ),
            ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 11, color: context.textSecondary, fontWeight: FontWeight.w500)),
        ],
      );
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 58,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: context.textPrimary)),
            Text(label, maxLines: 1, style: TextStyle(fontSize: 9.5, color: context.textMuted)),
          ],
        ),
      );
}

class _Metric extends StatelessWidget {
  const _Metric(this.icon, this.value);
  final IconData icon;
  final int value;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: context.textMuted),
          const SizedBox(width: 3),
          Text(_compact(value), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.textSecondary)),
        ],
      );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.icon, required this.color});
  final String url;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(
      radius: 16,
      backgroundColor: color.withValues(alpha: 0.15),
      child: Icon(icon, size: 16, color: color),
    );
    if (url.isEmpty) return fallback;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: 32,
        height: 32,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => fallback,
        placeholder: (_, _) => fallback,
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url, required this.icon});
  final String url;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: 56,
      height: 56,
      color: context.surfaceMid,
      child: Icon(icon, size: 20, color: context.textMuted),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: url.isEmpty
          ? box
          : CachedNetworkImage(
              imageUrl: url,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              memCacheWidth: 168,
              errorWidget: (_, _, _) => box,
              placeholder: (_, _) => box,
            ),
    );
  }
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({required this.label, required this.share, required this.color});
  final String label;
  final double share;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: Text(label,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: context.textSecondary)),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.full),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value: (share / 100).clamp(0, 1),
                  color: color,
                  backgroundColor: context.surfaceMid,
                ),
              ),
            ),
            SizedBox(
              width: 44,
              child: Text('${share.toStringAsFixed(share < 10 ? 1 : 0)}%',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
            ),
          ],
        ),
      );
}

class _GenderBar extends StatelessWidget {
  const _GenderBar({required this.slices});
  final List<AudienceSlice> slices;

  Color _color(BuildContext context, String label) => switch (label) {
        'Female' => AppColors.brandPink,
        'Male' => AppColors.brandBlue,
        _ => context.textMuted,
      };

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<double>(0, (a, s) => a + s.share);
    if (total <= 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                for (final s in slices)
                  if (s.share > 0)
                    Expanded(flex: math.max(1, (s.share * 10).round()), child: Container(color: _color(context, s.label))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          children: [
            for (final s in slices)
              _Legend(color: _color(context, s.label), label: '${s.label} ${(s.share * 100 / total).toStringAsFixed(0)}%'),
          ],
        ),
      ],
    );
  }
}

class _FilterHeader extends SliverPersistentHeaderDelegate {
  _FilterHeader({required this.child, required this.color});
  final Widget child;
  final Color color;

  static const _height = 82.0;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Container(color: color, alignment: Alignment.topCenter, child: child);

  @override
  bool shouldRebuild(_FilterHeader old) => true;
}
