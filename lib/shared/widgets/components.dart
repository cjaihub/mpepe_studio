import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
class OneovaCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final VoidCallback? onTap;

  const OneovaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderColor,
    this.onTap,
  });

  @override
  State<OneovaCard> createState() => _OneovaCardState();
}

class _OneovaCardState extends State<OneovaCard> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget card = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: widget.borderColor ?? 
                 (isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.05)),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? (widget.borderColor?.withValues(alpha: _isHovered ? 0.3 : 0.0) ?? Colors.black.withValues(alpha: 0.4)) : Colors.black.withValues(alpha: _isHovered ? 0.08 : 0.04),
            blurRadius: _isHovered ? 30 : 15,
            spreadRadius: _isHovered ? 2 : 0,
            offset: _isHovered ? const Offset(0, 15) : const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
            padding: widget.padding,
            decoration: BoxDecoration(
              color: isDark 
                  ? theme.colorScheme.surface.withValues(alpha: 0.85)
                  : theme.colorScheme.surface.withValues(alpha: 0.95),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: isDark ? 0.06 : 0.3)),
                left: BorderSide(color: Colors.white.withValues(alpha: isDark ? 0.06 : 0.3)),
              ),
            ),
            child: widget.child,
        ),
      ),
    );

    if (widget.onTap != null) {
      card = GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap!();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: AnimatedScale(
            scale: _isPressed ? 0.96 : (_isHovered ? 1.02 : 1.0),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: card,
          ),
        ),
      );
    } else {
      card = MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: card,
      );
    }

    return card;
  }
}

class OneovaAvatar extends StatelessWidget {
  final String text;
  final double size;
  final Gradient? gradient;
  final Color? backgroundColor;

  const OneovaAvatar({
    super.key,
    required this.text,
    this.size = 32,
    this.gradient,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: gradient,
        color: gradient == null ? (backgroundColor ?? Theme.of(context).scaffoldBackgroundColor) : null,
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          color: gradient == null ? Theme.of(context).colorScheme.onSurface : Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: size * 0.4,
        ),
      ),
    );
  }
}

class OneovaPill extends StatelessWidget {
  final String text;
  final bool isOutline;
  final bool isLive;
  final bool isAi;
  final bool isGhost;
  final Color? color;

  const OneovaPill({
    super.key,
    required this.text,
    this.isOutline = false,
    this.isLive = false,
    this.isAi = false,
    this.isGhost = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    Color bgColor = isGhost ? (color?.withValues(alpha: 0.15) ?? Colors.transparent) : (color ?? Colors.transparent);
    Color textColor = isGhost ? (color ?? Theme.of(context).colorScheme.onSurface) : Theme.of(context).colorScheme.surface;
    Border? border;

    if (isAi) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: AppColors.aiGradient,
        ),
        child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
      );
    } else if (isLive) {
      bgColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.1);
      textColor = Theme.of(context).colorScheme.primary;
      border = Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3));
    } else if (isOutline) {
      textColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
      border = Border.all(color: Theme.of(context).colorScheme.outline);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
        border: border,
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class OneovaButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;
  final bool isPrimary;
  final IconData? icon;
  final Widget? customIconWidget;

  const OneovaButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isPrimary = true,
    this.icon,
    this.customIconWidget,
  });

  @override
  State<OneovaButton> createState() => _OneovaButtonState();
}

class _OneovaButtonState extends State<OneovaButton> {
  bool _isPressed = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onPressed();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: AnimatedScale(
          scale: _isPressed ? 0.95 : (_isHovered ? 1.02 : 1.0),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: widget.isPrimary ? AppColors.brandBlue : theme.colorScheme.surface,
              border: widget.isPrimary 
                  ? null 
                  : Border.all(color: theme.colorScheme.outline),
              boxShadow: widget.isPrimary && (_isHovered || _isPressed) ? [
                BoxShadow(
                  color: AppColors.neonPink.withValues(alpha: 0.4),
                  blurRadius: 20,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                )
              ] : [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.customIconWidget != null) ...[widget.customIconWidget!, const SizedBox(width: 8)]
                else if (widget.icon != null) ...[Icon(widget.icon, size: 18, color: widget.isPrimary ? Colors.white : theme.colorScheme.onSurface), const SizedBox(width: 8)],
                Text(
                  widget.text, 
                  style: TextStyle(
                    fontWeight: FontWeight.bold, 
                    fontSize: 14.5,
                    color: widget.isPrimary ? Colors.white : theme.colorScheme.onSurface,
                  )
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StepProgressIndicator extends StatelessWidget {
  final int totalSteps;
  final int completedSteps;

  const StepProgressIndicator({
    super.key,
    required this.totalSteps,
    required this.completedSteps,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(totalSteps, (index) {
        final isCompleted = index < completedSteps;
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        
        return AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          width: isCompleted ? 18 : 10,
          height: 6,
          margin: EdgeInsets.only(right: index == totalSteps - 1 ? 0 : 5),
          decoration: BoxDecoration(
            color: isCompleted 
                ? theme.colorScheme.primary 
                : (isDark ? Colors.white.withValues(alpha: 0.1) : theme.colorScheme.outline.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(4),
            boxShadow: isCompleted ? [
              BoxShadow(
                color: theme.colorScheme.primary.withValues(alpha: 0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              )
            ] : null,
          ),
        );
      }),
    );
  }
}

class OneovaInputField extends StatelessWidget {
  final TextEditingController? controller;
  final String hintText;
  final IconData? prefixIcon;
  final TextInputType keyboardType;
  final bool obscureText;
  final TextAlign textAlign;
  final TextStyle? style;

  const OneovaInputField({
    super.key,
    this.controller,
    required this.hintText,
    this.prefixIcon,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.textAlign = TextAlign.start,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        textAlign: textAlign,
        style: style ?? TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 16),
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)) : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
          ),
        ),
      ),
    );
  }
}

// Rebranding aliases for zero-breakage backwards and forward compatibility
typedef OneOvaCard = OneovaCard;
typedef OneOvaAvatar = OneovaAvatar;
typedef OneOvaPill = OneovaPill;
typedef OneOvaButton = OneovaButton;
typedef OneOvaInputField = OneovaInputField;

typedef OnerovaCard = OneovaCard;
typedef OnerovaAvatar = OneovaAvatar;
typedef OnerovaPill = OneovaPill;
typedef OnerovaButton = OneovaButton;
typedef OnerovaInputField = OneovaInputField;

typedef MpepeCard = OneovaCard;
typedef MpepeAvatar = OneovaAvatar;
typedef MpepePill = OneovaPill;
typedef MpepeButton = OneovaButton;
typedef MpepeInputField = OneovaInputField;

