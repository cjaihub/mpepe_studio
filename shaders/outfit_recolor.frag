#version 460 core
// Outfit colour (camera preview). Same maths as FRAGMENT_COMPOSITE's
// outfit() in ArGlPipeline.kt, so recordings match the viewfinder:
// inside the person mask, below the neck line, skin tones kept; the
// fabric keeps its own brightness (folds, texture) and takes the hue.
#include <flutter/runtime_effect.glsl>

precision mediump float;

uniform vec2 uSize;
uniform vec4 uColor;   // rgb 0..1, a = strength
uniform float uNeckY;  // 0 top .. 1 bottom
uniform sampler2D uTexture;
uniform sampler2D uMask;

out vec4 fragColor;

vec3 toYcc(vec3 c) {
  float y = dot(c, vec3(0.299, 0.587, 0.114));
  return vec3(y, (c.b - y) * 0.564, (c.r - y) * 0.713);
}

vec3 fromYcc(vec3 q) {
  float r = q.x + 1.403 * q.z;
  float b = q.x + 1.773 * q.y;
  float g = (q.x - 0.299 * r - 0.114 * b) / 0.587;
  return vec3(r, g, b);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 src = texture(uTexture, uv);
  float person = texture(uMask, uv).a;
  float below = smoothstep(uNeckY - 0.02, uNeckY + 0.04, uv.y);
  vec3 s = toYcc(src.rgb);
  float skin = step(-0.2, s.y) * step(s.y, 0.0) * step(0.02, s.z) * step(s.z, 0.18);
  float w = person * below * (1.0 - skin) * uColor.a;
  vec3 t = toYcc(uColor.rgb);
  vec3 rec = clamp(fromYcc(vec3(s.x * 0.7 + t.x * 0.3, t.y, t.z)), 0.0, 1.0);
  fragColor = vec4(mix(src.rgb, rec, w), src.a);
}
