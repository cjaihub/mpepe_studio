import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';
import '../shared/utils/friendly_error_parser.dart';
import '../shared/widgets/studio_background.dart';
import 'services/youtube_account_store.dart';
import 'services/youtube_auth_service.dart' show YouTubeChannel;
import 'yt_channel_intelligence_wizard.dart';

const _ytRed = Color(0xFFFF0000);
const _ytRedDark = Color(0xFFCC0000);

class YtChannelsScreen extends ConsumerWidget {
  const YtChannelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeAsync = ref.watch(ytAccountStoreProvider);

    return StudioBackground(
      backgroundIcons: const [
        Icons.camera_front,
        Icons.subscriptions_outlined,
        Icons.analytics_outlined,
      ],
      appBar: AppBar(
        title: Text(
          'YouTube Accounts',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: -0.5,
            color: context.textPrimary,
          ),
        ),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: context.textSecondary),
            tooltip: 'Refresh all channels',
            onPressed: () => ref.invalidate(ytAccountStoreProvider),
          ),
        ],
      ),
      floatingActionButton: storeAsync.when(
        data: (store) => store.accounts.length < 5
            ? _AddAccountFab(ref: ref)
            : null,
        loading: () => null,
        error: (_, _) => _AddAccountFab(ref: ref),
      ),
      child: storeAsync.when(
        data: (store) => _buildContent(context, ref, store),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, color: AppColors.brandBlue, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Failed to load accounts',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  FriendlyErrorParser.parse(err),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(color: context.textSecondary),
                ),
                const SizedBox(height: 24),
                OneovaButton(
                  text: 'Retry',
                  onPressed: () => ref.invalidate(ytAccountStoreProvider),
                  isPrimary: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, WidgetRef ref, YtAccountsState store) {
    if (store.accounts.isEmpty) {
      return _buildEmptyState(context, ref);
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // Error banner (non-fatal)
        if (store.error != null)
          SliverToBoxAdapter(
            child: _ErrorBanner(
              message: FriendlyErrorParser.parse(store.error!),
              onDismiss: () =>
                  ref.read(ytAccountStoreProvider.notifier).clearError(),
            ).animate().fadeIn().slideY(begin: -0.2),
          ),

        // Loading banner
        if (store.isLoading)
          SliverToBoxAdapter(
            child: _LoadingBanner(message: store.statusMessage ?? 'Working…'),
          ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Manage your empire.',
                  style: GoogleFonts.outfit(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                    letterSpacing: -1,
                    color: context.textPrimary,
                  ),
                ).animate().fadeIn(duration: 500.ms).slideY(begin: -0.08),
                const SizedBox(height: 6),
                Text(
                  '${store.accounts.length} Google Account${store.accounts.length == 1 ? '' : 's'} · ${store.accounts.fold<int>(0, (sum, a) => sum + a.channels.length)} Channel${store.accounts.fold<int>(0, (sum, a) => sum + a.channels.length) == 1 ? '' : 's'} connected',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    color: context.textSecondary,
                    height: 1.4,
                  ),
                ).animate().fadeIn(delay: 100.ms),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),

        // Per-account sections
        ...store.accounts.asMap().entries.expand((entry) {
          final index = entry.key;
          final account = entry.value;
          return [
            SliverToBoxAdapter(
              child: _AccountSection(
                account: account,
                isFirst: index == 0,
                onRemove: () => _confirmRemove(context, ref, account),
                onRefresh: () => ref
                    .read(ytAccountStoreProvider.notifier)
                    .refreshAccount(account.googleId),
              ).animate().fadeIn(delay: (200 + index * 120).ms).slideY(
                    begin: 0.08,
                    delay: (200 + index * 120).ms,
                  ),
            ),
          ];
        }),

        // Limit info
        if (store.accounts.length >= 5)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.brandBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: AppColors.brandBlue.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: AppColors.brandBlue, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'You\'ve reached the 5-account limit. Remove one to add another.',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: AppColors.brandBlue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ).animate().fadeIn(delay: 600.ms),
          ),

        const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    final storeState = ref.watch(ytAccountStoreProvider);
    final isLoading = storeState.when(
      data: (s) => s.isLoading,
      loading: () => true,
      error: (_, _) => false,
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _ytRed.withValues(alpha: 0.1),
                border:
                    Border.all(color: _ytRed.withValues(alpha: 0.2), width: 1.5),
              ),
              child: const Icon(Icons.subscriptions_rounded,
                  color: _ytRed, size: 48),
            )
                .animate(onPlay: (c) => c.forward())
                .scale(
                    begin: const Offset(1, 1),
                    end: const Offset(1.04, 1.04),
                    duration: 2.5.seconds,
                    curve: Curves.easeInOutSine),
            const SizedBox(height: 28),
            Text(
              'No channels connected',
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: context.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Link your Google account to start managing YouTube channels, analytics, and uploads from Oneova Studio.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: context.textSecondary,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 36),
            if (isLoading)
              Column(
                children: [
                  const CircularProgressIndicator(color: _ytRed),
                  const SizedBox(height: 16),
                  Text(
                    storeState.value?.statusMessage ?? 'Connecting…',
                    style: GoogleFonts.outfit(color: context.textSecondary),
                  ),
                ],
              )
            else
              _AddAccountButton(
                onTap: () =>
                    ref.read(ytAccountStoreProvider.notifier).addAccount(),
              ),
            const SizedBox(height: 16),
            Text(
              'You can add up to 5 Google accounts',
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: context.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(
      BuildContext context, WidgetRef ref, YtLinkedAccount account) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _RemoveAccountSheet(account: account),
    );

    if (confirmed == true) {
      await ref
          .read(ytAccountStoreProvider.notifier)
          .removeAccount(account.googleId);
    }
  }
}

