/// FNV-1a 64-bit hash of the Look shader source. Stamped into the generated
/// native shaders so a test can tell when they are stale.
String shaderSourceHash(List<int> bytes) {
  // Two 32-bit halves keep the arithmetic exact on every platform.
  var hi = 0xcbf29ce4, lo = 0x84222325;
  const primeHi = 0x00000100, primeLo = 0x000001b3;
  for (final byte in bytes) {
    lo ^= byte & 0xff;
    final loProd = lo * primeLo;
    final newLo = loProd & 0xffffffff;
    final carry = (loProd - newLo) ~/ 0x100000000;
    hi = (hi * primeLo + lo * primeHi + carry) & 0xffffffff;
    lo = newLo;
  }
  return hi.toRadixString(16).padLeft(8, '0') + lo.toRadixString(16).padLeft(8, '0');
}
