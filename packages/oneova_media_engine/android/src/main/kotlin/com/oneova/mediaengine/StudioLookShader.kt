// Derived from packages/oneova_camera_kit LookEngineShader.kt (generated from
// shaders/look_engine.frag, hash 8dccdcaf54101990) and rewritten to GLSL ES 1.00 so it
// runs in Media3's SDR (OpenGL ES 2) frame processor. Same math as the Flutter
// preview (`shaders/studio_look.frag`).
package com.oneova.mediaengine

internal object StudioLookShader {
    const val SOURCE_HASH = "8dccdcaf54101990"
    const val FLOAT_COUNT = 61

    class Uniform(val name: String, val offset: Int, val components: Int)

    val UNIFORMS = arrayOf(
        Uniform("uSize", 0, 2),
        Uniform("uMasterIntensity", 2, 1),
        Uniform("uExposure", 3, 1),
        Uniform("uContrast", 4, 1),
        Uniform("uPivot", 5, 1),
        Uniform("uHighlights", 6, 1),
        Uniform("uShadows", 7, 1),
        Uniform("uWhites", 8, 1),
        Uniform("uBlacks", 9, 1),
        Uniform("uTemperature", 10, 1),
        Uniform("uTint", 11, 1),
        Uniform("uVibrance", 12, 1),
        Uniform("uSaturation", 13, 1),
        Uniform("uLift", 14, 4),
        Uniform("uGamma", 18, 4),
        Uniform("uGain", 22, 4),
        Uniform("uOffset", 26, 4),
        Uniform("uGrain", 30, 1),
        Uniform("uFade", 31, 1),
        Uniform("uVignette", 32, 1),
        Uniform("uSharpen", 33, 1),
        Uniform("uLutSize", 34, 1),
        Uniform("uLutIntensity", 35, 1),
        Uniform("uCurvesIntensity", 36, 1),
        Uniform("uHslHueA", 37, 4),
        Uniform("uHslHueB", 41, 4),
        Uniform("uHslSatA", 45, 4),
        Uniform("uHslSatB", 49, 4),
        Uniform("uHslLumA", 53, 4),
        Uniform("uHslLumB", 57, 4),
    )

    const val VERTEX = """
attribute vec4 aFramePosition;
uniform highp vec2 uSize;
varying highp vec2 _fragCoord;
void main() {
    gl_Position = aFramePosition;
    _fragCoord = (aFramePosition.xy * 0.5 + 0.5) * uSize;
}
"""

