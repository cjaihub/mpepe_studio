import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class MpepeCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;

  const MpepeCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor ?? AppColors.lineSoft),
      ),
      child: child,
    );
  }
}

class MpepeAvatar extends StatelessWidget {
  final String text;
  final double size;
  final Gradient? gradient;
  final Color? backgroundColor;

  const MpepeAvatar({
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
        color: gradient == null ? (backgroundColor ?? AppColors.surface2) : null,
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: size * 0.4,
        ),
      ),
    );
  }
}

class MpepePill extends StatelessWidget {
  final String text;
  final bool isOutline;
  final bool isLive;
  final bool isAi;

  const MpepePill({
    super.key,
    required this.text,
    this.isOutline = false,
    this.isLive = false,
    this.isAi = false,
  });

  @override
  Widget build(BuildContext context) {
    Color bgColor = Colors.transparent;
    Color textColor = AppColors.primaryText;
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
      bgColor = const Color(0x24FF0000);
      textColor = AppColors.ytAccent;
      border = Border.all(color: const Color(0x4DFF0000));
    } else if (isOutline) {
      textColor = AppColors.ashText;
      border = Border.all(color: AppColors.line);
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

class MpepeButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final bool isPrimary;
  final IconData? icon;

  const MpepeButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isPrimary = true,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isPrimary ? AppColors.ytAccent : Colors.white,
        foregroundColor: isPrimary ? Colors.white : AppColors.ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        elevation: 0,
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
          Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5)),
        ],
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
        return Container(
          width: 14,
          height: 6,
          margin: EdgeInsets.only(right: index == totalSteps - 1 ? 0 : 4),
          decoration: BoxDecoration(
            color: isCompleted ? AppColors.violet : AppColors.surface2,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}
