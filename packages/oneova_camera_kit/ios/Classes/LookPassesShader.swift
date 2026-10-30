/// Metal passes around the generated Look shader: the source pass (camera
/// NV12 or an RGB texture, with WebRTC's crop) into an RGB texture, the vertex stage
/// that feeds the Look shader's `_fragCoord`, and a plain copy used when
/// cross-fading to or from the original frame.
enum LookPassesShader {
  static let sourceVertex = "oneova_source_vertex"
  static let sourceNV12 = "oneova_source_nv12"
  static let sourceRGB = "oneova_source_rgb"
  static let lookVertex = "oneova_look_vertex"
  static let copyFragment = "oneova_copy_fragment"

  static let metalSource = #"""
#include <metal_stdlib>
using namespace metal;

// Triangle strip covering the target; uv (0,0) is the top-left texel.
constant float2 kQuad[4] = { float2(0.0, 0.0), float2(1.0, 0.0), float2(0.0, 1.0), float2(1.0, 1.0) };

struct SourceParams {
    float4 crop;    // x, y, width, height in normalised source coordinates
    float4 range;   // luma offset, luma scale, chroma offset, chroma scale
    float4 coeffs;  // Cr→R, Cb→G, Cr→G, Cb→B
};

struct SourceOut {
    float4 position [[position]];
    float2 uv;
};

vertex SourceOut oneova_source_vertex(uint vid [[vertex_id]],
                                      constant SourceParams& p [[buffer(0)]]) {
    float2 q = kQuad[vid];
    SourceOut out;
    out.position = float4(q.x * 2.0 - 1.0, 1.0 - q.y * 2.0, 0.0, 1.0);
    out.uv = p.crop.xy + q * p.crop.zw;
    return out;
}

fragment float4 oneova_source_nv12(SourceOut in [[stage_in]],
                                   texture2d<float> luma [[texture(0)]],
                                   texture2d<float> chroma [[texture(1)]],
                                   sampler s [[sampler(0)]],
                                   constant SourceParams& p [[buffer(0)]]) {
    float y = (luma.sample(s, in.uv).r - p.range.x) * p.range.y;
    float2 c = (chroma.sample(s, in.uv).rg - p.range.z) * p.range.w;
    float3 rgb = float3(y + p.coeffs.x * c.y,
                        y - p.coeffs.y * c.x - p.coeffs.z * c.y,
                        y + p.coeffs.w * c.x);
    return float4(clamp(rgb, 0.0, 1.0), 1.0);
}

fragment float4 oneova_source_rgb(SourceOut in [[stage_in]],
                                   texture2d<float> source [[texture(0)]],
                                   sampler s [[sampler(0)]]) {
    return float4(source.sample(s, in.uv).rgb, 1.0);
}

struct LookVertexOut {
    float4 position [[position]];
    float2 fragCoord [[user(locn0)]];
};

// Pixel centres of the source frame, matching FlutterFragCoord.
vertex LookVertexOut oneova_look_vertex(uint vid [[vertex_id]],
                                        constant float2& size [[buffer(0)]]) {
    float2 q = kQuad[vid];
    LookVertexOut out;
    out.position = float4(q.x * 2.0 - 1.0, 1.0 - q.y * 2.0, 0.0, 1.0);
    out.fragCoord = q * size;
    return out;
}

fragment float4 oneova_copy_fragment(LookVertexOut in [[stage_in]],
                                     texture2d<float> source [[texture(0)]],
                                     sampler s [[sampler(0)]],
                                     constant float2& size [[buffer(0)]]) {
    return float4(source.sample(s, in.fragCoord / size).rgb, 1.0);
}
"""#
}
