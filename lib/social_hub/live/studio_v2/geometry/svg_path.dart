import 'dart:ui';

// ─────────────────────────────────────────────────────────────────────────────
// A tiny SVG path parser for the subset used in studio-geometry.json:
// absolute M, L, Q, Z (plus implicit repeats: extra pairs after M are L,
// extra quads after Q are Q). Anything else throws [FormatException] so a
// bad studio file fails loudly in tests, not silently on a device.
// ─────────────────────────────────────────────────────────────────────────────

final RegExp _token = RegExp(r'[A-Za-z]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?');

/// Parses [d] into a Flutter [Path].
Path parseSvgPath(String d) {
  final tokens = _token.allMatches(d).map((m) => m.group(0)!).toList();
  final path = Path();
  var i = 0;
  String? cmd;

  double num() {
    if (i >= tokens.length) throw FormatException('Unexpected end of path', d);
    final v = double.tryParse(tokens[i]);
    if (v == null) throw FormatException('Expected a number at "${tokens[i]}"', d);
    i++;
    return v;
  }

  bool nextIsNumber() => i < tokens.length && double.tryParse(tokens[i]) != null;

  while (i < tokens.length) {
    final t = tokens[i];
    if (double.tryParse(t) == null) {
      cmd = t;
      i++;
    } else if (cmd == null) {
      throw FormatException('Path must start with a command', d);
    }
    switch (cmd) {
      case 'M':
        path.moveTo(num(), num());
        cmd = 'L'; // implicit lineto for further pairs
        break;
      case 'L':
        path.lineTo(num(), num());
        break;
      case 'Q':
        path.quadraticBezierTo(num(), num(), num(), num());
        break;
      case 'Z':
      case 'z':
        path.close();
        cmd = null;
        if (nextIsNumber()) throw FormatException('Numbers after Z', d);
        break;
      default:
        throw FormatException('Unsupported path command "$cmd" (only absolute M, L, Q, Z)', d);
    }
  }
  return path;
}

/// All coordinate pairs of [d] (anchor and control points), for exact bounds
/// checks that do not depend on the engine's curve flattening.
List<Offset> svgPathPoints(String d) {
  final nums = RegExp(r'-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?')
      .allMatches(d)
      .map((m) => double.parse(m.group(0)!))
      .toList();
  return [for (var k = 0; k + 1 < nums.length; k += 2) Offset(nums[k], nums[k + 1])];
}
