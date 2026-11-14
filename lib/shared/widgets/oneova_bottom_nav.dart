// LOCKED WIDGET — see .agents/rules/oneova_home_launch_screen.md and AGENTS.md.
// Matches the approved home design: Reels | Chat(badge) | STUDIO (+) | Wallet | Me(dot).
// 2026-11-14: AI Lab tab replaced by Wallet on the user's explicit request (AI now opens from Chats).
// Glyphs upgraded on user request (custom Reels/Chat painters, gradient AI, avatar Me); layout unchanged.
// Do NOT restyle, reorder, or replace without explicit user approval.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../../backend/social/providers/unread_chat_count_provider.dart';
import '../../backend/user_service.dart';
import 'oneova_nav_glyphs.dart';

/// Draws a tab glyph for the given state.
typedef _GlyphBuilder = Widget Function(bool active, Color color, double size);

enum OneovaTab { reels, chat, wallet, me }

class OneovaBottomNav extends ConsumerWidget {
  final OneovaTab? active;
  final VoidCallback onReels;
  final VoidCallback onChat;
  final VoidCallback onStudio;
  final VoidCallback onWallet;
  final VoidCallback onMe;

  const OneovaBottomNav({
    super.key,
    required this.active,
    required this.onReels,
    required this.onChat,
    required this.onStudio,
    required this.onWallet,
    required this.onMe,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadChatCountProvider).maybeWhen(data: (v) => v, orElse: () => 0);
    final me = ref.watch(currentUserProfileProvider).value;
    final photoUrl = me?.profilePhotoUrl ?? '';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.background(context),
        border: Border(
          top: BorderSide(
            color: AppColors.border(context),
            width: 0.8,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _item(
                context,
                (a, c, s) => ReelsGlyph(active: a, color: c, size: s),
                'Reels',
                active == OneovaTab.reels,
                onReels,
              ),
              _item(
                context,
                (a, c, s) => ChatGlyph(active: a, color: c, size: s),
                'Chat',
                active == OneovaTab.chat,
                onChat,
                badge: unread > 0 ? (unread > 99 ? '99+' : '$unread') : null,
              ),
              _studio(context),
              _item(
                context,
                (a, c, s) => a
                    ? GradientIcon(Icons.account_balance_wallet_rounded, size: s)
                    : Icon(Icons.account_balance_wallet_outlined, color: c, size: s),
                'Wallet',
                active == OneovaTab.wallet,
                onWallet,
              ),
              _item(
                context,
                (a, c, s) => _MeGlyph(active: a, color: c, size: s, photoUrl: photoUrl),
                'Me',
                active == OneovaTab.me,
                onMe,
                dot: AppColors.brandPink,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(
    BuildContext context,
    _GlyphBuilder glyph,
    String label,
    bool isActive,
    VoidCallback onTap, {
    String? badge,
    Color? dot,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // In Dark mode: active icon is brandBlue; in White mode: active icon is brandPink
    final activeColor = isDark ? AppColors.brandBlue : AppColors.brandPink;
    final inactiveColor = AppColors.textSecondaryOf(context);

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedScale(
                    scale: isActive ? 1.08 : 1.0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutBack,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isActive
                            ? (isDark
                                ? AppColors.brandBlue.withValues(alpha: 0.14)
                                : AppColors.brandPink.withValues(alpha: 0.10))
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        switchInCurve: Curves.easeOutBack,
                        transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                        child: KeyedSubtree(
                          key: ValueKey(isActive),
                          child: glyph(isActive, isActive ? activeColor : inactiveColor, isActive ? 22 : 20),
                        ),
                      ),
                    ),
                  ),
                  if (badge != null)
                    Positioned(
                      right: -4,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.brandPink,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.brandPink.withValues(alpha: 0.5),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Text(
                          badge,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    )
                  else if (dot != null)
                    Positioned(
                      right: 2,
                      top: 0,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: dot,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: dot.withValues(alpha: 0.6),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: isActive
                      ? (isDark ? Colors.white : AppColors.brandPink)
                      : inactiveColor,
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(height: 2),
              AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutBack,
                width: isActive ? 5 : 0,
                height: isActive ? 5 : 0,
                decoration: BoxDecoration(
                  color: AppColors.brandPink,
                  shape: BoxShape.circle,
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: AppColors.brandPink.withValues(alpha: 0.6),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _studio(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          onStudio();
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 32,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color.lerp(AppColors.brandBlue, Colors.white, 0.18)!, AppColors.brandBlue],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: isDark ? 0.16 : 0.35),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? AppColors.brandBlue.withValues(alpha: 0.5)
                        : AppColors.brandBlue.withValues(alpha: 0.35),
                    blurRadius: 10,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
              child: const Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'STUDIO',
              style: GoogleFonts.inter(
                color: isDark ? AppColors.textSecondaryOf(context) : AppColors.brandBlue,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Profile photo for the "Me" tab with a brand-gradient ring when active;
/// falls back to a person icon until the photo is available.
class _MeGlyph extends StatelessWidget {
  final bool active;
  final Color color;
  final double size;
  final String photoUrl;
  const _MeGlyph({required this.active, required this.color, required this.size, required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    if (!photoUrl.startsWith('http')) {
      return active
          ? GradientIcon(Icons.account_circle_rounded, size: size)
          : Icon(Icons.account_circle_outlined, color: color, size: size);
    }
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: active ? kOneovaNavGradient : null,
        border: active ? null : Border.all(color: color, width: 1.2),
      ),
      child: ClipOval(
        child: Image.network(
          photoUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Icon(Icons.person_rounded, color: color, size: size * 0.7),
        ),
      ),
    );
  }
}
