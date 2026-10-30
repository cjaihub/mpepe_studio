// Renders the Flutter-path fixtures (test/looks/native_parity_fixtures_test.dart)
// through the plugin's Metal pipeline (ios/Classes/LookMetalPipeline.swift)
// on this Mac's GPU and reports CIEDE2000 against the Flutter output.
//
// Pass: p99 ΔE2000 < 1.0 and no channel more than one 8-bit level apart
// (rounding; one level near black alone can exceed ΔE 1). Film grain is a
// hash of the pixel position whose fract() is precision-sensitive across
// GPU backends, so the grain look is held to mean ΔE < 0.5 instead.
import Foundation
import Metal

struct Fixture {
  let name: String
  let width: Int
  let height: Int
  let input: Data
  let expected: Data
  let look: NativeLookData
}

func loadFixture(_ dir: URL) throws -> Fixture {
  func read(_ name: String) throws -> Data { try Data(contentsOf: dir.appendingPathComponent(name)) }
  let meta = try JSONSerialization.jsonObject(with: read("meta.json")) as! [String: Any]
  let uniforms = try read("uniforms.f32").withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
  precondition(uniforms.count == LookEngineShader.floatCount, "uniform count mismatch in \(dir.lastPathComponent)")
  return Fixture(
    name: dir.lastPathComponent,
    width: meta["width"] as! Int,
    height: meta["height"] as! Int,
    input: try read("input.rgba"),
    expected: try read("expected.rgba"),
    look: NativeLookData(
      id: dir.lastPathComponent, uniforms: uniforms, lutAtlas: try read("lut.rgba"),
      lutSize: meta["lutSize"] as! Int, curves: try read("curves.rgba")))
}

