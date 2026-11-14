# Oneova build log

The running record of the current build. Rules: `.agents/rules/oneova_build_vision.md`.
Take the first step that isn't ✅, do it fully, then update this file in the same commit.

Status: ✅ done · 🔨 in progress · ⏳ next · ⛔ blocked (says why)

## Stage A: Focus the app (this version)
- ✅ A1. Vision and rules every agent follows (`.agents/rules/oneova_build_vision.md`, linked from `AGENTS.md`).
- ✅ A2. Removed studio management: YouTube manager screens, video and audio production, team tab, CRM,
  communication manager, and unused hub, drawer and studio hub screens. Fixed links to pages that never
  existed (`/creator_studio/*`, `/communication/*`) in the Reels author panel and deep links. Old routes redirect (`/yt/*` → `/social_hub`,
  `/video/*` and `/audio/*` → `/create/studio`, `/hub/team` → `/hub/home`).
- ✅ A3. Shared compact UI parts in `lib/shared/widgets/compact/`.
- ✅ A4. Settings and Me on compact rows. Settings: `CompactGroup`/`CompactRow` (50 px rows), quick
  controls as one wrap of chips, the health card only shows when something needs attention (summary
  first, issues and Fix on tap), slim profile row. Me sidebar: plain row icons, stats on one text line,
  borderless quick actions, unread as pink dots. All routes, health dots and live hints kept.

## Stage B: Compact UI everywhere (one area per release, each checked in light and dark)
- 🔨 B1. Business portal and shop tools (next).
- ⏳ B2. Chats: bubble padding 10–12, inline small previews for links, payments, gifts and reels;
  AI suggestion chips as one thin row only when useful.
- ⏳ B3. Ova and AI Lab: replies without boxes, tool results as one-line summaries, small orb,
  agents in the same Ova screen (`lib/ova_assistant/main_interface/`).
- ⏳ B4. Live: narrow faded comments, small gift pill, compact deal bar, seller tools in a sheet.
- ⏳ B5. Reels (locked layout, see `.agents/rules/oneova_home_launch_screen.md`): only shrink controls and
  fade extras after inactivity.

## Stage C: My computer inside Ova (security first)
Existing code: `lib/hub/phone_controller/`, `lib/hub/live_control/`, `lib/desktop_agent/`,
`functions/src/ovaAgentBridge.ts`.
- ⏳ C1. Security review of the control path: pairing is account plus device bound, sessions expire,
  either side can stop at once, commands are checked on the desktop against an allow list, signalling
  rules are owner-only, and media is end-to-end encrypted. Write findings into this file before C2.
- ⏳ C2. Control icons in the Ova overlay: live screen, mouse pad, voice keyboard, shortcuts. One tap opens
  each; no separate screens needed.
- ⏳ C3. Works across networks: TURN relay fallback verified on mobile data (no same Wi-Fi needed).
- ⏳ C4. Natural-language computer commands: Ova plans in the background, shows one animated activity
  line, and asks before risky actions (delete, send, buy, install).
- ⏳ C5. Media back in chat: screenshots, recordings, files and audio from the computer shown inline and small.

## Stage D: Oneova Pay, Globe ID, Merchant Hub, Sentinel
Design: `docs/payments/platform/` (architecture, security model, schema and API, code and deployment).
- 🔨 D1. Device binding: built, not yet deployed or tried on a phone.
  - Server `functions/src/pay/devices.ts` (+ pure checks and tests in `devicesLogic.ts`): challenge,
    register with Google key attestation (secure chip, our app, our challenge, needs a biometric,
    Google root, not revoked), trust after a fresh email code, 24 h cool-down for large payments on
    extra phones, verify, list, revoke. `verifyDeviceApproval()` is ready for D2.
  - Android `DeviceKeyChannel.kt`: P-256 key in StrongBox or TEE, every signature needs a strong
    biometric, new fingerprints invalidate the key. iOS not done yet (Secure Enclave + App Attest).
  - App `lib/pay/security/` (device key, service, live face card with mesh that follows the real
    checks) and `/id/devices` (Payment phones, linked from Oneova ID).
  - Left: deploy the six `payDevice*` functions (needs your OK), try on a real phone, iOS.
- ⏳ D2. Payment requests with biometric approval and countdown, success screen (`003_pay_core.sql`).
  Approval uses the face card + `verifyDeviceApproval()`. After each payment, a payment report for
  both sides: written from the server's own records (ledger journal, approval, risk decision), with
  plain-language wording added by AI that can't change any fact. Every step is stored as a
  `payment_events` row and published on Pub/Sub so other systems (merchant webhooks, admin, analytics)
  can follow it.
- ⏳ D3. Signed receipts and verify.
- ⏳ D4. Send by Oneova ID, personal QR.
- ⏳ D5. Sentinel rules and admin review queue; App Check enforcement; KMS for funding methods.
- ⏳ D6. Merchant Hub: sales from the ledger, refunds, staff roles, statements.
- ⛔ Release to production waits for the Play organization account.

## Session notes
- 2026-11-14: build 1.0.0 (33) on Play internal. A1–A4 done; B1 next. A4 checked with analyze, the guard
  test and a render test at 360 px in light and dark; not yet seen on a signed-in phone (not in a Play build yet).
