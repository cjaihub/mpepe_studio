// LIVE STUDIO v2 — "Gaming lives" discovery (route /live/gaming).
//
// Game lives on air right now: live_streams where status == 'live' and
// liveKind == 'gaming', newest first, limit 50, streamed from Firestore.
// Needs the composite index (liveKind ASC, status ASC, createdAt DESC).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../backend/live_studio/contracts/studio_contracts.dart';
import '../../../../backend/live_studio/session/studio_session_controller.dart';
import '../shell/shell_widgets.dart';
import '../theme/live_studio_tokens.dart';

/// One card of the Gaming lives list (from a `live_streams` doc).
@immutable
class GamingLive {
  const GamingLive({
    required this.id,
    required this.title,
    required this.hostName,
    this.hostAvatarUrl = '',
    this.gameTitle,
    this.viewers = 0,
  });

  final String id;
  final String title;
  final String hostName;
  final String hostAvatarUrl;
  final String? gameTitle;
  final int viewers;

  factory GamingLive.fromDoc(String id, Map<String, dynamic> d) {
    String s(Object? v) => v is String ? v.trim() : '';
    final game = s(d['gameTitle']);
    return GamingLive(
      id: id,
      title: s(d['title']),
      hostName: s(d['hostDisplayName']).isEmpty ? 'Oneova creator' : s(d['hostDisplayName']),
      hostAvatarUrl: s(d['hostAvatarUrl']),
      gameTitle: game.isEmpty ? null : game,
      viewers: d['viewerCount'] is num ? (d['viewerCount'] as num).toInt() : 0,
    );
  }
}

/// Max cards shown.
const int kGamingLivesLimit = 50;

final gamingLivesProvider = StreamProvider.autoDispose<List<GamingLive>>((ref) {
  final db = ref.watch(studioFirestoreProvider);
  return db
      .collection(StudioPaths.streams)
      .where('liveKind', isEqualTo: 'gaming')
      .where('status', isEqualTo: 'live')
      .orderBy('createdAt', descending: true)
      .limit(kGamingLivesLimit)
      .snapshots()
      .map((q) => [for (final d in q.docs) GamingLive.fromDoc(d.id, d.data())]);
});

class GamingLivesScreen extends ConsumerWidget {
  const GamingLivesScreen({super.key});

  static const String emptyText = 'No one is streaming a game right now';
  static const String goLiveLabel = 'Go live with a game';

  void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/hub/home');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const t = LiveStudioTokens.dark;
    final lives = ref.watch(gamingLivesProvider);
    return Scaffold(
      backgroundColor: t.base,
      appBar: AppBar(
        backgroundColor: t.base,
        foregroundColor: t.textHigh,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => _back(context),
        ),
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.sports_esports, color: LiveStudioAccent.pink, size: 22),
          const SizedBox(width: 8),
          Text('Gaming lives', style: LiveStudioType.s(18, FontWeight.w700, t.textHigh, height: 24)),
        ]),
      ),
      body: lives.when(
        loading: () => const Center(child: CircularProgressIndicator(color: LiveStudioAccent.pink)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load gaming lives.',
                textAlign: TextAlign.center, style: LiveStudioType.s(14, FontWeight.w500, t.textMedium, height: 20)),
          ),
        ),
        data: (list) => list.isEmpty ? const _Empty(tokens: t) : _Grid(lives: list, tokens: t),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.tokens});
  final LiveStudioTokens tokens;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.sports_esports, size: 56, color: t.textDim),
          const SizedBox(height: 14),
          Text(GamingLivesScreen.emptyText,
              textAlign: TextAlign.center, style: LiveStudioType.s(16, FontWeight.w600, t.textHigh, height: 22)),
          const SizedBox(height: 18),
          StudioPillButton(
            key: const ValueKey('gaming-go-live'),
            label: GamingLivesScreen.goLiveLabel,
            icon: Icons.sports_esports,
            fill: LiveStudioAccent.pink,
            textColor: LiveStudioAccent.white,
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            onTap: () => context.push('/live/setup?mode=gaming'),
          ),
        ]),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.lives, required this.tokens});
  final List<GamingLive> lives;
  final LiveStudioTokens tokens;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 900 ? 4 : (box.maxWidth >= 600 ? 3 : 2);
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.72,
        ),
        itemCount: lives.length,
        itemBuilder: (context, i) => GamingLiveCard(live: lives[i], tokens: tokens),
      );
    });
  }
}

class GamingLiveCard extends StatelessWidget {
  const GamingLiveCard({super.key, required this.live, required this.tokens});
  final GamingLive live;
  final LiveStudioTokens tokens;

  static String viewersLabel(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Semantics(
      button: true,
      label: '${live.hostName} is playing ${live.gameTitle ?? 'a game'}: ${live.title}. ${live.viewers} watching.',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('gaming-live-${live.id}'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/live/viewer/${live.id}'),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LiveStudioWorld.hostBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.ghostBorder),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const ShellLivePill(compact: true),
                  const Spacer(),
                  const Icon(Icons.visibility, size: 14, color: LiveStudioWorld.textHigh),
                  const SizedBox(width: 4),
                  Text(viewersLabel(live.viewers),
                      style: LiveStudioType.s(12, FontWeight.w600, LiveStudioWorld.textHigh, height: 16)),
                ]),
                const Expanded(
                  child: Center(child: Icon(Icons.sports_esports, size: 44, color: LiveStudioAccent.pinkLight)),
                ),
                if (live.gameTitle != null)
                  Text(live.gameTitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LiveStudioType.s(12, FontWeight.w700, LiveStudioAccent.pinkLight, height: 16)),
                Text(live.title.isEmpty ? 'Game Live' : live.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: LiveStudioType.s(14, FontWeight.w700, LiveStudioWorld.textHigh, height: 18)),
                const SizedBox(height: 8),
                Row(children: [
                  StudioAvatar(
                    name: live.hostName,
                    url: live.hostAvatarUrl,
                    size: 24,
                    fill: LiveStudioWorld.surface3,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(live.hostName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LiveStudioType.s(12, FontWeight.w500, LiveStudioWorld.textMedium, height: 16)),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