// sRGB (0–255) → CIE L*a*b* (D65).
func lab(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> (Double, Double, Double) {
  func lin(_ v: UInt8) -> Double {
    let c = Double(v) / 255
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
  }
  let (lr, lg, lb) = (lin(r), lin(g), lin(b))
  let x = (0.4124564 * lr + 0.3575761 * lg + 0.1804375 * lb) / 0.95047
  let y = 0.2126729 * lr + 0.7151522 * lg + 0.0721750 * lb
  let z = (0.0193339 * lr + 0.1191920 * lg + 0.9503041 * lb) / 1.08883
  func f(_ t: Double) -> Double { t > 216.0 / 24389 ? cbrt(t) : (24389.0 / 27 * t + 16) / 116 }
  return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
}

// CIEDE2000 (Sharma, Wu, Dalal 2005).
func deltaE2000(_ p: (Double, Double, Double), _ q: (Double, Double, Double)) -> Double {
  let (l1, a1, b1) = p
  let (l2, a2, b2) = q
  let rad = Double.pi / 180
  let c1 = hypot(a1, b1), c2 = hypot(a2, b2)
  let cm = (c1 + c2) / 2
  let g = 0.5 * (1 - sqrt(pow(cm, 7) / (pow(cm, 7) + pow(25, 7))))
  let a1p = (1 + g) * a1, a2p = (1 + g) * a2
  let c1p = hypot(a1p, b1), c2p = hypot(a2p, b2)
  func hue(_ b: Double, _ a: Double) -> Double {
    if a == 0 && b == 0 { return 0 }
    let h = atan2(b, a) / rad
    return h < 0 ? h + 360 : h
  }
  let h1p = hue(b1, a1p), h2p = hue(b2, a2p)
  let dLp = l2 - l1
  let dCp = c2p - c1p
  var dhp = 0.0
  if c1p * c2p != 0 {
    dhp = h2p - h1p
    if dhp > 180 { dhp -= 360 } else if dhp < -180 { dhp += 360 }
  }
  let dHp = 2 * sqrt(c1p * c2p) * sin(dhp / 2 * rad)
  let lpm = (l1 + l2) / 2
  let cpm = (c1p + c2p) / 2
  var hpm = h1p + h2p
  if c1p * c2p != 0 {
    if abs(h1p - h2p) <= 180 { hpm /= 2 } else if h1p + h2p < 360 { hpm = (hpm + 360) / 2 } else { hpm = (hpm - 360) / 2 }
  }
  let t = 1 - 0.17 * cos((hpm - 30) * rad) + 0.24 * cos(2 * hpm * rad) + 0.32 * cos((3 * hpm + 6) * rad)
    - 0.20 * cos((4 * hpm - 63) * rad)
  let dTheta = 30 * exp(-pow((hpm - 275) / 25, 2))
  let rc = 2 * sqrt(pow(cpm, 7) / (pow(cpm, 7) + pow(25, 7)))
  let sl = 1 + 0.015 * pow(lpm - 50, 2) / sqrt(20 + pow(lpm - 50, 2))
  let sc = 1 + 0.045 * cpm
  let sh = 1 + 0.015 * cpm * t
  let rt = -sin(2 * dTheta * rad) * rc
  return sqrt(pow(dLp / sl, 2) + pow(dCp / sc, 2) + pow(dHp / sh, 2) + rt * (dCp / sc) * (dHp / sh))
}

/// Renders `fixture` through the source pass and the Look pass; with
/// `fadeFromSource`, cross-fades from the ungraded frame at alpha `fade`.
func render(_ f: Fixture, _ pipeline: LookMetalPipeline, fade: Float? = nil) throws -> [UInt8] {
  let device = pipeline.device
  let inDesc = MTLTextureDescriptor.texture2DDescriptor(
    pixelFormat: .rgba8Unorm, width: f.width, height: f.height, mipmapped: false)
  inDesc.usage = .shaderRead
  let input = device.makeTexture(descriptor: inDesc)!
  f.input.withUnsafeBytes {
    input.replace(
      region: MTLRegionMake2D(0, 0, f.width, f.height), mipmapLevel: 0, withBytes: $0.baseAddress!,
      bytesPerRow: f.width * 4)
  }
  let src = try pipeline.makeSourceTexture(width: f.width, height: f.height)
  let out = try pipeline.makeSourceTexture(width: f.width, height: f.height)
  let readback = device.makeBuffer(length: f.width * f.height * 4, options: .storageModeShared)!
  let look = try pipeline.upload(f.look)

  let cmd = pipeline.queue.makeCommandBuffer()!
  let p1 = MTLRenderPassDescriptor()
  p1.colorAttachments[0].texture = src
  p1.colorAttachments[0].loadAction = .dontCare
  p1.colorAttachments[0].storeAction = .store
  let e1 = cmd.makeRenderCommandEncoder(descriptor: p1)!
  pipeline.drawSource(
    [input], nv12: false, params: .init(crop: SIMD4(0, 0, 1, 1), range: .zero, coeffs: .zero), encoder: e1)
  e1.endEncoding()

  let p2 = MTLRenderPassDescriptor()
  p2.colorAttachments[0].texture = out
  p2.colorAttachments[0].loadAction = .dontCare
  p2.colorAttachments[0].storeAction = .store
  let e2 = cmd.makeRenderCommandEncoder(descriptor: p2)!
  if let fade {
    pipeline.drawLook(nil, src: src, width: f.width, height: f.height, blend: false, encoder: e2)
    e2.setBlendColor(red: 0, green: 0, blue: 0, alpha: fade)
    pipeline.drawLook(look, src: src, width: f.width, height: f.height, blend: true, encoder: e2)
  } else {
    pipeline.drawLook(look, src: src, width: f.width, height: f.height, blend: false, encoder: e2)
  }
  e2.endEncoding()

  let blit = cmd.makeBlitCommandEncoder()!
  blit.copy(
    from: out, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
    sourceSize: MTLSize(width: f.width, height: f.height, depth: 1), to: readback,
    destinationOffset: 0, destinationBytesPerRow: f.width * 4, destinationBytesPerImage: f.width * f.height * 4)
  blit.endEncoding()
  cmd.commit()
  cmd.waitUntilCompleted()
  if let error = cmd.error { throw error }

  // BGRA → RGBA
  let bgra = readback.contents().bindMemory(to: UInt8.self, capacity: f.width * f.height * 4)
  var rgba = [UInt8](repeating: 0, count: f.width * f.height * 4)
  for i in stride(from: 0, to: rgba.count, by: 4) {
    rgba[i] = bgra[i + 2]
    rgba[i + 1] = bgra[i + 1]
    rgba[i + 2] = bgra[i]
    rgba[i + 3] = bgra[i + 3]
  }
  return rgba
}

struct Score {
  var mean = 0.0
  var p99 = 0.0
  var max = 0.0
  var maxLevel = 0
}

func score(_ a: [UInt8], _ b: [UInt8]) -> Score {
  var des: [Double] = []
  var maxLevel = 0
  for i in stride(from: 0, to: a.count, by: 4) {
    des.append(deltaE2000(lab(a[i], a[i + 1], a[i + 2]), lab(b[i], b[i + 1], b[i + 2])))
    for c in 0..<3 { maxLevel = max(maxLevel, abs(Int(a[i + c]) - Int(b[i + c]))) }
  }
  des.sort()
  return Score(
    mean: des.reduce(0, +) / Double(des.count), p99: des[(des.count - 1) * 99 / 100], max: des.last!,
    maxLevel: maxLevel)
}

let args = CommandLine.arguments
guard args.count == 2 else {
  print("usage: metal_parity <fixtures dir>")
  exit(2)
}
let root = URL(fileURLWithPath: args[1])
let dirs = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
  .filter { $0.hasDirectoryPath }.sorted { $0.lastPathComponent < $1.lastPathComponent }
guard let device = MTLCreateSystemDefaultDevice() else {
  print("No Metal device")
  exit(2)
}
let pipeline = try LookMetalPipeline(device: device)
print("Metal device: \(device.name)  looks: \(dirs.count)")
print("look".padding(toLength: 22, withPad: " ", startingAt: 0) + "mean ΔE   p99 ΔE   max ΔE   max Δ8bit")
var failed = false
for dir in dirs {
  let f = try loadFixture(dir)
  let s = score(try render(f, pipeline), [UInt8](f.expected))
  let ok = f.name == "grain" ? s.mean < 0.5 : (s.p99 < 1.0 && s.maxLevel <= 1)
  failed = failed || !ok
  print(
    f.name.padding(toLength: 22, withPad: " ", startingAt: 0)
      + String(format: "%7.3f  %7.3f  %7.3f  %9d", s.mean, s.p99, s.max, s.maxLevel) + (ok ? "" : "  FAIL"))
}

// Cross-fade halfway from the original frame: expect the average of both.
if let dir = dirs.first(where: { $0.lastPathComponent == "cinematic_mix" }) {
  let f = try loadFixture(dir)
  let half = try render(f, pipeline, fade: 0.5)
  let expected = [UInt8](f.expected)
  let input = [UInt8](f.input)
  var worst = 0
  for i in 0..<half.count where i % 4 != 3 {
    let mid = (Int(expected[i]) + Int(input[i])) / 2
    worst = max(worst, abs(Int(half[i]) - mid))
  }
  failed = failed || worst > 2
  print("cross-fade 50% vs mean of original and graded: max Δ8bit \(worst)\(worst > 2 ? "  FAIL" : "")")
}
exit(failed ? 1 : 0)
