import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Which physical keyboard the on-screen keyboard imitates.
enum LiveKeyboardStyle { mac, windows }

/// Compact, premium on-screen computer keyboard for Online Control.
///
/// Looks and behaves like a real macOS (space-grey, ⌘ ⌥ ⌃ ⇧) or Windows
/// (matte black, Ctrl ⊞ Alt) keyboard: textured keycaps with a lit top edge,
/// a lip that sinks when pressed and an accent glow on the active key.
/// Modifiers latch for one key (tap) or lock (double-tap), so shortcuts like
/// ⌘C are two taps. Output goes through [onKey] (single key or character) and
/// [onCombo] (`"cmd+shift+4"` style strings the desktop agent understands).
class LiveKeyboard extends StatefulWidget {
  const LiveKeyboard({
    super.key,
    required this.style,
    required this.onKey,
    required this.onCombo,
    this.onStyleChanged,
    this.onClose,
  });

  final LiveKeyboardStyle style;
  final ValueChanged<String> onKey;
  final ValueChanged<String> onCombo;
  final ValueChanged<LiveKeyboardStyle>? onStyleChanged;
  final VoidCallback? onClose;

  @override
  State<LiveKeyboard> createState() => _LiveKeyboardState();
}

/// A key on the board. [id] is what is sent; [label]/[shiftLabel] are drawn.
class _K {
  const _K(this.id, this.label, {this.flex = 1.0, this.shiftLabel, this.mod, this.small = false});
  final String id;
  final String label;
  final String? shiftLabel;
  final double flex;
  final String? mod; // cmd | ctrl | alt | shift | fn
  final bool small;
}

class _Palette {
  const _Palette({
    required this.base,
    required this.baseEdge,
    required this.capTop,
    required this.capBottom,
    required this.capLip,
    required this.legend,
    required this.legendMuted,
    required this.accent,
    required this.brushed,
  });
  final Color base;
  final Color baseEdge;
  final Color capTop;
  final Color capBottom;
  final Color capLip;
  final Color legend;
  final Color legendMuted;
  final Color accent;
  final bool brushed;

  static const mac = _Palette(
    base: Color(0xFF2B2D31),
    baseEdge: Color(0xFF45484E),
    capTop: Color(0xFF3A3C41),
    capBottom: Color(0xFF2E3034),
    capLip: Color(0xFF141518),
    legend: Color(0xFFF2F3F5),
    legendMuted: Color(0xFFA9ADB5),
    accent: Color(0xFF4C9BFF),
    brushed: true,
  );

  static const windows = _Palette(
    base: Color(0xFF16171A),
    baseEdge: Color(0xFF2A2C31),
    capTop: Color(0xFF26282C),
    capBottom: Color(0xFF1C1D20),
    capLip: Color(0xFF060607),
    legend: Color(0xFFECEDEF),
    legendMuted: Color(0xFF9097A1),
    accent: Color(0xFF3AA0FF),
    brushed: false,
  );
}

class _LiveKeyboardState extends State<LiveKeyboard> {
  final Set<String> _latched = {};
  final Set<String> _locked = {};
  final Map<String, DateTime> _lastModTap = {};
  bool _capsOn = false;
  bool _fnRow = false;

  bool get _isMac => widget.style == LiveKeyboardStyle.mac;
  _Palette get _p => _isMac ? _Palette.mac : _Palette.windows;

  bool _modActive(String m) => _latched.contains(m) || _locked.contains(m);
  bool get _shiftActive => _modActive('shift');

  void _tapModifier(String mod) {
    HapticFeedback.selectionClick();
    final now = DateTime.now();
    final last = _lastModTap[mod];
    _lastModTap[mod] = now;
    setState(() {
      if (_locked.contains(mod)) {
        _locked.remove(mod);
        _latched.remove(mod);
      } else if (last != null && now.difference(last).inMilliseconds < 320) {
        _locked.add(mod);
        _latched.remove(mod);
      } else if (_latched.contains(mod)) {
        _latched.remove(mod);
      } else {
        _latched.add(mod);
      }
    });
  }

