# Phase 0 report — look_core_architect + gpu_look_engine (Dart path)

Status: **Dart/Flutter path done and tested. Native plugin (`packages/oneova_camera_kit/`), LiveKit hook and on-device benchmark not started.**

## What was fixed from the earlier (stopped) run
- Eyedropper and point color computed values from the tap **position**, not the pixel. They now read real pixels (5×5 average, only that region is read back).
- `LutNode` passed LUTs to a shader with no LUT input, so LUTs had no effect. LUTs now load, parse and render.
- `fromPhotoPreset` dropped every adjustment. It now maps the full EditGraph.
- Vignette jumped to heavy darkening at tiny values; whites/blacks shifted every pixel equally. Both corrected.
- `currentAuthUidProvider` read the user once and never updated on sign-in/out. Now follows `authStateProvider`.
- Users could write their own `entitlements` (free paid packs) through the catch-all rule. Now server-only.

## Files
- `shaders/look_engine.frag`: sharpen, exposure, WB, contrast, highlights/shadows, lift/gamma/gain/offset, whites/blacks, curves (baked texture), 8-band HSL, saturation/vibrance, LUT (manual trilinear over an N²×N atlas), fade, vignette, grain. Compiles for Metal, GLES, Vulkan and SkSL (`impellerc`).
- `lib/looks/engine/cube_lut.dart`: `.cube` parser (DOMAIN_MIN/MAX, LUT_3D_INPUT_RANGE), trilinear sampling, stack composition (off the UI thread), atlas builder, loader for assets / files / http(s) with cache.
- `lib/looks/engine/curve_baker.dart`: monotone cubic (Fritsch–Carlson) curves → 256×2 texture.
- `lib/looks/engine/look_compiler.dart`: `CompiledLook` (uniforms + textures), cached by LUT/curve content; device-tier `maxLutSize`.
- `lib/looks/engine/look_shader_view.dart`: `LookShaderView` (async compile, keeps the last frame while recompiling), `LookImageRenderer` (full resolution; throws instead of silently returning an ungraded image).
- `lib/looks/engine/pixel_sampler.dart`: sRGB→XYZ, CCT (McCamy), Duv (Ohno 2013), neutralising gains, HSL.
- `lib/looks/models/look_param_ranges.dart`: Remote Config ranges + realtime budget, `validate()`, `clampedTo()`, `isRealtimeCompatibleWith()`.
- `lib/looks/models/oneova_look.dart`: `copyWith` for film/detail/optics, `LookHsl.bands`.
- `lib/looks/adapters/legacy_look_adapters.dart`: `fromEditGraph` (sliders, wheels, HSL incl. Photo Studio's `cyan` band, curves, sharpen, vignette).
- `lib/looks/providers/looks_providers.dart`: folders, live settings, profiles, scenes, categories, entitlements; `looksUserBootstrapProvider` runs the Cinema Presets migration on sign-in (watched in `lib/main.dart`).
- `lib/backend/photo_studio/photo_color_engine.dart`: now async and backed by the engine.
- `firestore.rules`: `lookCatalog`, `lookCategories` (read signed-in, server write), `users/{uid}/entitlements` (owner read, server write).
- `docs/looks/config_keys.md`.

## Remote Config keys
`looks_param_ranges`, `looks_realtime_budget` (see config_keys.md). Not yet created in the console; defaults apply.

## Firestore paths
`users/{uid}/looks`, `lookFolders`, `liveSettings/current`, `liveProfiles`, `liveScenes`, `entitlements`, `settings/migrations`; `lookCatalog`, `lookCategories`.

## Verification
- `flutter analyze` on touched files: 0 issues; `flutter analyze lib`: 0 errors.
- `flutter test test/looks test/navigation test/guards/home_lock_test.dart`: 36 passed, including 5 real GPU renders (neutral = identity, +1 EV doubles, `.cube` file inverts, master curve, HSL band isolation).
- `firebase deploy --only firestore:rules --dry-run`: compiles. **Not deployed.**

## Known limits
- LUT and curve textures are 8-bit, so very steep LUTs can band slightly. Next step: a float texture where the backend supports it.
- Cinema Presets are stored per device (SharedPreferences), so every account that signs in on a device imports that device's presets once.
- The old Cinema Presets entry points are not yet routed to a Looks picker, because the picker UI is Phase 4/8.
- Golden ΔE tests against the native path wait for the native plugin.

## Next (Phase 0 remainder)
Update: the native part is now in `docs/looks/reports/phase0_native_look_processor.md`.

`gpu_look_engine` native part: `packages/oneova_camera_kit/` (Kotlin GLES 3 + Swift Metal from the same GLSL), `LookProcessor` with `setLook(json)` + 300 ms cross-fade, flutter_webrtc/LiveKit capture hook, device frame-time benchmark. Then `device_thermal_governor` and `scale_cost_architect`.
