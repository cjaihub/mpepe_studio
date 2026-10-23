import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/theme/app_theme.dart';
import '../ova_assistant_manager.dart';
import '../services/ova_context_service.dart';
import '../services/ova_device_control.dart';

/// Comprehensive Trigger & Gesture Conflict Solver Settings Screen.
/// Provides configuration, direct deep-links, and guidance for all activation modes:
/// 1. System-wide Floating Overlay (over any app)
/// 2. Draw "O" gesture & conflict solver
/// 3. Double-tap trigger
/// 4. Power button / Side-key hold (Digital Assistant app)
/// 5. Quick Settings tile ("Ask Ova")
/// 6. Accessibility button & biometric security gate
class OvaTriggerSettingsScreen extends ConsumerStatefulWidget {
  const OvaTriggerSettingsScreen({super.key});

  @override
  ConsumerState<OvaTriggerSettingsScreen> createState() => _OvaTriggerSettingsScreenState();
}

class _OvaTriggerSettingsScreenState extends ConsumerState<OvaTriggerSettingsScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;

  bool _isOverlayActive = false;
  bool _canDrawOverlays = false;
  bool _isA11yActive = false;
  double _gestureSensitivity = 0.8; // 0.5 to 1.0

  // Live test pad state
  final List<Offset> _testStroke = [];
  String _testDetectionStatus = 'Draw an "O" or "1" shape below to test';
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    _refreshHardwareState();
  }

  @override
  void dispose() {
    _tabController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshHardwareState();
    }
  }

  Future<void> _refreshHardwareState() async {
    final native = ref.read(ovaNativeServiceProvider);
    final control = ref.read(ovaDeviceControlProvider);

    final canOverlay = await native.canDrawOverlays();
    final isOverlayRunning = await native.isSystemOverlayActive();
    final a11yRunning = await control.isEnabled();

    if (mounted) {
      setState(() {
        _canDrawOverlays = canOverlay;
        _isOverlayActive = isOverlayRunning;
        _isA11yActive = a11yRunning;
      });
    }
  }

  Future<void> _toggleSystemOverlay(bool enabled) async {
    HapticFeedback.lightImpact();
    final native = ref.read(ovaNativeServiceProvider);

    if (enabled) {
      if (!_canDrawOverlays) {
        await native.requestOverlayPermission();
        return;
      }
      await native.startSystemOverlay();
    } else {
      await native.stopSystemOverlay();
    }
    await _refreshHardwareState();
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
          icon: Icon(Icons.arrow_back, color: context.textPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Ova Triggers & System Control',
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: context.textPrimary,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.brandPink,
          indicatorWeight: 2.5,
          labelColor: context.textPrimary,
          unselectedLabelColor: context.textSecondary,
          labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
          unselectedLabelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
          tabs: const [
            Tab(text: 'Triggers & Overlay'),
            Tab(text: 'Conflict Solver & Test'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTriggersTab(context),
          _buildConflictSolverTab(context),
        ],
      ),
    );
  }

  Widget _buildTriggersTab(BuildContext context) {
    final doubleTapEnabled = ref.watch(ovaDoubleTapEnabledProvider);
    final drawOEnabled = ref.watch(ovaDrawOGestureEnabledProvider);
    final drawOneEnabled = ref.watch(ovaDrawOneGestureEnabledProvider);
    final doubleTapHoldEnabled = ref.watch(ovaDoubleTapHoldEnabledProvider);
    final tripleTapHoldEnabled = ref.watch(ovaTripleTapHoldEnabledProvider);
    final onlyTripleTap = ref.watch(ovaOnlyTripleTapHoldProvider);
    final holdDurationSeconds = ref.watch(ovaHoldDurationSecondsProvider);
    final voiceCallModeEnabled = ref.watch(ovaVoiceCallModeEnabledProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        // Hero status banner
        _buildHeroBanner(context),
        const SizedBox(height: 16),

        _buildSectionHeader(context, 'AMBIENT SYSTEM OVERLAY'),
        const SizedBox(height: 8),

        // System-Wide Floating Dock (over any app)
        _buildSettingCard(
          context: context,
          icon: Icons.picture_in_picture_alt_rounded,
          iconColor: AppColors.brandBlue,
          title: 'Floating Assistant Over Apps',
          subtitle: _isOverlayActive
              ? 'Active over other applications • Drag edge bubble or tap to command'
              : 'Shows floating assistant pill over all applications on device',
          trailing: Switch.adaptive(
            value: _isOverlayActive,
            activeTrackColor: AppColors.brandBlue,
            onChanged: _toggleSystemOverlay,
          ),
          extraContent: !_canDrawOverlays
              ? Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: InkWell(
                    onTap: () => ref.read(ovaNativeServiceProvider).requestOverlayPermission(),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.brandPink.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning_amber_rounded, color: AppColors.brandPink, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            'Grant "Display over other apps" permission',
                            style: GoogleFonts.inter(
                              color: AppColors.brandPink,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : null,
        ),
        const SizedBox(height: 16),

        _buildSectionHeader(context, 'GESTURE & TOUCH ACTIVATION'),
        const SizedBox(height: 8),

        // Draw "O" Gesture
        _buildSettingCard(
          context: context,
          icon: Icons.gesture_rounded,
          iconColor: AppColors.brandPink,
          title: 'Draw "O" Circle Gesture',
          subtitle: 'Draw a circle anywhere on screen to trigger Ova with screen capture context',
          trailing: Switch.adaptive(
            value: drawOEnabled,
            activeTrackColor: AppColors.brandPink,
            onChanged: (val) {
              HapticFeedback.lightImpact();
              ref.read(ovaDrawOGestureEnabledProvider.notifier).setEnabled(val);
            },
          ),
          extraContent: drawOEnabled
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Gesture Sensitivity',
                            style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary)),
                        Text('${(_gestureSensitivity * 100).toInt()}%',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: context.textPrimary)),
                      ],
                    ),
                    Slider(
                      value: _gestureSensitivity,
                      min: 0.5,
                      max: 1.0,
                      divisions: 5,
                      activeColor: AppColors.brandPink,
                      inactiveColor: context.surfaceMid,
                      onChanged: (val) {
                        setState(() => _gestureSensitivity = val);
                      },
                    ),
                  ],
                )
              : null,
        ),
        const SizedBox(height: 10),

        // Draw "1" Gesture
        _buildSettingCard(
          context: context,
          icon: Icons.straighten_rounded,
          iconColor: AppColors.brandBlue,
          title: 'Draw "1" Vertical Stroke',
          subtitle: 'Swipe a straight downward stroke "1" anywhere to wake Ova instantly',
          trailing: Switch.adaptive(
            value: drawOneEnabled,
            activeTrackColor: AppColors.brandBlue,
            onChanged: (val) {
              HapticFeedback.lightImpact();
              ref.read(ovaDrawOneGestureEnabledProvider.notifier).setEnabled(val);
            },
          ),
        ),
        const SizedBox(height: 10),

        // Double-Tap Anywhere
        _buildSettingCard(
          context: context,
          icon: Icons.touch_app_rounded,
          iconColor: AppColors.brandBlue,
          title: 'Double-Tap Anywhere',
          subtitle: 'Rapidly double-tap the screen to instantly summon Ova floating bottom dock',
          trailing: Switch.adaptive(
            value: doubleTapEnabled,
            activeTrackColor: AppColors.brandBlue,
            onChanged: (val) {
              HapticFeedback.lightImpact();
              ref.read(ovaDoubleTapEnabledProvider.notifier).setEnabled(val);
            },
          ),
        ),
        const SizedBox(height: 10),

        // Safe Mode: Only Triple-Tap & Hold (Prevents accidental triggers on home page)
        _buildSettingCard(
          context: context,
          icon: Icons.verified_user_rounded,
          iconColor: AppColors.brandBlue,
          title: 'Safe Mode: Only Triple-Tap & Hold (${holdDurationSeconds}s)',
          subtitle: 'Only pop up Ova when you click 3 times with hold ${holdDurationSeconds}s. Prevents any accidental popups on Home Page video feeds and reels.',
          trailing: Switch.adaptive(
            value: onlyTripleTap,
            activeTrackColor: AppColors.brandBlue,
            onChanged: (val) {
              HapticFeedback.lightImpact();
              ref.read(ovaOnlyTripleTapHoldProvider.notifier).setEnabled(val);
              if (val) {
                // When Safe Mode is active, ensure triple-tap hold is enabled
                ref.read(ovaTripleTapHoldEnabledProvider.notifier).setEnabled(true);
              }
            },
          ),
        ),
        const SizedBox(height: 10),

        // Triple-Tap & Hold (3s)
        _buildSettingCard(
          context: context,
          icon: Icons.touch_app_outlined,
          iconColor: AppColors.brandPink,
          title: 'Triple-Tap & Hold (${holdDurationSeconds}s)',
          subtitle: 'Click 3 times on the screen and hold down on the 3rd click for $holdDurationSeconds seconds to summon Ova',
          trailing: Switch.adaptive(
            value: tripleTapHoldEnabled,
            activeTrackColor: AppColors.brandPink,
            onChanged: (val) {
              HapticFeedback.lightImpact();
              ref.read(ovaTripleTapHoldEnabledProvider.notifier).setEnabled(val);
            },
          ),
          extraContent: tripleTapHoldEnabled
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Hold Countdown Duration',
                            style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary)),
                        Text('${holdDurationSeconds}s',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: context.textPrimary)),
                      ],
                    ),
                    Slider(
                      value: holdDurationSeconds.toDouble().clamp(1.0, 5.0),
                      min: 1.0,
                      max: 5.0,
                      divisions: 4,
                      activeColor: AppColors.brandPink,
                      inactiveColor: context.surfaceMid,
                      onChanged: (val) {
                        HapticFeedback.selectionClick();
                        ref.read(ovaHoldDurationSecondsProvider.notifier).setDuration(val.toInt());
                      },
                    ),
                  ],
                )
              : null,
        ),
        const SizedBox(height: 10),

        // Double-Tap & Hold
        _buildSettingCard(
          context: context,
          icon: Icons.timer_outlined,
          iconColor: AppColors.brandPink,
          title: 'Double-Tap & Hold ($holdDurationSeconds s)',
          subtitle: 'Double-tap and hold on the second tap to charge the luminous wake ring',
          trailing: Switch.adaptive(
            value: doubleTapHoldEnabled,
            activeTrackColor: AppColors.brandPink,
            onChanged: (val) {
              HapticFeedback.lightImpact();
              ref.read(ovaDoubleTapHoldEnabledProvider.notifier).setEnabled(val);
            },
          ),
          extraContent: doubleTapHoldEnabled
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Hold Countdown Duration',
                            style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary)),
                        Text('${holdDurationSeconds}s',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: context.textPrimary)),
                      ],
                    ),
                    Slider(
                      value: holdDurationSeconds.toDouble().clamp(1.0, 5.0),
                      min: 1.0,
                      max: 5.0,
                      divisions: 4,
                      activeColor: AppColors.brandPink,
                      inactiveColor: context.surfaceMid,
                      onChanged: (val) {
                        HapticFeedback.selectionClick();
                        ref.read(ovaHoldDurationSecondsProvider.notifier).setDuration(val.toInt());
                      },
                    ),
                  ],
                )
              : null,
        ),
        const SizedBox(height: 10),

        // Voice Call Mode on Trigger
        _buildSettingCard(
          context: context,
          icon: Icons.record_voice_over_rounded,
          iconColor: AppColors.brandPink,
          title: 'Auto Voice Call Mode',
          subtitle: 'Summons Ova directly into active hands-free voice conversation mode',
          trailing: Switch.adaptive(
            value: voiceCallModeEnabled,
            activeTrackColor: AppColors.brandPink,
            onChanged: (val) {
              HapticFeedback.lightImpact();
              ref.read(ovaVoiceCallModeEnabledProvider.notifier).setEnabled(val);
            },
          ),
        ),
        const SizedBox(height: 16),

        _buildSectionHeader(context, 'HARDWARE & SYSTEM KEYS (ELLA STYLE)'),
        const SizedBox(height: 8),

        // Power Button / Side Key Hold
        _buildActionTile(
          context: context,
          icon: Icons.power_settings_new_rounded,
          title: 'Power / Side Key Hold',
          subtitle: 'Set Oneova as your Android Default Digital Assistant to launch with power button',
          actionText: 'Configure',
          onTap: () {
            HapticFeedback.lightImpact();
            ref.read(ovaNativeServiceProvider).openAssistantSettings();
          },
        ),
        const SizedBox(height: 10),

        // Quick Settings Tile ("Ask Ova")
        _buildActionTile(
          context: context,
          icon: Icons.dashboard_customize_rounded,
          title: 'Quick Settings Tile ("Ask Ova")',
          subtitle: 'Add the quick settings tile to your Android notification shade for 1-tap access',
          actionText: 'Guide',
          onTap: () => _showQuickSettingsGuide(context),
        ),
        const SizedBox(height: 10),

        // Accessibility Service & Full Device Control
        _buildActionTile(
          context: context,
          icon: Icons.accessibility_new_rounded,
          title: 'Accessibility Device Control',
          subtitle: _isA11yActive
              ? 'Enabled • Ova can tap, scroll, type, and navigate apps'
              : 'Setup required • Allows Ova to control phone and read screen',
          actionText: _isA11yActive ? 'Active' : 'Setup',
          isActive: _isA11yActive,
          onTap: () {
            HapticFeedback.lightImpact();
            context.push('/ova/setup');
          },
        ),
      ],
    );
  }

  Widget _buildConflictSolverTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.brandBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.25), width: 1.0),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.shield_outlined, color: AppColors.brandBlue, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gesture Conflict Solver Active',
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Oneova filters out native Android gestures (e.g. edge-swipe back, 3-finger screenshot) and active scroll bars so your strokes never accidentally conflict with system navigation.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        height: 1.4,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        _buildSectionHeader(context, 'HOW TO AVOID CONFLICTS'),
        const SizedBox(height: 8),

        _buildConflictRuleTile(
          context,
          icon: Icons.swipe_left_alt_rounded,
          title: 'Edge Back Gestures (Android 10+)',
          description:
              'Always start your "O" circle at least 15px away from the left or right screen edge to avoid triggering Android\'s system back arrow.',
        ),
        const SizedBox(height: 10),

        _buildConflictRuleTile(
          context,
          icon: Icons.touch_app_outlined,
          title: 'Text Fields & Keyboard',
          description:
              'When the software keyboard is active, drawing gestures are paused automatically so you can type and swipe without interference.',
        ),
        const SizedBox(height: 10),

        _buildConflictRuleTile(
          context,
          icon: Icons.speed_rounded,
          title: 'Drawing Speed & Closure',
          description:
              'Complete the circle stroke smoothly within 1.5 seconds. The stroke ends should touch or come within 60px of the starting point.',
        ),
        const SizedBox(height: 20),

        _buildSectionHeader(context, 'INTERACTIVE STROKE TEST PAD'),
        const SizedBox(height: 6),
        Text(
          'Draw an "O" or "1" shape inside the pad below to verify real-time gesture recognition.',
          style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary),
        ),
        const SizedBox(height: 10),

        // Live Test Pad
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            height: 260,
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: _testSuccess ? AppColors.brandPink : context.border,
                width: _testSuccess ? 1.5 : 1.0,
              ),
            ),
            child: Stack(
              children: [
                GestureDetector(
                  onPanStart: (details) {
                    setState(() {
                      _testStroke.clear();
                      _testStroke.add(details.localPosition);
                      _testSuccess = false;
                      _testDetectionStatus = 'Tracing stroke...';
                    });
                  },
                  onPanUpdate: (details) {
                    setState(() {
                      _testStroke.add(details.localPosition);
                    });
                  },
                  onPanEnd: (details) {
                    _evaluateTestStroke();
                  },
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _TestStrokePainter(
                      points: _testStroke,
                      isSuccess: _testSuccess,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 12,
                  left: 14,
                  right: 14,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _testDetectionStatus,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _testSuccess ? AppColors.brandPink : context.textSecondary,
                          ),
                        ),
                      ),
                      if (_testStroke.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _testStroke.clear();
                              _testSuccess = false;
                              _testDetectionStatus = 'Draw an "O" or "1" shape below to test';
                            });
                          },
                          style: TextButton.styleFrom(padding: EdgeInsets.zero),
                          child: Text('Clear', style: GoogleFonts.inter(fontSize: 12, color: AppColors.brandBlue)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _evaluateTestStroke() {
    if (_testStroke.length < 8) {
      setState(() {
        _testDetectionStatus = 'Stroke too short. Draw "O" or "1".';
        _testSuccess = false;
      });
      return;
    }

    final start = _testStroke.first;
    final end = _testStroke.last;
    final closeDist = (start - end).distance;

    double minX = _testStroke.first.dx, maxX = _testStroke.first.dx;
    double minY = _testStroke.first.dy, maxY = _testStroke.first.dy;
    for (final p in _testStroke) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }

    final width = maxX - minX;
    final height = maxY - minY;
    final aspectRatio = width / (height > 0 ? height : 1);

    // 1. Check for "O" (Circle Loop)
    if (closeDist < 75 && width > 40 && height > 40 && aspectRatio >= 0.45 && aspectRatio <= 2.2) {
      HapticFeedback.heavyImpact();
      setState(() {
        _testSuccess = true;
        _testDetectionStatus = '✓ "O" Recognized! Circular loop detected.';
      });
      return;
    }

    // 2. Check for "1" (Vertical Downward Stroke)
    final verticalDownDist = end.dy - start.dy;
    if (height >= 45 && (height / (width > 0 ? width : 1)) >= 1.8 && verticalDownDist >= (height * 0.55)) {
      final lineVec = end - start;
      final lineLen = lineVec.distance;
      double maxDev = 0;
      for (final p in _testStroke) {
        final t = (((p.dx - start.dx) * lineVec.dx + (p.dy - start.dy) * lineVec.dy) / (lineLen * lineLen)).clamp(0.0, 1.0);
        final proj = Offset(start.dx + t * lineVec.dx, start.dy + t * lineVec.dy);
        final dev = (p - proj).distance;
        if (dev > maxDev) maxDev = dev;
      }

      if (maxDev <= 40) {
        HapticFeedback.heavyImpact();
        setState(() {
          _testSuccess = true;
          _testDetectionStatus = '✓ "1" Recognized! Vertical downward stroke detected.';
        });
        return;
      }
    }

    HapticFeedback.lightImpact();
    setState(() {
      _testSuccess = false;
      _testDetectionStatus = 'Not recognized. Draw a closed circle "O" or downward stroke "1".';
    });
  }

  Widget _buildHeroBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.brandBlue.withValues(alpha: 0.12),
              border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.3)),
            ),
            child: Icon(Icons.bolt_rounded, color: AppColors.brandBlue, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Oneova Ambient Engine',
                  style: GoogleFonts.inter(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Universal triggers allow Ova to listen, see your screen, and control your device from anywhere.',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    height: 1.35,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: context.textMuted,
      ),
    );
  }

  Widget _buildSettingCard({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget trailing,
    Widget? extraContent,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  color: iconColor.withValues(alpha: 0.12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        height: 1.3,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing,
            ],
          ),
          ?extraContent,
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionText,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              color: (isActive ? AppColors.brandBlue : context.surfaceMid),
            ),
            child: Icon(icon, color: isActive ? Colors.white : context.textSecondary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    height: 1.3,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 34,
            child: ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: isActive ? context.surfaceMid : AppColors.brandBlue,
                foregroundColor: isActive ? context.textSecondary : Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
              child: Text(
                actionText,
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConflictRuleTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.brandBlue, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    height: 1.35,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showQuickSettingsGuide(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add "Ask Ova" Quick Settings Tile',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: ctx.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '1. Swipe down twice from the top of your Android screen to open the full Quick Settings panel.\n'
                  '2. Tap the Pencil (Edit) icon at the bottom of the panel.\n'
                  '3. Scroll down to find the "Ask Ova" tile.\n'
                  '4. Drag and drop it into your active tiles.\n\n'
                  'Now you can summon Ova with a single tap from anywhere on your phone!',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    height: 1.45,
                    color: ctx.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                    ),
                    child: Text('Got it', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TestStrokePainter extends CustomPainter {
  final List<Offset> points;
  final bool isSuccess;

  _TestStrokePainter({required this.points, required this.isSuccess});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = isSuccess ? AppColors.brandPink : AppColors.brandBlue
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TestStrokePainter oldDelegate) => true;
}