  void _press(_K k) {
    if (k.mod != null) {
      if (k.mod == 'fn') {
        HapticFeedback.selectionClick();
        setState(() => _fnRow = !_fnRow);
      } else {
        _tapModifier(k.mod!);
      }
      return;
    }
    HapticFeedback.selectionClick();
    if (k.id == 'caps') {
      setState(() => _capsOn = !_capsOn);
      return;
    }

    final mods = <String>[
      for (final m in const ['ctrl', 'alt', 'shift', 'cmd'])
        if (_modActive(m)) m,
    ];
    final isChar = k.id.length == 1;

    if (mods.isEmpty || (isChar && mods.length == 1 && mods.first == 'shift')) {
      if (isChar) {
        final upper = _shiftActive || _capsOn;
        final ch = _shiftActive && k.shiftLabel != null
            ? k.shiftLabel!
            : (upper ? k.id.toUpperCase() : k.id);
        widget.onKey(ch);
      } else {
        widget.onKey(k.id);
      }
    } else {
      widget.onCombo([...mods, k.id].join('+'));
    }
    if (_latched.isNotEmpty) setState(_latched.clear);
  }

  List<List<_K>> _rows() {
    final mac = _isMac;
    final top = _fnRow
        ? <_K>[
            const _K('escape', 'esc', flex: 1.3, small: true),
            for (var i = 1; i <= 12; i++) _K('f$i', 'F$i', small: true),
          ]
        : const <_K>[
            _K('`', '`', shiftLabel: '~'),
            _K('1', '1', shiftLabel: '!'),
            _K('2', '2', shiftLabel: '@'),
            _K('3', '3', shiftLabel: '#'),
            _K('4', '4', shiftLabel: r'$'),
            _K('5', '5', shiftLabel: '%'),
            _K('6', '6', shiftLabel: '^'),
            _K('7', '7', shiftLabel: '&'),
            _K('8', '8', shiftLabel: '*'),
            _K('9', '9', shiftLabel: '('),
            _K('0', '0', shiftLabel: ')'),
            _K('-', '-', shiftLabel: '_'),
            _K('=', '=', shiftLabel: '+'),
            _K('backspace', '⌫', flex: 1.5),
          ];
    return [
      top,
      [
        _K('tab', mac ? '⇥' : 'Tab', flex: 1.5, small: !mac),
        for (final c in 'qwertyuiop'.split('')) _K(c, c),
        const _K('[', '[', shiftLabel: '{'),
        const _K(']', ']', shiftLabel: '}'),
        const _K(r'\', r'\', shiftLabel: '|'),
      ],
      [
        _K('caps', mac ? '⇪' : 'Caps', flex: 1.8, small: !mac),
        for (final c in 'asdfghjkl'.split('')) _K(c, c),
        const _K(';', ';', shiftLabel: ':'),
        const _K("'", "'", shiftLabel: '"'),
        _K('return', mac ? 'return' : 'Enter', flex: 2.0, small: true),
      ],
      [
        _K('shift', mac ? '⇧' : 'Shift', flex: 2.3, mod: 'shift', small: !mac),
        for (final c in 'zxcvbnm'.split('')) _K(c, c),
        const _K(',', ',', shiftLabel: '<'),
        const _K('.', '.', shiftLabel: '>'),
        const _K('/', '/', shiftLabel: '?'),
        _K('up', '↑', flex: 1.0),
        _K('shift', mac ? '⇧' : 'Shift', flex: 1.4, mod: 'shift', small: !mac),
      ],
      mac
          ? const [
              _K('fn', 'fn', mod: 'fn', small: true),
              _K('ctrl', '⌃', mod: 'ctrl'),
              _K('alt', '⌥', mod: 'alt'),
              _K('cmd', '⌘', flex: 1.3, mod: 'cmd'),
              _K('space', '', flex: 5.0),
              _K('cmd', '⌘', flex: 1.3, mod: 'cmd'),
              _K('left', '←'),
              _K('down', '↓'),
              _K('right', '→'),
            ]
          : const [
              _K('fn', 'Fn', mod: 'fn', small: true),
              _K('ctrl', 'Ctrl', flex: 1.3, mod: 'ctrl', small: true),
              _K('cmd', '⊞', mod: 'cmd'),
              _K('alt', 'Alt', mod: 'alt', small: true),
              _K('space', '', flex: 5.0),
              _K('alt', 'Alt', mod: 'alt', small: true),
              _K('left', '←'),
              _K('down', '↓'),
              _K('right', '→'),
            ],
    ];
  }

  List<({String label, String combo})> _shortcuts() {
    if (_isMac) {
      return const [
        (label: 'Copy', combo: 'cmd+c'),
        (label: 'Paste', combo: 'cmd+v'),
        (label: 'Undo', combo: 'cmd+z'),
        (label: 'Select all', combo: 'cmd+a'),
        (label: 'Search', combo: 'cmd+space'),
        (label: 'Switch app', combo: 'cmd+tab'),
        (label: 'Screenshot', combo: 'cmd+shift+4'),
        (label: 'Close', combo: 'cmd+w'),
      ];
    }
    return const [
      (label: 'Copy', combo: 'ctrl+c'),
      (label: 'Paste', combo: 'ctrl+v'),
      (label: 'Undo', combo: 'ctrl+z'),
      (label: 'Select all', combo: 'ctrl+a'),
      (label: 'Start', combo: 'win'),
      (label: 'Switch app', combo: 'alt+tab'),
      (label: 'Snip', combo: 'win+shift+s'),
      (label: 'Close', combo: 'ctrl+w'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(p.base, Colors.white, 0.05)!, p.base],
          ),
          border: Border.all(color: p.baseEdge, width: 1),
          boxShadow: const [
            BoxShadow(color: Color(0x99000000), blurRadius: 24, offset: Offset(0, 10)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: CustomPaint(
            painter: _BasePainter(brushed: p.brushed),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _header(p),
                  const SizedBox(height: 6),
                  _shortcutStrip(p),
                  const SizedBox(height: 6),
                  for (final row in _rows()) _row(row, p),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(_Palette p) {
    Widget seg(LiveKeyboardStyle s, String label, IconData icon) {
      final on = widget.style == s;
      return GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onStyleChanged?.call(s);
          setState(() {
            _latched.clear();
            _locked.clear();
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: on ? p.accent.withValues(alpha: 0.22) : Colors.transparent,
            border: Border.all(color: on ? p.accent : Colors.transparent),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: on ? p.legend : p.legendMuted),
            const SizedBox(width: 5),
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: on ? p.legend : p.legendMuted)),
          ]),
        ),
      );
    }

    return Row(
      children: [
        const SizedBox(width: 4),
        seg(LiveKeyboardStyle.mac, 'macOS', Icons.laptop_mac_rounded),
        const SizedBox(width: 4),
        seg(LiveKeyboardStyle.windows, 'Windows', Icons.window_rounded),
        const Spacer(),
        if (_locked.isNotEmpty || _capsOn)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              [
                if (_capsOn) 'CAPS',
                ..._locked.map((m) => m.toUpperCase()),
              ].join(' · '),
              style: GoogleFonts.inter(
                  fontSize: 10, fontWeight: FontWeight.w800, color: p.accent, letterSpacing: 0.6),
            ),
          ),
        if (widget.onClose != null)
          GestureDetector(
            onTap: widget.onClose,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.keyboard_hide_rounded, size: 20, color: p.legendMuted),
            ),
          ),
      ],
    );
  }

  Widget _shortcutStrip(_Palette p) {
    return SizedBox(
      height: 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: _shortcuts().length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final s = _shortcuts()[i];
          return _Keycap(
            palette: p,
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onCombo(s.combo);
            },
            pill: true,
            child: Text(s.label,
                style: GoogleFonts.inter(
                    fontSize: 11, fontWeight: FontWeight.w600, color: p.legend)),
          );
        },
      ),
    );
  }

  Widget _row(List<_K> keys, _Palette p) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SizedBox(
        height: 38,
        child: Row(
          children: [
            for (var i = 0; i < keys.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                flex: (keys[i].flex * 10).round(),
                child: _keyFor(keys[i], p),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _keyFor(_K k, _Palette p) {
    final active = (k.mod != null && k.mod != 'fn' && _modActive(k.mod!)) ||
        (k.mod == 'fn' && _fnRow) ||
        (k.id == 'caps' && _capsOn);
    final locked = k.mod != null && _locked.contains(k.mod);
    final isChar = k.id.length == 1;
    String label = k.label;
    if (isChar) {
      if (_shiftActive && k.shiftLabel != null) {
        label = k.shiftLabel!;
      } else if (_shiftActive || _capsOn) {
        label = k.label.toUpperCase();
      }
    }
    return _Keycap(
      palette: p,
      active: active,
      locked: locked,
      onTap: () => _press(k),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: (k.small || label.length > 2
                ? GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600)
                : GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500))
            .copyWith(color: active ? Colors.white : p.legend, height: 1.0),
      ),
    );
  }
}

