# Oneova fintech platform: architecture

Oneova Pay, Oneova Globe ID, merchant payments, Biz marketplace and Sentinel (AI security), as one
platform. Companion docs in this folder: `SECURITY_MODEL.md`, `DATA_AND_API.md`,
`CODE_AND_DEPLOYMENT.md`. Status and build order: `../MASTER_PLAN.md` and `docs/plans/BUILD_LOG.md`.

Status keys: ✅ built · 🔨 to build · 🤝 needs a partner, licence or contract.

## 1. Product rules
- **Pay by request and biometric approval.** Every payment is either a *request* someone approves, or a
  *scan/tap* the payer approves. Approval is always a device biometric on a registered device.
- **No phone or account numbers between people.** People pay an Oneova ID (`@handle`), a QR code or a
  request. A mobile-money number or bank account is linked once by its owner, stored encrypted, and
  never shown to anyone else.
- **One ledger is the truth.** All money moves as balanced double-entry journals in PostgreSQL.
- **Zero trust.** No service trusts the network or another service by default. Every call proves who
  it is, every money action proves which device approved it.

## 2. System map

```
 Phone (Flutter)                     Edge (Firebase)                      Core (Cloud Run, private)
 ─────────────────                   ───────────────────                  ───────────────────────────
 Oneova Pay UI         ──HTTPS──►   Cloud Functions (TypeScript)  ──IAM──►  pay-core  (Python FastAPI)
 Globe ID UI           App Check     • auth, App Check, rate limit           • ledger        ✅ services/ledger
 Merchant Hub UI       + Firebase    • input validation                      • requests      🔨
 Device key (Keystore/  Auth token   • risk pre-check (Sentinel)             • approvals     🔨
   Secure Enclave)     + device sig  • writes the Firestore read model       • receipts      🔨
                                     • outbox → ledger            ✅          • risk engine   🔨
                                                                             PostgreSQL (Cloud SQL, private IP)
 Firestore (read model, real-time UI)  ◄── written only by Functions          Secret Manager · Cloud KMS
 Cloud Storage (ID documents, encrypted)                                      Pub/Sub (events)  BigQuery (risk analytics)

 Partners 🤝: M-Pesa Daraja, MTN MoMo, Flutterwave / Paystack (pay-ins, payouts), liveness vendor
 (iBeta level 2), SIM-swap APIs (operators / GSMA Open Gateway), card issuer (BIN sponsor).
```

Why this split: Functions already hold Firebase Auth, App Check and the Firestore read model the app
streams from. The money core sits behind them in a private Python service with its own database, so a
bug or a stolen token at the edge can't write journals directly: the ledger accepts calls only from the
functions service account, and it refuses unbalanced, edited or overdrawn entries on its own.

## 3. Components

### 3.1 Oneova Pay
| Flow | How it works | Status |
|---|---|---|
| Top-up (pay-in) | Mobile money STK / card / bank via provider router with failover | ✅ sandbox, 🤝 live keys |
| Merchant QR (static, one-time) | Scan → server resolves the verified merchant → amount → device biometric → pay | ✅ |
| Payment request | Requester creates a request → payer gets a push → sees who, what, amount, countdown → biometric → pay | 🔨 |
| Send by Oneova ID | Pick a person by `@handle` or QR, amount, biometric. Limits per day and per new contact | 🔨 |
| Personal QR | Same signed QR format, pays into the personal balance | 🔨 |
| Receipts | Signed by the server (Ed25519 via KMS); QR on the receipt verifies the signature | 🔨 |
| Withdraw (payout) | Locked in ledger → provider → paid / returned. Never paid twice | ✅ |
| Tap / NFC, nearby | Android HCE one-time token; iOS needs Apple's NFC entitlement 🤝 | 🔨 later |
| Voice ("Send Sarah $50") | Ova fills the form; the device biometric still approves | 🔨 later |

Balances: personal (`user:`) and business (`biz:`) are separate accounts ✅. Coins (`XCN`) and Diamonds
(`XDM`) are separate currencies that can never become cash except through the creator payout path.

### 3.2 Oneova Globe ID
| Factor | Used for | Notes |
|---|---|---|
| Fingerprint / face (OS biometrics) | Approving every money action | ✅ Never leaves the phone. The OS unlocks a device key; the server checks the signature |
| Face match + liveness | Onboarding and recovery | ✅ ID + selfie with AI pre-check and human review; 🤝 certified liveness vendor (iBeta level 2) |
| Trusted device registration | Binding money actions to a phone | 🔨 Hardware-backed key pair per device; new device = step-up + 24 h cool-down on large sends |
| Eye verification | Liveness signal at onboarding only | Done by the liveness vendor (blink, gaze). **True iris recognition needs IR hardware most phones don't have, so it is not a payment factor** |
| Voice identity | Convenience signal for Ova voice commands | **Never a sole factor**: cloned voices beat voice ID. Voice can start a payment; a device biometric approves it |
| Business (KYB) | Merchant verification with owners | ✅ |

