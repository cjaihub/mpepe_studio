import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../auth/security/login_security.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/router.dart' show routerProvider, rootNavigatorKey;
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/theme_provider.dart';
import '../services/ova_abilities.dart';
import '../services/ova_chat_controller.dart';
import '../services/ova_device_abilities.dart';
import '../services/ova_device_hub.dart';
import '../services/ova_task_center.dart';
import '../services/ova_tool_registry.dart';
import 'ova_assistant_sheet.dart';
import 'ova_confirm_card.dart';

/// Tracks dialogs and sheets on the root navigator so the dock can step aside.
class OvaPopupObserver extends NavigatorObserver {
  static final ValueNotifier<int> depth = ValueNotifier<int>(0);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) depth.value++;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute && depth.value > 0) depth.value--;
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute && depth.value > 0) depth.value--;
  }
}

/// One suggested action. Either runs a tool directly, sends a prompt in the
/// background, or opens the sheet (prefilled when [fill] is true).
class OvaSuggestion {
  final IconData icon;
  final String label;
  final String? tool;
  final Map<String, dynamic> args;
  final String? prompt;
  final bool openSheet;
  final bool fill;
  final bool accent;
  final OvaInvocationContext invocation;

  const OvaSuggestion(
    this.icon,
    this.label, {
    this.tool,
    this.args = const {},
    this.prompt,
    this.openSheet = false,
    this.fill = false,
    this.accent = false,
    this.invocation = const OvaInvocationContext(),
  });
}

