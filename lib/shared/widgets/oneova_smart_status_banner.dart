import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

enum OneovaStatusKind {
  info,
  live,
  uploading,
  success,
  warning,
  error,
}

class OneovaStatusEvent {
  final String id;
  final String title;
  final String? subtitle;
  final String source;
  final OneovaStatusKind kind;
  final DateTime timestamp;

  const OneovaStatusEvent({
    required this.id,
    required this.title,
    this.subtitle,
    required this.source,
    required this.kind,
    required this.timestamp,
  });
}

/// Global Smart Status & Error Reporter with smooth auto-fade overlays,
/// retry callbacks, haptic cues, and an inspectable live event history log.
class OneovaSmartStatus {
  OneovaSmartStatus._();

  static final ValueNotifier<List<OneovaStatusEvent>> historyNotifier =
      ValueNotifier<List<OneovaStatusEvent>>(<OneovaStatusEvent>[]);

  static OverlayEntry? _activeEntry;
  static _OneovaOverlayEntryController? _activeController;

  static void recordEvent({
    required String title,
    String? subtitle,
    String source = 'System',
    OneovaStatusKind kind = OneovaStatusKind.info,
  }) {
    final event = OneovaStatusEvent(
      id: '${DateTime.now().microsecondsSinceEpoch}_${historyNotifier.value.length}',
      title: title,
      subtitle: subtitle,
      source: source,
      kind: kind,
      timestamp: DateTime.now(),
    );
    final updated = <OneovaStatusEvent>[event, ...historyNotifier.value];
    if (updated.length > 80) {
      updated.removeRange(80, updated.length);
    }
    historyNotifier.value = updated;
  }

  static void clearHistory() {
    historyNotifier.value = const <OneovaStatusEvent>[];
  }

  /// Displays a compact, high-contrast auto-fading popup pill at the top or bottom
  /// of the viewport and records it in [historyNotifier].
  static void show(
    BuildContext context, {
    required String title,
    String? subtitle,
    String source = 'Oneova',
    OneovaStatusKind kind = OneovaStatusKind.info,
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
    bool alignBottom = false,
    bool logToHistory = true,
  }) {
    if (logToHistory) {
      recordEvent(
        title: title,
        subtitle: subtitle,
        source: source,
        kind: kind,
      );
    }

    if (!context.mounted) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true) ??
        Overlay.maybeOf(context);
    if (overlay == null) {
      // Fallback to themed SnackBar if no Overlay is available in context.
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(
          backgroundColor: kind == OneovaStatusKind.error ||
                  kind == OneovaStatusKind.warning
              ? AppColors.brandPink
              : AppColors.brandBlue,
          duration: duration ?? const Duration(seconds: 4),
          content: Text(
            subtitle != null && subtitle.isNotEmpty
                ? '$title — $subtitle'
                : title,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          action: (actionLabel != null && onAction != null)
              ? SnackBarAction(
                  label: actionLabel,
                  textColor: Colors.white,
                  onPressed: onAction,
                )
              : null,
        ),
      );
      return;
    }

    dismiss();

    final effectiveDuration = duration ??
        switch (kind) {
          OneovaStatusKind.error => const Duration(milliseconds: 5600),
          OneovaStatusKind.warning => const Duration(milliseconds: 4800),
          OneovaStatusKind.uploading => const Duration(seconds: 8),
          _ => const Duration(milliseconds: 3400),
        };

