# Oneova payments audit (Phase 0)

Date: 2026-10-31 · Branch at audit time: `feat/settings-autosave-reels-theme-nav-icons` (HEAD `44a6c585`)
Scope: everything that moves or records value: coins, Diamonds, withdrawals, KYC, Biz escrow and plans.
No code was changed for this audit.

---

## 1. Architecture today

```
Flutter app (Riverpod, go_router)
  │  reads: Firestore streams (wallets/{uid}, ledger, withdrawals, kyc, payout_methods)
  │  writes: none on money docs (rules deny); everything else via callables
  ▼
Firebase Functions v2 (TypeScript, Node 22, project mpepe-2b4bd)
  ├─ coins/coinEconomy.ts         Play Billing coin packs → balanceCoins; person-to-person gifts
  ├─ liveStudio/gifts.ts          live gifts (same wallet fields)
  ├─ creator/payouts.ts           Diamonds hold/release, payout methods, withdrawals, FX
  ├─ creator/payoutLogic.ts       pure rules (fees, rails, fraud reasons), unit tested
  ├─ creator/kyc.ts               Stripe Identity (hosted ID + selfie)
  ├─ creator/planSubscriptions.ts Play subscriptions Plus/Pro/Biz + RTDN
  └─ commerce/stripeEscrow.ts     Biz orders on Stripe Connect, escrow until handover code
  ▼
Firestore (source of truth for balances) · Secret Manager (optionalSecret, read at run time)
External: Google Play Developer API, Stripe (Connect, Identity, PaymentIntents),
          Flutterwave, Paystack, open.er-api.com (FX), Google Maps (geocode, directions)
```

Secrets: `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_PAYOUTS_WEBHOOK_SECRET`,
`FLUTTERWAVE_SECRET_KEY`, `FLUTTERWAVE_WEBHOOK_HASH`, `PAYSTACK_SECRET_KEY`, `GOOGLE_MAPS_SERVER_KEY`,
all read through `functions/src/optionalSecrets.ts`. If a secret is missing, its rail just turns off.
`STRIPE_PUBLISHABLE_KEY` is a param in `functions/.env.mpepe-2b4bd`, which is gitignored.

Deploy state (from the hand-over brief, not re-verified): `stripeConfig` is live. `createOrderCheckout`,
`stripeWebhook` and the other escrow functions are **not deployed**.
The brief mentions separate `oc*` Stripe functions. **No `oc*` identifiers exist anywhere in
`functions/src` or `lib/`.** They are either deployed from another codebase or only exist in the
console, and need a human to check (`firebase functions:list`).

## 2. How the wallet works today

One Firestore doc per user, `wallets/{uid}`, holds **mutable counters**:

| Field | Meaning | Written by |
|---|---|---|
| `balanceCoins` | purchased coins (Play credit, never withdrawable) | verifyCoinPurchase, sendUserGift, lsGift |
| `pendingCoins` | Diamonds earned, held 7 days | gifts |
| `availableCoins` | Diamonds withdrawable | walletSync/releaseMatured, settle |
| `lockedCoins` | Diamonds inside an open withdrawal | requestWithdrawal, settle |
| `withdrawnCoins`, `lifetimeEarnedCoins` | totals | settle, release |

`wallets/{uid}/ledger/{id}` is a **single-entry history log** next to the counters. The counters are
the source of truth and the log is not used to derive them. Ledger docs are also **updated in place**:
status goes from pending to available or completed.

Flows:
- **Buy coins:** Play purchase → `verifyCoinPurchase` → the token hash in `coin_purchases` gives exactly-once crediting → `balanceCoins += n`.
- **Gift:** sender `balanceCoins -= total`; receiver `pendingCoins += ceil(total × 0.5)`.
- **Release:** `walletSync` moves ledger entries older than 7 days from pending to available.
- **Withdraw:** KYC verified → payout method (sensitive data stored in `payout_method_secrets`) → `requestWithdrawal` (an idempotency key, velocity and fraud reasons, lock Diamonds) → `dispatch` to Stripe Transfer, Flutterwave or Paystack → webhook → `settle`.
- **Biz order:** PaymentIntent on the platform → webhook marks the order paid → the buyer enters a 4-digit handover code → Transfers to the seller and rider.

Client: `lib/backend/money/money_service.dart` only reads streams and calls callables. That's good.

## 3. Security risks (ranked)

### Critical
1. **Coin refund abuse turns into cash.** Nothing handles Play *voided* purchases or refunds for coins: there's no Voided Purchases API poll and no RTDN for one-time products. Someone can buy coins, gift them to a second account they control, refund the purchase on Play, and after 7 days the second account withdraws 50% as real money. The 7-day hold is shorter than Play's refund and chargeback window.
2. **Money moved but recorded as failed.** In `payouts.ts` `dispatch()`, any exception after the provider request is sent (a timeout, or a JSON parse error on a 5xx) calls `settle(failed)` and **returns the Diamonds**, even though Flutterwave or Paystack may already have paid out. The user can then withdraw again, so they get paid twice. Flutterwave transfers have no idempotency header, and failures are not reconciled against the provider.
3. **No real ledger.** Balances are counters changed with `FieldValue.increment`. Nothing proves that sum(entries) = balance, there's no daily reconciliation, entries are mutable, and there's no audit log of who changed what. Any bug in a function silently creates or destroys value.