/// Builds suggestions for the current screen and recent phone events.
List<OvaSuggestion> ovaSuggestionsFor({
  required String path,
  required OvaAbilities abilities,
  required OvaDeviceEvents events,
  required Map<String, dynamic> device,
  required bool dark,
}) {
  final out = <OvaSuggestion>[];
  final android = !kIsWeb && Platform.isAndroid;

  // Phone events first: they are the most time-sensitive.
  if (android && abilities.readNotifications && events.notifications.isNotEmpty) {
    final n = events.notifications.first;
    if (n.canReply) {
      out.add(OvaSuggestion(Icons.reply_rounded, 'Reply to ${_clip(n.title, 14)} · ${_clip(n.app, 10)}',
          prompt: 'Read my latest ${n.app} notification from ${n.title} and suggest a short reply I can send.', openSheet: true, accent: true));
    }
    out.add(OvaSuggestion(Icons.notifications_active_rounded,
        '${events.notifications.length} new notification${events.notifications.length == 1 ? '' : 's'}',
        tool: 'read_notifications'));
  }
  final battery = (device['battery'] as num?)?.toInt();
  if (battery != null && battery <= 20 && device['charging'] != true) {
    out.add(const OvaSuggestion(Icons.brightness_low_rounded, 'Low battery: dim screen', tool: 'set_brightness', args: {'percent': 25}));
  }
  if (android && device['musicActive'] == true) {
    out.add(const OvaSuggestion(Icons.pause_rounded, 'Pause music', tool: 'media_control', args: {'action': 'pause'}));
    out.add(const OvaSuggestion(Icons.skip_next_rounded, 'Next song', tool: 'media_control', args: {'action': 'next'}));
  }

  final seg = Uri.parse(path).pathSegments;
  if (path.startsWith('/hub/home') || path == '/') {
    out.addAll(const [
      OvaSuggestion(Icons.sensors_rounded, 'Go live', tool: 'open_screen', args: {'screen': 'go_live'}, accent: true),
      OvaSuggestion(Icons.upload_rounded, 'Post a video', tool: 'open_screen', args: {'screen': 'upload'}),
      OvaSuggestion(Icons.search_rounded, 'Search', prompt: 'search ', openSheet: true, fill: true),
      OvaSuggestion(Icons.local_fire_department_rounded, 'Caption ideas', prompt: 'Give me 3 short, catchy caption ideas for my next reel.', openSheet: true),
    ]);
  } else if (seg.length >= 3 && seg[0] == 'hub' && seg[1] == 'messages') {
    out.add(OvaSuggestion(Icons.edit_note_rounded, 'Draft a reply',
        prompt: 'Help me write a friendly reply for this chat.', openSheet: true, invocation: OvaInvocationContext(chatId: seg[2])));
    out.add(const OvaSuggestion(Icons.translate_rounded, 'Translate a message', prompt: 'Translate this to English: ', openSheet: true, fill: true));
  } else if (path.startsWith('/hub/messages')) {
    out.addAll(const [
      OvaSuggestion(Icons.send_rounded, 'Message someone', prompt: 'message @', openSheet: true, fill: true),
      OvaSuggestion(Icons.notifications_rounded, 'Unread on my phone', tool: 'read_notifications'),
    ]);
  } else if (seg.length == 2 && seg[0] == 'profile' && seg[1] != 'me') {
    final uid = seg[1];
    if (uid != FirebaseAuth.instance.currentUser?.uid) {
      out.addAll([
        OvaSuggestion(Icons.person_add_alt_1_rounded, 'Follow', tool: 'follow_user', args: {'user_id': uid}, accent: true),
        OvaSuggestion(Icons.call_rounded, 'Voice call', tool: 'start_app_call', args: {'user_id': uid, 'video': false}),
        OvaSuggestion(Icons.videocam_rounded, 'Video call', tool: 'start_app_call', args: {'user_id': uid, 'video': true}),
      ]);
    }
  } else if (path.startsWith('/profile/me')) {
    out.addAll(const [
      OvaSuggestion(Icons.auto_awesome_rounded, 'Improve my bio', prompt: 'Write me a short, punchy creator bio. Ask me 2 questions first.', openSheet: true),
      OvaSuggestion(Icons.upload_rounded, 'Post a video', tool: 'open_screen', args: {'screen': 'upload'}),
    ]);
  } else if (path.startsWith('/notifications')) {
    out.add(const OvaSuggestion(Icons.phone_android_rounded, 'Phone notifications', tool: 'read_notifications'));
  } else if (path.startsWith('/live/viewer')) {
    out.addAll([
      if (android && device['dnd'] != true) const OvaSuggestion(Icons.do_not_disturb_on_rounded, 'Do Not Disturb', tool: 'do_not_disturb', args: {'on': true}),
      const OvaSuggestion(Icons.volume_up_rounded, 'Volume 70%', tool: 'set_volume', args: {'percent': 70}),
    ]);
  } else if (path.startsWith('/upload') || path.startsWith('/create') || path.startsWith('/photo')) {
    out.addAll(const [
      OvaSuggestion(Icons.edit_note_rounded, 'Write a caption', prompt: 'Write a catchy caption with 5 hashtags for my video about ', openSheet: true, fill: true),
      OvaSuggestion(Icons.light_mode_rounded, 'Brightness 100%', tool: 'set_brightness', args: {'percent': 100}),
    ]);
  } else if (path.startsWith('/settings')) {
    out.add(const OvaSuggestion(Icons.tune_rounded, 'Ova abilities', tool: 'open_screen', args: {'screen': 'ova_abilities'}));
  } else if (path.startsWith('/hub/discover')) {
    out.add(const OvaSuggestion(Icons.search_rounded, 'Find creators', prompt: 'search ', openSheet: true, fill: true));
  } else if (path.startsWith('/connect') || path.startsWith('/remote')) {
    out.addAll(const [
      OvaSuggestion(Icons.screenshot_monitor_rounded, 'PC screenshot', tool: 'pc_command', args: {'command': 'take_screenshot'}),
      OvaSuggestion(Icons.movie_creation_rounded, 'Render timeline', tool: 'pc_command', args: {'command': 'render_timeline'}),
    ]);
  }

  // Always-useful fallbacks.
  out.add(OvaSuggestion(dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, dark ? 'Light mode' : 'Dark mode',
      tool: 'set_app_theme', args: {'mode': dark ? 'light' : 'dark'}));
  if (android && abilities.deviceState) out.add(const OvaSuggestion(Icons.phone_android_rounded, 'Phone status', tool: 'device_overview'));
  out.add(OvaDeviceAbilities.torchOn
      ? const OvaSuggestion(Icons.flashlight_off_rounded, 'Flashlight off', tool: 'flashlight', args: {'on': false}, accent: true)
      : const OvaSuggestion(Icons.flashlight_on_rounded, 'Flashlight', tool: 'flashlight', args: {'on': true}));

  final seen = <String>{};
  return out.where((s) => seen.add(s.label)).take(7).toList();
}

String _clip(String s, int n) => s.length > n ? '${s.substring(0, n)}…' : s;

/// Draggable Ova bubble that floats over every screen. Tap opens a compact
/// bar with live task progress, inline confirmations and screen-aware
/// suggestions that keep working while the user browses.
class OvaFloatingDock extends ConsumerStatefulWidget {
  const OvaFloatingDock({super.key});

  @override
  ConsumerState<OvaFloatingDock> createState() => _OvaFloatingDockState();
}

class _OvaFloatingDockState extends ConsumerState<OvaFloatingDock> with WidgetsBindingObserver {
  static const _size = 42.0;
  static const _hiddenPrefixes = [
    '/splash', '/auth', '/live/setup', '/live/broadcast', '/live/studio', '/call/active', '/create/camera', '/hub/ova_assistant', '/ova',
    '/qr_scanner', '/tiktok-callback', '/meta-callback',
  ];

