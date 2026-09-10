import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../backend/meta_oauth_service.dart';
import '../shared/theme/app_theme.dart';

// Platform colour palette — used only for card glow & icon halo,
// NOT replacing the brand's mpepeMaroon/Gold.
const _fbBlue = Color(0xFF0081FB);
const _igPurple = Color(0xFF833AB4);
const _igOrange = Color(0xFFE1306C);
const _waGreen = Color(0xFF25D366);

class MetaPlatformPickerScreen extends ConsumerWidget {
  const MetaPlatformPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: Stack(
        children: [
          // ── Ambient background glow (Meta blue, very subtle) ──────────
          Positioned(
            top: -120,
            right: -80,
            child: Container(
              width: 380,
              height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _fbBlue.withValues(alpha: 0.06),
                boxShadow: [
                  BoxShadow(
                    color: _fbBlue.withValues(alpha: 0.12),
                    blurRadius: 120,
                    spreadRadius: 60,
                  ),
                ],
              ),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scale(
                  begin: const Offset(1, 1),
                  end: const Offset(1.08, 1.08),
                  duration: 7.seconds,
                  curve: Curves.easeInOutSine,
                ),
          ),
          Positioned(
            bottom: -100,
            left: -60,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _igPurple.withValues(alpha: 0.05),
                boxShadow: [
                  BoxShadow(
                    color: _igPurple.withValues(alpha: 0.10),
                    blurRadius: 100,
                    spreadRadius: 40,
                  ),
                ],
              ),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .moveY(
                  begin: 0,
                  end: -20,
                  duration: 9.seconds,
                  curve: Curves.easeInOutSine,
                ),
          ),

          // ── Main content ──────────────────────────────────────────────
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: AppColors.textPrimary,
                          size: 20,
                        ),
                        onPressed: () => context.pop(),
                      ),
                      const Spacer(),
                      _MetaBadge(),
                    ],
                  ),
                ).animate().fadeIn(duration: 400.ms),

                const SizedBox(height: 32),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Connect via',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ).animate().fadeIn(delay: 100.ms),
                      const SizedBox(height: 4),
                      Text(
                        'Meta',
                        style: GoogleFonts.outfit(
                          fontSize: 42,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                          letterSpacing: -1.5,
                        ),
                      ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.1),
                      const SizedBox(height: 8),
                      Text(
                        'Choose a platform to link to your Studio. Your credentials are always secured by OAuth — we never see your password.',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                          height: 1.55,
                        ),
                      ).animate().fadeIn(delay: 200.ms),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // Platform cards
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      _MetaPlatformCard(
                        app: MetaApp.facebook,
                        glowColor: _fbBlue,
                        subtitle: 'Pages, posts & analytics',
                        entranceDelay: 300.ms,
                      ),
                      const SizedBox(height: 14),
                      _MetaPlatformCard(
                        app: MetaApp.instagram,
                        glowColor: _igOrange,
                        subtitle: 'Reels, stories & engagement',
                        entranceDelay: 400.ms,
                      ),
                      const SizedBox(height: 14),
                      _MetaPlatformCard(
                        app: MetaApp.whatsapp,
                        glowColor: _waGreen,
                        subtitle: 'Broadcast & customer messaging',
                        entranceDelay: 500.ms,
                        isLocked: true,
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),

                // Security footer
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 13,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Secured by Meta OAuth 2.0 — we never store your password',
                        style: GoogleFonts.outfit(
                          fontSize: 11.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 700.ms),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Meta Badge widget
// ─────────────────────────────────────────────

class _MetaBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _fbBlue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _fbBlue.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _fbBlue,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Powered by Meta',
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _fbBlue,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Platform Card
// ─────────────────────────────────────────────

class _MetaPlatformCard extends ConsumerStatefulWidget {
  final MetaApp app;
  final Color glowColor;
  final String subtitle;
  final Duration entranceDelay;
  final bool isLocked;

  const _MetaPlatformCard({
    required this.app,
    required this.glowColor,
    required this.subtitle,
    required this.entranceDelay,
    this.isLocked = false,
  });

  @override
  ConsumerState<_MetaPlatformCard> createState() => _MetaPlatformCardState();
}

