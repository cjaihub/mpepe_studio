import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../backend/social/repositories/relationship_repository.dart';
import '../theme/app_theme.dart';

enum FollowButtonSize { compact, regular }

/// The one follow/unfollow control for the app.
///
/// Reads the live [FollowState] (both directions) and shows Follow, Follow
/// back, Requested, Following or Friends. Unfollowing and withdrawing a
/// request always ask first. Changes show instantly and roll back if the
/// write fails.
class FollowButton extends ConsumerStatefulWidget {
  final String targetUserId;

  /// Used in the confirmation sheet ("Unfollow Abdoul?").
  final String? targetName;
  final FollowButtonSize size;

  /// Light styling for use on the blue top bar or over video.
  final bool onBrand;

  /// Stretch to the available width (profile pages).
  final bool expand;
  final ValueChanged<FollowState>? onChanged;

  const FollowButton({
    super.key,
    required this.targetUserId,
    this.targetName,
    this.size = FollowButtonSize.regular,
    this.onBrand = false,
    this.expand = false,
    this.onChanged,
  });

  @override
  ConsumerState<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<FollowButton> {
  FollowState? _optimistic;
  bool _busy = false;

  String get _me => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> _onTap(FollowState current) async {
    if (_busy) return;
    final repo = ref.read(relationshipRepositoryProvider);
    final name = (widget.targetName?.trim().isNotEmpty ?? false) ? widget.targetName!.trim() : 'this account';

    Future<void> Function()? action;
    FollowState? next;
    switch (current) {
      case FollowState.none:
      case FollowState.followsYou:
        HapticFeedback.lightImpact();
        action = () => repo.followUser(_me, widget.targetUserId);
        next = current == FollowState.followsYou ? FollowState.mutual : FollowState.following;
        break;
      case FollowState.requested:
        final ok = await _confirm(
          title: 'Cancel follow request?',
          message: '$name won\'t see your request any more.',
          confirmLabel: 'Cancel request',
        );
        if (!ok) return;
        action = () => repo.cancelFollowRequest(_me, widget.targetUserId);
        next = FollowState.none;
        break;
      case FollowState.following:
      case FollowState.mutual:
        final ok = await _confirm(
          title: 'Unfollow $name?',
          message: 'Their posts will stop showing in your Following feed. You can follow again any time.',
          confirmLabel: 'Unfollow',
        );
        if (!ok) return;
        action = () => repo.unfollowUser(_me, widget.targetUserId);
        next = current == FollowState.mutual ? FollowState.followsYou : FollowState.none;
        break;
      case FollowState.self:
      case FollowState.blocked:
        return;
    }

    setState(() {
      _busy = true;
      _optimistic = next;
    });
    try {
      await action();
      widget.onChanged?.call(next);
    } catch (e) {
      debugPrint('[FollowButton] ${current.name} → ${next.name} failed: $e');
      if (!mounted) return;
      setState(() => _optimistic = null);
      final text = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(
          text.contains('blocked')
              ? 'You can\'t follow this account.'
              : text.contains('permission-denied')
                  ? 'Following isn\'t allowed for this account right now.'
                  : 'Couldn\'t update. Check your connection.',
          style: GoogleFonts.inter(fontSize: 12.5),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.brandBlue,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm({required String title, required String message, required String confirmLabel}) async {
    HapticFeedback.lightImpact();
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: ctx.border, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
              const SizedBox(height: 6),
              Text(message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 12.5, height: 1.35, color: ctx.textSecondary)),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandPink,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(confirmLabel,
                      style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.brandWhite)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: ctx.border, width: 1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text('Keep',
                      style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: ctx.textPrimary)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    if (_me.isEmpty || widget.targetUserId.isEmpty || widget.targetUserId == _me) {
      return const SizedBox.shrink();
    }
    final live = ref.watch(followStateProvider((me: _me, them: widget.targetUserId)));
    // Drop the optimistic value once the server agrees.
    if (_optimistic != null && live.value == _optimistic) _optimistic = null;
    final state = _optimistic ?? live.value;
    if (state == null) return _shell(label: '', primary: false, loading: true);
    if (state == FollowState.self || state == FollowState.blocked) return const SizedBox.shrink();

    final (label, icon, primary) = switch (state) {
      FollowState.none => ('Follow', Icons.person_add_alt_1_rounded, true),
      FollowState.followsYou => ('Follow back', Icons.person_add_alt_1_rounded, true),
      FollowState.requested => ('Requested', Icons.schedule_rounded, false),
      FollowState.following => ('Following', Icons.check_rounded, false),
      FollowState.mutual => ('Friends', Icons.people_alt_rounded, false),
      _ => ('Follow', Icons.person_add_alt_1_rounded, true),
    };
    return _shell(label: label, icon: icon, primary: primary, onTap: () => _onTap(state));
  }

  Widget _shell({
    required String label,
    IconData? icon,
    required bool primary,
    bool loading = false,
    VoidCallback? onTap,
  }) {
    final compact = widget.size == FollowButtonSize.compact;
    final height = compact ? 28.0 : 38.0;
    final fontSize = compact ? 11.5 : 13.0;

    final Color fill;
    final Color fg;
    final Color border;
    if (widget.onBrand) {
      fill = primary ? AppColors.brandWhite : AppColors.brandWhite.withValues(alpha: 0.14);
      fg = primary ? AppColors.brandBlue : AppColors.brandWhite;
      border = AppColors.brandWhite.withValues(alpha: primary ? 1 : 0.4);
    } else {
      fill = primary ? AppColors.brandBlue : context.surfaceMid;
      fg = primary ? AppColors.brandWhite : context.textPrimary;
      border = primary ? AppColors.brandBlue : context.border;
    }

    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: height,
      width: widget.expand ? double.infinity : null,
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 16),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(compact ? AppRadius.full : AppRadius.md),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading || _busy)
            SizedBox(
              width: compact ? 12 : 14,
              height: compact ? 12 : 14,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: fg),
            )
          else if (icon != null)
            Icon(icon, size: compact ? 13 : 16, color: fg),
          if (label.isNotEmpty) ...[
            SizedBox(width: compact ? 4 : 6),
            Text(
              label,
              style: GoogleFonts.inter(fontSize: fontSize, fontWeight: FontWeight.w700, color: fg),
            ),
          ],
        ],
      ),
    );

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.1,
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: child.animate(key: ValueKey(label)).fadeIn(duration: 160.ms),
        ),
      ),
    );
  }
}
