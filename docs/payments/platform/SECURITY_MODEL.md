# Oneova fintech platform: security model

Security is priority one (`.agents/rules/oneova_build_vision.md`). This is the model every pay,
identity and merchant change must follow. Status keys: ✅ built · 🔨 to build · 🤝 partner.

## 1. Zero-trust principles
1. **Verify every call.** Each request carries a Firebase ID token (who), an App Check token (which
   app), and for money actions a device signature (which phone, approved by a biometric).
2. **Least privilege.** Clients never write money, balances, KYC results or risk scores: Firestore rules
   deny it and only Functions write them. pay-core accepts only the functions service account.
3. **Assume breach.** Append-only ledger, hash-chained audit, separate database roles, no shared
   secrets in code, every admin action logged and two-person approved for money.
4. **Short-lived everything.** Requests expire in 10 minutes, one-time QR codes in 15, approvals
   carry a nonce and a 60-second expiry, sessions refresh hourly.

## 2. Threats and controls

| Threat | Control | Status |
|---|---|---|
| Stolen password / session | Money needs the device key + biometric, not just a session | 🔨 device binding |
| New phone takes over an account | Step-up (biometric + PIN + email code), 24 h limit on large sends from a new device, alert to old devices | 🔨 |
| SIM swap | No SMS as a factor for money; operator SIM-swap check before payouts | 🤝 |
| Fake or modded app | App Check (Play Integrity / App Attest) enforced on money callables | 🔨 turn on enforcement |
| Tampered amount or payee | Payer signs `{requestId, amount, currency, payee, nonce, exp}`; server compares | 🔨 |
| Replay / double charge | Nonce + idempotency key per request; ledger refuses duplicates | ✅ ledger, 🔨 nonce |
| Deepfake face or voice | Certified liveness at onboarding; voice never a sole factor; no iris claims | 🤝 liveness |
| Scam requests ("pay me back") | Requester's verified name and badge shown, first-time payee warning, Sentinel holds unusual amounts | 🔨 |
| Insider abuse | Separate DB owner and app roles, no direct DB access in prod, admin actions two-person and logged | 🔨 |
| Provider webhook forgery | Signature check per provider, amounts re-fetched from the provider before crediting | ✅ |
| Money logic bugs | Ledger enforces balance, no overdraft, append-only in the database itself; daily reconcile | ✅, 🔨 alerts |
| Data leak | KMS envelope encryption for numbers and IDs, masked display, retention deletes | ✅ IDs, 🔨 payout numbers |

## 3. Authentication layers
| Layer | Used for | How |
|---|---|---|
| Account sign-in | Opening the app | Firebase Auth (email code, Google, passkeys); biometric quick sign-in ✅ |
| Device key | Approving money | 🔨 P-256 key in Android Keystore (StrongBox where present) / iOS Secure Enclave, created at registration, usable only after a biometric; public key stored server-side with attestation |
| Step-up | New device, high risk, limits raised | Biometric + 6-digit Oneova PIN (hashed with Argon2id server-side) + email code |
| Admin | oneova.web.app/admin | Google sign-in with hardware security key, role claims, IP allow list |

## 4. Key management
| Key | Where | Rotation |
|---|---|---|
| Device signing keys | Phone hardware only (never exported) | On re-registration; revoked on sign-out or report |
| Receipt and credential signing (Ed25519) | Cloud KMS (asymmetric, HSM protection level) | Yearly; old public keys kept to verify old receipts |
| Data encryption keys | Cloud KMS key per data class (payout numbers, ID numbers, documents), envelope encryption | 90 days automatic; re-wrap job |
| Provider API keys, webhook secrets | Secret Manager, read only by the functions that need them | On staff change or suspected leak; runbook in `docs/security` |
| Ledger service auth | Google-signed ID tokens (no shared secret) | Automatic |

Rules: no secret in the app bundle or `.env` that ships with it (the release script refuses), no
secret in logs, no key material in Firestore.

## 5. Fraud detection (Sentinel)
- **Every money action** gets one decision: allow, step-up, or review, with reasons stored next to the
  journal for audit.
- **Rules first:** limits by KYC level and account age, velocity caps, first-time payee caps, new-device
  caps, country and currency rules, sanctioned-party screening 🤝.
- **Model second:** gradient-boosted risk score trained on labelled outcomes; it can only raise the
  decision. Features and model versions are logged so any decision can be explained.
- **Signals:** device binding and attestation, IP and location change, velocity, counterparty graph
  (new accounts paying each other in rings), refunds and chargebacks, reports.
- **Response:** hold in `pending`, notify the user in plain words, review queue with one-tap actions,
  freeze on confirmed fraud (Ova Guard ✅).

## 6. Privacy and compliance
- Data minimisation: store only what the licence and the law need; mask numbers everywhere in the UI.
- Retention: ID documents deleted on schedule ✅; ledger entries kept for the legal period (append-only).
- User rights: data export ✅ (`/settings/data-export`), deletion that keeps the legally required
  financial records.
- Frameworks to map to before launch: Kenya Data Protection Act, Nigeria NDPA, GDPR for EU users,
  PCI DSS (only when cards arrive; card data never touches Oneova servers before then), AML/CFT rules
  of each licence.

## 7. Security testing
- Unit and property tests on the ledger and fees ✅; add tests for every approval rule.
- Firestore rules tests: clients can never write balances, requests' status or risk fields.
- Dependency and secret scanning in CI; container scanning for pay-core.
- External penetration test of pay-core and the app before real money; a bug-bounty after launch.
