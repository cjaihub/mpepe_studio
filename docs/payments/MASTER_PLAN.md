# Oneova global fintech: master plan

This is the master build command (Globe ID, Oneova Pay, Sentinel, Merchant Hub), mapped onto what is
built and what comes next. The look follows the Oneova Pay mockups: balance card, Send / Request /
Bank / Scan, live requests, biometric confirm, success screen, signed receipt, history, merchant
dashboard. All of it uses Oneova colours (blue first, pink accent) and Material icons.

Status: ✅ live in mpepe-2b4bd (sandbox rails) · 🔨 next · 🤝 needs a partner, licence or contract.

Full design (architecture, security model, schema, API, code structure, deployment): `platform/`.

## 1. Money core (backend: Python + PostgreSQL ledger, Firebase Functions in TypeScript)
- ✅ Double-entry ledger in PostgreSQL on Cloud Run (`services/ledger`). Entries are append-only, every journal must balance, there is no overdraft, entries are idempotent, the audit log is hash-chained, and there's a reconcile check.
- ✅ Every money movement is mirrored from Firestore into the ledger, inside the same transaction, through the outbox.
- ✅ Fees engine (`docs/FEES.md`): basis points, minimums, caps, corridors and partner shares, in exact integer maths.
- ✅ Personal and business balances (`pay_balances`, `pay_business_balances`; accounts `user:` and `biz:`).
- 🔨 Separate database owner and app roles; read replicas; daily reconcile alerts.

## 2. Oneova Pay methods
| Method | Status |
|---|---|
| QR: merchant, static and dynamic (one-time) | ✅ scan, verify the merchant, amount, device biometric, pay; receive codes |
| Pay-ins: M-Pesa STK, MTN MoMo, card or bank via Flutterwave / Paystack | ✅ built, 🤝 live keys and merchant accounts |
| Payment requests ("John Store requested $100", approve with a biometric) | 🔨 push request → approve → pay, with a countdown like the mockup |
| Send to a person by Oneova ID (no phone or account numbers) | 🔨 P2P transfer, velocity limits, step-up above limits |
| Personal QR | 🔨 the same code system, paying into a personal balance |
| Tap / NFC and nearby (BLE) | 🔨 later; Android HCE token handshake. iOS NFC payments need Apple approval 🤝 |
| Voice ("Send Sarah $50") | 🔨 Ova parses the request, then a device biometric confirms. A voice print is never the only factor (deepfake risk) |

## 3. Globe ID (identity)
- ✅ ID and selfie KYC with an AI pre-check, then human review (`kycSubmit`, `kycReview`); business KYB with owners (`identity/`).
- ✅ Device biometrics confirm money actions: the fingerprint or face never leaves the phone (Android Keystore / Secure Enclave).
- 🔨 Device binding: a key pair created on the device signs each money request; new devices need step-up.
- 🔨 Liveness and anti-spoofing at onboarding through a certified liveness vendor (iBeta level 2) 🤝.
- Not planned as payment factors: iris/eye scanning (needs special hardware) and voice ID as a sole factor. Neither is safe on ordinary phones today.

## 4. Sentinel (risk)
- ✅ Payout fraud reasons, Ova Guard withdrawal freeze, refund clawback holds, never paying twice.
- 🔨 One risk score per action (device age, location change, velocity, amount, counterparty, SIM-swap). It decides: allow, step-up, or review queue.
- 🔨 Review queue on the admin dashboard (oneova.web.app/admin).
- 🤝 SIM-swap checks through the operator APIs (Safaricom, MTN, or GSMA Open Gateway).

## 5. Merchant Hub
- ✅ Business balance, receive codes with totals, withdraw, order escrow, store portal and insights.
- 🔨 Today's sales from the ledger, refunds from the business balance, staff accounts with roles, settlement statements (CSV and PDF).

## 6. Receipts
- 🔨 Signed receipts: transaction id, reference, both parties, amount, time, how it was approved, and a QR that checks the signature on the server (the key already exists in Secret Manager for identity credentials).

## 7. Cards
- 🤝 Virtual and physical cards need an issuing partner (a BIN sponsor). Until then the Cards tab only shows "coming soon", with no fake card numbers.

## 8. Platform
- ✅ Secrets only in Secret Manager. TLS everywhere, Cloud SQL encrypted at rest, IAM between services, App Check available.
- 🔨 Turn on App Check enforcement; KMS envelope encryption for payout account numbers; key rotation runbook.
- 🔨 Disaster recovery: point-in-time recovery is on; next are a cross-region backup copy, a restore drill, and RPO/RTO targets (15 minutes / 1 hour).
- Post-quantum: TLS hybrid key exchange comes from Google's front end; our own signatures can move to ML-DSA once Cloud KMS offers it.

## 9. Legal and partners (🤝, not code)
- E-money or PSP licence, or an agent agreement with a licensed partner, per country, before real stored balances.
- Partner merchant accounts (Safaricom Daraja, MTN MoMo, Flutterwave or Paystack).
- Play: an organization developer account and the financial-features declaration.
- Card issuing: a BIN sponsor and PCI DSS.

## Next build order
1. Payment requests with live approval and a countdown, the success screen, and signed receipts.
2. Send by Oneova ID (P2P), plus personal QR codes.
3. Sentinel risk score, step-up and device binding.
4. Merchant Hub sales from the ledger, refunds, staff and statements.
5. Tap / NFC.
