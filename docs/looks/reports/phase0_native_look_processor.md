# Phase 0 report: gpu_look_engine, native part (`packages/oneova_camera_kit`)

Status: **The native `LookProcessor` is built for Android (GLES 3) and iOS (Metal) and hooked into flutter_webrtc local camera tracks. It compiles on both platforms. The Metal path matches the Flutter path on 20 reference looks. Not yet run on a phone: the frame-time benchmark and the GLES parity check need a real Android/iOS device.**

## How it works
- **One shader source.** `tool/generate_shaders.dart` compiles `shaders/look_engine.frag` with Flutter's own `impellerc` (`--runtime-stage-gles3`, `--runtime-stage-metal`). The native paths run the same compiled shader as the Flutter previews and exports. The generator also emits the uniform table (name, float offset, Metal buffer index) from impellerc's reflection, so nothing is maintained by hand. Re-run it after editing the shader; a test fails if the generated files are stale.
- **Same inputs.** `LookCompiler.uniformValues()` now produces the uniform list for both paths. `CompiledLook` keeps the raw RGBA bytes of the LUT atlas and curve texture. `compiledLook.toNative()` (`lib/looks/engine/native_look.dart`) builds the `NativeLook` payload.
- **Per frame:** source pass (camera texture with WebRTC's transform/crop → RGBA texture), then the Look pass into a pooled output texture. The graded frame goes to WebRTC, so both the encoder and the local preview see it. Frames never go through the CPU.
- **Cross-fade.** On a look switch, the old look (or the original frame) is drawn first and the new look is blended over it with a constant alpha, for `looks_realtime_budget.crossFadeMs` (default 300 ms).
- **Never stalls capture.** If a frame cannot be graded, the original frame is sent and the reason is counted in `stats()`: `no_look`, `cpu_buffer`, `unsupported_format`, `no_gl_context`, `output_pool_exhausted`, `render_error`.

### Android (`android/src/main/kotlin/com/oneova/camerakit/`)
- `TrackLookHook` registers as a flutter_webrtc `LocalVideoTrack.ExternalVideoFrameProcessing`. It runs on the SurfaceTextureHelper thread, where the capture EGL context is current.
- `GlLookRenderer`:
  - Input is an OES or RGB `TextureBuffer`, using its transform matrix.
  - Output is an RGB `TextureBufferImpl` from a pool, at most `maxInFlightFrames` (default 4) frames in flight.
  - It calls `glFinish` before handing a frame on, because the encoder reads it from another shared context.
  - Each output frame is released on the next frame, after WebRTC's sink has taken its own reference.
  - If the GL context changes, it rebuilds its GPU resources.
  - Detach frees GPU resources on the GL thread; outputs still in use are freed when WebRTC releases them.

### iOS (`ios/Classes/`)
- `OneovaWebRTCBridge.mm` adds and removes the processor on flutter_webrtc's `VideoProcessingAdapter`. It is Objective-C++ so Swift never imports flutter_webrtc's C++ header.
- `LookMetalPipeline.swift` holds the Metal pipelines and draw calls. It does not depend on WebRTC, so the macOS parity tool tests this same code.
- `MetalLookRenderer.swift`:
  - Input is a camera `CVPixelBuffer` (NV12 in video or full range, BT.601/709 from its attachment, or BGRA), read as zero-copy textures through `CVMetalTextureCache`.
  - Output is an IOSurface BGRA buffer from a `CVPixelBufferPool` with an allocation threshold of `maxInFlightFrames`.
  - It waits for the command buffer to finish before returning the frame.
- The pod is a `static_framework`, like flutter_webrtc, so both share one `FlutterWebRTCPlugin.sharedSingleton`. The Metal source is therefore compiled at runtime when a track is attached, off the main thread.

## API for `live_looks_engineer`
```dart
final compiled = await LookCompiler.compile(look, maxLutSize: budget.maxLutSize);
final p = await TrackLookProcessor.attach(localVideoTrack.mediaStreamTrack.id);
await p.setLook(compiled.toNative(), crossFade: Duration(milliseconds: budget.crossFadeMs));
await p.setLook(null, crossFade: ...);   // back to the original frames
final s = await p.stats();               // framesGraded, averageFrameMs, p95FrameMs, lastPassThroughReason
await p.detach();                        // before the track is disposed
```
- Attach to the **primary camera track**. On Android, secondary tracks that share the same source (`buildSharedVideoTrack`) are not the source's processor, so a look set on them is never applied. On iOS, non-camera tracks are rejected with `track_not_found`.
- Error codes: `track_not_found`, `not_attached`, `bad_args`, `gpu_unavailable` (iOS).

## Files
- New package `packages/oneova_camera_kit/` (path dependency in `pubspec.yaml`):
  - `lib/`: `TrackLookProcessor`, `NativeLook`, `LookProcessorStats`, `shaderSourceHash`.
  - `tool/generate_shaders.dart`.
  - `tool/metal_parity/`: `main.swift`, `run.sh`.
  - `android/`: `build.gradle`, manifest, Kotlin sources (the `LookEngineShader.kt` file is generated).
  - `ios/`: podspec, Swift and Objective-C++ sources (the `LookEngineShader.swift` file is generated).
  - `test/look_processor_test.dart`.
- `lib/looks/engine/look_compiler.dart`: `uniformValues()`, plus `lutAtlasRgba`/`curvesRgba` on `CompiledLook`. `bindUniforms` now uses `uniformValues()`.
- `lib/looks/engine/native_look.dart`: `CompiledLook.toNative()`.
- `lib/looks/models/look_param_ranges.dart`: `LookRealtimeBudget.crossFadeMs`.
- `docs/looks/config_keys.md`: documents `crossFadeMs`.
- Tests: `test/looks/native_look_test.dart`, `test/looks/native_parity_fixtures_test.dart`.

## Remote Config keys
`looks_realtime_budget.crossFadeMs` (default `300`). No new Firestore paths.

## Verification
- `flutter analyze lib/looks lib/main.dart test/looks packages/oneova_camera_kit`: 0 issues.
- `flutter test test/looks test/navigation test/guards/home_lock_test.dart`: 40 passed.
- `flutter test` in `packages/oneova_camera_kit`: 8 passed (payload validation, channel protocol, generated shaders match the shader source).
- Android: `flutter build apk --debug` succeeds with the plugin's Kotlin compiled.
- iOS: the `oneova_camera_kit` pod target builds for `iphoneos` with Xcode 16.0. The full `flutter build ios --no-codesign` stops earlier, in `device_info_plus` 13.3.0 (`isiOSAppOnVision`), because that package needs a newer Xcode SDK than the installed 16.0. That failure is not caused by this work, but it blocks a full iOS app build on this Mac.
- **Metal parity** (AMD Radeon Pro 575X, macOS). Commands:
  ```bash
  ONEOVA_PARITY_OUT=/tmp/parity flutter test test/looks/native_parity_fixtures_test.dart
  ```
  ```bash
  packages/oneova_camera_kit/tool/metal_parity/run.sh /tmp/parity
  ```

  | look | mean ΔE2000 | p99 | max | max 8-bit Δ |
  |---|---|---|---|---|
  | neutral, s_curve, rgb_curves | 0.000 | 0.000 | 0.000 | 0 |
  | exposure_up / exposure_down | 0.005 / 0.012 | 0.22 / 0.37 | 0.56 / 0.69 | 1 |
  | contrast, highlights_shadows, whites_blacks | ≤ 0.020 | ≤ 0.38 | ≤ 1.00 | 1 |
  | warm_tint, vibrance_sat, desaturate, wheels, hsl | ≤ 0.024 | ≤ 0.50 | ≤ 1.19 | 1 |
  | lut_teal_orange, lut_half, lut_stack | ≤ 0.023 | ≤ 0.54 | ≤ 0.97 | 1 |
  | fade_vignette, sharpen, cinematic_mix | ≤ 0.024 | ≤ 0.52 | ≤ 1.11 | 1 |
  | grain | 0.065 | 0.40 | 10.8 | 28 |
  | 50% cross-fade vs. average of original and graded | | | | 1 |

  - Every look except grain is within one 8-bit level everywhere. The maximum ΔE is just over 1 in a few dark pixels, where a single level of rounding already exceeds ΔE 1.
  - Grain hashes the pixel position, and its `fract()` differs on a few pixels between GPU backends. Its statistics match (mean ΔE 0.065).
  - The tool's pass rule is: p99 ΔE < 1.0 and at most one level of difference; for grain, mean ΔE < 0.5.

## Not done / known limits
- **No device run yet.** Not done on a phone:
  - the frame-time benchmark (`stats().averageFrameMs` / `p95FrameMs` exist for it),
  - the GLES on-device parity check,
  - an end-to-end LiveKit publish with a look.
  Only an Android emulator AVD is available here, and its host-emulated GPU timings would not be a valid benchmark. **Needed:** a physical Android phone and iPhone connected to this Mac.
- On Android, `glFinish` and the iOS `waitUntilCompleted` block the capture thread for the GPU time of each frame. A fence-based handoff (EGL sync / `MTLSharedEvent`) is the next optimisation once device numbers exist.
- On Android, non-texture (I420) frames, such as from some screen-share capturers, are passed through ungraded (`cpu_buffer`). Camera frames are always textures.
- The GLES path builds the shader with `highp` floats, while Flutter's GLES backend defaults to `mediump`. That keeps camera grading at full precision, but on GLES devices the native output can differ slightly from the Flutter preview.
- The Kotlin plugin applies the Kotlin Gradle Plugin when `android.builtInKotlin=false`, like flutter_webrtc. Flutter warns that this will be removed in a future Flutter release, so all those plugins will have to migrate at the same time.
- The parity fixtures are written only when `ONEOVA_PARITY_OUT` is set, so CI renders the 20 looks but does not compare paths. The comparison needs macOS with Metal.

## Next
- `live_looks_engineer`: attach a `TrackLookProcessor` to the Live Studio camera track (`lib/backend/live_studio/media/livekit_studio_room.dart`) and drive it from the Looks providers.
- `device_thermal_governor`, `scale_cost_architect`.