// ─────────────────────────────────────────────
//  Account Section
// ─────────────────────────────────────────────

class _AccountSection extends ConsumerWidget {
  final YtLinkedAccount account;
  final bool isFirst;
  final VoidCallback onRemove;
  final VoidCallback onRefresh;

  const _AccountSection({
    required this.account,
    required this.isFirst,
    required this.onRemove,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Account header row
          Row(
            children: [
              // Google avatar
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.surface,
                  border: Border.all(
                    color: isFirst
                        ? AppColors.brandBlue.withValues(alpha: 0.5)
                        : context.border,
                    width: 1.5,
                  ),
                  image: account.profilePictureUrl.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(account.profilePictureUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: account.profilePictureUrl.isEmpty
                    ? Center(
                        child: Text(
                          account.accountName.isNotEmpty
                              ? account.accountName[0].toUpperCase()
                              : '?',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w800,
                            color: context.textPrimary,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          account.accountName,
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: context.textPrimary,
                          ),
                        ),
                        if (isFirst) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.brandBlue.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                  color: AppColors.brandBlue
                                      .withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              'Primary',
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.brandBlue,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      account.email,
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              // Account actions
              IconButton(
                icon: Icon(Icons.refresh_rounded,
                    size: 18, color: context.textSecondary),
                tooltip: 'Refresh channels',
                onPressed: onRefresh,
              ),
              IconButton(
                icon: Icon(Icons.remove_circle_outline_rounded,
                    size: 18,
                    color: Colors.red[400]),
                tooltip: 'Remove account',
                onPressed: onRemove,
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Channel cards
          if (account.channels.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: context.textMuted, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    'No YouTube channels on this account',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: context.textMuted,
                    ),
                  ),
                ],
              ),
            )
          else
            ...account.channels.asMap().entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ChannelCard(
                  account: account,
                  channel: entry.value,
                  channelIndex: entry.key,
                  onActivate: () => ref
                      .read(ytAccountStoreProvider.notifier)
                      .setActiveChannel(account.googleId, entry.value.id),
                  onAiScan: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => YtChannelIntelligenceWizard(
                        channel: _toOldYtChannel(entry.value),
                      ),
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Channel Card
// ─────────────────────────────────────────────

class _ChannelCard extends ConsumerStatefulWidget {
  final YtLinkedAccount account;
  final YtConnectedChannel channel;
  final int channelIndex;
  final VoidCallback onActivate;
  final VoidCallback onAiScan;

  const _ChannelCard({
    required this.account,
    required this.channel,
    required this.channelIndex,
    required this.onActivate,
    required this.onAiScan,
  });

  @override
  ConsumerState<_ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends ConsumerState<_ChannelCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final numFormat = NumberFormat.compact();
    final isActive = widget.channel.isActive;

    return AnimatedContainer(
      duration: 300.ms,
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isActive
              ? _ytRed.withValues(alpha: 0.55)
              : context.border,
          width: isActive ? 1.5 : 1,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: _ytRed.withValues(alpha: 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                )
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )
              ],
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onActivate();
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Channel thumbnail
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _ytRed.withValues(alpha: 0.1),
                      border: Border.all(
                        color: isActive
                            ? _ytRed.withValues(alpha: 0.4)
                            : context.border,
                        width: 1.5,
                      ),
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: _ytRed.withValues(alpha: 0.2),
                                blurRadius: 12,
                                spreadRadius: 2,
                              )
                            ]
                          : null,
                      image: widget.channel.thumbnailUrl.isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(widget.channel.thumbnailUrl),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: widget.channel.thumbnailUrl.isEmpty
                        ? Center(
                            child: Text(
                              widget.channel.title.isNotEmpty
                                  ? widget.channel.title[0].toUpperCase()
                                  : '?',
                              style: GoogleFonts.outfit(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: _ytRed,
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),

                  // Channel info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.channel.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: context.textPrimary,
                                ),
                              ),
                            ),
                            if (isActive) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _ytRed.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                      color:
                                          _ytRed.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  '● Active',
                                  style: GoogleFonts.outfit(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: _ytRed,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${numFormat.format(widget.channel.subscriberCount)} subscribers',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Actions
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.auto_awesome_rounded,
                            color: Colors.purpleAccent, size: 20),
                        tooltip: 'AI Deep Scan',
                        onPressed: widget.onAiScan,
                      ),
                      IconButton(
                        icon: AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: 250.ms,
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: context.textSecondary,
                            size: 22,
                          ),
                        ),
                        onPressed: () =>
                            setState(() => _expanded = !_expanded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Expanded stats row
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: _buildStatsRow(context, numFormat),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: 300.ms,
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(BuildContext context, NumberFormat numFormat) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statCol(
              context,
              Icons.people_outline_rounded,
              numFormat.format(widget.channel.subscriberCount),
              'Subscribers',
              Colors.blue),
          _divider(),
          _statCol(
              context,
              Icons.video_library_outlined,
              numFormat.format(widget.channel.videoCount),
              'Videos',
              _ytRed),
          _divider(),
          _statCol(
              context,
              Icons.visibility_outlined,
              numFormat.format(widget.channel.viewCount),
              'Total Views',
              Colors.green),
        ],
      ),
    );
  }

  Widget _statCol(BuildContext context, IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 6),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: context.textPrimary,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 10,
            color: context.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _divider() {
    return Container(
        height: 36, width: 1, color: AppColors.outline);
  }
}

