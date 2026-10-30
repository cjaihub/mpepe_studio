# Oneova Looks Program — Agent Contract (applies to EVERY looks/filter subagent)

Install path after approval: `docs/looks/AGENT_CONTRACT.md`

## Read first (every run)
1. `AGENTS.md`, `.agents/rules/ui_ux_guidelines.md`, `.agents/rules/oneova_home_launch_screen.md`
2. `docs/looks/LOOKS_PROGRAM_PLAN.md`: the section for your phase plus §1 Principles
3. Reports from the agents you depend on: `docs/looks/reports/<agent>.md`

## Working style
- **Take your time.** Study the existing code before writing anything. Plan your file list, then build step by step. Correctness beats speed.
- Build only what your brief owns. If you need something from another agent's area, write a request in your report instead of building it yourself.
- Edit forward only. No `git checkout`/revert, no bulk `sed` across `lib/`, no restoring old copies.

## Absolute bans (the QA agent fails the phase if found)
- `TODO`, `FIXME`, `mock`, `dummy`, `fake`, `placeholder`, `simulated`, `return null; // later`, empty handlers, hard-coded catalog lists, hard-coded thresholds, hard-coded resolutions/fps/bitrates.
- Static `Colors.white/black` or hex colors in UI (use `AppColors` / `context.*`). `lucide_icons`.
- Fake data seeded to make screens look full.

## Configuration sources (use these instead of hard-coding)
- Content and catalogs → Firestore. Tunables, thresholds, ladders and quotas → Remote Config (with documented default keys in `docs/looks/config_keys.md`). Device limits → capability probes + `deviceProfiles`.

## If blocked
If you need credentials, licenses, store access, a paid quota or a product decision: **stop, write `BLOCKED:` with the exact need in your report, and end.** Never fake around it.

## Definition of done (all required)
1. `flutter analyze` on touched files: 0 issues. `flutter test test/guards/home_lock_test.dart` passes.
2. New unit/widget tests for your logic pass. For native code, it builds on Android (`flutter build apk --debug`) and iOS (`flutter build ios --no-codesign`).
3. Functions: `npm --prefix functions run build` + tests pass. Deploy only your functions: `firebase deploy --only functions:<names>`. Rules/indexes go through `firestore-rules-author`.
4. Checked visually in light and dark mode (screenshots in the report) for UI work.
5. Write `docs/looks/reports/<your_agent>.md`: files changed, Remote Config keys, Firestore paths, deploy output, how to test, known limits.
