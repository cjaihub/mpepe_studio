import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../settings/widgets/settings_kit.dart';
import '../../shared/theme/app_theme.dart';
import '../services/ova_context_service.dart';
import '../services/ova_permissions.dart';
import '../services/ova_trigger_settings.dart';

/// Ways to open Ova. Every switch auto-saves to
/// `user_settings/{uid}.ovaTriggers`; the app mirrors it to Android, where
/// the system-wide triggers run:
/// - Draw "O": anywhere inside Oneova; over other apps, the home screen and
///   the lock screen, start the "O" on the Ova handle at the screen edge.
/// - Button shortcut: volume keys (the power key cannot be intercepted; use
///   "default digital assistant" for long-press power instead).
/// - Lock screen: allowed or not; unlocking is always required first.
class OvaTriggerSettingsScreen extends ConsumerStatefulWidget {
  const OvaTriggerSettingsScreen({super.key});

  @override
  ConsumerState<OvaTriggerSettingsScreen> createState() => _OvaTriggerSettingsScreenState();
}

class _OvaTriggerSettingsScreenState extends ConsumerState<OvaTriggerSettingsScreen> with WidgetsBindingObserver {
  static const _cat = OvaTriggerSettings.category;

  bool get _android => !kIsWeb && Platform.isAndroid;

  bool _a11y = false;
  bool _overlayPermission = false;
  bool _bubble = false;
  bool _notifications = false;

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

