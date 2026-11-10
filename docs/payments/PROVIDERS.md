# Oneova Pay: providers and the Phase 0.5 fixes

Branch: `feat/oneova-pay-hardening`. Nothing is deployed. Firebase billing for mpepe-2b4bd is
suspended, so all of this is built and tested locally only.

## Provider layer (`functions/src/payments/`)

| File | What it does |
|---|---|
| `provider.ts` | `PaymentProvider` interface, integer minor units (`toMinor` / `toMajor`), and `callJson`, which sorts every HTTP reply into ok, client_error or unknown |
| `router.ts` | `routePayout`: preference order, a circuit breaker per provider, failover; `reconcileAction` |
| `adapters.ts` | Flutterwave, Paystack and Stripe Transfers adapters, plus each one's reconcile policy |
| `mockProvider.ts` | deterministic scenarios, chosen by the amount's last two digits, for tests and sandbox drills |

The money-safety rule, enforced in the router and covered by tests:

- **accepted:** the provider has it; a webhook finishes it.
- **rejected:** the provider took nothing; give the money back, or fail over if the refusal is retryable.
- **unknown** (timeout, 5xx, unreadable reply): **never refund and never fail over.** The payout stays `processing` with `needsCheck`, and `payoutReconcile` (every 15 minutes) asks the provider later.

| Provider | Status lookup | When `not_found` may refund |
|---|---|---|
| Paystack | `GET /transfer/verify/:reference` (documented) | after 1 hour |
| Flutterwave | `GET /v3/transfers?reference=`; only an item with our exact reference counts | never; goes to review after 24 hours |
| Stripe | re-sends with the same idempotency key (Stripe replays the original result) | n/a |

Note: check that Flutterwave's `reference` filter works in the sandbox. If it's ignored, the adapter
still only trusts an exact match, so the worst case is a review, not a double payout.

To add a partner (M-Pesa Daraja, MTN MoMo, pawaPay, a bank): implement `PaymentProvider`, add its
`POLICY` entry, add it to `adapterFor` in `creator/payouts.ts`, and add tests that run the mock
scenarios against it.

## Phase 0.5 fixes

1. **Refunded coin packs** (`coins/voidedPurchases.ts`, `coins/clawbackLogic.ts`):
   - Play's `voidedPurchaseNotification` arrives on the existing `play-billing` topic, and the `coinVoidSweep` job runs every 6 hours as a backstop. Each void is applied once (`coin_voids/{tokenHash}`).
   - Coins are taken from the buyer's balance first. Anything already spent becomes `coinDebt`, which the next pack pays off first.
   - If any coins were already spent, the buyer and everyone they gifted since that purchase get a `payout_holds/{uid}` entry, so their next withdrawal goes to review. Diamonds are never taken from a creator automatically.
2. **Payouts with unclear replies** (`creator/payouts.ts`):
   - `dispatch` uses the adapters and the router.
   - Accepted payouts that never get a webhook are checked after 6 hours.
   - `reviewWithdrawal` with approve on a payout still `processing` means "I saw it paid in the provider dashboard", and it settles as paid.
3. **Gifts charged twice:** `sendUserGift` and `lsGift` accept a `requestId`. The same id gives the same ledger doc, so a retry charges nothing. The app sends a fresh UUID per tap.
4. **Escrow webhook:** if the PaymentIntent's amount or currency differs from the order, the order is marked `payment_mismatch` instead of paid.
5. **Client clean-up:** removed the always-successful `PaymentProviderService`, the client-written `ledgers/` service and the unrouted `earnings_screen.dart`. The Monetization screen now shows the server wallet and opens `/wallet/withdraw`.

## Tests
- `cd functions && npm run test:pay` runs 22 tests: routing, failover, the no-double-payout cases, the circuit breaker, reconcile rules, HTTP classification, minor units, clawback and gift ids.
- `npm test` (48) and `npm run test:livestudio` (260) pass.
- `flutter test test/guards/home_lock_test.dart` passes, and `flutter analyze` shows no errors.

## Waiting on you (nothing here is done without your OK)
- **Firebase billing:** pay the balance so anything can be deployed.
- **Deploy:** `coinVoidSweep`, `payoutReconcile`, and the updated `verifyCoinPurchase`, `sendUserGift`, `lsGift`, `requestWithdrawal`, `reviewWithdrawal`, `playBillingNotifications` and `stripeWebhook`.
- **Play Console:** make sure Real-time developer notifications are on for the `play-billing` topic. Voided notifications use the same topic.
- **Admin dashboard:** a way to view and clear `payout_holds` (admin tools belong on oneova.web.app/admin).
- **Policy:** the 7-day Diamond hold is shorter than Play's refund window. Decide whether to raise it.
- **Partners:** sandbox keys and agreements for M-Pesa Daraja, MTN MoMo and pawaPay or Onafriq, so their adapters can be built and tested.
- **Phase 1 stack:** TypeScript (recommended) or Python for the ledger service.