    if (kind == OneovaStatusKind.error) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }

    final controller = _OneovaOverlayEntryController();
    _activeController = controller;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) => _SmartStatusFloatingToast(
        title: title,
        subtitle: subtitle,
        source: source,
        kind: kind,
        duration: effectiveDuration,
        actionLabel: actionLabel,
        onAction: onAction,
        alignBottom: alignBottom,
        controller: controller,
        onDismissed: () {
          if (_activeEntry == entry) {
            entry.remove();
            _activeEntry = null;
            _activeController = null;
          }
        },
      ),
    );

    _activeEntry = entry;
    overlay.insert(entry);
  }

  static void dismiss() {
    _activeController?.dismissNow();
    if (_activeEntry != null) {
      try {
        _activeEntry!.remove();
      } catch (_) {}
      _activeEntry = null;
      _activeController = null;
    }
  }

  /// Opens a clean dual-mode bottom sheet inspecting recent notifications,
  /// status transitions, and smart error reports.
  static Future<void> showHistorySheet(
    BuildContext context, {
    String heading = 'Live Status & Event History',
  }) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.72,
          ),
          decoration: BoxDecoration(
            color: sheetCtx.bg,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.xl),
            ),
            border: Border(
              top: BorderSide(color: sheetCtx.border, width: 1.0),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: sheetCtx.border,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.brandBlue.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: const Icon(
                          Icons.bolt_rounded,
                          size: 16,
                          color: AppColors.brandBlue,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          heading,
                          style: AppTypography.sectionTitle(
                            sheetCtx.textPrimary,
                          ),
                        ),
                      ),
                      ValueListenableBuilder<List<OneovaStatusEvent>>(
                        valueListenable: historyNotifier,
                        builder: (ctx, items, _) {
                          if (items.isEmpty) return const SizedBox.shrink();
                          return TextButton(
                            onPressed: clearHistory,
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: sheetCtx.textSecondary,
                            ),
                            child: Text(
                              'Clear',
                              style: AppTypography.small(
                                sheetCtx.textSecondary,
                              ),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: sheetCtx.textSecondary,
                        ),
                        onPressed: () => Navigator.of(sheetCtx).pop(),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: sheetCtx.border),
                Flexible(
                  child: ValueListenableBuilder<List<OneovaStatusEvent>>(
                    valueListenable: historyNotifier,
                    builder: (ctx, items, _) {
                      if (items.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 40,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.verified_outlined,
                                size: 32,
                                color: ctx.textMuted,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'All systems healthy',
                                style: AppTypography.callout(ctx.textPrimary),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Live connection events, background sync updates, and smart error reports appear here automatically.',
                                textAlign: TextAlign.center,
                                style: AppTypography.caption(ctx.textSecondary),
                              ),
                            ],
                          ),
                        );
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (ctx, index) {
                          final item = items[index];
                          final accent = _accentForKind(item.kind);
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: ctx.surface,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.md),
                              border: Border.all(
                                color: ctx.border,
                                width: 1.0,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(top: 2),
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.14),
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.xs),
                                  ),
                                  child: Icon(
                                    _iconForKind(item.kind),
                                    size: 14,
                                    color: accent,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              item.title,
                                              style: AppTypography.bodyMedium(
                                                ctx.textPrimary,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            _formatAgo(item.timestamp),
                                            style: AppTypography.caption(
                                              ctx.textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (item.subtitle != null &&
                                          item.subtitle!.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          item.subtitle!,
                                          style: AppTypography.caption(
                                            ctx.textSecondary,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 4),
                                      Text(
                                        item.source.toUpperCase(),
                                        style: AppTypography.micro(accent),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Color _accentForKind(OneovaStatusKind kind) {
    switch (kind) {
      case OneovaStatusKind.error:
      case OneovaStatusKind.warning:
        return AppColors.brandPink;
      case OneovaStatusKind.live:
      case OneovaStatusKind.uploading:
      case OneovaStatusKind.success:
      case OneovaStatusKind.info:
        return AppColors.brandBlue;
    }
  }

  static IconData _iconForKind(OneovaStatusKind kind) {
    switch (kind) {
      case OneovaStatusKind.error:
        return Icons.error_outline_rounded;
      case OneovaStatusKind.warning:
        return Icons.warning_amber_rounded;
      case OneovaStatusKind.success:
        return Icons.check_circle_outline_rounded;
      case OneovaStatusKind.uploading:
        return Icons.cloud_upload_outlined;
      case OneovaStatusKind.live:
        return Icons.sensors_rounded;
      case OneovaStatusKind.info:
        return Icons.info_outline_rounded;
    }
  }

  static String _formatAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 5) return 'now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}

class _OneovaOverlayEntryController {
  VoidCallback? _onDismissNow;
  void dismissNow() => _onDismissNow?.call();
}

class _SmartStatusFloatingToast extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String source;
  final OneovaStatusKind kind;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool alignBottom;
  final _OneovaOverlayEntryController controller;
  final VoidCallback onDismissed;

  const _SmartStatusFloatingToast({
    required this.title,
    this.subtitle,
    required this.source,
    required this.kind,
    required this.duration,
    this.actionLabel,
    this.onAction,
    required this.alignBottom,
    required this.controller,
    required this.onDismissed,
  });

  @override
  State<_SmartStatusFloatingToast> createState() =>
      _SmartStatusFloatingToastState();
}

class _SmartStatusFloatingToastState extends State<_SmartStatusFloatingToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  Timer? _autoFadeTimer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: Offset(0, widget.alignBottom ? 0.25 : -0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));

    widget.controller._onDismissNow = _startClose;
    _anim.forward();
    _autoFadeTimer = Timer(widget.duration, _startClose);
  }

  Future<void> _startClose() async {
    if (_closing || !mounted) return;
    _closing = true;
    _autoFadeTimer?.cancel();
    await _anim.reverse();
    if (mounted) {
      widget.onDismissed();
    }
  }

  @override
  void dispose() {
    _autoFadeTimer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final accent = OneovaSmartStatus._accentForKind(widget.kind);
    final isAlert = widget.kind == OneovaStatusKind.error ||
        widget.kind == OneovaStatusKind.warning;

    return Positioned(
      top: widget.alignBottom ? null : media.padding.top + 10,
      bottom: widget.alignBottom
          ? media.padding.bottom + media.viewInsets.bottom + 72
          : null,
      left: 14,
      right: 14,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SlideTransition(
            position: _slide,
            child: FadeTransition(
              opacity: _fade,
              child: Dismissible(
                key: ValueKey('smart_status_${widget.title}_${widget.source}'),
                direction: DismissDirection.horizontal,
                onDismissed: (_) => widget.onDismissed(),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      color: context.surface,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: isAlert
                            ? AppColors.brandPink.withValues(alpha: 0.55)
                            : context.border,
                        width: 1.0,
                      ),
                      boxShadow: AppShadows.md,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.14),
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.sm),
                                ),
                                child: widget.kind == OneovaStatusKind.uploading
                                    ? const Padding(
                                        padding: EdgeInsets.all(6),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                            AppColors.brandBlue,
                                          ),
                                        ),
                                      )
                                    : Icon(
                                        OneovaSmartStatus._iconForKind(
                                          widget.kind,
                                        ),
                                        size: 16,
                                        color: accent,
                                      ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      widget.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: context.textPrimary,
                                      ),
                                    ),
                                    if (widget.subtitle != null &&
                                        widget.subtitle!.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        widget.subtitle!,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          fontSize: 11.2,
                                          fontWeight: FontWeight.w500,
                                          color: context.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (widget.actionLabel != null &&
                                  widget.onAction != null) ...[
                                const SizedBox(width: 8),
                                InkWell(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.sm),
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    final cb = widget.onAction!;
                                    _startClose();
                                    cb();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: accent,
                                      borderRadius:
                                          BorderRadius.circular(AppRadius.sm),
                                    ),
                                    child: Text(
                                      widget.actionLabel!,
                                      style: GoogleFonts.inter(
                                        fontSize: 11.0,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(width: 4),
                              InkWell(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.full),
                                onTap: _startClose,
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 15,
                                    color: context.textMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 1.0, end: 0.0),
                          duration: widget.duration,
                          builder: (ctx, value, _) => LinearProgressIndicator(
                            value: value,
                            minHeight: 2,
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              accent.withValues(alpha: 0.75),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact inline live status / progress / retry banner for screens & composers.
class OneovaInlineStatusBanner extends StatelessWidget {
  final String title;
  final String? subtitle;
  final OneovaStatusKind kind;
  final double? progress;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onClose;

  const OneovaInlineStatusBanner({
    super.key,
    required this.title,
    this.subtitle,
    this.kind = OneovaStatusKind.info,
    this.progress,
    this.actionLabel,
    this.onAction,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final accent = OneovaSmartStatus._accentForKind(kind);
    final isAlert = kind == OneovaStatusKind.error ||
        kind == OneovaStatusKind.warning;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isAlert
            ? AppColors.brandPink.withValues(alpha: context.isDark ? 0.14 : 0.08)
            : AppColors.brandBlue.withValues(alpha: context.isDark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: accent.withValues(alpha: 0.45),
          width: 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                if (kind == OneovaStatusKind.uploading)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      value: progress != null && progress! > 0 ? progress : null,
                      strokeWidth: 2.0,
                      valueColor: AlwaysStoppedAnimation<Color>(accent),
                    ),
                  )
                else
                  Icon(
                    OneovaSmartStatus._iconForKind(kind),
                    size: 16,
                    color: accent,
                  ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12.0,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11.0,
                            fontWeight: FontWeight.w500,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (progress != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${(progress!.clamp(0.0, 1.0) * 100).round()}%',
                    style: GoogleFonts.inter(
                      fontSize: 11.0,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                ],
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      onAction!();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        actionLabel!,
                        style: GoogleFonts.inter(
                          fontSize: 10.8,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
                if (onClose != null) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    onTap: onClose,
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Icon(
                        Icons.close_rounded,
                        size: 15,
                        color: context.textMuted,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (progress != null)
            LinearProgressIndicator(
              value: progress!.clamp(0.0, 1.0),
              minHeight: 2.5,
              backgroundColor: accent.withValues(alpha: 0.14),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
        ],
      ),
    );
  }
}
