import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/theme/app_theme.dart';
import '../services/ova_context_service.dart';
import '../services/ova_device_control.dart';

/// Guided one-time setup for Ova system-wide control (Phase 0).
/// Android never allows silent permission grants, so each capability is
/// explained and enabled by the user.
class OvaSetupScreen extends ConsumerStatefulWidget {
  const OvaSetupScreen({super.key});

  @override
  ConsumerState<OvaSetupScreen> createState() => _OvaSetupScreenState();
}

class _OvaSetupScreenState extends ConsumerState<OvaSetupScreen> with WidgetsBindingObserver {
  bool _a11y = false;
  bool _overlay = false;
  bool _biometric = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final control = ref.read(ovaDeviceControlProvider);
    final native = ref.read(ovaNativeServiceProvider);
    final a11y = await control.isEnabled();
    final overlay = await native.canDrawOverlays();
    if (!mounted) return;
    setState(() {
      _a11y = a11y;
      _overlay = overlay;
    });
  }

  Future<void> _confirmAccessibility() async {
    HapticFeedback.lightImpact();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        title: Text('Allow Ova to control your device?',
            style: GoogleFonts.inter(fontSize: 15.5, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
        content: Text(
          'Oneova uses Android Accessibility only when you ask Ova to act. '
          'Ova can read the text on your screen and tap, scroll, type and navigate apps for you. '
          'Password fields are never read, and sensitive actions need your fingerprint or PIN. '
          'You can turn this off any time in Settings.',
          style: GoogleFonts.inter(fontSize: 12.5, height: 1.35, color: ctx.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(ovaDeviceControlProvider).openAccessibilitySettings();
    }
  }

  Future<void> _testBiometric() async {
    final ok = await ref.read(ovaDeviceControlProvider).verifyOwner();
    if (mounted) setState(() => _biometric = ok);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        toolbarHeight: 52,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('Ova Setup',
            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: context.textPrimary)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Let Ova work over any app. Open it from the Ask Ova quick-settings tile or the Accessibility button.',
            style: GoogleFonts.inter(fontSize: 12.5, height: 1.35, color: context.textSecondary),
          ),
          const SizedBox(height: 14),
          _StepTile(
            icon: Icons.accessibility_new_rounded,
            title: 'Device control',
            subtitle: 'Read screen, tap, scroll, type, back/home',
            done: _a11y,
            actionLabel: _a11y ? 'Enabled' : 'Enable',
            onTap: _a11y ? null : _confirmAccessibility,
          ),
          _StepTile(
            icon: Icons.layers_outlined,
            title: 'Display over other apps',
            subtitle: 'Show Ova chat bubbles on top of any app',
            done: _overlay,
            actionLabel: _overlay ? 'Enabled' : 'Allow',
            onTap: _overlay ? null : () => ref.read(ovaNativeServiceProvider).requestOverlayPermission(),
          ),
          _StepTile(
            icon: Icons.fingerprint_rounded,
            title: 'Fingerprint / PIN gate',
            subtitle: 'Required before Ova taps, types or locks',
            done: _biometric,
            actionLabel: _biometric ? 'Verified' : 'Test',
            onTap: _testBiometric,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: AppDecorations.card(context),
            child: Text(
              'Try: "go back", "scroll down", "tap Send", "type hello", "open notifications", "take a screenshot".',
              style: GoogleFonts.inter(fontSize: 11.5, height: 1.4, color: context.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool done;
  final String actionLabel;
  final VoidCallback? onTap;

  const _StepTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.done,
    required this.actionLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: AppDecorations.card(context),
      child: Row(
        children: [
          Icon(icon, size: 22, color: done ? AppColors.brandBlue : context.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: context.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle, style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 34,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: done ? context.surfaceMid : AppColors.brandBlue,
                foregroundColor: done ? context.textSecondary : Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
              child: Text(actionLabel, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