/// One keycap: lit top edge, textured face, a lip that sinks on press and an
/// accent glow while pressed or latched.
class _Keycap extends StatefulWidget {
  const _Keycap({
    required this.palette,
    required this.child,
    required this.onTap,
    this.active = false,
    this.locked = false,
    this.pill = false,
  });

  final _Palette palette;
  final Widget child;
  final VoidCallback onTap;
  final bool active;
  final bool locked;
  final bool pill;

  @override
  State<_Keycap> createState() => _KeycapState();
}

class _KeycapState extends State<_Keycap> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final lit = _down || widget.active;
    final radius = BorderRadius.circular(widget.pill ? 999 : 7);
    const lip = 2.5;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 70),
        curve: Curves.easeOut,
        margin: EdgeInsets.only(top: _down ? lip : 0),
        padding: EdgeInsets.only(bottom: _down ? 0.5 : lip),
        decoration: BoxDecoration(
          borderRadius: radius,
          color: p.capLip,
          boxShadow: [
            if (lit)
              BoxShadow(
                color: p.accent.withValues(alpha: widget.locked ? 0.75 : 0.5),
                blurRadius: 12,
                spreadRadius: 0.5,
              )
            else
              const BoxShadow(color: Color(0x66000000), blurRadius: 2, offset: Offset(0, 1)),
          ],
        ),
        child: Container(
          padding: widget.pill ? const EdgeInsets.symmetric(horizontal: 12) : EdgeInsets.zero,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: lit
                  ? [
                      Color.lerp(p.capTop, p.accent, 0.55)!,
                      Color.lerp(p.capBottom, p.accent, 0.38)!,
                    ]
                  : [p.capTop, p.capBottom],
            ),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: lit ? 0.35 : 0.13),
                width: 1,
              ),
            ),
          ),
          child: CustomPaint(
            painter: const _CapGrainPainter(),
            child: Center(child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// Fine grain on each keycap face (fixed pattern, no per-frame randomness).
class _CapGrainPainter extends CustomPainter {
  const _CapGrainPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    final light = Paint()..color = const Color(0x0DFFFFFF);
    final dark = Paint()..color = const Color(0x12000000);
    final count = (size.width * size.height / 26).clamp(8, 120).toInt();
    for (var i = 0; i < count; i++) {
      final o = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      canvas.drawRect(Rect.fromLTWH(o.dx, o.dy, 1, 1), i.isEven ? light : dark);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Keyboard base: brushed aluminium lines (macOS) or a soft matte grain.
class _BasePainter extends CustomPainter {
  const _BasePainter({required this.brushed});
  final bool brushed;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(11);
    if (brushed) {
      for (double y = 0; y < size.height; y += 1.5) {
        final a = 0.015 + rnd.nextDouble() * 0.035;
        canvas.drawLine(
          Offset(0, y),
          Offset(size.width, y),
          Paint()
            ..color = Colors.white.withValues(alpha: a)
            ..strokeWidth = 0.6,
        );
      }
    } else {
      final p = Paint()..color = const Color(0x0AFFFFFF);
      for (var i = 0; i < (size.width * size.height / 40); i++) {
        canvas.drawRect(
          Rect.fromLTWH(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height, 1, 1),
          p,
        );
      }
    }
    // Soft top sheen.
    canvas.drawRect(
      Offset.zero & Size(size.width, size.height * 0.35),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x14FFFFFF), Color(0x00FFFFFF)],
        ).createShader(Offset.zero & Size(size.width, size.height * 0.35)),
    );
  }

  @override
  bool shouldRepaint(covariant _BasePainter oldDelegate) => oldDelegate.brushed != brushed;
}
