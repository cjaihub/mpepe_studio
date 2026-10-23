// LIVE STUDIO v2 — the 16:9 content inside TableFrame (workstream #5).
//
//   StudioStage(tableContent: StudioTableContent(streamId: id, phone: phone), …)
//
// Only the active mode's widget is built (each mode is its own consumer that
// subscribes to its own data), and the video player is created through a
// deferred import only after the viewer taps Join.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../backend/live_studio/contracts/studio_contracts.dart';
import '../../../../backend/live_studio/contracts/studio_ports.dart';
import '../../../../backend/live_studio/media/studio_video_view.dart';
import '../../../../backend/live_studio/session/studio_session_controller.dart';
import '../../../../backend/live_studio/table/studio_table_controller.dart';
import '../../../../backend/live_studio/table/table_sources.dart';
import '../../../../backend/live_studio/table/watch_party_sync.dart';
import '../theme/live_studio_tokens.dart';
import 'table_chrome.dart';
import 'table_metrics.dart';
import 'watch_player_handle.dart';

/// Called by "View item". The SPEC wires it to the Presenter's Goods tab;
/// when null, the product's `productUrl` (if any) opens externally.
typedef TableViewItem = void Function(TableGoodsItem item);

class StudioTableContent extends ConsumerWidget {
  const StudioTableContent({
    super.key,
    required this.streamId,
    this.phone = false,
    this.onViewItem,
    this.screenTitleFor,
  });

  final String streamId;
  final bool phone;
  final TableViewItem? onViewItem;

  /// Title for the screen-share publisher (e.g. "Amani's screen").
  final String Function(String publisherUid)? screenTitleFor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(studioTableStateProvider(streamId).select((t) => t.mode));
    return LayoutBuilder(builder: (context, c) {
      final m = TableMetrics.forWidth(c.maxWidth, phone: phone);
      // Lazy: only the active mode is constructed.
      final Widget body = switch (mode) {
        TableMode.goods => _GoodsMode(streamId: streamId, m: m, onViewItem: onViewItem),
        TableMode.screen => _ScreenMode(streamId: streamId, m: m, titleFor: screenTitleFor),
        TableMode.match || TableMode.movie => _WatchMode(streamId: streamId, mode: mode, m: m),
      };
      return KeyedSubtree(key: ValueKey('table-mode-${mode.wire}'), child: body);
    });
  }
}

// ─── Goods ───────────────────────────────────────────────────────────────────

class _GoodsMode extends ConsumerWidget {
  const _GoodsMode({required this.streamId, required this.m, this.onViewItem});
  final String streamId;
  final TableMetrics m;
  final TableViewItem? onViewItem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goods = ref.watch(studioTableStateProvider(streamId).select((t) => t.goods));
    final canManage = ref.watch(studioTableControllerProvider(streamId).select((v) => v.canManage));
    final item = goods == null
        ? null
        : ref.watch(tableGoodsProvider((streamId, goods.source.wire, goods.productId))).value;

    final art = Stack(fit: StackFit.expand, children: [
      const GoodsArt(),
      Positioned(
        left: 0,
        right: 0,
        top: m.cubeTop,
        child: Center(child: GoodsCube(m: m, imageUrl: item?.imageUrl ?? '')),
      ),
    ]);

    if (goods == null || item == null) {
      final empty = goods == null;
      return TableChrome(
        m: m,
        mode: TableMode.goods,
        background: art,
        title: empty ? TableModeCopy.noGoods : '',
        sub: empty && canManage ? TableModeCopy.noGoodsHost : '',
      );
    }
    final open = onViewItem ?? _openUrl;
    final canOpen = onViewItem != null || item.productUrl.isNotEmpty;
    return TableChrome(
      m: m,
      mode: TableMode.goods,
      background: art,
      title: item.name,
      sub: item.formattedPrice,
      cta: TableCta(label: TableModeCopy.viewItem, m: m, onTap: canOpen ? () => open(item) : null),
    );
  }

  static void _openUrl(TableGoodsItem item) {
    final uri = Uri.tryParse(item.productUrl);
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
    }
  }
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class _ScreenMode extends ConsumerStatefulWidget {
  const _ScreenMode({required this.streamId, required this.m, this.titleFor});
  final String streamId;
  final TableMetrics m;
  final String Function(String uid)? titleFor;

  @override
  ConsumerState<_ScreenMode> createState() => _ScreenModeState();
}

class _ScreenModeState extends ConsumerState<_ScreenMode> {
  Timer? _poll;
  StudioVideoHandle? _handle;

  @override
  void initState() {
    super.initState();
    _read();
    // The room exposes the table track as a snapshot; re-check each second
    // so "Waiting for screen share" flips as soon as it is published.
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _read());
  }

  void _read() {
    final h = ref.read(studioTableRoomProvider(widget.streamId)).tableScreen();
    if (!mounted) return;
    if (!identical(h, _handle) || (h?.hasVideo ?? false) != (_handle?.hasVideo ?? false)) {
      setState(() => _handle = h);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    final screen = ref.watch(studioTableStateProvider(widget.streamId).select((t) => t.screen));
    final joined = ref.watch(
        studioTableControllerProvider(widget.streamId).select((v) => v.isJoined(TableMode.screen)));
    final h = _handle;
    final live = h != null && h.hasVideo;
    final title = screen != null && widget.titleFor != null
        ? widget.titleFor!(screen.publisherUid)
        : TableModeCopy.hostScreen;

    if (!live) {
      return TableChrome(
        m: m,
        mode: TableMode.screen,
        background: TableEmptyArt(m: m, icon: Icons.desktop_windows, background: const ScreenArt()),
        title: TableModeCopy.waitingScreen,
      );
    }
    return TableChrome(
      m: m,
      mode: TableMode.screen,
      background: joined
          ? ColoredBox(
              color: LiveStudioWorld.screen,
              child: StudioVideoView(h, fit: BoxFit.contain, placeholder: const ScreenArt()),
            )
          : ScreenWindowArt(m: m),
      title: title,
      sub: TableModeCopy.defaultSub(TableMode.screen),
      cta: _joinCta(ref, widget.streamId, TableMode.screen, joined, m, enabled: true),
    );
  }
}

