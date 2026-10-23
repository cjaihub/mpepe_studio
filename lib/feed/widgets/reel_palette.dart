import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../shared/theme/app_theme.dart';

/// Colour tokens for everything the Reels feed draws over (or around) video.
///
/// Dark: white type on smoky glass with dark scrims (the classic look).
/// Light: slate type on frosted white glass with soft white scrims, so the
/// feed follows the app's Light mode instead of staying black.
@immutable
class ReelPalette {
  final bool dark;
  const ReelPalette({required this.dark});

  /// Feed background (letterboxing, loading, empty state).
  Color get bg => dark ? AppColors.darkBackground : AppColors.lightBackground;

  /// Primary overlay foreground (icons, usernames, captions).
  Color get fg => dark ? Colors.white : AppColors.lightTextPrimary;

  /// Secondary overlay foreground (inactive tabs, hints).
  Color get fgSoft => dark ? Colors.white.withValues(alpha: 0.75) : AppColors.lightTextSecondary;

  /// Glass fill for pills, rail buttons and docks.
  Color get glass => dark ? Colors.black.withValues(alpha: 0.32) : Colors.white.withValues(alpha: 0.74);

  /// Denser glass for bars that hold body text (comment bar, toasts).
  Color get glassStrong => dark ? Colors.black.withValues(alpha: 0.42) : Colors.white.withValues(alpha: 0.86);

  /// Hairline around glass surfaces.
  Color get glassBorder =>
      dark ? Colors.white.withValues(alpha: 0.16) : AppColors.lightTextPrimary.withValues(alpha: 0.08);

  /// Thin separators inside docks.
  Color get divider => dark ? Colors.white24 : AppColors.lightTextPrimary.withValues(alpha: 0.14);

  /// Base colour of the top/bottom legibility gradients.
  Color get scrim => dark ? Colors.black : Colors.white;
  double get scrimStrength => dark ? 0.55 : 0.78;

  /// Halo that keeps bare overlay text readable on any frame.
  List<Shadow> get textShadow => dark
      ? const [Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 1))]
      : [Shadow(color: Colors.white.withValues(alpha: 0.85), blurRadius: 8)];

  /// Placeholder behind thumbnails / avatars that have not loaded.
  Color get placeholder => dark ? AppColors.darkSurface : AppColors.lightSurfaceHighlight;

  /// Status-bar icon style matching the palette.
  SystemUiOverlayStyle get systemOverlay => dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;

  /// Nearest palette from a [ReelTheme], else from the ambient brightness.
  static ReelPalette of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ReelTheme>();
    return scope?.palette ?? ReelPalette(dark: Theme.of(context).brightness == Brightness.dark);
  }

  @override
  bool operator ==(Object other) => other is ReelPalette && other.dark == dark;

  @override
  int get hashCode => dark.hashCode;
}

/// Provides the active [ReelPalette] to the feed subtree.
class ReelTheme extends InheritedWidget {
  final ReelPalette palette;
  const ReelTheme({super.key, required this.palette, required super.child});

  @override
  bool updateShouldNotify(ReelTheme oldWidget) => oldWidget.palette != palette;
}
