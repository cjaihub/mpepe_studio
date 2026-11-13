#version 460 core
// Person cut-out for the camera preview: the segmentation mask refined to
// the camera image (edge-aware), so hair and fingers keep clean edges.
// Same maths as matte() in ArGlPipeline.kt's FRAGMENT_COMPOSITE.
#include <flutter/runtime_effect.glsl>

precision mediump float;

uniform vec2 uSize;
uniform vec2 uMaskTexel;
uniform sampler2D uTexture;
uniform sampler2D uMask;

out vec4 fragColor;

void main() {
  vec2 p = FlutterFragCoord().xy / uSize;
  vec4 c0 = texture(uTexture, p);
  float a = texture(uMask, p).a;
  if (a > 0.02 && a < 0.98) {
    float sum = a;
    float wsum = 1.0;
    for (int i = 0; i < 8; i++) {
      float ang = float(i) * 0.785398;
      vec2 o = vec2(cos(ang), sin(ang)) * uMaskTexel * 1.6;
      vec3 d = texture(uTexture, p + o).rgb - c0.rgb;
      float w = exp(-dot(d, d) * 40.0);
      sum += texture(uMask, p + o).a * w;
      wsum += w;
    }
    a = smoothstep(0.08, 0.92, sum / wsum);
  }
  fragColor = vec4(c0.rgb * a, a);
}