class _MetaPlatformCardState extends ConsumerState<_MetaPlatformCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final connectionAsync =
        ref.watch(metaConnectionStatusProvider(widget.app));
    final connectionData = connectionAsync.when(
      data: (d) => d,
      loading: () => null,
      error: (e, _) => null,
    );
    final isConnected = connectionData != null;

    return GestureDetector(
      onTapDown: widget.isLocked ? null : (_) => setState(() => _isPressed = true),
      onTapUp: widget.isLocked
          ? null
          : (_) {
              setState(() => _isPressed = false);
              _handleTap(context, isConnected, connectionData);
            },
      onTapCancel: widget.isLocked ? null : () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.97 : 1.0,
        duration: 150.ms,
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: 300.ms,
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.darkSurface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isConnected
                  ? widget.glowColor.withValues(alpha: 0.5)
                  : AppColors.outline,
              width: isConnected ? 1.5 : 1.0,
            ),
            boxShadow: isConnected
                ? [
                    BoxShadow(
                      color: widget.glowColor.withValues(alpha: 0.18),
                      blurRadius: 24,
                      spreadRadius: 0,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Row(
            children: [
              // Platform icon with halo
              _PlatformIcon(
                app: widget.app,
                glowColor: widget.glowColor,
                isConnected: isConnected,
                isLocked: widget.isLocked,
              ),
              const SizedBox(width: 16),

              // Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          widget.app.displayName,
                          style: GoogleFonts.outfit(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: widget.isLocked
                                ? AppColors.textSecondary
                                : AppColors.textPrimary,
                          ),
                        ),
                        if (isConnected) ...[
                          const SizedBox(width: 8),
                          _StatusPill(
                              label: 'Connected', color: widget.glowColor),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.isLocked
                          ? widget.subtitle
                          : isConnected
                              ? (connectionData['accountName'] as String? ?? widget.subtitle)
                              : widget.subtitle,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    if (widget.isLocked) ...[
                      const SizedBox(height: 8),
                      _StatusPill(
                          label: '🔒  Coming Soon',
                          color: AppColors.textMuted),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Trailing arrow or lock
              if (widget.isLocked)
                Icon(Icons.lock_outline_rounded,
                    color: AppColors.textMuted, size: 18)
              else
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: isConnected
                      ? widget.glowColor
                      : AppColors.textSecondary,
                  size: 16,
                ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: widget.entranceDelay).slideY(
          begin: 0.12,
          delay: widget.entranceDelay,
          duration: 450.ms,
          curve: Curves.easeOutCubic,
        );
  }

  void _handleTap(
    BuildContext context,
    bool isConnected,
    Map<String, dynamic>? connectionData,
  ) {
    if (widget.isLocked) return;

    if (isConnected) {
      // Show disconnect bottom sheet
      _showConnectedSheet(context, connectionData);
    } else {
      // Navigate to wizard
      context.push('/social_hub/meta_wizard/${widget.app.name}');
    }
  }

  void _showConnectedSheet(
      BuildContext context, Map<String, dynamic>? data) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConnectedSheet(
        app: widget.app,
        glowColor: widget.glowColor,
        connectionData: data,
        ref: ref,
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Platform Icon with glow
// ─────────────────────────────────────────────

class _PlatformIcon extends StatelessWidget {
  final MetaApp app;
  final Color glowColor;
  final bool isConnected;
  final bool isLocked;

  const _PlatformIcon({
    required this.app,
    required this.glowColor,
    required this.isConnected,
    required this.isLocked,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isLocked
            ? AppColors.darkSurfaceHighlight
            : glowColor.withValues(alpha: 0.1),
        border: Border.all(
          color: isConnected
              ? glowColor.withValues(alpha: 0.4)
              : isLocked
                  ? AppColors.outline
                  : glowColor.withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: isConnected
            ? [
                BoxShadow(
                  color: glowColor.withValues(alpha: 0.25),
                  blurRadius: 16,
                  spreadRadius: 2,
                )
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: ColorFiltered(
          colorFilter: isLocked
              ? const ColorFilter.mode(
                  AppColors.textMuted, BlendMode.srcIn)
              : const ColorFilter.mode(
                  Colors.transparent, BlendMode.dst),
          child: SvgPicture.asset(
            app.logoAsset,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Status Pill
// ─────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Connected bottom sheet
// ─────────────────────────────────────────────

class _ConnectedSheet extends StatelessWidget {
  final MetaApp app;
  final Color glowColor;
  final Map<String, dynamic>? connectionData;
  final WidgetRef ref;

  const _ConnectedSheet({
    required this.app,
    required this.glowColor,
    required this.connectionData,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final accountName = connectionData?['accountName'] ?? app.displayName;
    final followerCount = connectionData?['followerCount'] as int?;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: glowColor.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: 0.12),
            blurRadius: 30,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Account summary
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: glowColor.withValues(alpha: 0.12),
                  border:
                      Border.all(color: glowColor.withValues(alpha: 0.3)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SvgPicture.asset(app.logoAsset, fit: BoxFit.contain),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      accountName,
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (followerCount != null)
                      Text(
                        '${_formatCount(followerCount)} followers',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              _StatusPill(label: '● Live', color: glowColor),
            ],
          ),

          const SizedBox(height: 28),
          const Divider(color: AppColors.outline),
          const SizedBox(height: 20),

          // Actions
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.red.withValues(alpha: 0.4)),
                foregroundColor: Colors.red[400],
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.link_off_rounded, size: 18),
              label: Text(
                'Disconnect ${app.displayName}',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
              ),
              onPressed: () async {
                Navigator.pop(context);
                await ref.read(metaOAuthProvider.notifier).disconnect(app);
              },
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Keep Connected',
                style: GoogleFonts.outfit(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}