    val FRAGMENT = """
precision highp float;

uniform highp float uLutSize;
uniform sampler2D uLut;
uniform sampler2D uCurves;
uniform highp vec2 uSize;
uniform sampler2D uTexture;
uniform highp float uSharpen;
uniform highp float uExposure;
uniform highp float uTemperature;
uniform highp float uTint;
uniform highp float uPivot;
uniform highp float uContrast;
uniform highp float uShadows;
uniform highp float uHighlights;
uniform highp vec4 uLift;
uniform highp vec4 uGain;
uniform highp vec4 uGamma;
uniform highp vec4 uOffset;
uniform highp float uBlacks;
uniform highp float uWhites;
uniform highp float uCurvesIntensity;
uniform highp vec4 uHslHueA;
uniform highp vec4 uHslHueB;
uniform highp vec4 uHslSatA;
uniform highp vec4 uHslSatB;
uniform highp vec4 uHslLumA;
uniform highp vec4 uHslLumB;
uniform highp float uSaturation;
uniform highp float uVibrance;
uniform highp float uLutIntensity;
uniform highp float uFade;
uniform highp float uVignette;
uniform highp float uGrain;
uniform highp float uMasterIntensity;

varying highp vec2 _fragCoord;

void main()
{
    highp vec2 _604 = _fragCoord / uSize;
    highp vec4 _609 = texture2D(uTexture, _604);
    highp vec3 _612 = _609.xyz;
    highp vec2 _616 = vec2(1.0) / uSize;
    highp vec2 _622 = vec2(_616.x, 0.0);
    highp vec2 _639 = vec2(0.0, _616.y);
    highp vec3 _669 = (_612 + (((_612 - ((((texture2D(uTexture, _604 + _622).xyz + texture2D(uTexture, _604 - _622).xyz) + texture2D(uTexture, _604 + _639).xyz) + texture2D(uTexture, _604 - _639).xyz) * 0.25)) * uSharpen) * 1.5)) * exp2(uExposure);
    highp float _673 = uTemperature * 0.00200000009499490261077880859375;
    highp vec3 _697 = vec3(uPivot);
    highp vec3 _704 = ((max(vec3(0.0), vec3(_669.x + _673, _669.y - (uTint * 0.00200000009499490261077880859375), _669.z - _673)) - _697) * uContrast) + _697;
    highp float _1130 = dot(_704, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    highp vec3 _727 = _704 + (_704 * ((uShadows * clamp(1.0 - (_1130 * 2.0), 0.0, 1.0)) * 0.5));
    highp vec3 _788 = pow(max(vec3(0.0), ((_727 + (_727 * ((uHighlights * clamp((_1130 - 0.5) * 2.0, 0.0, 1.0)) * 0.5))) + ((uLift.xyz + vec3(uLift.w)) * (1.0 - clamp(_1130, 0.0, 1.0)))) * ((vec3(1.0) + uGain.xyz) + vec3(uGain.w))), vec3(1.0) / max(vec3(0.00999999977648258209228515625), (vec3(1.0) + uGamma.xyz) + vec3(uGamma.w))) + (uOffset.xyz + vec3(uOffset.w));
    highp float _793 = clamp(dot(_788, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875)), 0.0, 1.0);
    highp vec3 _814 = (_788 + (vec3(uBlacks * 0.1500000059604644775390625) * pow(1.0 - _793, 3.0))) + (vec3(uWhites * 0.1500000059604644775390625) * pow(_793, 3.0));
    highp vec3 _819 = clamp(_814, vec3(0.0), vec3(1.0));
    highp float _1185 = clamp(_819.x, 0.0, 1.0) * 255.0;
    highp float _1187 = floor(_1185);
    highp float _1225 = clamp(_819.y, 0.0, 1.0) * 255.0;
    highp float _1227 = floor(_1225);
    highp float _1265 = clamp(_819.z, 0.0, 1.0) * 255.0;
    highp float _1267 = floor(_1265);
    highp float _1305 = clamp(mix(texture2D(uCurves, vec2((_1187 + 0.5) * 0.00390625, 0.75)), texture2D(uCurves, vec2((min(_1187 + 1.0, 255.0) + 0.5) * 0.00390625, 0.75)), vec4(_1185 - _1187)).x, 0.0, 1.0) * 255.0;
    highp float _1307 = floor(_1305);
    highp float _1345 = clamp(mix(texture2D(uCurves, vec2((_1227 + 0.5) * 0.00390625, 0.75)), texture2D(uCurves, vec2((min(_1227 + 1.0, 255.0) + 0.5) * 0.00390625, 0.75)), vec4(_1225 - _1227)).x, 0.0, 1.0) * 255.0;
    highp float _1347 = floor(_1345);
    highp float _1385 = clamp(mix(texture2D(uCurves, vec2((_1267 + 0.5) * 0.00390625, 0.75)), texture2D(uCurves, vec2((min(_1267 + 1.0, 255.0) + 0.5) * 0.00390625, 0.75)), vec4(_1265 - _1267)).x, 0.0, 1.0) * 255.0;
    highp float _1387 = floor(_1385);
    highp vec3 _825 = mix(_814, vec3(mix(texture2D(uCurves, vec2((_1307 + 0.5) * 0.00390625, 0.25)), texture2D(uCurves, vec2((min(_1307 + 1.0, 255.0) + 0.5) * 0.00390625, 0.25)), vec4(_1305 - _1307)).x, mix(texture2D(uCurves, vec2((_1347 + 0.5) * 0.00390625, 0.25)), texture2D(uCurves, vec2((min(_1347 + 1.0, 255.0) + 0.5) * 0.00390625, 0.25)), vec4(_1345 - _1347)).y, mix(texture2D(uCurves, vec2((_1387 + 0.5) * 0.00390625, 0.25)), texture2D(uCurves, vec2((min(_1387 + 1.0, 255.0) + 0.5) * 0.00390625, 0.25)), vec4(_1385 - _1387)).z), vec3(uCurvesIntensity));
    highp vec3 _830 = clamp(_825, vec3(0.0), vec3(1.0));
    highp vec3 _2354 = vec3(0.0);
    for (int _once = 0; _once < 1; _once++)
    {
        highp float _1428 = _830.x;
        highp float _1430 = _830.y;
        highp float _1432 = _830.z;
        highp float _1434 = max(_1428, max(_1430, _1432));
        highp float _1442 = min(_1428, min(_1430, _1432));
        highp float _1445 = _1434 + _1442;
        highp float _1446 = _1445 * 0.5;
        highp float _1449 = _1434 - _1442;
        if (_1449 < 9.9999997473787516355514526367188e-06)
        {
            _2354 = vec3(0.0, 0.0, _1446);
            break;
        }
        highp float _2352 = 0.0;
        if (_1434 == _1428)
        {
            _2352 = mod((_1430 - _1432) / _1449, 6.0);
        }
        else
        {
            highp float _2353 = 0.0;
            if (_1434 == _1430)
            {
                _2353 = ((_1432 - _1428) / _1449) + 2.0;
            }
            else
            {
                _2353 = ((_1428 - _1430) / _1449) + 4.0;
            }
            _2352 = _2353;
        }
        _2354 = vec3(_2352 * 60.0, _1449 / max(9.9999997473787516355514526367188e-06, 1.0 - abs(_1445 - 1.0)), _1446);
        break;
    }
    highp float _1518 = mod(_2354.x + 540.0, 360.0) - 180.0;
    highp float _2355 = 0.0;
    if (_1518 < 0.0)
    {
        _2355 = max(0.0, 1.0 + (_1518 * 0.01666666753590106964111328125));
    }
    else
    {
        _2355 = max(0.0, 1.0 - (_1518 * 0.0333333350718021392822265625));
    }
    highp float _1544 = mod(_2354.x + 510.0, 360.0) - 180.0;
    highp float _2356 = 0.0;
    if (_1544 < 0.0)
    {
        _2356 = max(0.0, 1.0 + (_1544 * 0.0333333350718021392822265625));
    }
    else
    {
        _2356 = max(0.0, 1.0 - (_1544 * 0.0333333350718021392822265625));
    }
    highp float _1570 = mod(_2354.x + 480.0, 360.0) - 180.0;
    highp float _2357 = 0.0;
    if (_1570 < 0.0)
    {
        _2357 = max(0.0, 1.0 + (_1570 * 0.0333333350718021392822265625));
    }
    else
    {
        _2357 = max(0.0, 1.0 - (_1570 * 0.01666666753590106964111328125));
    }
    highp float _1596 = mod(_2354.x + 420.0, 360.0) - 180.0;
    highp float _2358 = 0.0;
    if (_1596 < 0.0)
    {
        _2358 = max(0.0, 1.0 + (_1596 * 0.01666666753590106964111328125));
    }
    else
    {
        _2358 = max(0.0, 1.0 - (_1596 * 0.01666666753590106964111328125));
    }
    highp vec4 _863 = vec4(_2355, _2356, _2357, _2358);
    highp float _1622 = mod(_2354.x + 360.0, 360.0) - 180.0;
    highp float _2359 = 0.0;
    if (_1622 < 0.0)
    {
        _2359 = max(0.0, 1.0 + (_1622 * 0.01666666753590106964111328125));
    }
    else
    {
        _2359 = max(0.0, 1.0 - (_1622 * 0.01666666753590106964111328125));
    }
    highp float _1648 = mod(_2354.x + 300.0, 360.0) - 180.0;
    highp float _2360 = 0.0;
    if (_1648 < 0.0)
    {
        _2360 = max(0.0, 1.0 + (_1648 * 0.01666666753590106964111328125));
    }
    else
    {
        _2360 = max(0.0, 1.0 - (_1648 * 0.0333333350718021392822265625));
    }
    highp float _1674 = mod(_2354.x + 270.0, 360.0) - 180.0;
    highp float _2361 = 0.0;
    if (_1674 < 0.0)
    {
        _2361 = max(0.0, 1.0 + (_1674 * 0.0333333350718021392822265625));
    }
    else
    {
        _2361 = max(0.0, 1.0 - (_1674 * 0.0333333350718021392822265625));
    }
    highp float _1700 = mod(_2354.x + 240.0, 360.0) - 180.0;
    highp float _2362 = 0.0;
    if (_1700 < 0.0)
    {
        _2362 = max(0.0, 1.0 + (_1700 * 0.0333333350718021392822265625));
    }
    else
    {
        _2362 = max(0.0, 1.0 - (_1700 * 0.01666666753590106964111328125));
    }
    highp vec4 _892 = vec4(_2359, _2360, _2361, _2362);
    highp float _902 = dot(_863, uHslHueA) + dot(_892, uHslHueB);
    highp float _912 = dot(_863, uHslSatA) + dot(_892, uHslSatB);
    highp float _922 = dot(_863, uHslLumA) + dot(_892, uHslLumB);
    highp float _937 = clamp(_2354.y * (1.0 + _912), 0.0, 1.0);
    highp float _945 = clamp(_2354.z + ((_922 * 0.25) * _2354.y), 0.0, 1.0);
    highp vec3 _2378 = vec3(0.0);
    for (int _once = 0; _once < 1; _once++)
    {
        highp float _1739 = mod((_2354.x + _902) + 360.0, 360.0) * 0.00277777784503996372222900390625;
        if (_937 < 9.9999997473787516355514526367188e-06)
        {
            _2378 = vec3(_945);
            break;
        }
        highp float _2374 = 0.0;
        if (_945 < 0.5)
        {
            _2374 = _945 * (1.0 + _937);
        }
        else
        {
            _2374 = (_945 + _937) - (_945 * _937);
        }
        highp float _1770 = (2.0 * _945) - _2374;
        highp float _2375 = 0.0;
        for (int _once = 0; _once < 1; _once++)
        {
            highp float _1794 = fract(_1739 + 0.3333333432674407958984375);
            if (_1794 < 0.16666667163372039794921875)
            {
                _2375 = _1770 + (((_2374 - _1770) * 6.0) * _1794);
                break;
            }
            if (_1794 < 0.5)
            {
                _2375 = _2374;
                break;
            }
            if (_1794 < 0.666666686534881591796875)
            {
                _2375 = _1770 + (((_2374 - _1770) * (0.666666686534881591796875 - _1794)) * 6.0);
                break;
            }
            _2375 = _1770;
            break;
        }
        highp float _2376 = 0.0;
        for (int _once = 0; _once < 1; _once++)
        {
            highp float _1834 = fract(_1739);
            if (_1834 < 0.16666667163372039794921875)
            {
                _2376 = _1770 + (((_2374 - _1770) * 6.0) * _1834);
                break;
            }
            if (_1834 < 0.5)
            {
                _2376 = _2374;
                break;
            }
            if (_1834 < 0.666666686534881591796875)
            {
                _2376 = _1770 + (((_2374 - _1770) * (0.666666686534881591796875 - _1834)) * 6.0);
                break;
            }
            _2376 = _1770;
            break;
        }
        highp float _2377 = 0.0;
        for (int _once = 0; _once < 1; _once++)
        {
            highp float _1874 = fract(_1739 - 0.3333333432674407958984375);
            if (_1874 < 0.16666667163372039794921875)
            {
                _2377 = _1770 + (((_2374 - _1770) * 6.0) * _1874);
                break;
            }
            if (_1874 < 0.5)
            {
                _2377 = _2374;
                break;
            }
            if (_1874 < 0.666666686534881591796875)
            {
                _2377 = _1770 + (((_2374 - _1770) * (0.666666686534881591796875 - _1874)) * 6.0);
                break;
            }
            _2377 = _1770;
            break;
        }
        _2378 = vec3(_2375, _2376, _2377);
        break;
    }
    highp vec3 _964 = mix(_825, _2378, vec3(step(9.9999997473787516355514526367188e-05, (abs(_902) + abs(_912)) + abs(_922))));
    highp float _1911 = dot(_964, vec3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
    highp vec3 _970 = vec3(_1911);
    highp vec3 _975 = mix(_970, _964, vec3(uSaturation));
    highp float _978 = _975.x;
    highp float _980 = _975.y;
    highp float _982 = _975.z;
    highp float _984 = max(_978, max(_980, _982));
    highp vec3 _1012 = mix(_970, _975, vec3(1.0 + (uVibrance * (1.0 - ((_984 - min(_978, min(_980, _982))) / max(0.001000000047497451305389404296875, _984))))));
    highp float _1948 = uLutSize - 1.0;
    highp vec3 _1954 = clamp(_1012, vec3(0.0), vec3(1.0)) * _1948;
    highp vec3 _1956 = floor(_1954);
    highp vec3 _1962 = min(_1956 + vec3(1.0), vec3(_1948));
    highp vec3 _1965 = _1954 - _1956;
    highp float _1967 = _1956.x;
    highp float _2061 = _1956.z * uLutSize;
    highp float _2067 = uLutSize * uLutSize;
    highp float _2068 = ((_2061 + _1967) + 0.5) / _2067;
    highp float _2072 = (_1956.y + 0.5) / uLutSize;
    highp float _1974 = _1962.x;
    highp float _2092 = ((_2061 + _1974) + 0.5) / _2067;
    highp vec3 _1982 = vec3(_1965.x);
    highp float _2120 = (_1962.y + 0.5) / uLutSize;
    highp float _2157 = _1962.z * uLutSize;
    highp float _2164 = ((_2157 + _1967) + 0.5) / _2067;
    highp float _2188 = ((_2157 + _1974) + 0.5) / _2067;
    highp vec3 _2042 = vec3(_1965.y);
    highp vec3 _2252 = fract(_fragCoord.xyx * 0.103100001811981201171875);
    highp vec3 _2261 = _2252 + vec3(dot(_2252, _2252.yzx + vec3(33.3300018310546875)));
    highp vec3 _1085 = ((mix(mix(_1012, mix(mix(mix(texture2D(uLut, vec2(_2068, _2072)).xyz, texture2D(uLut, vec2(_2092, _2072)).xyz, _1982), mix(texture2D(uLut, vec2(_2068, _2120)).xyz, texture2D(uLut, vec2(_2092, _2120)).xyz, _1982), _2042), mix(mix(texture2D(uLut, vec2(_2164, _2072)).xyz, texture2D(uLut, vec2(_2188, _2072)).xyz, _1982), mix(texture2D(uLut, vec2(_2164, _2120)).xyz, texture2D(uLut, vec2(_2188, _2120)).xyz, _1982), _2042), vec3(_1965.z)), vec3(uLutIntensity)), vec3(1.0), vec3(uFade * 0.100000001490116119384765625)) + vec3(uFade * 0.0500000007450580596923828125)) * mix(1.0, smoothstep(0.800000011920928955078125, 0.20000000298023223876953125, length((_604 - vec2(0.5)) * vec2(1.0, uSize.y / uSize.x)) * (1.0 + uVignette)), uVignette)) + vec3(((((fract((_2261.x + _2261.y) * _2261.z) - 0.5) * 2.0) * uGrain) * 0.119999997317790985107421875) * (1.0 - (abs(_1911 - 0.5) * 2.0)));
    gl_FragColor = vec4(mix(_612, clamp(_1085, vec3(0.0), vec3(1.0)), vec3(uMasterIntensity)), _609.w);
}

"""
}
