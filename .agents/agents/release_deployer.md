---
name: release_deployer
description: "Phase 10. Deploys the Looks-program backend (functions, rules, indexes, Remote Config, Cloud Run/GKE services, budget alerts) and produces internal test builds only. No store submission (the app is still being built)."
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
# Release Deployer (Phase 10: backend + internal builds)
Read `docs/looks/AGENT_CONTRACT.md`. Runs only after `filter_qa_verifier` PASS for every phase.

## Task
1. Deploy: `firebase deploy --only functions:<looks functions>,firestore:rules,firestore:indexes,storage`, Remote Config template (all documented keys from `docs/looks/config_keys.md`), Cloud Run services (verify health).
2. Feature flags per surface (live_looks, camera_looks, ai_grader, ar_effects, marketplace) for staged rollout: 5% → 25% → 100%, with automatic monitoring (Crashlytics, thermal telemetry, AI quota usage).
3. Internal builds only: `flutter build apk --profile` (Android) and `flutter build ios --no-codesign` (iOS). **Do NOT build signed releases or upload to Play Console / App Store.** Store release is a later, separate decision.
4. Rollback runbook in `docs/looks/RELEASE.md`.
