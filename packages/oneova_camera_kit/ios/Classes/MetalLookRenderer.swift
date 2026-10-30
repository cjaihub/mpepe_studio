import CoreVideo
import Foundation
import Metal
import QuartzCore
import WebRTC

/// Grades WebRTC camera frames with the generated Look shader on Metal.
/// `process` runs on the capture queue (one frame at a time); `requestLook`
/// may be called from any thread.
///
/// Passes per frame: camera pixel buffer (NV12 or BGRA, with WebRTC's crop)
/// → RGB texture, then the Look shader → a pooled IOSurface BGRA buffer that
/// is handed to WebRTC. During a cross-fade the old look is drawn first and
/// the new one is blended over it with a constant alpha.
final class MetalLookRenderer {
  private let pipeline: LookMetalPipeline
  private let textureCache: CVMetalTextureCache
  private let stats: FrameStats
  private let maxInFlight: Int

  private let pendingLock = NSLock()
  private var pending: LookRequest?

  // Capture-queue state.
  private var current: LookMetalPipeline.GpuLook?
  private var fadeFrom: LookMetalPipeline.GpuLook?
  private var fading = false
  private var fadeStart: CFTimeInterval = 0
  private var fadeDuration: CFTimeInterval = 0
  private var pool: CVPixelBufferPool?
  private var poolWidth = 0
  private var poolHeight = 0
  private var sourceTexture: MTLTexture?
  private var loggedError = false

  /// Compiles the shaders; call off the main thread.
  init(maxInFlight: Int, stats: FrameStats) throws {
    guard let device = MTLCreateSystemDefaultDevice() else { throw LookMetalPipeline.SetupError.noDevice }
    pipeline = try LookMetalPipeline(device: device)
    var cache: CVMetalTextureCache?
    CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
    guard let cache else { throw LookMetalPipeline.SetupError.allocation("CoreVideo Metal texture cache") }
    textureCache = cache
    self.stats = stats
    self.maxInFlight = maxInFlight
  }

  func requestLook(_ request: LookRequest) {
    pendingLock.lock()
    pending = request
    pendingLock.unlock()
  }