  Offset? _pos; // fractions of the screen (0..1)
  bool _dragging = false;
  bool _expanded = false;
  String _path = '/';
  Map<String, dynamic> _device = const {};
  Timer? _poll;
  StreamSubscription<User?>? _auth;
  // Only after the full two-check sign-in (never for guests or half-way).
  bool _signedIn = LoginSecurity.instance.isVerified(FirebaseAuth.instance.currentUser);
  OvaChatController? _chat;
  // Held so dispose() can unsubscribe without touching `ref`.
  GoRouterDelegate? _routerDelegate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPos();
    _auth = FirebaseAuth.instance.authStateChanges().listen((u) {
      if (mounted) setState(() => _signedIn = LoginSecurity.instance.isVerified(u));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _routerDelegate = ref.read(routerProvider).routerDelegate..addListener(_onRoute);
      _onRoute();
      final chat = ref.read(ovaChatProvider)..addListener(_onChat);
      _chat = chat;
    });
    OvaAssistantSheet.openState.addListener(_rebuild);
    OvaPopupObserver.depth.addListener(_rebuild);
    LoginSecurity.instance.addListener(_onSecurity);
    _poll = Timer.periodic(const Duration(seconds: 45), (_) => _pollDevice());
    _pollDevice();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _routerDelegate?.removeListener(_onRoute);
    _chat?.removeListener(_onChat);
    OvaAssistantSheet.openState.removeListener(_rebuild);
    LoginSecurity.instance.removeListener(_onSecurity);
    OvaPopupObserver.depth.removeListener(_rebuild);
    _poll?.cancel();
    _auth?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _pollDevice();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _onSecurity() {
    if (mounted) setState(() => _signedIn = LoginSecurity.instance.isVerified(FirebaseAuth.instance.currentUser));
  }

  void _onChat() {
    if (!mounted) return;
    // A confirmation needs the user: open the bar so it is seen right away.
    if (_chat?.pendingConfirm != null && !OvaAssistantSheet.openState.value) _expanded = true;
    setState(() {});
  }

  void _onRoute() {
    final config = _routerDelegate!.currentConfiguration;
    // Pushed routes are not part of `uri`; read the top match instead.
    final top = config.isNotEmpty ? config.last : null;
    final p = top is ImperativeRouteMatch ? top.matches.uri.path : config.uri.path;
    if (p != _path && mounted) {
      setState(() {
        _path = p.isEmpty ? '/' : p;
        // Keep the bar open while browsing so suggestions update live.
      });
    }
  }

  Future<void> _pollDevice() async {
    if (!OvaDeviceHub.supported) return;
    if (!ref.read(ovaAbilitiesProvider).deviceState) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    try {
      final d = await ref.read(ovaDeviceHubProvider).deviceState();
      if (mounted) setState(() => _device = d);
    } catch (_) {}
  }

  Future<void> _loadPos() async {
    final sp = await SharedPreferences.getInstance();
    final x = sp.getDouble('ova_dock_x');
    final y = sp.getDouble('ova_dock_y');
    if (mounted) setState(() => _pos = Offset(x ?? 0.0, y ?? 0.34));
  }

