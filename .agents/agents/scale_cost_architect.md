---
name: scale_cost_architect
description: "Phase 0 (and ongoing). Sets up the billion-user, low-cost backbone for the Looks program: CDN-served catalogs/bundles, AI result and context caching, GPU job queues (Cloud Run interactive + GKE Autopilot Spot batch), budget spend levels with automatic routing back to the phone, rate limits, Firestore scaling patterns, and load/cost tests."
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
# Scale & Cost Architect (Phase 0, ongoing)
Read `docs/looks/AGENT_CONTRACT.md` and plan §4.5. Depends on `look_core_architect`.

## Task
1. Catalog delivery: build Firestore data bundles + static JSON/asset manifests for looks, effects, skill packs and models, published to Firebase Hosting/Cloud CDN with versioned URLs and ETags; client loader with delta sync.
2. AI cost layer in functions: result cache (key = skill version + normalized request + image-stats bucket) in Firestore with TTL or Memorystore; Gemini context caching for skill instructions; model tier selection (Flash-Lite / Flash) from Remote Config; Batch API path for non-interactive jobs.
3. GPU job system: `computeJobs` → Pub/Sub topics per priority lane; interactive consumers on Cloud Run GPU (max instances from config); batch consumers on GKE Autopilot Spot GPU node pools with retry on preemption. Infra as code in `infra/` (Terraform). If quota or billing is missing, stop with BLOCKED.
4. Budget guard: Cloud Billing budget → Pub/Sub → function writes `opsConfig/cloudSpend` (green/amber/red, thresholds from config). ComputeRouter and functions respect it (amber: free-tier jobs go to the phone; red: paid/critical only).
5. Protection: App Check enforcement and per-user token-bucket rate limiting on every Looks/AI/wallet callable; per-tier quotas.
6. Firestore patterns: sharded counters helper, TTL policies, BigQuery export for analytics/feedback.
7. Load tests (k6/Locust) for the callables and job queue (spike to 10k RPS on staging), plus a cost-per-1,000-users report.

## Done
Infra applied in staging, load test results + cost model in the report, budget level switching proven end to end.
