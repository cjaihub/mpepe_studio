# Oneova fintech platform: code structure and deployment plan

Status keys: ✅ exists · 🔨 to build · ↪ move here when next touched (edit forward, no big-bang moves).

## 1. Flutter (`lib/`)
Money code lives in one feature folder per domain. Screens hold no money logic: they call a service,
the service calls a callable, the server decides.

```
lib/
  pay/                         🔨 home for Oneova Pay (target)
    data/
      pay_service.dart         ↪ from lib/backend/pay/oneova_pay_service.dart ✅
      pay_models.dart          ↪ from lib/backend/money/money_models.dart ✅
      requests_repository.dart 🔨 streams pay_requests for the signed-in user
      receipts_repository.dart 🔨
    security/
      device_key.dart          🔨 creates/uses the hardware key (Keystore/StrongBox, Secure Enclave) via a
                                  small platform channel; signs the canonical approval payload
      approval_gate.dart       🔨 biometric → sign → payApprove; one place, used by every flow
    screens/
      pay_home_screen.dart     ↪ from lib/social_hub/money/oneova_pay_home_screen.dart ✅
      scan_to_pay_screen.dart  ↪ from lib/social_hub/money/scan_to_pay_screens.dart ✅
      request_incoming_sheet.dart 🔨 who, amount, memo, countdown, approve / decline
      send_screen.dart         🔨 pick by @handle or QR, amount
      success_screen.dart      🔨
      receipt_screen.dart      🔨 shows the signed receipt and its verify QR
      withdraw_screen.dart     ↪ from lib/social_hub/money/withdraw_screen.dart ✅
      history_screen.dart      ↪ from lib/social_hub/money/payments_history_screen.dart ✅
    widgets/                   amount field, balance card, request tile (built on lib/shared/widgets/compact)
  identity/                    ✅ Globe ID
    identity_service.dart, identity_vault.dart, id_photo_check.dart ✅
    screens/ oneova_id_screen, business_verify_screen, id_data_screen, id_share_sheet ✅
    devices/                   🔨 trusted devices list, step-up, revoke
  shops3d/business/            ✅ Merchant Hub (portal, orders, insights, settings)
    staff_screen.dart          🔨 roles
    statements_screen.dart     🔨
```
Rules: compact UI parts only, `AppColors`, Material icons, every screen has a back path, light and
dark checked. No amounts computed on the phone except for display; the server returns the totals.

## 2. Python back end (`services/`)
Grow the existing ledger service into **pay-core**, one deployable, clear modules:

```
services/ledger/               ✅ (rename to services/pay_core when the first new module lands)
  ledger/
    api.py        ✅ FastAPI app, routes
    auth.py       ✅ Google ID token check, allowed callers
    db.py         ✅ pool, serializable transactions
    core.py       ✅ journals, postings, idempotency
    templates.py  ✅ wallet movements
    fees.py       ✅ fee engine (basis points, minimums, caps, corridors)
    policy.py     ✅ accounts and currencies
    requests.py   🔨 payment request state machine
    approvals.py  🔨 signature verify (cryptography, ECDSA P-256), nonce store
    receipts.py   🔨 canonical body + KMS Ed25519 signing
    risk/         🔨 Sentinel
      rules.py        explainable rules
      features.py     builds features from Postgres + Firestore signals
      model.py        loads a versioned model from Cloud Storage; can only raise a decision
  migrations/     ✅ 001, 002; 🔨 003_pay_core.sql (see DATA_AND_API.md)
  tests/          ✅ ledger, fees, templates, api; 🔨 approvals, requests, risk, receipts
```
Cloud Functions (`functions/src/`) stay the edge: auth, App Check, validation, rate limits, Firestore
read model, provider webhooks, and calls into pay-core. ✅ `pay/`, `payments/`, `identity/`,
`ledger/outbox.ts`, `guard/`; 🔨 `pay/requests.ts`, `pay/devices.ts`, `pay/receipts.ts`.

## 3. Environments
| Env | Project | Money | Who |
|---|---|---|---|
| local | emulators + local Postgres (`scripts/dev.py`) | fake | developers |
| sandbox | `mpepe-2b4bd` today | provider sandboxes only | Play internal testers |
| production 🔨 | new project per region, separate billing and IAM | real, after licences 🤝 | public |
Production must be a **separate GCP project**: no shared service accounts, keys or data with sandbox.

## 4. Deployment plan
1. **Infrastructure as code** 🔨: Terraform for Cloud SQL (private IP, PITR, HA), Cloud Run (no public
   ingress, min 1 instance for pay-core), Secret Manager, KMS keyrings, Pub/Sub, VPC connector, IAM.
2. **CI** 🔨 on every pull request: `flutter analyze`, guard test, Flutter tests, `npm test` in
   functions, `pytest` in pay-core against a real Postgres container, Firestore rules tests, secret and
   dependency scanning.
3. **Release pay-core**: build image → scan → deploy a new Cloud Run revision with 0% traffic → run
   migrations (forward-only, reviewed) → smoke tests (`/health`, `/v1/reconcile`) → shift traffic
   10% → 100%. Roll back by moving traffic to the previous revision.
4. **Release functions**: deploy only the changed functions (`tools/play/guard_deploy.sh` pattern),
   with the user's OK.
5. **Release the app**: `tools/play/release.sh internal` → testers → closed → production with
   `--confirm-production` (needs the Play organization account 🤝).
6. **Operations**: dashboards for approval latency, error rates, reconcile result, outbox dead letters,
   Sentinel holds; alerts to on-call; daily reconcile alert; quarterly restore drill and key rotation
   check.

## 5. Build order (security first)
1. Device binding: `deviceRegister`, step-up, revoke, `device_key.dart`, `approval_gate.dart`.
2. Payment requests and approvals end to end (`003_pay_core.sql`, `payRequestCreate`, `payChallenge`,
   `payApprove`, incoming request sheet with countdown, success screen).
3. Signed receipts and verify.
4. Send by Oneova ID and personal QR (reuse the request/approve path).
5. Sentinel rules + review queue on oneova.web.app/admin; model later.
6. App Check enforcement, KMS envelope encryption for funding methods, separate DB roles.
7. Merchant Hub: sales from the ledger, refunds, staff roles, statements.
8. Tap / NFC, voice payments, cards 🤝.
Each step: tests, docs updated, `docs/plans/BUILD_LOG.md` updated, committed; deploys only with the
user's OK.