Widget _joinCta(WidgetRef ref, String streamId, TableMode mode, bool joined, TableMetrics m,
        {required bool enabled}) =>
    TableCta(
      label: joined ? TableModeCopy.watching : TableModeCopy.join,
      watching: joined,
      m: m,
      onTap: enabled ? () => ref.read(studioTableControllerProvider(streamId).notifier).toggleJoin(mode) : null,
    );

// ─── Match / Movie ───────────────────────────────────────────────────────────

class _WatchMode extends ConsumerWidget {
  const _WatchMode({required this.streamId, required this.mode, required this.m});
  final String streamId;
  final TableMode mode;
  final TableMetrics m;

  Widget _art() => mode == TableMode.match ? const MatchArt() : MovieArt(m: m);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watch = ref.watch(studioTableStateProvider(streamId).select((t) => t.watch));
    final canManage = ref.watch(studioTableControllerProvider(streamId).select((v) => v.canManage));
    final joined = ref.watch(studioTableControllerProvider(streamId).select((v) => v.isJoined(mode)));

    if (watch == null) {
      // Empty admin catalog (decision Q7) or nothing picked yet.
      return TableChrome(
        m: m,
        mode: mode,
        background: TableEmptyArt(
          m: m,
          icon: TableModeCopy.icon(mode),
          background: mode == TableMode.match ? const MatchArt() : MovieArt(m: m, showPlay: false),
        ),
        title: canManage ? TableModeCopy.noLicensed : TableModeCopy.viewerNothing,
        sub: canManage ? '' : TableModeCopy.viewerNothingSub,
      );
    }

    final entryAsync = ref.watch(watchCatalogEntryProvider(watch.catalogId));
    final entry = entryAsync.value;
    final now = ref.watch(tableNowMsProvider);
    final loading = entryAsync.isLoading && entry == null;
    final available = entry != null && entry.isAvailableAt(now(), mode: mode);
    final playing = watch.state == PlaybackState.playing;

    final poster = TablePoster(url: entry?.posterUrl ?? '', fallback: _art());
    final background = joined && available
        ? _WatchSurface(
            key: ValueKey('watch-${watch.catalogId}'),
            entry: entry,
            party: watch,
            poster: poster,
          )
        : poster;

    final String title;
    final String sub;
    if (loading) {
      title = '';
      sub = '';
    } else if (!available) {
      title = TableModeCopy.unavailable;
      sub = '';
    } else {
      title = entry.title.isEmpty ? TableModeCopy.label(mode) : entry.title;
      sub = entry.subtitle.isEmpty ? TableModeCopy.defaultSub(mode) : entry.subtitle;
    }

    Widget? center;
    if (canManage && available) {
      center = Semantics(
        button: true,
        label: playing ? 'Pause for everyone' : 'Play for everyone',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: () {
            final clock = ref.read(studioClockProvider);
            final pos = watch.targetPositionMs(clock.serverNowMs());
            final ctl = ref.read(studioTableControllerProvider(streamId).notifier);
            unawaited(playing ? ctl.pause(pos) : ctl.play(pos));
          },
          child: PlayDisc(m: m, icon: playing ? Icons.pause : Icons.play_arrow),
        ),
      );
    }

    return TableChrome(
      m: m,
      mode: mode,
      // The movie art draws its own decorative play disc; hide it under the control.
      background: center != null && mode == TableMode.movie && !(joined && available)
          ? TablePoster(url: entry?.posterUrl ?? '', fallback: MovieArt(m: m, showPlay: false))
          : background,
      center: center,
      title: title,
      sub: sub,
      cta: loading ? null : _joinCta(ref, streamId, mode, joined, m, enabled: available),
    );
  }
}

/// Creates the player (deferred), syncs it to the room's WatchParty.
class _WatchSurface extends ConsumerStatefulWidget {
  const _WatchSurface({super.key, required this.entry, required this.party, required this.poster});
  final WatchCatalogEntry entry;
  final WatchParty party;
  final Widget poster;

  @override
  ConsumerState<_WatchSurface> createState() => _WatchSurfaceState();
}

class _WatchSurfaceState extends ConsumerState<_WatchSurface> {
  WatchPlayerHandle? _handle;
  WatchPartySync? _sync;
  bool _failed = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    final clock = ref.read(studioClockProvider);
    final factory = ref.read(watchPlayerFactoryProvider);
    try {
      unawaited(clock.calibrate().catchError((Object _) {}));
      final h = await factory(widget.entry.hlsUrl);
      if (_disposed) {
        await h.dispose();
        return;
      }
      final sync = WatchPartySync(player: h.player, clock: clock);
      _handle = h;
      _sync = sync;
      await sync.update(widget.party);
      sync.start();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(_WatchSurface old) {
    super.didUpdateWidget(old);
    unawaited(_sync?.update(widget.party));
  }

  @override
  void dispose() {
    _disposed = true;
    _sync?.dispose();
    final h = _handle;
    if (h != null) {
      unawaited(h.player.pause().catchError((Object _) {}).whenComplete(h.dispose));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _handle;
    if (h == null || _failed) return widget.poster;
    return ColoredBox(color: LiveStudioWorld.screen, child: h.buildView(context));
  }
}
