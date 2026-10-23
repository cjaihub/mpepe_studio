# Live Studio v2 — rules for every workstream agent

Read these first, in this order:
1. `AGENTS.md`;
2. `.agents/rules/ui_ux_guidelines.md`;
3. `docs/live-studio/SPEC.md`;
4. `docs/live-studio/ARCHITECTURE.md` (decisions are at the top);
5. `lib/backend/live_studio/contracts/studio_contracts.dart`;
6. `lib/backend/live_studio/contracts/studio_ports.dart`;
7. `lib/social_hub/live/studio_v2/theme/live_studio_tokens.dart`;
8. `functions/src/liveStudio/contracts.ts`;
9. `functions/src/liveStudio/shared.ts`.

## Hard rules
- **Edit only the paths your brief says you own.** Several agents work in the same checkout at the same time.
  - Integrator-owned files are read-only for you: contracts, ports, tokens, `shared.ts`, `firestore.rules`, `functions/src/index.ts`, `lib/shared/router.dart`, `pubspec.yaml`, `functions/package.json` and the feature flag.
  - If you need a change there, put it under "Requested integrator changes" in your report and code against the API you asked for, behind a small local adapter.
- **No git commands at all**: no commit, stash, checkout, restore, reset or branch. Do not restore from backups and do not run any `patch*`/`fix*` scripts in the repo root.
- **Do not install packages**: no `flutter pub add/get/upgrade`, no `npm install`. If you need a package, request it.
- No bulk `sed`/regex edits across `lib/`. Make targeted edits only.
- Material `Icons` only (`lucide_icons` is banned). In studio v2 code, colors come from `live_studio_tokens.dart`, never literals.
- No mock or seeded data in production code. Fakes are for tests only (`test/live_studio_v2/<your area>/fakes/…`).
- Design for the Riverpod 3 patterns already used in `lib/backend/live/**` (`Notifier`, `StreamProvider.family`, `NotifierProvider.autoDispose.family`).
- Cloud Functions are TypeScript, `firebase-functions/v2/https` `onCall`.
  - Use the `shared.ts` helpers (`requireUid`, `requireRole`, `patchState`, `broadcast`, `rateLimit`).
  - Any callable that talks to LiveKit declares `secrets: LIVEKIT_SECRETS`.
  - Keep pure logic in `*_logic.ts` with no Firestore/LiveKit imports, so it is unit-testable.
  - TS tests go in `functions/src/liveStudio/__tests__/<area>*.test.ts` (node:test) and run with `npm --prefix functions run test:livestudio`. The full `tsc` build has two pre-existing errors in unrelated files; ignore them, but your files must typecheck: `npx --prefix functions tsc --noEmit -p functions/tsconfig.livestudio.json`.

## Verification you must run before reporting
- `flutter analyze <your paths>`: 0 issues.
- `flutter test <your test paths>`: green. Run only your own test paths; other agents are running theirs.
- `flutter test test/guards/home_lock_test.dart`: green.
- For functions work: `npm --prefix functions run test:livestudio` green and the typecheck above clean.

## Report format (your final message)
1. Files created/changed (paths).
2. Public API other workstreams use (classes, providers, callables with their args and results).
3. Tests: what is covered, plus the exact commands and pass counts.
4. Requested integrator changes (contracts, rules, index exports, router, deps), with exact code.
5. Known gaps, and what you could not verify (e.g. needs real LiveKit credentials or a device).
