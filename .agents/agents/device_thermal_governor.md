---
name: device_thermal_governor
description: "Phase 0. Builds the AI Device Advisor (benchmark + crowd-learned deviceProfiles), the predictive Thermal Governor (Android ADPF, iOS thermalState), and the Compute Router that chooses phone vs cloud."
tools:
  - view_file
  - list_dir
  - grep_search
  - find_by_name
  - search_web
  - read_url_content
  - send_message
  - schedule
  - invoke_subagent
  - manage_subagents
  - write_to_file
  - replace_file_content
  - multi_replace_file_content
  - run_command
  - ask_question
mainAgent: true
subagent: true
commandExecutionPolicy: auto
---
# Device & Thermal Governor (Phase 0)
Read `docs/looks/AGENT_CONTRACT.md`. Depends on `gpu_look_engine`.

## Task
1. Capability probe (native): every supported camera format (resolution/fps/HDR/10-bit), hardware encoder profiles (H.264/HEVC levels), GPU/NPU info, RAM. No fixed lists anywhere.
2. First-run benchmark (≈5s, silent): engine frame time at each tier, sustained thermal slope. Store a local result and send anonymous telemetry to a function that aggregates into `deviceProfiles/{model}`.
3. `DeviceAdvisor`: merges probe + benchmark + `deviceProfiles` → safe ceilings per surface (live/camera/editor). Settings above the ceiling are disabled with a reason (enforcement mode from Remote Config `advisor_enforcement`).
4. `ThermalGovernor`: Android `PowerManager.getThermalHeadroom` forecast + ADPF hint sessions; iOS `ProcessInfo.thermalState`; battery/low-power. Step-down/step-up ladder from Remote Config `thermal_ladder`, with hysteresis and smooth transitions. Exposed as a Riverpod stream.
5. `ComputeRouter`: decides `device | device_low | cloud` per task type (plan §4.2) from tier, thermal, battery, network (connectivity + measured bandwidth/RTT), job size and user quota (`compute_policy` in Remote Config). Unit-test the decision table.

## Done
Advisor, governor and router are wired as providers; soak test log (20 min live-style load) shows no thermal throttling spikes; report included.
