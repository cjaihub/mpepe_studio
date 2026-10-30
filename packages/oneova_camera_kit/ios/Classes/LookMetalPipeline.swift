import Foundation
import Metal

/// Metal pipelines, samplers and draw calls of the Look engine. Free of
/// WebRTC and CoreVideo so tool/metal_parity can compile and test it on macOS.
final class LookMetalPipeline {
  enum SetupError: Error, CustomStringConvertible {
    case noDevice
    case noCommandQueue
    case missingFunction(String)
    case allocation(String)

    var description: String {
      switch self {
      case .noDevice: return "Metal is unavailable"
      case .noCommandQueue: return "Could not create a Metal command queue"
      case .missingFunction(let name): return "Metal function \(name) missing"
      case .allocation(let what): return "Could not allocate \(what)"
      }
    }
  }

  struct GpuLook {
    let data: NativeLookData
    let lut: MTLTexture
    let curves: MTLTexture
  }

  /// Matches `SourceParams` in LookPassesShader.
  struct SourceParams {
    var crop: SIMD4<Float>
    var range: SIMD4<Float>
    var coeffs: SIMD4<Float>
  }

  static let pixelFormat = MTLPixelFormat.bgra8Unorm

  let device: MTLDevice
  let queue: MTLCommandQueue
  let nv12Pipeline: MTLRenderPipelineState
  let rgbPipeline: MTLRenderPipelineState
  private let lookPipeline: MTLRenderPipelineState
  private let lookBlendPipeline: MTLRenderPipelineState
  private let copyPipeline: MTLRenderPipelineState
  private let copyBlendPipeline: MTLRenderPipelineState
  let linearSampler: MTLSamplerState
  private let nearestSampler: MTLSamplerState

  /// Compiles both shader libraries; call off the main thread.
  init(device: MTLDevice) throws {
    guard let queue = device.makeCommandQueue() else { throw SetupError.noCommandQueue }
    self.device = device
    self.queue = queue

    let options = MTLCompileOptions()
    let look = try device.makeLibrary(source: LookEngineShader.metalSource, options: options)
    let passes = try device.makeLibrary(source: LookPassesShader.metalSource, options: options)
    func fn(_ lib: MTLLibrary, _ name: String) throws -> MTLFunction {
      guard let f = lib.makeFunction(name: name) else { throw SetupError.missingFunction(name) }
      return f
    }
    func pipeline(_ vertex: MTLFunction, _ fragment: MTLFunction, blend: Bool) throws
      -> MTLRenderPipelineState
    {
      let d = MTLRenderPipelineDescriptor()
      d.vertexFunction = vertex
      d.fragmentFunction = fragment
      let color = d.colorAttachments[0]!
      color.pixelFormat = Self.pixelFormat
      if blend {
        // out = new · t + old · (1 − t), t from setBlendColor's alpha.
        color.isBlendingEnabled = true
        color.rgbBlendOperation = .add
        color.alphaBlendOperation = .add
        color.sourceRGBBlendFactor = .blendAlpha
        color.sourceAlphaBlendFactor = .blendAlpha
        color.destinationRGBBlendFactor = .oneMinusBlendAlpha
        color.destinationAlphaBlendFactor = .oneMinusBlendAlpha
      }
      return try device.makeRenderPipelineState(descriptor: d)
    }
    let sourceVertex = try fn(passes, LookPassesShader.sourceVertex)
    let lookVertex = try fn(passes, LookPassesShader.lookVertex)
    let lookFragment = try fn(look, LookEngineShader.fragmentFunction)
    let copyFragment = try fn(passes, LookPassesShader.copyFragment)
    nv12Pipeline = try pipeline(sourceVertex, try fn(passes, LookPassesShader.sourceNV12), blend: false)
    rgbPipeline = try pipeline(sourceVertex, try fn(passes, LookPassesShader.sourceRGB), blend: false)
    lookPipeline = try pipeline(lookVertex, lookFragment, blend: false)
    lookBlendPipeline = try pipeline(lookVertex, lookFragment, blend: true)
    copyPipeline = try pipeline(lookVertex, copyFragment, blend: false)
    copyBlendPipeline = try pipeline(lookVertex, copyFragment, blend: true)

    func sampler(_ filter: MTLSamplerMinMagFilter) throws -> MTLSamplerState {
      let d = MTLSamplerDescriptor()
      d.minFilter = filter
      d.magFilter = filter
      d.sAddressMode = .clampToEdge
      d.tAddressMode = .clampToEdge
      guard let s = device.makeSamplerState(descriptor: d) else { throw SetupError.allocation("sampler") }
      return s
    }
    linearSampler = try sampler(.linear)
    nearestSampler = try sampler(.nearest)
  }

