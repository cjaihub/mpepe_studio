#include <flutter/runtime_effect.glsl>

// Oneova Look engine — single source of truth for Photo, Video, Camera and
// Live previews. Uniform order is mirrored by LookCompiler.bindUniforms;
// every uniform below is used so none is stripped and indices stay stable.

uniform vec2 uSize;
uniform sampler2D uTexture;
uniform float uMasterIntensity;

// Primary tonality
uniform float uExposure;    // -2.0 to 2.0 (EV)
uniform float uContrast;    // 0.5 to 2.0
uniform float uPivot;       // 0.0 to 1.0 (default 0.435)
uniform float uHighlights;  // -1.0 to 1.0
uniform float uShadows;     // -1.0 to 1.0
uniform float uWhites;      // -1.0 to 1.0
uniform float uBlacks;      // -1.0 to 1.0

// Color balance
uniform float uTemperature; // -100 to 100
uniform float uTint;        // -100 to 100
uniform float uVibrance;    // -1.0 to 1.0
uniform float uSaturation;  // 0.0 to 2.0

// Wheels: Lift, Gamma, Gain, Offset (RGB + Lum)
uniform vec4 uLift;
uniform vec4 uGamma;
uniform vec4 uGain;
uniform vec4 uOffset;

// Effects: Film, Optics, Detail
uniform float uGrain;       // 0.0 to 1.0
uniform float uFade;        // 0.0 to 1.0
uniform float uVignette;    // 0.0 to 1.0
uniform float uSharpen;     // 0.0 to 1.0

// LUT stack (pre-composed into one atlas) and tone curves
uniform float uLutSize;         // N of the N³ atlas (identity atlas uses 2)
uniform float uLutIntensity;    // 0.0 to 1.0
uniform float uCurvesIntensity; // 0.0 (neutral curves) or 1.0

// HSL mixer: A = red, orange, yellow, green · B = aqua, blue, purple, magenta
uniform vec4 uHslHueA;  // degrees
uniform vec4 uHslHueB;
uniform vec4 uHslSatA;  // -1.0 to 1.0
uniform vec4 uHslSatB;
uniform vec4 uHslLumA;  // -1.0 to 1.0
uniform vec4 uHslLumB;

uniform sampler2D uLut;     // width N², height N; x = b·N + r, y = g
uniform sampler2D uCurves;  // 256×2; row 0 = R,G,B curves, row 1 = master

out vec4 fragColor;