  Future<void> _savePos() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble('ova_dock_x', _pos!.dx);
    await sp.setDouble('ova_dock_y', _pos!.dy);
  }

  bool get _hiddenRoute => _hiddenPrefixes.any((p) => _path.startsWith(p));

  // ── actions ────────────────────────────────────────────────────────────

  void _openSheet({String? prompt, bool send = false, bool voice = false, OvaInvocationContext inv = const OvaInvocationContext()}) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    setState(() => _expanded = false);
    OvaAssistantSheet.show(ctx, initialPrompt: prompt, sendInitialPrompt: send, autoStartVoice: voice, invocation: inv);
  }

  void _run(OvaSuggestion s) {
    HapticFeedback.selectionClick();
    final chat = ref.read(ovaChatProvider);
    if (s.openSheet) {
      _openSheet(prompt: s.prompt, send: !s.fill, inv: s.invocation);
      return;
    }
    if (chat.busy) return;
    chat.invocation = s.invocation;
    if (s.tool != null) {
      chat.runDirect(s.label, s.tool!, s.args);
    } else if (s.prompt != null) {
      chat.send(s.prompt!);
    }
  }

  // ── build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ab = ref.watch(ovaAbilitiesProvider);
    final tasks = ref.watch(ovaTaskCenterProvider);
    final events = ref.watch(ovaDeviceEventsProvider);
    ref.watch(themeProvider);
    final mq = MediaQuery.of(context);

    final hidden = !ab.bubble ||
        !_signedIn ||
        _pos == null ||
        _hiddenRoute ||
        OvaAssistantSheet.openState.value ||
        OvaPopupObserver.depth.value > 0 ||
        mq.viewInsets.bottom > 0;
    if (hidden) return const SizedBox.shrink();

    final size = mq.size;
    final pad = mq.padding;
    final minY = pad.top + 8;
    final maxY = size.height - pad.bottom - 90 - _size;
    final left = _pos!.dx < 0.5;
    final x = left ? 6.0 : size.width - _size - 6;
    final y = (_pos!.dy * size.height).clamp(minY, maxY).toDouble();

    final active = tasks.active;
    final finished = tasks.justFinished;
    final chat = ref.read(ovaChatProvider);

    return Stack(
      children: [
        if (_expanded)
          _bar(context, size, y, ab, events, active, finished, chat),
        if (!_expanded && finished != null && !_dragging)
          _toast(context, finished, x, y, left, size),
        AnimatedPositioned(
          duration: _dragging ? Duration.zero : const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          left: _dragging ? (_pos!.dx * size.width - _size / 2).clamp(0, size.width - _size).toDouble() : x,
          top: y,
          child: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _expanded = !_expanded);
            },
            onLongPress: () {
              HapticFeedback.mediumImpact();
              _openSheet(voice: true);
            },
            onPanStart: (_) => setState(() {
              _dragging = true;
              _expanded = false;
            }),
            onPanUpdate: (d) => setState(() {
              _pos = Offset(
                ((_pos!.dx * size.width) + d.delta.dx) / size.width,
                ((_pos!.dy * size.height) + d.delta.dy) / size.height,
              );
            }),
            onPanEnd: (_) {
              HapticFeedback.selectionClick();
              setState(() {
                _dragging = false;
                _pos = Offset(_pos!.dx < 0.5 ? 0.0 : 1.0, (_pos!.dy).clamp(0.05, 0.85));
              });
              _savePos();
            },
            child: _bubble(active != null, chat.pendingConfirm != null, finished),
          ),
        ),
      ],
    );
  }

  Widget _bubble(bool working, bool needsYou, OvaTask? finished) {
    final ok = finished?.status == OvaTaskStatus.done;
    Widget core = AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: _dragging || working || needsYou || _expanded ? 1 : 0.82,
      child: Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.brandBlue, AppColors.brandPink],
          ),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 10, offset: const Offset(0, 3))],
          border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.2),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (working)
              const SizedBox(
                width: _size - 6,
                height: _size - 6,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            Icon(
              finished != null ? (ok ? Icons.check_rounded : Icons.priority_high_rounded) : Icons.auto_awesome_rounded,
              size: 19,
              color: Colors.white,
            ),
            if (needsYou)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.brandPink,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (working) {
      core = core.animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(begin: 1, end: 1.06, duration: 700.ms);
    }
    return core;
  }

  Widget _toast(BuildContext context, OvaTask t, double x, double y, bool left, Size size) {
    final ok = t.status == OvaTaskStatus.done;
    final text = (t.summary?.trim().isNotEmpty ?? false) ? t.summary!.trim() : t.title;
    return Positioned(
      top: y + 3,
      left: left ? x + _size + 6 : null,
      right: left ? null : size.width - x + 6,
      child: GestureDetector(
        onTap: () => _openSheet(),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: size.width * 0.66),
          child: Material(
            color: context.surface,
            elevation: 4,
            shadowColor: Colors.black26,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.full),
              side: BorderSide(color: ok ? AppColors.brandBlue.withValues(alpha: 0.5) : AppColors.brandPink.withValues(alpha: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(ok ? Icons.check_circle_rounded : Icons.error_outline_rounded, size: 14, color: ok ? AppColors.brandBlue : AppColors.brandPink),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '${t.source == 'ai_lab' ? 'AI Lab: ' : ''}$text',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.textPrimary),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ).animate().fadeIn(duration: 200.ms).slideX(begin: left ? -0.1 : 0.1, end: 0),
    );
  }

  Widget _bar(
    BuildContext context,
    Size size,
    double bubbleY,
    OvaAbilities ab,
    OvaDeviceEvents events,
    OvaTask? active,
    OvaTask? finished,
    OvaChatController chat,
  ) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final suggestions = ab.suggestions
        ? ovaSuggestionsFor(path: _path, abilities: ab, events: events, device: _device, dark: dark)
        : const <OvaSuggestion>[];
    final pending = chat.pendingConfirm;
    final below = bubbleY < size.height * 0.5;
    final last = chat.lastResult;

    final panel = Material(
      color: context.surface,
      elevation: 8,
      shadowColor: Colors.black38,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: context.border, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('Ova', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  active != null ? 'Working · ${active.title}' : _screenName(_path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 11, color: context.textMuted),
                ),
              ),
              _iconBtn(context, Icons.mic_rounded, () => _openSheet(voice: true)),
              _iconBtn(context, Icons.open_in_full_rounded, () => _openSheet()),
              _iconBtn(context, Icons.close_rounded, () => setState(() => _expanded = false)),
            ]),
            if (active != null) ...[
              const SizedBox(height: 6),
              for (final s in active.steps.reversed.take(3).toList().reversed) _stepRow(context, s),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    chat.stop();
                  },
                  child: Text('Stop', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.brandPink)),
                ),
              ),
            ],
            if (pending != null) ...[
              const SizedBox(height: 6),
              OvaConfirmCard(item: pending, chat: chat, dense: true),
            ] else if (active == null && last != null && finished != null) ...[
              const SizedBox(height: 6),
              Row(children: [
                Icon(last.icon, size: 14, color: last.ok ? AppColors.brandBlue : AppColors.brandPink),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(last.summary.split('\n').first,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 12, color: context.textPrimary)),
                ),
              ]),
            ],
            if (suggestions.isNotEmpty && pending == null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < suggestions.length; i++)
                    _chip(context, suggestions[i], disabled: chat.busy && !suggestions[i].openSheet)
                        .animate(delay: (25 * i).ms)
                        .fadeIn(duration: 180.ms)
                        .slideY(begin: 0.2, end: 0),
                ],
              ),
            ],
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _openSheet(),
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: context.border),
                ),
                child: Row(children: [
                  Icon(Icons.auto_awesome_rounded, size: 14, color: AppColors.brandBlue),
                  const SizedBox(width: 8),
                  Text('Ask Ova anything…', style: GoogleFonts.inter(fontSize: 12.5, color: context.textMuted)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );

    return Positioned(
      left: 12,
      right: 12,
      top: below ? bubbleY + _size + 8 : null,
      bottom: below ? null : size.height - bubbleY + 8,
      child: panel.animate().fadeIn(duration: 180.ms).scaleXY(begin: 0.96, end: 1, curve: Curves.easeOutCubic),
    );
  }

  Widget _iconBtn(BuildContext context, IconData icon, VoidCallback onTap) => InkResponse(
        radius: 18,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon, size: 17, color: context.textSecondary)),
      );

  Widget _stepRow(BuildContext context, OvaTaskStep s) {
    final (IconData icon, Color color) = switch (s.status) {
      OvaStepStatus.done => (Icons.check_circle_rounded, AppColors.brandBlue),
      OvaStepStatus.failed => (Icons.cancel_rounded, AppColors.brandPink),
      OvaStepStatus.waiting => (Icons.pan_tool_alt_rounded, AppColors.brandPink),
      OvaStepStatus.running => (Icons.more_horiz_rounded, context.textSecondary),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        s.status == OvaStepStatus.running
            ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.brandBlue))
            : Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 12, color: context.textPrimary)),
        ),
      ]),
    ).animate().fadeIn(duration: 160.ms);
  }

  Widget _chip(BuildContext context, OvaSuggestion s, {bool disabled = false}) {
    return Opacity(
      opacity: disabled ? 0.45 : 1,
      child: Material(
        color: s.accent ? AppColors.brandPink.withValues(alpha: 0.10) : context.surfaceMid,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.full),
          side: BorderSide(color: s.accent ? AppColors.brandPink.withValues(alpha: 0.45) : context.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.full),
          onTap: disabled ? null : () => _run(s),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(s.icon, size: 14, color: s.accent ? AppColors.brandPink : AppColors.brandBlue),
              const SizedBox(width: 6),
              Text(s.label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: context.textPrimary)),
            ]),
          ),
        ),
      ),
    );
  }

  static String _screenName(String path) {
    if (path.startsWith('/hub/home') || path == '/') return 'Suggestions for Reels';
    if (path.startsWith('/hub/messages')) return 'Suggestions for Chat';
    if (path.startsWith('/profile/me')) return 'Suggestions for your profile';
    if (path.startsWith('/profile')) return 'Suggestions for this profile';
    if (path.startsWith('/live')) return 'Suggestions for Live';
    if (path.startsWith('/settings')) return 'Suggestions for Settings';
    if (path.startsWith('/upload') || path.startsWith('/create')) return 'Suggestions for creating';
    return 'Suggestions';
  }
}