  /// Uploads the LUT atlas and curve texture of `data`.
  func upload(_ data: NativeLookData) throws -> GpuLook {
    GpuLook(
      data: data,
      lut: try texture(data.lutAtlas, width: data.lutSize * data.lutSize, height: data.lutSize),
      curves: try texture(data.curves, width: NativeLookData.curvesWidth, height: NativeLookData.curvesHeight))
  }

  /// A render-target texture for the RGB source pass.
  func makeSourceTexture(width: Int, height: Int) throws -> MTLTexture {
    let d = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: Self.pixelFormat, width: width, height: height, mipmapped: false)
    d.usage = [.renderTarget, .shaderRead]
    d.storageMode = .private
    guard let t = device.makeTexture(descriptor: d) else { throw SetupError.allocation("source texture") }
    return t
  }

  /// Draws the source pass: `textures` (Y + CbCr for NV12, else one RGB
  /// texture) cropped by `params` into the bound render target.
  func drawSource(
    _ textures: [MTLTexture], nv12: Bool, params: SourceParams, encoder: MTLRenderCommandEncoder
  ) {
    var p = params
    encoder.setRenderPipelineState(nv12 ? nv12Pipeline : rgbPipeline)
    for (i, t) in textures.enumerated() { encoder.setFragmentTexture(t, index: i) }
    encoder.setVertexBytes(&p, length: MemoryLayout<SourceParams>.stride, index: 0)
    if nv12 { encoder.setFragmentBytes(&p, length: MemoryLayout<SourceParams>.stride, index: 0) }
    encoder.setFragmentSamplerState(linearSampler, index: 0)
    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
  }

  /// Draws `look` over `src` into the bound render target (the ungraded
  /// source when `look` is nil). With `blend`, the result is mixed over the
  /// target by the encoder's blend-colour alpha.
  func drawLook(
    _ look: GpuLook?, src: MTLTexture, width: Int, height: Int, blend: Bool,
    encoder: MTLRenderCommandEncoder
  ) {
    var size = SIMD2<Float>(Float(width), Float(height))
    encoder.setVertexBytes(&size, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
    guard let look else {
      encoder.setRenderPipelineState(blend ? copyBlendPipeline : copyPipeline)
      encoder.setFragmentTexture(src, index: 0)
      encoder.setFragmentSamplerState(linearSampler, index: 0)
      encoder.setFragmentBytes(&size, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
      encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
      return
    }
    encoder.setRenderPipelineState(blend ? lookBlendPipeline : lookPipeline)
    look.data.uniforms.withUnsafeBytes { raw in
      for u in LookEngineShader.uniforms {
        if u.name == "uSize" {
          encoder.setFragmentBytes(&size, length: MemoryLayout<SIMD2<Float>>.stride, index: u.bufferIndex)
        } else {
          encoder.setFragmentBytes(
            raw.baseAddress! + u.offset * MemoryLayout<Float>.stride,
            length: u.components * MemoryLayout<Float>.stride, index: u.bufferIndex)
        }
      }
    }
    encoder.setFragmentTexture(src, index: LookEngineShader.sourceTexture)
    encoder.setFragmentTexture(look.lut, index: LookEngineShader.lutTexture)
    encoder.setFragmentTexture(look.curves, index: LookEngineShader.curvesTexture)
    // LUT/curve lookups address texel centres, so nearest is exact.
    encoder.setFragmentSamplerState(linearSampler, index: LookEngineShader.sourceTexture)
    encoder.setFragmentSamplerState(nearestSampler, index: LookEngineShader.lutTexture)
    encoder.setFragmentSamplerState(nearestSampler, index: LookEngineShader.curvesTexture)
    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
  }

  private func texture(_ pixels: Data, width: Int, height: Int) throws -> MTLTexture {
    let d = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
    d.usage = .shaderRead
    guard let t = device.makeTexture(descriptor: d) else {
      throw SetupError.allocation("texture \(width)x\(height)")
    }
    pixels.withUnsafeBytes { raw in
      t.replace(
        region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: raw.baseAddress!,
        bytesPerRow: width * 4)
    }
    return t
  }
}
