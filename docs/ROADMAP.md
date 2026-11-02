# Oneova Pay roadmap

Goal: one fast, secure way to pay. Scan a QR code, confirm, and the money is taken from a connected
mobile-money or bank account. Plus a digital card and full account opening, in Oneova's own brand
(blue #0C4FA8 first, pink #FF2D87 accent). Equity Bank's app is visual inspiration only.

Rules for every phase: no money logic in Flutter; secrets only in Secret Manager or env; sandbox and test
mode only; a feature branch with small commits; tests and `docs/` updated at the end of each phase;
ask before any deploy, destructive migration or live-money action. **Each phase is checked with the
user before it starts.**

Method (from the "MVP, test, then expand" approach): every phase ships a thin **MVP slice** with an exit
test before anything wider. Pay-ins, chat-style extras and cards don't start until the money core has
been shown to be correct.

---

## Decision needed before Phase 1: stack

| Option | Pros | Cons |
|---|---|---|
| **A. TypeScript on Cloud Run + Cloud SQL Postgres (recommended)** | same language as `functions/src`; shared types and validators; one CI and toolchain; Functions call it over private IAM | not Python |
| B. Python (FastAPI) on Cloud Run + Cloud SQL Postgres | what you asked for; strong for data and risk work | second language and toolchain; types duplicated across the boundary |

Both give the same design: Postgres (`SERIALIZABLE` transactions, `bigint` minor units, append-only
tables enforced by triggers and grants), Cloud Run with no public ingress (Functions call it with an IAM
ID token), Cloud SQL private IP, migrations in git, and Secret Manager.
Cost note: Cloud SQL starts at roughly $10–30 a month for a small instance. Firestore stays the read
model for the app.

Where Oneova sits in a card or bank flow (customer → merchant → gateway → acquirer/processor → scheme →
issuer, with fraud screening alongside): Oneova is the **wallet + gateway + merchant-of-record
orchestration layer**. Acquiring, scheme membership and issuing come from licensed partners (Stripe,
Flutterwave, Paystack, a bank, MNOs). Build the ledger, rules, routing, risk and UX ourselves. Buy
Identity, Radar, Connect, Financial Connections and Issuing where they're available in the country.

---

## Phase 0.5: stop the bleeding (small fixes to existing code, if approved)
These are the critical audit items. They're small and independent of the new platform.
1. Handle Play voided purchases for coins (scheduled Voided Purchases API poll → claw back pending Diamonds, freeze if negative).
2. In `dispatch()`, don't refund on an ambiguous error. Mark it `unknown` and reconcile by querying the provider by reference.
3. Add an idempotency key to `sendUserGift`, and check amount and currency in the escrow webhook.
4. Remove the fake `PaymentProviderService` and move the two screens off the client `LedgerService`.
- Exit test: unit tests for each fix; existing `payoutLogic` tests still pass. No deploy without a yes.

## Phase 1: the ledger
- **MVP slice:** a `ledger` service with `accounts`, `journal` (transactions), `postings` (≥ 2 lines, sum = 0 per currency), `idempotency_keys`, `audit_log`. Balances = SUM(postings), plus a cached `balances` table updated in the same transaction and checked nightly.
- Integer minor units (`bigint`) with an ISO-4217 exponent table. Coins and Diamonds are their own "currencies" (`XCN`, `XDM`), so they can never mix with fiat.
- APIs: `post(journal, idempotencyKey)`, `hold/release/capture`, `balance(account)`, `history(account, cursor)`.
- Move Diamonds release, withdrawals and gifts to post through the ledger. Firestore `wallets/{uid}` becomes a **projection** written by the service.
- One-time backfill from current counters into opening-balance journals (**destructive-adjacent: ask first**; dry-run report first).
- Exit test: property tests (random postings never break sum = 0; replaying the same idempotency key does nothing), concurrency test (100 parallel debits never overdraw), reconciliation job green against the backfill.

## Phase 2: fees engine
- Versioned rules in config (Postgres table + `docs/FEES.md`): percentage, minimum, cap, flat amount, per corridor (from-country → to-country, rail), per-partner revenue share, effective-from dates.
- The quote returns the breakdown, and the same rule version is used at posting time. Each fee is its own posting to `fees:revenue` and `partner:{id}:share` accounts.
- Exit test: a table of worked examples in `FEES.md` runs as tests (rounding half-even in minor units).

## Phase 3: partner layer
- An `PaymentProvider` interface: `collect` (pay-in), `payout`, `status(ref)`, `verifyWebhook`, `normalizeEvent`, `capabilities(country, rail)`.
- A **mock provider** first (deterministic success, failure, timeout and late-webhook scenarios).
- Sandbox adapters: M-Pesa Daraja (STK push + B2C), MTN MoMo (collections + disbursements), Flutterwave and Paystack (moved over from today's code), and one bank partner's sandbox (or Stripe Financial Connections where supported).
- Routing: score providers by health, cost and success rate per corridor; on a timeout or 5xx, **check status before failing over** so the same payment is never sent twice. A circuit breaker per provider.
- Daily reconciliation against provider statements → a break report.
- Exit test: chaos tests with the mock (provider A down → B used once, no double payout).

## Phase 4: security and risk
- Device binding (a key pair in the Android Keystore / iOS Secure Enclave, server-registered; payment requests signed).
- Step-up 2FA (biometric + OTP) above thresholds, and for new payees or devices.
- SIM-swap check before payouts and at login on a new device (MNO or aggregator API, sandbox).
- Velocity limits per KYC tier; a risk score (rules first, ML later) folded into today's `fraudReasons`.
- A review queue for live agents: claim, approve or reject with a reason, four-eyes above a limit, full audit; admin as a custom claim plus MFA.
- Enforce App Check on money callables.
- Exit test: abuse scenarios scripted against the emulator.

## Phase 5: partner portal and API
- Partner API keys (hashed, scoped, rotatable), signed webhooks with retries, a sandbox environment with test keys, per-partner dashboards, and settlement and statement reports for banks (CSV + API).
- Exit test: a partner can onboard in the sandbox end-to-end with the docs alone.

## Track U: Flutter UI (runs alongside, display and calls only)
- **Scan-to-pay:** the camera opens instantly → parse the merchant QR (an EMVCo-style payload signed by Oneova) → a confirm sheet (merchant, amount, fee, source account) → biometric → pay → receipt. Target: under 3 seconds from scan to receipt on the happy path.
- **Account opening:** phone → basic info → ID + selfie (Stripe Identity or a regional KYC vendor) → tier shown with limits.
- **Digital card screen:** card art in Oneova brand; number masked; reveal through the issuer's secure SDK only (we never see the PAN). Shows "coming soon" until an issuer is signed, with no fake card numbers.
- **Home "money" layouts:** balances, quick actions (Scan, Send, Pay bill, Top up), recent activity. Inspired by modern mobile-banking layouts, built from Oneova `AppColors` and Material Icons only.
- Each screen ships after the backend endpoint it calls exists in the sandbox.

## Order and slicing (story map)

| | Auth / KYC | Pay | Accounts | Partners | Risk |
|---|---|---|---|---|---|
| **MVP 1** | phone + Stripe Identity (exists) | ledger + payouts (exist, moved over) | Diamonds/coins on ledger | mock + Flutterwave/Paystack | 0.5 fixes, velocity |
| **MVP 2** | tiered KYC, account opening | scan-to-pay with momo collect (sandbox) | fiat wallet (only if licensed) | M-Pesa, MTN, failover | device binding, step-up |
| **MVP 3** | sanctions/PEP screening | bank debit, bills | digital card (issuer) | partner portal and API | SIM-swap, review queue |

Out of scope: crypto (licensing and Play policy load with no clear user need right now).

## Needs human or legal review (standing list)
- The licence or partner model per country before any real-money stored value or pay-in goes live.
- KYC/AML programme: tiers, limits, sanctions screening provider, STR reporting owner.
- Card issuing: BIN sponsor, PCI DSS scope, scheme rules.
- Play Console financial-features declaration; keep coins and fiat separate.
- Data protection impact assessment for KYC and payout data.
- Corporate structure (a regulated entity or a partner-agent model).