  // Coming back from Android Settings: re-read what was granted.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (!_android) return;
    final native = ref.read(ovaNativeServiceProvider);
    final a11y = await native.isAccessibilityEnabled();
    final overlay = await native.canDrawOverlays();
    final bubble = await native.isSystemOverlayActive();
    final notif = await Permission.notification.isGranted;
    if (!mounted) return;
    setState(() {
      _a11y = a11y;
      _overlayPermission = overlay;
      _bubble = bubble;
      _notifications = notif;
    });
  }

  Future<void> _toggleBubble(bool on) async {
    final native = ref.read(ovaNativeServiceProvider);
    if (on) {
      if (!_overlayPermission) {
        await native.requestOverlayPermission();
        return;
      }
      await native.startSystemOverlay();
    } else {
      await native.stopSystemOverlay();
    }
    await _refresh();
  }

  Future<void> _enableAccessibility() async {
    if (_a11y) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: BorderSide(color: ctx.border, width: 1),
        ),
        title: Text('Turn on Oneova Ova',
            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
        content: Text(
          'The Ova handle and the button shortcut run as an Android accessibility service.\n\n'
          'In the next screen open "Installed apps" (or "Downloaded apps"), tap Oneova Ova and turn it on.',
          style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: ctx.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Not now', style: GoogleFonts.inter(fontSize: 13, color: ctx.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              minimumSize: const Size(0, 38),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Open Settings',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.brandWhite)),
          ),
        ],
      ),
    );
    if (go == true) await ref.read(ovaNativeServiceProvider).openAccessibilitySettings();
  }

  Future<void> _enableNotifications() async {
    if (_notifications) return;
    await OvaPermissions.ensure(
      context,
      Permission.notification,
      title: 'Allow notifications',
      why: 'Ova uses a quiet notification to keep the floating bubble running and to tell you when a task is done.',
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return CompactSettingsScaffold(
      title: 'Ways to open Ova',
      children: [
        SettingsAsyncBody(builder: (settings) {
          final data = settingsCategory(settings, _cat);
          final t = OvaTriggerSettings.fromMap(data);
          void write(String key, Object value, String label) =>
              settingsWrite(ref, category: _cat, current: data, key: key, value: value, label: label);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_android && (!_a11y || !_notifications)) _setupBanner(context),
              SettingsSection(
                label: 'Draw "O"',
                footer: _android
                    ? 'Inside Oneova, draw an O anywhere. Over other apps, the home screen and the lock screen, '
                        'start the O on the Ova handle (the slim bar on the screen edge) and draw it anywhere. '
                        'Tap the handle to open Ova too; long-press it to move it.'
                    : 'Draw an O anywhere inside Oneova to open Ova.',
                children: [
                  SettingsSwitchTile(
                    icon: Icons.gesture_rounded,
                    accent: AppColors.brandPink,
                    title: 'Draw "O" to open Ova',
                    subtitle: _android && !_a11y && t.drawO ? 'In Oneova only until Oneova Ova is on' : null,
                    value: t.drawO,
                    onChanged: (v) => write('drawO', v, 'Draw O'),
                  ),
                ],
              ),
              if (t.drawO) const _DrawOTestPad(),
              if (_android) ...[
                SettingsSection(
                  label: 'Button shortcut',
                  footer: 'Works with the screen on, including the lock screen. Android does not let apps use the '
                      'power key, and volume keys do not reach apps while the screen is off. For the power key, '
                      'set Oneova as your digital assistant below.',
                  children: [
                    SettingsChoiceTile<String>(
                      icon: Icons.volume_down_rounded,
                      title: 'Volume keys',
                      subtitle: !_a11y && t.buttonShortcut != OvaTriggerSettings.shortcutOff
                          ? 'Needs Oneova Ova turned on'
                          : 'Press to open Ova from any screen',
                      options: const {
                        OvaTriggerSettings.shortcutOff: 'Off',
                        OvaTriggerSettings.shortcutDoubleVolumeDown: 'Vol − twice',
                        OvaTriggerSettings.shortcutVolumeUpDown: 'Vol + and −',
                      },
                      value: t.buttonShortcut,
                      onChanged: (v) => write('buttonShortcut', v, 'Button shortcut'),
                    ),
                    SettingsNavTile(
                      icon: Icons.power_settings_new_rounded,
                      title: 'Power button',
                      subtitle: 'Choose Oneova as digital assistant, then hold power (or Home) to open Ova',
                      onTap: () => ref.read(ovaNativeServiceProvider).openAssistantSettings(),
                    ),
                  ],
                ),
                SettingsSection(
                  label: 'Lock screen',
                  footer: 'Ova never shows anything on a locked phone. It asks for your fingerprint, face, PIN, '
                      'pattern or password first. With the screen fully off no app can see touches, so wake the '
                      'screen first (or hold power, if Oneova is your digital assistant).',
                  children: [
                    SettingsSwitchTile(
                      icon: Icons.lock_open_rounded,
                      title: 'Allow on lock screen',
                      subtitle: 'Draw "O" or use the shortcut, then unlock',
                      value: t.lockScreen,
                      onChanged: (v) => write('lockScreen', v, 'Lock screen'),
                    ),
                  ],
                ),
              ],
              SettingsSection(
                label: 'When Ova opens',
                children: [
                  SettingsSwitchTile(
                    icon: Icons.record_voice_over_rounded,
                    accent: AppColors.brandPink,
                    title: 'Start in voice mode',
                    subtitle: 'Ova starts listening right away',
                    value: t.voiceMode,
                    onChanged: (v) => write('voiceMode', v, 'Voice mode'),
                  ),
                ],
              ),
              if (_android) ...[
                SettingsSection(
                  label: 'Permissions',
                  children: [
                    SettingsNavTile(
                      icon: Icons.accessibility_new_rounded,
                      title: 'Oneova Ova (accessibility)',
                      subtitle: 'Ova handle and button shortcut',
                      value: _a11y ? 'On' : 'Set up',
                      onTap: _enableAccessibility,
                    ),
                    SettingsNavTile(
                      icon: Icons.layers_rounded,
                      title: 'Display over other apps',
                      subtitle: 'Floating Ova bubble',
                      value: _overlayPermission ? 'On' : 'Set up',
                      onTap: () => ref.read(ovaNativeServiceProvider).requestOverlayPermission(),
                    ),
                    SettingsNavTile(
                      icon: Icons.notifications_active_outlined,
                      title: 'Notifications',
                      subtitle: 'Keeps the floating bubble running',
                      value: _notifications ? 'On' : 'Set up',
                      onTap: _enableNotifications,
                    ),
                  ],
                ),
                SettingsSection(
                  label: 'More ways',
                  children: [
                    SettingsSwitchTile(
                      icon: Icons.bubble_chart_rounded,
                      title: 'Floating Ova bubble',
                      subtitle: 'A small bubble over other apps; tap it to ask Ova',
                      value: _bubble,
                      onChanged: _toggleBubble,
                    ),
                    SettingsNavTile(
                      icon: Icons.dashboard_customize_rounded,
                      title: 'Quick Settings tile',
                      subtitle: 'Add "Ask Ova" to the notification shade',
                      onTap: () => _showQuickSettingsGuide(context),
                    ),
                    SettingsNavTile(
                      icon: Icons.open_in_new_rounded,
                      title: 'Try the overlay',
                      subtitle: 'See Ova as it opens over other apps',
                      onTap: () => ref.read(ovaNativeServiceProvider).openSystemOverlayPreview(),
                    ),
                  ],
                ),
              ],
              if (!kIsWeb && Platform.isIOS) _iosNote(context),
            ],
          );
        }),
      ],
    );
  }

  Widget _setupBanner(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.brandBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt_rounded, size: 20, color: AppColors.brandBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              !_a11y
                  ? 'Turn on Oneova Ova to open Ova over other apps and the lock screen.'
                  : 'Allow notifications so the floating bubble can keep running.',
              style: GoogleFonts.inter(fontSize: 12, height: 1.35, color: context.textPrimary),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 32,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
              onPressed: !_a11y ? _enableAccessibility : _enableNotifications,
              child: Text('Set up',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brandWhite)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _iosNote(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsIconChip(icon: Icons.phone_iphone_rounded),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'iOS does not let apps draw over other apps or watch gestures outside the app, so Draw "O" '
              'works inside Oneova only. To open Oneova from anywhere, make a Shortcut and add it to the '
              'Action Button (Settings › Action Button), Back Tap (Settings › Accessibility › Touch › Back Tap) '
              'or a Lock Screen widget.',
              style: GoogleFonts.inter(fontSize: 11.5, height: 1.4, color: context.textSecondary),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add the "Ask Ova" tile',
                  style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
              const SizedBox(height: 10),
              Text(
                '1. Swipe down twice from the top of the screen.\n'
                '2. Tap the pencil (Edit) icon.\n'
                '3. Find "Ask Ova" and drag it into your tiles.',
                style: GoogleFonts.inter(fontSize: 12.5, height: 1.45, color: ctx.textSecondary),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                  child: Text('Got it',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AppColors.brandWhite)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small pad to practise the "O" (same rules as the real recogniser).
class _DrawOTestPad extends StatefulWidget {
  const _DrawOTestPad();

  @override
  State<_DrawOTestPad> createState() => _DrawOTestPadState();
}

class _DrawOTestPadState extends State<_DrawOTestPad> {
  final List<Offset> _points = [];
  bool? _ok;

  void _evaluate() {
    final ok = _isCircle(_points);
    ok ? HapticFeedback.heavyImpact() : HapticFeedback.lightImpact();
    setState(() => _ok = ok);
  }

  static bool _isCircle(List<Offset> p) {
    if (p.length < 12) return false;
    double minX = p.first.dx, maxX = minX, minY = p.first.dy, maxY = minY, length = 0;
    for (var i = 0; i < p.length; i++) {
      minX = math.min(minX, p[i].dx);
      maxX = math.max(maxX, p[i].dx);
      minY = math.min(minY, p[i].dy);
      maxY = math.max(maxY, p[i].dy);
      if (i > 0) length += (p[i] - p[i - 1]).distance;
    }
    final w = maxX - minX, h = maxY - minY;
    if (w < 35 || h < 35) return false;
    final aspect = w / h;
    if (aspect < 0.4 || aspect > 2.4) return false;
    if ((p.first - p.last).distance > math.max(w, h) * 0.5) return false;
    final r = (w + h) / 4;
    if (length < 3.2 * r || length > 12 * r) return false;
    final c = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    double total = 0;
    double? prev;
    for (final q in p) {
      final a = math.atan2(q.dy - c.dy, q.dx - c.dx);
      if (prev != null) {
        var d = a - prev;
        while (d > math.pi) {
          d -= 2 * math.pi;
        }
        while (d < -math.pi) {
          d += 2 * math.pi;
        }
        total += d;
      }
      prev = a;
    }
    return total.abs() >= 4.3;
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (_ok) {
      null => 'Practise here: draw an O',
      true => 'Recognised. That opens Ova.',
      false => 'Not quite. Close the loop.',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        height: 150,
        decoration: BoxDecoration(
          color: context.surfaceMid,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: _ok == true ? AppColors.brandPink : context.border, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            GestureDetector(
              onPanStart: (d) => setState(() {
                _points
                  ..clear()
                  ..add(d.localPosition);
                _ok = null;
              }),
              onPanUpdate: (d) => setState(() => _points.add(d.localPosition)),
              onPanEnd: (_) => _evaluate(),
              child: CustomPaint(
                size: Size.infinite,
                painter: _StrokePainter(_points, _ok == true ? AppColors.brandPink : AppColors.brandBlue),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 10,
              child: IgnorePointer(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _ok == true ? AppColors.brandPink : context.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StrokePainter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  _StrokePainter(this.points, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _StrokePainter old) => true;
}
