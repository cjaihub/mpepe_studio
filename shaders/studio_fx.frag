#include <flutter/runtime_effect.glsl>

// Oneova Studio effects (preview through ImageFilter.shader). The body below
// is identical to oneova_media_engine StudioFxShader.kt, which bakes the same
// effect into exports. Effect ids are listed in lib/create/studio/services/studio_effects.dart.

uniform vec2 uSize;
uniform float uType;
uniform float uAmount;
uniform float uTime;
uniform float uProgress;
uniform sampler2D uTexture;

out vec4 fragColor;

vec4 fxTex(vec2 p) {
    vec2 q = clamp(p, 0.0, 1.0);
#ifdef IMPELLER_TARGET_OPENGLES
    q.y = 1.0 - q.y;
#endif
    return texture(uTexture, q);
}
#define SAMPLE(p) fxTex(p)

float fxHash(float n) { return fract(sin(n) * 43758.5453123); }
float fxHash2(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float fxLuma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

vec4 fxBlur(vec2 uv, vec2 stepUv) {
    vec4 acc = vec4(0.0);
    for (int i = -2; i <= 2; i++) {
        for (int j = -2; j <= 2; j++) {
            acc += SAMPLE(uv + vec2(float(i), float(j)) * stepUv);
        }
    }
    return acc / 25.0;
}

// uv: 0..1 with (0,0) at the top-left of the frame.
vec4 fxApply(vec2 uv) {
    float a = clamp(uAmount, 0.0, 1.0);
    float t = uTime;
    float k = uType;
    float ar = uSize.x / max(1.0, uSize.y);
    vec4 src = SAMPLE(uv);
    vec3 c = src.rgb;
    if (k < 0.5 || a <= 0.0) return src;
    if (k < 1.5) { // blur
        return fxBlur(uv, vec2(a * 0.006, a * 0.006 * ar));
    }
    if (k < 2.5) { // rgb split
        vec2 off = vec2(a * 0.012 * (0.65 + 0.35 * sin(t * 6.0)), 0.0);
        return vec4(SAMPLE(uv + off).r, c.g, SAMPLE(uv - off).b, src.a);
    }
    if (k < 3.5) { // glitch
        float band = floor(uv.y * 24.0);
        float seed = floor(t * 10.0);
        float n = fxHash(band * 13.1 + seed * 7.7);
        float shift = max(0.0, n - 0.72) * 3.6 * a * 0.12 * (fxHash(band + seed * 3.3) < 0.5 ? -1.0 : 1.0);
        vec2 p = uv + vec2(shift, 0.0);
        float s = a * 0.01;
        return vec4(SAMPLE(p + vec2(s, 0.0)).r, SAMPLE(p).g, SAMPLE(p - vec2(s, 0.0)).b, src.a);
    }
    if (k < 4.5) { // vhs
        float wob = sin(uv.y * 120.0 + t * 8.0) * 0.0015 * a + (fxHash(floor(uv.y * 240.0) + floor(t * 30.0)) - 0.5) * 0.002 * a;
        vec2 p = uv + vec2(wob, 0.0);
        vec3 v = vec3(SAMPLE(p + vec2(0.004 * a, 0.0)).r, SAMPLE(p).g, SAMPLE(p - vec2(0.004 * a, 0.0)).b);
        v = mix(v, vec3(fxLuma(v)), 0.3 * a);
        v *= 1.0 - a * 0.12 * (0.5 + 0.5 * sin(uv.y * 700.0));
        v += (fxHash2(uv * vec2(731.0, 1031.0) + vec2(t, t * 1.3)) - 0.5) * 0.08 * a;
        return vec4(clamp(v, 0.0, 1.0), src.a);
    }
    if (k < 5.5) { // pixelate
        float cells = mix(220.0, 24.0, a);
        vec2 cell = vec2(1.0 / cells, ar / cells);
        return SAMPLE((floor(uv / cell) + 0.5) * cell);
    }
    if (k < 6.5) { // mirror
        return SAMPLE(vec2(uv.x > 0.5 ? 1.0 - uv.x : uv.x, uv.y));
    }
    if (k < 7.5) { // shake
        vec2 off = vec2(sin(t * 47.0) + sin(t * 23.0) * 0.5, cos(t * 39.0) + sin(t * 17.0) * 0.5) * 0.012 * a;
        return SAMPLE((uv - 0.5) / (1.0 + 0.04 * a) + 0.5 + off);
    }
    if (k < 8.5) { // zoom pulse
        float s = 1.0 + a * 0.12 * (0.5 + 0.5 * sin(t * 12.566));
        return SAMPLE((uv - 0.5) / s + 0.5);
    }
    if (k < 9.5) { // flicker
        return vec4(clamp(c * (1.0 + a * 0.35 * (fxHash(floor(t * 18.0)) - 0.5)), 0.0, 1.0), src.a);
    }
    if (k < 10.5) { // light leak
        float pos = fract(t * 0.15);
        float d = uv.x * 0.7 + uv.y * 0.3 - (pos * 1.6 - 0.3);
        vec3 v = c + vec3(1.0, 0.45, 0.15) * exp(-d * d * 18.0) * a * 0.8;
        float d2 = d + 0.35;
        v += vec3(1.0, 0.18, 0.53) * exp(-d2 * d2 * 25.0) * a * 0.5;
        return vec4(clamp(v, 0.0, 1.0), src.a);
    }
    if (k < 11.5) { // posterize
        float lv = mix(24.0, 3.0, a);
        return vec4(floor(c * lv + 0.5) / lv, src.a);
    }
    if (k < 12.5) { // invert
        return vec4(mix(c, 1.0 - c, a), src.a);
    }
    if (k < 13.5) { // duotone (brand blue -> pink)
        vec3 duo = mix(vec3(0.047, 0.31, 0.66), vec3(1.0, 0.176, 0.53), fxLuma(c));
        return vec4(mix(c, duo, a), src.a);
    }
    if (k < 14.5) { // spotlight
        vec2 p = uv - 0.5;
        p.y /= ar;
        float mask = smoothstep(0.55, 0.15, length(p) * ar);
        return vec4(c * mix(1.0 - a * 0.85, 1.0, mask), src.a);
    }
    if (k < 15.5) { // bulge
        vec2 p = uv - 0.5;
        p.y /= ar;
        float r = length(p);
        p *= 1.0 - a * 0.45 * (1.0 - smoothstep(0.0, 0.6, r));
        p.y *= ar;
        return SAMPLE(p + 0.5);
    }
    if (k < 16.5) { // kaleido (four-way mirror)
        return SAMPLE(vec2(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)) * 2.0);
    }
    if (k < 17.5) { // crt
        vec2 p = uv * 2.0 - 1.0;
        p *= 1.0 + a * 0.1 * vec2(p.y * p.y, p.x * p.x);
        vec2 q = p * 0.5 + 0.5;
        if (q.x < 0.0 || q.x > 1.0 || q.y < 0.0 || q.y > 1.0) return vec4(0.0, 0.0, 0.0, src.a);
        vec3 v = SAMPLE(q).rgb;
        v *= mix(1.0, 0.82 + 0.18 * sin(q.y * 900.0), a);
        v *= mix(1.0, smoothstep(1.4, 0.4, length(p)), a);
        return vec4(v, src.a);
    }
    if (k < 18.5) { // sepia
        vec3 s = vec3(dot(c, vec3(0.393, 0.769, 0.189)), dot(c, vec3(0.349, 0.686, 0.168)), dot(c, vec3(0.272, 0.534, 0.131)));
        return vec4(mix(c, clamp(s, 0.0, 1.0), a), src.a);
    }
    if (k < 19.5) { // strobe
        float on = step(0.5, fract(t * 8.0));
        return vec4(clamp(c * mix(1.0, 1.0 + 0.6 * (on * 2.0 - 1.0), a), 0.0, 1.0), src.a);
    }
    if (k < 20.5) { // old film
        float n = (fxHash2(uv * uSize * 0.5 + fract(t * 24.0) * vec2(17.0, 31.0)) - 0.5) * 0.25 * a;
        float f = floor(t * 12.0);
        float line = smoothstep(0.002, 0.0, abs(uv.x - fxHash(f))) * step(0.5, fxHash(f + 3.1)) * a;
        vec3 v = mix(c, vec3(fxLuma(c)) * vec3(1.05, 0.98, 0.86), 0.5 * a) + n + line * 0.4;
        v *= 1.0 + a * 0.12 * (fxHash(f + 9.0) - 0.5);
        return vec4(clamp(v, 0.0, 1.0), src.a);
    }
    if (k < 21.5) { // radial (zoom) blur
        vec2 dir = uv - 0.5;
        vec4 acc = vec4(0.0);
        for (int i = 0; i < 10; i++) {
            acc += SAMPLE(uv - dir * float(i) * a * 0.012);
        }
        return acc / 10.0;
    }
    if (k < 22.5) { // neon edges
        vec2 px = vec2(0.0015, 0.0015 * ar);
        float gx = fxLuma(SAMPLE(uv + vec2(px.x, 0.0)).rgb) - fxLuma(SAMPLE(uv - vec2(px.x, 0.0)).rgb);
        float gy = fxLuma(SAMPLE(uv + vec2(0.0, px.y)).rgb) - fxLuma(SAMPLE(uv - vec2(0.0, px.y)).rgb);
        float e = clamp(length(vec2(gx, gy)) * 6.0, 0.0, 1.0);
        vec3 neon = c * 0.25 + e * mix(vec3(0.2, 0.55, 1.0), vec3(1.0, 0.18, 0.53), uv.y);
        return vec4(mix(c, clamp(neon, 0.0, 1.0), a), src.a);
    }
    if (k < 23.5) { // dreamy glow
        vec3 b = fxBlur(uv, vec2(0.008, 0.008 * ar)).rgb;
        vec3 v = 1.0 - (1.0 - c) * (1.0 - b * 0.6 * a);
        return vec4(clamp(v, 0.0, 1.0), src.a);
    }
    if (k < 24.5) { // black & white
        return vec4(mix(c, vec3(fxLuma(c)), a), src.a);
    }
    if (k < 25.5) { // thermal
        float l = fxLuma(c);
        vec3 h = l < 0.5 ? mix(vec3(0.05, 0.0, 0.4), vec3(0.9, 0.1, 0.3), l * 2.0) : mix(vec3(0.9, 0.1, 0.3), vec3(1.0, 0.95, 0.3), l * 2.0 - 1.0);
        return vec4(mix(c, h, a), src.a);
    }
    if (k < 26.5) { // triple split
        return SAMPLE(vec2(uv.x, fract(uv.y * 3.0) / 3.0 + 1.0 / 3.0));
    }
    if (k < 27.5) { // quad split
        return SAMPLE(vec2(fract(uv.x * 2.0), fract(uv.y * 2.0)));
    }
    if (k < 28.5) { // flash in
        float w = a * (1.0 - smoothstep(0.0, 0.35, uProgress));
        return vec4(mix(c, vec3(1.0), w), src.a);
    }
    if (k < 29.5) { // fade from black
        return vec4(c * mix(1.0, smoothstep(0.0, 0.5, uProgress), a), src.a);
    }
    if (k < 30.5) { // fade to black
        return vec4(c * mix(1.0, 1.0 - smoothstep(0.5, 1.0, uProgress), a), src.a);
    }
    return src;
}

void main() {
    fragColor = fxApply(FlutterFragCoord().xy / uSize);
}
