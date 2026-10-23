import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

enum ModalVariant {
  confirmation,
  destructive,
  information,
  form,
  warning,
  permission,
  success,
  error,
}

class AppModals {
  static Future<T?> _showBaseDialog<T>({
    required BuildContext context,
    required ModalVariant variant,
    required String title,
    required String message,
    Widget? customContent,
    List<Widget>? customActions,
    String confirmText = "Confirm",
    String cancelText = "Cancel",
    VoidCallback? onConfirm,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) {
        Color primaryColor;
        IconData icon;

        switch (variant) {
          case ModalVariant.destructive:
          case ModalVariant.error:
            primaryColor = Colors.redAccent;
            icon = Icons.warning_amber_rounded;
            break;
          case ModalVariant.warning:
            primaryColor = Colors.orangeAccent;
            icon = Icons.report_problem_outlined;
            break;
          case ModalVariant.success:
            primaryColor = Colors.green;
            icon = Icons.check_circle_outline;
            break;
          case ModalVariant.permission:
            primaryColor = Colors.blueAccent;
            icon = Icons.security;
            break;
          case ModalVariant.information:
            primaryColor = ctx.brandBlue;
            icon = Icons.info_outline;
            break;
          case ModalVariant.confirmation:
          case ModalVariant.form:
            primaryColor = AppColors.brandBlue;
            icon = Icons.help_outline;
            break;
        }

        return AlertDialog(
          backgroundColor: ctx.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(icon, color: primaryColor, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w900,
                    color: ctx.textPrimary,
                    fontSize: 20,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: GoogleFonts.inter(color: ctx.textSecondary, fontSize: 16),
              ),
              if (customContent != null) ...[
                const SizedBox(height: 24),
                customContent,
              ]
            ],
          ),
          actions: customActions ??
              [
                if (variant != ModalVariant.information && variant != ModalVariant.success && variant != ModalVariant.error)
                  TextButton(
                    onPressed: () => ctx.pop(),
                    child: Text(cancelText, style: GoogleFonts.inter(color: ctx.textMuted, fontWeight: FontWeight.bold)),
                  ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  onPressed: () {
                    ctx.pop();
                    onConfirm?.call();
                  },
                  child: Text(
                    confirmText,
                    style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
        );
      },
    );
  }

  static Future<void> showConfirmation(BuildContext context, String title, String message, VoidCallback onConfirm) {
    return _showBaseDialog(
      context: context,
      variant: ModalVariant.confirmation,
      title: title,
      message: message,
      onConfirm: onConfirm,
    );
  }

  static Future<void> showDestructive({
    required BuildContext context,
    required String title,
    required String message,
    required VoidCallback onConfirm,
    bool isIrreversible = false,
  }) {
    if (!isIrreversible) {
      return _showBaseDialog(
        context: context,
        variant: ModalVariant.destructive,
        title: title,
        message: message,
        confirmText: "Delete",
        onConfirm: onConfirm,
      );
    }

    // For irreversible operations, force the user to type CONFIRM.
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _IrreversibleDialogContent(
        title: title,
        message: message,
        onConfirm: onConfirm,
      ),
    );
  }

  static Future<void> showInformation(BuildContext context, String title, String message) {
    return _showBaseDialog(
      context: context,
      variant: ModalVariant.information,
      title: title,
      message: message,
      confirmText: "Understood",
    );
  }
}

class _IrreversibleDialogContent extends StatefulWidget {
  final String title;
  final String message;
  final VoidCallback onConfirm;

  const _IrreversibleDialogContent({
    required this.title,
    required this.message,
    required this.onConfirm,
  });

  @override
  State<_IrreversibleDialogContent> createState() => _IrreversibleDialogContentState();
}

class _IrreversibleDialogContentState extends State<_IrreversibleDialogContent> {
  final TextEditingController _controller = TextEditingController();
  bool _isValid = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Colors.redAccent, width: 2),
      ),
      title: Row(
        children: [
          const Icon(Icons.warning, color: Colors.redAccent, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.title,
              style: GoogleFonts.inter(fontWeight: FontWeight.w900, color: context.textPrimary, fontSize: 20),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.message,
            style: GoogleFonts.inter(color: context.textSecondary, fontSize: 16),
          ),
          const SizedBox(height: 16),
          Text(
            "This action is permanent and irreversible. Please type CONFIRM to proceed.",
            style: GoogleFonts.inter(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            style: TextStyle(color: context.textPrimary),
            decoration: InputDecoration(
              hintText: "CONFIRM",
              hintStyle: TextStyle(color: context.textMuted),
              filled: true,
              fillColor: context.bg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.border)),
            ),
            onChanged: (val) {
              setState(() {
                _isValid = val == "CONFIRM";
              });
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => context.pop(),
          child: Text("Cancel", style: GoogleFonts.inter(color: context.textMuted, fontWeight: FontWeight.bold)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _isValid ? Colors.redAccent : (context.isDark ? Colors.grey.shade800 : Colors.grey.shade300),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _isValid ? () {
            context.pop();
            widget.onConfirm();
          } : null,
          child: Text("Permanently Delete", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w900)),
        ),
      ],
    );
  }
}
