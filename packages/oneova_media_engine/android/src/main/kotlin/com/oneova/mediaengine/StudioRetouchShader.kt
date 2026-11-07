// Oneova Studio face & skin retouch, GLSL ES 1.00 for Media3. rtApply is
// identical to shaders/studio_retouch.frag (the preview).
package com.oneova.mediaengine

internal object StudioRetouchShader {
    val UNIFORMS = arrayOf("uP0", "uP1", "uP2", "uFA0", "uFA1", "uFA2", "uFA3", "uFB0", "uFB1", "uFB2", "uFB3")

    val FRAGMENT = """
precision highp float;
uniform highp vec2 uSize;
uniform vec4 uP0;
uniform vec4 uP1;
uniform vec4 uP2;
uniform vec4 uFA0;
uniform vec4 uFA1;
uniform vec4 uFA2;
uniform vec4 uFA3;
uniform vec4 uFB0;
uniform vec4 uFB1;
uniform vec4 uFB2;
uniform vec4 uFB3;
uniform sampler2D uTexture;
varying highp vec2 _fragCoord;

vec4 rtTex(vec2 p) {
    vec2 q = clamp(p, 0.0, 1.0);
    return texture2D(uTexture, vec2(q.x, 1.0 - q.y));
}
#define SAMPLE(p) rtTex(p)

// Face record (4 vec4): [valid, cx, cy, rx] [ry, lex, ley, rex] [rey, nx, ny, mx] [my, mw, 0, 0]
// All positions in 0..1 of the frame, (0,0) top-left.
float rtLuma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

float rtSkin(vec3 c) {
    float y = rtLuma(c);
    float cb = 0.5 + (-0.168736 * c.r - 0.331264 * c.g + 0.5 * c.b);
    float cr = 0.5 + (0.5 * c.r - 0.418688 * c.g - 0.081312 * c.b);
    float m = smoothstep(0.25, 0.31, cb) * (1.0 - smoothstep(0.50, 0.56, cb));
    m *= smoothstep(0.50, 0.53, cr) * (1.0 - smoothstep(0.68, 0.72, cr));
    return m * smoothstep(0.06, 0.16, y);
}

// Pixel-space vector (x scaled by aspect so circles stay round).
vec2 rtPx(vec2 d) { return vec2(d.x * uSize.x / uSize.y, d.y); }

float rtEllipse(vec2 p, vec2 c, vec2 r) {
    vec2 q = (p - c) / max(r, vec2(0.0001));
    return dot(q, q);
}

vec2 rtWarpFace(vec2 p, vec4 f0, vec4 f1, vec4 f2, vec4 f3) {
    if (f0.x < 0.5) return p;
    vec2 c = vec2(f0.y, f0.z);
    vec2 r = vec2(f0.w, f1.x);
    vec2 le = vec2(f1.y, f1.z);
    vec2 re = vec2(f1.w, f2.x);
    vec2 nose = vec2(f2.y, f2.z);
    vec2 mouth = vec2(f2.w, f3.x);
    float eyeDist = length(rtPx(re - le));
    // Slim: pull the lower face in toward the centre line.
    float slim = uP1.z;
    if (slim > 0.0) {
        float d = rtEllipse(p, c + vec2(0.0, r.y * 0.15), r * vec2(1.35, 1.1));
        if (d < 1.0) {
            float lower = smoothstep(c.y - r.y * 0.2, c.y + r.y * 0.3, p.y);
            float w = (1.0 - d) * lower;
            p.x = c.x + (p.x - c.x) * (1.0 + slim * 0.14 * w);
        }
    }
    // Bigger eyes: magnify around each eye.
    float big = uP1.w;
    if (big > 0.0 && eyeDist > 0.0) {
        float re2 = eyeDist * 0.36;
        vec2 dl = rtPx(p - le);
        float wl = 1.0 - clamp(dot(dl, dl) / (re2 * re2), 0.0, 1.0);
        p = le + (p - le) * (1.0 - big * 0.28 * wl);
        vec2 dr = rtPx(p - re);
        float wr = 1.0 - clamp(dot(dr, dr) / (re2 * re2), 0.0, 1.0);
        p = re + (p - re) * (1.0 - big * 0.28 * wr);
    }
    // Slimmer nose.
    float ns = uP2.x;
    if (ns > 0.0 && eyeDist > 0.0) {
        vec2 dn = rtPx(p - nose);
        float rn = eyeDist * 0.42;
        float wn = 1.0 - clamp(dot(dn, dn) / (rn * rn), 0.0, 1.0);
        p.x = nose.x + (p.x - nose.x) * (1.0 + ns * 0.22 * wn);
    }
    // Chin length (positive = longer).
    float chin = uP2.y;
    if (chin != 0.0) {
        float bottom = c.y + r.y;
        if (p.y > mouth.y && p.y < bottom + r.y * 0.3) {
            float w = smoothstep(0.0, 1.0, 1.0 - abs(p.x - c.x) / max(0.0001, r.x)) ;
            float k = clamp((p.y - mouth.y) / max(0.0001, bottom - mouth.y), 0.0, 1.0);
            p.y = p.y - chin * 0.06 * r.y * w * sin(k * 3.14159);
        }
    }
    return p;
}

float rtEyeMask(vec2 p, vec4 f0, vec4 f1, vec4 f2) {
    if (f0.x < 0.5) return 0.0;
    vec2 le = vec2(f1.y, f1.z);
    vec2 re = vec2(f1.w, f2.x);
    float ed = length(rtPx(re - le));
    float r = ed * 0.22;
    vec2 a = rtPx(p - le);
    vec2 b = rtPx(p - re);
    return max(1.0 - smoothstep(r * 0.5, r, length(a)), 1.0 - smoothstep(r * 0.5, r, length(b)));
}

float rtMouthMask(vec2 p, vec4 f0, vec4 f2, vec4 f3) {
    if (f0.x < 0.5) return 0.0;
    vec2 m = vec2(f2.w, f3.x - f0.w * 0.08);
    float d = rtEllipse(p, m, vec2(max(0.0001, f3.y), f0.w * 0.22));
    return 1.0 - smoothstep(0.6, 1.0, d);
}

float rtFaceMask(vec2 p, vec4 f0, vec4 f1) {
    if (f0.x < 0.5) return 0.0;
    return 1.0 - smoothstep(0.8, 1.15, rtEllipse(p, vec2(f0.y, f0.z), vec2(f0.w, f1.x) * 1.15));
}

vec4 rtApply(vec2 uv) {
    vec2 p = rtWarpFace(uv, uFA0, uFA1, uFA2, uFA3);
    p = rtWarpFace(p, uFB0, uFB1, uFB2, uFB3);
    vec4 src = SAMPLE(p);
    vec3 c = src.rgb;
    float soft = uP0.x, even = uP0.y, bright = uP0.z, warm = uP0.w;
    float eyes = uP1.x, teeth = uP1.y;
    float hasFace = max(uFA0.x, uFB0.x);
    float face = max(rtFaceMask(p, uFA0, uFA1), rtFaceMask(p, uFB0, uFB1));
    // With faces found, retouch stays on them; without, on any skin.
    float zone = hasFace > 0.5 ? face : 1.0;
    float skin = rtSkin(c) * zone;
    if (soft > 0.0 || even > 0.0) {
        vec2 st = vec2(0.0022, 0.0022 * uSize.x / max(1.0, uSize.y)) * (1.0 + soft);
        vec3 acc = vec3(0.0);
        float wsum = 0.0;
        vec3 wide = vec3(0.0);
        for (int i = -2; i <= 2; i++) {
            for (int j = -2; j <= 2; j++) {
                vec3 s = SAMPLE(p + vec2(float(i), float(j)) * st).rgb;
                vec3 dc = s - c;
                float w = exp(-dot(dc, dc) * 60.0);
                acc += s * w;
                wsum += w;
                wide += s;
            }
        }
        vec3 bil = acc / max(wsum, 0.0001);
        wide /= 25.0;
        c = mix(c, bil, clamp(soft * 1.1, 0.0, 1.0) * skin);
        // Even tone: keep the pixel's brightness, take the neighbourhood's colour.
        vec3 toned = wide + (rtLuma(c) - rtLuma(wide));
        c = mix(c, toned, even * 0.8 * skin);
    }
    if (bright != 0.0) c += bright * 0.12 * skin * (1.0 - rtLuma(c));
    if (warm != 0.0) c += vec3(warm * 0.045, warm * 0.012, -warm * 0.045) * skin;
    if (eyes > 0.0) {
        float em = max(rtEyeMask(p, uFA0, uFA1, uFA2), rtEyeMask(p, uFB0, uFB1, uFB2));
        vec3 pop = (c - 0.5) * 1.18 + 0.5 + 0.04;
        c = mix(c, pop, eyes * em);
    }
    if (teeth > 0.0) {
        float mm = max(rtMouthMask(p, uFA0, uFA2, uFA3), rtMouthMask(p, uFB0, uFB2, uFB3));
        float l = rtLuma(c);
        float mx = max(c.r, max(c.g, c.b));
        float sat = (mx - min(c.r, min(c.g, c.b))) / max(mx, 0.001);
        float tm = mm * smoothstep(0.35, 0.55, l) * (1.0 - smoothstep(0.25, 0.45, sat));
        vec3 white = mix(vec3(l), c, 0.35) * 1.08 + 0.02;
        c = mix(c, white, teeth * tm);
    }
    return vec4(clamp(c, 0.0, 1.0), src.a);
}

void main() {
    vec2 uv = _fragCoord / uSize;
    gl_FragColor = rtApply(vec2(uv.x, 1.0 - uv.y));
}
"""
}