  /// Returns the graded frame, or `frame` itself when it cannot be graded.
  func process(_ frame: RTCVideoFrame) -> RTCVideoFrame {
    do {
      try applyPending()
    } catch {
      return fail(frame, error)
    }
    if current == nil && !fading { return passThrough(frame, "no_look") }
    guard let buffer = frame.buffer as? RTCCVPixelBuffer else { return passThrough(frame, "cpu_buffer") }
    let input = buffer.pixelBuffer
    let format = CVPixelBufferGetPixelFormatType(input)
    let isNV12 =
      format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
      || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    guard isNV12 || format == kCVPixelFormatType_32BGRA else {
      return passThrough(frame, "unsupported_format")
    }

    let width = Int(buffer.width)
    let height = Int(buffer.height)
    let start = CACurrentMediaTime()
    do {
      var output: CVPixelBuffer?
      let aux = [kCVPixelBufferPoolAllocationThresholdKey: maxInFlight] as CFDictionary
      let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
        kCFAllocatorDefault, try outputPool(width, height), aux, &output)
      if status == kCVReturnWouldExceedAllocationThreshold {
        return passThrough(frame, "output_pool_exhausted")
      }
      guard status == kCVReturnSuccess, let output else {
        throw LookMetalPipeline.SetupError.allocation("output pixel buffer (\(status))")
      }
      CVBufferPropagateAttachments(input, output)

      let src = try sourceTexture(width, height)
      guard let cmd = pipeline.queue.makeCommandBuffer() else { throw LookMetalPipeline.SetupError.noCommandQueue }

      // Pass 1: camera buffer → RGB source texture.
      let inputs =
        isNV12
        ? [try cvTexture(input, plane: 0, format: .r8Unorm), try cvTexture(input, plane: 1, format: .rg8Unorm)]
        : [try cvTexture(input, plane: -1, format: .bgra8Unorm)]
      let srcPass = MTLRenderPassDescriptor()
      srcPass.colorAttachments[0].texture = src
      srcPass.colorAttachments[0].loadAction = .dontCare
      srcPass.colorAttachments[0].storeAction = .store
      guard let srcEncoder = cmd.makeRenderCommandEncoder(descriptor: srcPass) else {
        throw LookMetalPipeline.SetupError.allocation("render encoder")
      }
      pipeline.drawSource(
        inputs.compactMap { CVMetalTextureGetTexture($0) }, nv12: isNV12,
        params: sourceParams(buffer, isNV12: isNV12, format: format), encoder: srcEncoder)
      srcEncoder.endEncoding()

      // Pass 2: Look shader → output buffer.
      let out = try cvTexture(output, plane: -1, format: LookMetalPipeline.pixelFormat)
      let lookPass = MTLRenderPassDescriptor()
      lookPass.colorAttachments[0].texture = CVMetalTextureGetTexture(out)
      lookPass.colorAttachments[0].loadAction = .dontCare
      lookPass.colorAttachments[0].storeAction = .store
      guard let encoder = cmd.makeRenderCommandEncoder(descriptor: lookPass) else {
        throw LookMetalPipeline.SetupError.allocation("render encoder")
      }
      if fading {
        let t = min(1, max(0, (CACurrentMediaTime() - fadeStart) / fadeDuration))
        pipeline.drawLook(fadeFrom, src: src, width: width, height: height, blend: false, encoder: encoder)
        encoder.setBlendColor(red: 0, green: 0, blue: 0, alpha: Float(t))
        pipeline.drawLook(current, src: src, width: width, height: height, blend: true, encoder: encoder)
        if t >= 1 { endFade() }
      } else {
        pipeline.drawLook(current, src: src, width: width, height: height, blend: false, encoder: encoder)
      }
      encoder.endEncoding()

      cmd.commit()
      // The encoder reads the IOSurface outside Metal, so the frame must be
      // complete before it is handed on.
      cmd.waitUntilCompleted()
      withExtendedLifetime((inputs, out)) {}
      if cmd.status != .completed {
        throw cmd.error ?? LookMetalPipeline.SetupError.allocation("command buffer")
      }
      stats.graded(
        ms: (CACurrentMediaTime() - start) * 1000, width: width, height: height, lookId: current?.data.id)
      return RTCVideoFrame(
        buffer: RTCCVPixelBuffer(pixelBuffer: output), rotation: frame.rotation, timeStampNs: frame.timeStampNs)
    } catch {
      return fail(frame, error)
    }
  }

  private func passThrough(_ frame: RTCVideoFrame, _ reason: String) -> RTCVideoFrame {
    stats.passedThrough(reason)
    return frame
  }

  private func fail(_ frame: RTCVideoFrame, _ error: Error) -> RTCVideoFrame {
    if !loggedError {
      NSLog("[OneovaLookRenderer] Look render failed; sending original frames: \(error)")
      loggedError = true
    }
    return passThrough(frame, "render_error")
  }

  private func applyPending() throws {
    pendingLock.lock()
    let request = pending
    pending = nil
    pendingLock.unlock()
    guard let request else { return }
    if fading { endFade() }
    let next = try request.look.map { try pipeline.upload($0) }
    if current == nil && next == nil { return }
    fadeFrom = current
    current = next
    if request.crossFadeMs > 0 {
      fading = true
      fadeStart = CACurrentMediaTime()
      fadeDuration = Double(request.crossFadeMs) / 1000
    } else {
      fadeFrom = nil
    }
  }

  private func endFade() {
    fading = false
    fadeFrom = nil
  }

  private func sourceTexture(_ width: Int, _ height: Int) throws -> MTLTexture {
    if let t = sourceTexture, t.width == width, t.height == height { return t }
    let t = try pipeline.makeSourceTexture(width: width, height: height)
    sourceTexture = t
    return t
  }

  private func outputPool(_ width: Int, _ height: Int) throws -> CVPixelBufferPool {
    if let pool, poolWidth == width, poolHeight == height { return pool }
    let attrs: [CFString: Any] = [
      kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey: width,
      kCVPixelBufferHeightKey: height,
      kCVPixelBufferIOSurfacePropertiesKey: [CFString: Any](),
      kCVPixelBufferMetalCompatibilityKey: true,
    ]
    var created: CVPixelBufferPool?
    let status = CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &created)
    guard status == kCVReturnSuccess, let created else {
      throw LookMetalPipeline.SetupError.allocation("pixel buffer pool (\(status))")
    }
    // Buffers of the old pool stay valid until WebRTC releases them.
    pool = created
    poolWidth = width
    poolHeight = height
    return created
  }

  /// `plane` -1 means a non-planar buffer.
  private func cvTexture(_ buffer: CVPixelBuffer, plane: Int, format: MTLPixelFormat) throws -> CVMetalTexture {
    let w = plane < 0 ? CVPixelBufferGetWidth(buffer) : CVPixelBufferGetWidthOfPlane(buffer, plane)
    let h = plane < 0 ? CVPixelBufferGetHeight(buffer) : CVPixelBufferGetHeightOfPlane(buffer, plane)
    var texture: CVMetalTexture?
    let status = CVMetalTextureCacheCreateTextureFromImage(
      kCFAllocatorDefault, textureCache, buffer, nil, format, w, h, max(plane, 0), &texture)
    guard status == kCVReturnSuccess, let texture else {
      throw LookMetalPipeline.SetupError.allocation("CoreVideo texture (\(status))")
    }
    return texture
  }

  /// Crop rectangle and Y'CbCr → RGB conversion for `buffer`.
  private func sourceParams(_ buffer: RTCCVPixelBuffer, isNV12: Bool, format: OSType)
    -> LookMetalPipeline.SourceParams
  {
    let pb = buffer.pixelBuffer
    let bw = Float(CVPixelBufferGetWidth(pb))
    let bh = Float(CVPixelBufferGetHeight(pb))
    let crop = SIMD4<Float>(
      Float(buffer.cropX) / bw, Float(buffer.cropY) / bh,
      Float(buffer.cropWidth) / bw, Float(buffer.cropHeight) / bh)
    guard isNV12 else { return .init(crop: crop, range: .zero, coeffs: .zero) }

    let videoRange = format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    let range =
      videoRange
      ? SIMD4<Float>(16 / 255, 255 / 219, 128 / 255, 255 / 224)
      : SIMD4<Float>(0, 1, 128 / 255, 1)
    let matrix = CVBufferCopyAttachment(pb, kCVImageBufferYCbCrMatrixKey, nil) as? String
    let coeffs: SIMD4<Float>
    if matrix == (kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String) {
      coeffs = SIMD4<Float>(1.5748, 0.187324, 0.468124, 1.8556)
    } else {
      // BT.601 (camera default when no matrix is attached).
      coeffs = SIMD4<Float>(1.402, 0.344136, 0.714136, 1.772)
    }
    return .init(crop: crop, range: range, coeffs: coeffs)
  }
}