// ─────────────────────────────────────────────
//  Add Account FAB
// ─────────────────────────────────────────────

class _AddAccountFab extends StatelessWidget {
  final WidgetRef ref;

  const _AddAccountFab({required this.ref});

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(ytAccountStoreProvider).when(
          data: (s) => s.isLoading,
          loading: () => true,
          error: (_, _) => false,
        );

    return FloatingActionButton.extended(
      backgroundColor: _ytRedDark,
      onPressed: isLoading
          ? null
          : () {
              HapticFeedback.lightImpact();
              ref.read(ytAccountStoreProvider.notifier).addAccount();
            },
      icon: isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2),
            )
          : const Icon(Icons.add, color: Colors.white),
      label: Text(
        isLoading ? 'Connecting…' : 'Add Account',
        style: GoogleFonts.outfit(
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    )
        .animate()
        .scale(delay: 300.ms, duration: 400.ms, curve: Curves.easeOutBack);
  }
}

class _AddAccountButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddAccountButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_ytRedDark, _ytRed],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: _ytRed.withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_circle_outline_rounded,
                color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Text(
              'Connect Google Account',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Remove Account Bottom Sheet
// ─────────────────────────────────────────────

class _RemoveAccountSheet extends StatelessWidget {
  final YtLinkedAccount account;

  const _RemoveAccountSheet({required this.account});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red.withValues(alpha: 0.1),
              border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
            ),
            child: Icon(Icons.link_off_rounded,
                color: Colors.red[400], size: 30),
          ),
          const SizedBox(height: 20),
          Text(
            'Remove Account',
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Remove ${account.accountName} (${account.email}) and all its ${account.channels.length} channel${account.channels.length == 1 ? '' : 's'} from Oneova Studio?',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: context.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your YouTube data is not deleted — only the connection.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: context.textMuted,
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
                foregroundColor: Colors.red[400],
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: Text(
                'Yes, Remove',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
              ),
              onPressed: () => Navigator.pop(context, true),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancel',
                style: GoogleFonts.outfit(
                  color: context.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Utility Widgets
// ─────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded,
                color: Colors.red[400], size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: Colors.red[300],
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, size: 16, color: Colors.red[400]),
              onPressed: onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingBanner extends StatelessWidget {
  final String message;

  const _LoadingBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _ytRed.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _ytRed.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(color: _ytRed, strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              message,
              style: GoogleFonts.outfit(fontSize: 13, color: _ytRed),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Compat helper — YtChannelIntelligenceWizard still uses the old model
// ─────────────────────────────────────────────

// ignore: library_private_types_in_public_api
_OldYtChannel _toOldYtChannel(YtConnectedChannel ch) {
  return _OldYtChannel(
    id: ch.id,
    title: ch.title,
    thumbnailUrl: ch.thumbnailUrl,
    subscriberCount: ch.subscriberCount,
  );
}

typedef _OldYtChannel = YouTubeChannel;
