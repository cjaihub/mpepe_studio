import Foundation

/// A compiled look as sent by `NativeLook.toMap()` on the Dart side.
struct NativeLookData {
  static let curvesWidth = 256
  static let curvesHeight = 2

  let id: String
  /// `LookCompiler.uniformValues`, `LookEngineShader.floatCount` floats.
  let uniforms: [Float]
  let lutAtlas: Data
  let lutSize: Int
  let curves: Data
}

/// A look switch requested from the main thread, applied on the capture queue.
struct LookRequest {
  let look: NativeLookData?
  let crossFadeMs: Int
}

/// Thread-safe frame counters with a rolling window of graded frame times.
final class FrameStats {
  private let lock = NSLock()
  private var times: [Double]
  private var count = 0
  private var next = 0
  private var graded = 0
  private var passedThrough = 0
  private var reason: String?
  private var width = 0
  private var height = 0
  private var lookId: String?

  init(window: Int = 240) {
    times = Array(repeating: 0, count: window)
  }

  func graded(ms: Double, width w: Int, height h: Int, lookId look: String?) {
    lock.lock()
    defer { lock.unlock() }
    times[next] = ms
    next = (next + 1) % times.count
    count = min(count + 1, times.count)
    graded += 1
    width = w
    height = h
    lookId = look
  }

  func passedThrough(_ why: String) {
    lock.lock()
    defer { lock.unlock() }
    passedThrough += 1
    reason = why
  }

  func toMap() -> [String: Any] {
    lock.lock()
    defer { lock.unlock() }
    let sorted = times.prefix(count).sorted()
    let avg = count == 0 ? 0 : sorted.reduce(0, +) / Double(count)
    let p95 = count == 0 ? 0 : sorted[((count - 1) * 95) / 100]
    var map: [String: Any] = [
      "framesGraded": graded,
      "framesPassedThrough": passedThrough,
      "averageFrameMs": avg,
      "p95FrameMs": p95,
      "width": width,
      "height": height,
    ]
    if let reason { map["lastPassThroughReason"] = reason }
    if let lookId { map["lookId"] = lookId }
    return map
  }
}