### High
4. **Floating-point money.** USD amounts are `number` with `Math.round(x*100)/100` (fees, netUsd, FX), as are escrow `price × qty` and `sellerShare`. Rounding drift and off-by-one-cent transfers will happen.
5. **The escrow webhook doesn't check the amount.** `payment_intent.succeeded` marks the order paid without comparing `pi.amount` or `currency` against the order. Today the server sets the amount, so the risk is low, but it's a missing invariant.
6. **Product price and currency are client-written.** The `products` rule lets the owner write any `price` or `currency`, and stock is never decremented. A seller can change the price between the quote and checkout. Checkout reads it live, so the buyer pays the new price.
7. **`sendUserGift` has no idempotency key.** Its id is `uid_Date.now()`, so a client retry charges the sender twice.
8. **Sensitive payout data is stored in plaintext.** `payout_method_secrets` holds MSISDNs and bank account numbers as plain fields. Rules deny client reads, but there's no field encryption (KMS) and no access logging.
9. **A fake payment service is in the codebase.** `lib/backend/finance/services/payment_provider_service.dart` always returns success with a hard-coded `pi_…` id. It isn't referenced today, but it's a landmine. `lib/backend/finance/services/ledger_service.dart` writes `ledgers/{uid}/entries` **from the client** and sums balances as `double`. The rules deny that collection, so it fails closed, but `monetization_dashboard.dart` and `earnings_screen.dart` still use it and show a balance that's wrong or always zero.
10. **App Check is not enforced.** `APP_CHECK_ENFORCE` is off, so the money callables accept calls from scripts with a valid ID token.

### Medium
11. Admin is `users/{uid}.role == 'admin'`, checked inside functions and rules. The users rule protects privilege fields (`keepsPrivilegesOn*`), but admin should be a **custom claim** with MFA, and `reviewWithdrawal` has no four-eyes approval or reason code.
12. FX comes from a free public endpoint (open.er-api.com) with no second source, no spread policy and no rate lock shown to the user before confirming.
13. A legacy `withdrawal_requests` collection still allows client `create`. No function processes it, so it's harmless but confusing. Remove it in a later phase. That needs a rules change, so ask first.
14. The Biz escrow release can get stuck in `releasing` if the function dies between the claim and the transfers. There's no sweeper. The `release_failed` path also needs an ops queue.
15. Fees are hard-coded in `payoutFeeUsd` and `COMMERCE_COMMISSION_PERCENT`. There's no config, no versioning and no fee ledger entry. Fees are just the difference between gross and net.

### Exposed keys
- No Stripe, Flutterwave or Paystack secrets are in the repo (checked with `git grep` for `sk_`, `whsec_`, `FLWSECK` and `rk_live`).
- Firebase **web/Android/iOS API keys** are committed (`google-services.json`, `GoogleService-Info.plist`, `lib/firebase_options.dart`, `documentation_web`, `desktop_agent/test_firestore.py`). These are public identifiers by design, but they should be **restricted by app and API** in the Cloud console, and App Check should be enforced.

## 4. Play Store policy check
- Coins and plans go through Play Billing ✅.
- Stripe is used for **physical goods and delivery** (Biz) ✅. That's allowed.
- Scan-to-pay, P2P transfers and a stored-value wallet holding **real money** are not "digital goods", so Play Billing doesn't apply to them. They do bring Play's **financial services** declaration and, per country, a licence requirement (an e-money or PSP licence, or operating as a partner bank's or MNO's agent).
- **Coins must never be convertible into the real-money wallet**, or the Play Billing exemption breaks. Diamonds → cash payout is the TikTok-style creator model and is accepted.

## 5. Gap list against the goal

| Capability | Today | Gap |
|---|---|---|
| Double-entry ledger | counters + mutable log | everything (Phase 1) |
| Idempotency | withdrawals and coin purchases only | gifts, all future postings |
| Integer minor units | coins are ints; USD and local amounts are floats | everything in fiat |
| Fees engine | hard-coded | config, versioning, own ledger entries (Phase 2) |
| Provider abstraction | if/else in `dispatch()` | adapter interface, mock, sandbox adapters, failover (Phase 3) |
| Pay-ins (collect from momo or bank) | none (Stripe card for Biz only) | M-Pesa STK push, MTN collections, bank debit (Phase 3) |
| Reconciliation | none | daily provider statement matching (Phases 1 and 3) |
| Device binding / 2FA for money | device age heuristic only | bound device keys, step-up OTP or biometric (Phase 4) |
| SIM-swap check | none | MNO API (e.g. Africa's Talking or the operator's GSMA Open Gateway) (Phase 4) |
| Risk scoring and review queue | `fraudReasons()` + `review` flag, admin callable | scored engine, queue UI for agents, audit (Phase 4) |
| KYC tiers | Stripe Identity, one tier | tiered limits (phone only → ID → address), sanctions/PEP screening |
| Partner API and portal | none | keys, webhooks, sandbox, reports (Phase 5) |
| Scan-to-pay | none (only the escrow handover code) | merchant QR (EMVCo-style payload), confirm, pay |
| Digital card | none | needs an issuing partner; UI only until then |
| Account opening | KYC for creators only | full onboarding flow tied to tiers |

## 6. Needs human or legal review now
- Whether Oneova may hold customer funds at all: e-money, PSP or agent licensing in each launch country (e.g. CBK in Kenya, BoT in Tanzania, BoU in Uganda).
- Coin-refund exposure: decide on a hold of 30+ days or a clawback policy.
- Card issuing: needs a BIN sponsor or issuing programme (e.g. Stripe Issuing where supported, or a regional issuer). That means PCI DSS scope and a scheme agreement.
- Data protection: payout account numbers and KYC data under Kenya's DPA, Nigeria's NDPA and GDPR.
- Equity Bank: use visual inspiration only. Their name, logo, colours and copy must not be used.
- The corporate structure for a regulated subsidiary, if one is needed (this also affects any later exit or IPO).