float getLuminance(vec3 color) {
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec3 rgb2hsl(vec3 c) {
    float mx = max(c.r, max(c.g, c.b));
    float mn = min(c.r, min(c.g, c.b));
    float l = (mx + mn) * 0.5;
    float d = mx - mn;
    if (d < 1e-5) return vec3(0.0, 0.0, l);
    float s = d / max(1e-5, 1.0 - abs(2.0 * l - 1.0));
    float h;
    if (mx == c.r) {
        h = mod((c.g - c.b) / d, 6.0);
    } else if (mx == c.g) {
        h = (c.b - c.r) / d + 2.0;
    } else {
        h = (c.r - c.g) / d + 4.0;
    }
    return vec3(h * 60.0, s, l);
}

float hue2rgb(float p, float q, float t) {
    t = fract(t);
    if (t < 1.0 / 6.0) return p + (q - p) * 6.0 * t;
    if (t < 0.5) return q;
    if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
    return p;
}

vec3 hsl2rgb(vec3 hsl) {
    float h = hsl.x / 360.0;
    float s = hsl.y;
    float l = hsl.z;
    if (s < 1e-5) return vec3(l);
    float q = l < 0.5 ? l * (1.0 + s) : l + s - l * s;
    float p = 2.0 * l - q;
    return vec3(hue2rgb(p, q, h + 1.0 / 3.0), hue2rgb(p, q, h), hue2rgb(p, q, h - 1.0 / 3.0));
}

// Triangular weight of a hue band centred at c, reaching 0 at the
// neighbouring band centres (l degrees to the left, r to the right).
float bandWeight(float h, float c, float l, float r) {
    float d = mod(h - c + 540.0, 360.0) - 180.0;
    return d < 0.0 ? max(0.0, 1.0 + d / l) : max(0.0, 1.0 - d / r);
}

vec3 lutTexel(float r, float g, float b) {
    float n = uLutSize;
    vec2 uv = vec2((b * n + r + 0.5) / (n * n), (g + 0.5) / n);
    return texture(uLut, uv).rgb;
}

vec3 applyLut(vec3 color) {
    float m = uLutSize - 1.0;
    vec3 c = clamp(color, 0.0, 1.0) * m;
    vec3 c0 = floor(c);
    vec3 c1 = min(c0 + 1.0, vec3(m));
    vec3 f = c - c0;
    vec3 x00 = mix(lutTexel(c0.r, c0.g, c0.b), lutTexel(c1.r, c0.g, c0.b), f.r);
    vec3 x10 = mix(lutTexel(c0.r, c1.g, c0.b), lutTexel(c1.r, c1.g, c0.b), f.r);
    vec3 x01 = mix(lutTexel(c0.r, c0.g, c1.b), lutTexel(c1.r, c0.g, c1.b), f.r);
    vec3 x11 = mix(lutTexel(c0.r, c1.g, c1.b), lutTexel(c1.r, c1.g, c1.b), f.r);
    return mix(mix(x00, x10, f.g), mix(x01, x11, f.g), f.b);
}

vec4 curveTexel(float v, float row) {
    float x = clamp(v, 0.0, 1.0) * 255.0;
    float i0 = floor(x);
    float i1 = min(i0 + 1.0, 255.0);
    vec4 a = texture(uCurves, vec2((i0 + 0.5) / 256.0, (row + 0.5) / 2.0));
    vec4 b = texture(uCurves, vec2((i1 + 0.5) / 256.0, (row + 0.5) / 2.0));
    return mix(a, b, x - i0);
}

vec3 applyCurves(vec3 c) {
    vec3 m = vec3(curveTexel(c.r, 1.0).r, curveTexel(c.g, 1.0).r, curveTexel(c.b, 1.0).r);
    return vec3(curveTexel(m.r, 0.0).r, curveTexel(m.g, 0.0).g, curveTexel(m.b, 0.0).b);
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    vec4 baseTex = texture(uTexture, uv);
    vec3 color = baseTex.rgb;

    // 0. Detail: unsharp mask against the 4-neighbour average.
    vec2 px = 1.0 / uSize;
    vec3 blur = (texture(uTexture, uv + vec2(px.x, 0.0)).rgb +
                 texture(uTexture, uv - vec2(px.x, 0.0)).rgb +
                 texture(uTexture, uv + vec2(0.0, px.y)).rgb +
                 texture(uTexture, uv - vec2(0.0, px.y)).rgb) * 0.25;
    color += (color - blur) * uSharpen * 1.5;

    // 1. Exposure (photographic EV stops)
    color *= exp2(uExposure);

    // 2. White balance
    color.r += uTemperature * 0.002;
    color.b -= uTemperature * 0.002;
    color.g -= uTint * 0.002;
    color = max(vec3(0.0), color);

    // 3. Contrast around the pivot
    color = (color - vec3(uPivot)) * uContrast + vec3(uPivot);

    // 4. Highlights and shadows roll-off
    float lum = getLuminance(color);
    float shadowMask = clamp(1.0 - lum / 0.5, 0.0, 1.0);
    float highlightMask = clamp((lum - 0.5) / 0.5, 0.0, 1.0);
    color += color * (uShadows * shadowMask * 0.5);
    color += color * (uHighlights * highlightMask * 0.5);

    // 5. Lift / Gain / Gamma / Offset (lum component applies to all channels)
    color += (uLift.rgb + vec3(uLift.a)) * (1.0 - clamp(lum, 0.0, 1.0));
    color *= vec3(1.0) + uGain.rgb + vec3(uGain.a);
    vec3 gammaPow = vec3(1.0) / max(vec3(0.01), vec3(1.0) + uGamma.rgb + vec3(uGamma.a));
    color = pow(max(vec3(0.0), color), gammaPow);
    color += uOffset.rgb + vec3(uOffset.a);

    // 6. Whites and blacks: stretch the ends of the tonal range only
    float l6 = clamp(getLuminance(color), 0.0, 1.0);
    color += vec3(uBlacks * 0.15) * pow(1.0 - l6, 3.0);
    color += vec3(uWhites * 0.15) * pow(l6, 3.0);

    // 7. Tone curves (master, then per channel)
    color = mix(color, applyCurves(clamp(color, 0.0, 1.0)), uCurvesIntensity);

    // 8. HSL mixer, scaled by chroma so neutral grays never shift
    vec3 hsl = rgb2hsl(clamp(color, 0.0, 1.0));
    float h = hsl.x;
    vec4 wA = vec4(bandWeight(h, 0.0, 60.0, 30.0),
                   bandWeight(h, 30.0, 30.0, 30.0),
                   bandWeight(h, 60.0, 30.0, 60.0),
                   bandWeight(h, 120.0, 60.0, 60.0));
    vec4 wB = vec4(bandWeight(h, 180.0, 60.0, 60.0),
                   bandWeight(h, 240.0, 60.0, 30.0),
                   bandWeight(h, 270.0, 30.0, 30.0),
                   bandWeight(h, 300.0, 30.0, 60.0));
    float hueShift = dot(wA, uHslHueA) + dot(wB, uHslHueB);
    float satShift = dot(wA, uHslSatA) + dot(wB, uHslSatB);
    float lumShift = dot(wA, uHslLumA) + dot(wB, uHslLumB);
    float chroma = hsl.y;
    vec3 shifted = vec3(mod(h + hueShift + 360.0, 360.0),
                        clamp(hsl.y * (1.0 + satShift), 0.0, 1.0),
                        clamp(hsl.z + lumShift * 0.25 * chroma, 0.0, 1.0));
    float hslActive = step(1e-4, abs(hueShift) + abs(satShift) + abs(lumShift));
    color = mix(color, hsl2rgb(shifted), hslActive);

    // 9. Saturation and vibrance
    float newLum = getLuminance(color);
    color = mix(vec3(newLum), color, uSaturation);
    float maxChannel = max(color.r, max(color.g, color.b));
    float minChannel = min(color.r, min(color.g, color.b));
    float currentSat = (maxChannel - minChannel) / max(0.001, maxChannel);
    color = mix(vec3(newLum), color, 1.0 + uVibrance * (1.0 - currentSat));

    // 10. LUT stack
    color = mix(color, applyLut(color), uLutIntensity);

    // 11. Film fade (lifted black floor)
    color = mix(color, vec3(1.0), uFade * 0.1) + vec3(uFade * 0.05);

    // 12. Vignette (strength fades in from 0, no jump at small values)
    vec2 centerUV = uv - vec2(0.5);
    float dist = length(centerUV * vec2(1.0, uSize.y / uSize.x));
    float vignetteMask = smoothstep(0.8, 0.2, dist * (1.0 + uVignette));
    color *= mix(1.0, vignetteMask, uVignette);

    // 13. Film grain, strongest in midtones
    float noiseVal = (hash(uv * uSize) - 0.5) * 2.0;
    float grainWeight = 1.0 - abs(newLum - 0.5) * 2.0;
    color += vec3(noiseVal * uGrain * 0.12 * grainWeight);

    vec3 finalColor = mix(baseTex.rgb, clamp(color, 0.0, 1.0), uMasterIntensity);
    fragColor = vec4(finalColor, baseTex.a);
}
