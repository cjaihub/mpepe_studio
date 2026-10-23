#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uTime;
uniform vec2 uPointer;
uniform float uPointerActive;

out vec4 fragColor;

float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898,78.233))) * 43758.5453123);
}

float noise(vec2 st) {
    vec2 i = floor(st);
    vec2 f = fract(st);
    float a = random(i);
    float b = random(i + vec2(1.0, 0.0));
    float c = random(i + vec2(0.0, 1.0));
    float d = random(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

#define OCTAVES 5
float fbm(vec2 st) {
    float value = 0.0;
    float amplitude = 0.5;
    vec2 shift = vec2(100.0);
    mat2 rot = mat2(cos(0.5), sin(0.5), -sin(0.5), cos(0.50));
    for (int i = 0; i < OCTAVES; i++) {
        value += amplitude * noise(st);
        st = rot * st * 2.0 + shift;
        amplitude *= 0.5;
    }
    return value;
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    vec2 pos = FlutterFragCoord().xy;
    
    vec2 p = uv * 2.0 - 1.0;
    p.x *= uSize.x / uSize.y;

    float dist = distance(pos, uPointer);
    float maxDist = min(uSize.x, uSize.y) * 0.8;
    float pointerInfluence = 1.0 - clamp(dist / maxDist, 0.0, 1.0);
    
    // Zooming feature: pull UVs towards the pointer when touched
    vec2 uvPointer = uPointer / uSize;
    vec2 pPointer = uvPointer * 2.0 - 1.0;
    pPointer.x *= uSize.x / uSize.y;
    vec2 dirFromPointer = p - pPointer;
    p -= dirFromPointer * pointerInfluence * uPointerActive * 0.25;

    // Domain warping
    vec2 q = vec2(0.);
    q.x = fbm(p + 0.00 * uTime);
    q.y = fbm(p + vec2(1.0));

    vec2 r = vec2(0.);
    r.x = fbm(p + 1.0 * q + vec2(1.7,9.2) + 0.15 * uTime);
    r.y = fbm(p + 1.0 * q + vec2(8.3,2.8) + 0.126 * uTime);
    
    // Extreme turbulence during touch
    if (uPointerActive > 0.0) {
        vec2 dir = normalize(pos - uPointer);
        r += dir * pointerInfluence * uPointerActive * 1.5;
    }

    float f = fbm(p + r);

    // When inactive, we output fully transparent
    if (uPointerActive <= 0.001) {
        fragColor = vec4(0.0);
        return;
    }

    // Active Colors (Premium Red and White)
    vec3 activeMid = vec3(0.6, 0.0, 0.0); 
    vec3 activeHigh = vec3(1.0, 0.2, 0.2);

    vec3 fluidColor = mix(activeMid * 0.2, activeMid, clamp((f * f) * 4.0, 0.0, 1.0));
    fluidColor = mix(fluidColor, activeHigh, clamp(length(q), 0.0, 1.0));
    fluidColor = mix(fluidColor, vec3(1.0), clamp(length(r.x), 0.0, 1.0));
    
    float intensity = (f * f * f + 0.6 * f * f + 0.5 * f);
    fluidColor *= intensity;

    vec3 color = fluidColor * uPointerActive;
    
    // Premium glowing core under the finger
    float glowRadius = exp(-dist * 0.006) * uPointerActive;
    vec3 coreGlow = mix(activeMid, vec3(1.0), glowRadius);
    
    // Dynamic ripple
    float ripple = sin(dist * 0.06 - uTime * 8.0) * 0.5 + 0.5;
    color += coreGlow * glowRadius * 1.5 + (activeMid * ripple * glowRadius);
    
    color = smoothstep(0.0, 1.0, color);
    float vignette = length(p);
    color *= 1.0 - (vignette * vignette * 0.2);

    // Compute alpha based on overall intensity and activity so it blends seamlessly
    float alpha = clamp((intensity + glowRadius * 2.0) * uPointerActive, 0.0, 1.0);
    
    // Output with transparency so the trackpad base color shows through when fluid is thin
    fragColor = vec4(color * alpha, alpha);
}