### 3.3 Merchant Hub and Biz marketplace
- ✅ Business balance, receive codes with totals, withdraw, order escrow (buyer pays → held → released
  on delivery or refunded), store portal, insights.
- 🔨 Today's sales from the ledger, refunds from the business balance, staff with roles
  (owner, manager, cashier: cashiers can receive, never withdraw), settlement statements (CSV/PDF).
- Marketplace checkout uses the same request/approve flow: the order creates a payment request to
  the buyer, the approval pays into escrow.

### 3.4 Sentinel (AI security)
One risk decision per money action: **allow**, **step-up** (biometric again + PIN or a cool-down) or
**review** (held, sent to the admin queue on oneova.web.app/admin).
- Inputs: device age and binding, attestation (Play Integrity / App Attest), location and IP change,
  velocity (count and amount per hour/day), counterparty age and history, amount vs normal for this
  user, SIM-swap signal 🤝, reports and chargebacks.
- Model: transparent rules first (explainable, auditable), then a gradient-boosted model trained on
  labelled outcomes in BigQuery. The model can only *raise* the decision (allow → step-up → review),
  never lower a rule's decision.
- ✅ already live: payout fraud reasons, Ova Guard withdrawal freeze, refund clawback holds.

## 4. The core flow: request and biometric approval

```
Requester (merchant or person)                 Server                               Payer's phone
1. POST createRequest(to=@payer, amount, memo) ─► validate, risk pre-check,
                                                  store request (expires 10 min) ──push──► 2. Shows: who (verified badge),
                                                                                              amount, memo, countdown
                                                                                           3. Biometric unlocks device key;
                                                  ◄── approveRequest(requestId, challenge,     signs {requestId, amount,
                                                       deviceId, signature)                    currency, payee, nonce, exp}
4. verify: request open, signature matches the
   registered device key, nonce unused, amount
   unchanged, Sentinel decision = allow
5. ledger journal (idempotency key = requestId)
6. signed receipt → both parties, Firestore read model updates in real time
```
What makes it safe: the payer signs the exact amount and payee, so a changed amount fails; the
nonce and the request id make it single-use; the server, not the phone, decides the risk; the ledger
refuses duplicates through the idempotency key.

## 5. Encryption: what is end-to-end and what isn't
- **In transit:** TLS 1.3 everywhere; Google's front end offers hybrid post-quantum key exchange.
- **Approvals:** signed end-to-end from the device's hardware key to pay-core. Nobody in between can
  change them.
- **Personal data at rest:** mobile-money numbers, bank details and ID numbers are envelope-encrypted
  with Cloud KMS keys (per data class), on top of Cloud SQL / Firestore encryption at rest.
- **ID documents:** encrypted in Cloud Storage, readable only by the review function and reviewers,
  deleted on the retention schedule ✅ (`idRetention`).
- **Chats about money and receipts:** end-to-end encrypted like other Oneova chats.
- **Not end-to-end:** the server must see amounts and parties to keep the ledger, apply limits and stop
  fraud. That is true of every regulated payment system; the protection is strict access, audit and
  encryption at rest, not hiding the payment from the operator.

## 6. Scale and reliability targets
- Ledger: serializable Postgres transactions, sorted posting order (no deadlocks), idempotent writes.
- Availability 99.95% for approvals; RPO 15 min, RTO 1 h (point-in-time recovery on, cross-region
  copy 🔨).
- Regions: functions run in `us-central1` today; put pay-core and Cloud SQL in the same region to keep
  approvals fast. Add a second region (for example `europe-west1`, closer to African traffic) when
  volume and licences require data residency per country.

## 7. What "production" still needs (not code)
- 🤝 E-money or PSP licence, or an agent agreement with a licensed partner, per country, before real
  stored balances.
- 🤝 Live merchant accounts with Safaricom, MTN, Flutterwave or Paystack.
- 🤝 Play organization developer account and the financial-features declaration.
- 🤝 Certified liveness vendor; SIM-swap API access; card issuing partner and PCI DSS for cards.
- External penetration test and a security audit of pay-core before launch.
