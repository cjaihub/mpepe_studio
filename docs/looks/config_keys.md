# Looks — Remote Config keys

Values are JSON strings. Missing or malformed values fall back to the defaults below (in code: `lib/looks/models/look_param_ranges.dart`).

## `looks_param_ranges`
Per-parameter `[min, max]` used by `OneovaLook.validate()` and `clampedTo()`. Only the keys you set are overridden.

| Key | Default |
|---|---|
| `intensity` | `[0, 1]` |
| `primary.exposure` | `[-2, 2]` (EV) |
| `primary.contrast` | `[0.5, 2]` |
| `primary.pivot` | `[0, 1]` |
| `primary.highlights` / `shadows` / `whites` / `blacks` | `[-1, 1]` |
| `color.temperature` / `color.tint` | `[-100, 100]` |
| `color.vibrance` | `[-1, 1]` |
| `color.saturation` | `[0, 2]` |
| `wheels.channel` (every lift/gamma/gain/offset channel) | `[-1, 1]` |
| `hsl.hue` | `[-180, 180]` (degrees) |
| `hsl.sat` / `hsl.lum` | `[-1, 1]` |
| `lut.intensity` | `[0, 1]` |
| `lut.size` | `[2, 65]` |
| `film.grain` / `film.fade` / `optics.vignette` / `detail.sharpen` | `[0, 1]` |

Example: `{"primary.exposure": [-3, 3]}`

## `looks_realtime_budget`
Limits for Live and Camera (`isRealtimeCompatibleWith`).

| Field | Default | Meaning |
|---|---|---|
| `maxLutStack` | `4` | Enabled LUTs in one look (they are pre-composed into one texture, so this bounds compose time, not GPU cost) |
| `maxLutSize` | `33` | Largest LUT edge allowed in realtime |
| `allowSharpen` | `true` | Whether the 4-tap sharpen may run in realtime |
| `crossFadeMs` | `300` | Cross-fade when Live/Camera switches looks (native `LookProcessor`) |

Example: `{"maxLutStack": 2, "maxLutSize": 33, "allowSharpen": false, "crossFadeMs": 200}`

## `ai_model_tier`
Selects the Gemini model tier for server-side look creation and grading callables (`functions/src/looks/aiCostOptimizer.ts`).

| Value | Behavior |
|---|---|
| `auto` (default) | Flash-Lite for free users & lightweight tasks; Flash for Pro/Biz creative grading; auto-downgrades to Flash-Lite if Cloud Spend is Amber or Red |
| `flash_lite` | Enforces `gemini-2.5-flash-lite` globally (~50-70% lower token cost) |
| `flash` | Enforces `gemini-2.5-flash` globally |

Example: `"auto"`

## `ai_tier_quotas`
Per-user token-bucket rate limits and daily limits for AI generation and Cloud GPU rendering (`functions/src/looks/rateLimiter.ts`).

| Field | Default (Free / Pro / Biz) | Meaning |
|---|---|---|
| `ratePerMinute` | `10` / `30` / `60` | Token-bucket capacity and refill rate per minute for interactive callables |
| `dailyGenerations` | `10` / `100` / `500` | Daily AI look generation / conversational grading commands |
| `dailyCloudRenders` | `1` / `20` / `100` | Daily cloud-rendered video / photo exports |

Example:
```json
{
  "free": { "ratePerMinute": 10, "dailyGenerations": 10, "dailyCloudRenders": 1 },
  "pro": { "ratePerMinute": 30, "dailyGenerations": 100, "dailyCloudRenders": 20 },
  "biz": { "ratePerMinute": 60, "dailyGenerations": 500, "dailyCloudRenders": 100 }
}
```

## `cloud_spend_thresholds`
Budget guard threshold ratios for Cloud Billing notifications (`functions/src/looks/budgetGuard.ts`).

| Key | Default | Meaning |
|---|---|---|
| `amberThreshold` | `0.80` (80%) | Free-tier cloud jobs are routed to on-device compute |
| `redThreshold` | `1.00` (100%) | Cloud compute restricted to paid/critical jobs only |

Example: `{"amberThreshold": 0.80, "redThreshold": 1.00}`

## `cloud_run_gpu_max_instances`
Maximum concurrent Cloud Run GPU (L4) instances allowed to scale up (`infra/cloud_run_gpu.tf`).

| Default | Meaning |
|---|---|
| `10` | Hard instance cap preventing runaway billing spikes |

## `looks_cdn_base_url`
CDN origin serving static asset manifests and Firestore Data Bundles (`lib/looks/services/catalog_sync_service.dart`).

| Default | Meaning |
|---|---|
| `https://mpepe-2b4bd.web.app` | Firebase Hosting / Cloud CDN domain with ETag caching |

## `ai_result_cache_ttl_days`
Time-to-live for cached AI Look grading results in Firestore `aiResultCache` collection.

| Default | Meaning |
|---|---|
| `7` | Cached look results persist for 7 days before Firestore TTL auto-deletes |

## `compute_job_ttl_hours`
Time-to-live for completed/failed jobs in Firestore `computeJobs` collection.

| Default | Meaning |
|---|---|
| `72` | Job status records persist for 72 hours before Firestore TTL auto-deletes |

## `advisor_enforcement`
Controls enforcement behavior for DeviceAdvisor hardware ceilings (`lib/looks/device/advisor/device_advisor.dart`).

| Value | Behavior |
|---|---|
| `enforce` (default) | Settings above the ceiling are disabled with an explanatory tooltip |
| `warn` | Shows advisory warning badge but permits user selection |
| `off` | Ceilings calculated for telemetry only; all UI controls enabled |

Example: `"enforce"`

## `thermal_ladder`
Configures thermal throttling mitigation thresholds, hysteresis, and step-down actions (`lib/looks/device/governor/thermal_governor.dart`).

| Field | Default | Meaning |
|---|---|---|
| `stepDownHeadroomThreshold` | `0.85` | Predictive thermal headroom triggering next step-down tier |
| `stepUpHeadroomThreshold` | `0.70` | Thermal headroom required to allow recovery step-up |
| `recoveryHysteresisSeconds` | `15` | Required continuous stable duration below recovery threshold before stepping up |
| `maxMitigationTier` | `6` | Maximum mitigation severity tier (0 = nominal, 6 = emergency cooldown) |

Mitigation Ladder Steps:
1. ML inference rate reduction (30fps → 15fps)
2. Effects quality and LUT stack constraint
3. Background segmentation disable
4. Boost Beauty downsample
5. Video frame rate step-down (60fps → 30fps)
6. Stream resolution step-down (4K → 1080p, 1080p → 720p)

Example:
```json
{
  "stepDownHeadroomThreshold": 0.85,
  "stepUpHeadroomThreshold": 0.70,
  "recoveryHysteresisSeconds": 15,
  "maxMitigationTier": 6
}
```

