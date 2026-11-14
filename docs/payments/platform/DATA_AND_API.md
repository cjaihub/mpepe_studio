# Oneova fintech platform: database schema and API

Two stores, each with one job:
- **PostgreSQL (Cloud SQL, private)**: the money and identity truth. Append-only where it matters.
- **Firestore**: the real-time read model the app streams. Written only by Cloud Functions.

Status keys: ✅ built · 🔨 to build (planned migration `003_pay_core.sql`).

## 1. PostgreSQL

### 1.1 Ledger ✅ (`services/ledger/migrations/001_init.sql`, `002_order_accounts.sql`)
| Table | Purpose | Key rules (enforced in the database) |
|---|---|---|
| `currencies` | ISO codes + exponent, plus `XCN` coins and `XDM` Diamonds | |
| `accounts` | `u:{uid}:…`, `biz:…`, `sys:…`, `p:…` (provider) accounts per currency | `allow_negative` only for source/debt accounts |
| `journals` | One money movement | unique `idempotency_key`, `request_hash` (same key + different body = refused) |
| `postings` | Signed `bigint` minor units per account | sum 0 per currency per journal, ≥ 2 postings, append-only |
| `balances` | Running balance per account | written only by trigger; no overdraft (`OL001`) |
| `audit_log` | Hash-chained log | append-only; `GET /v1/reconcile` finds a broken link |

### 1.2 Pay core 🔨 (`003_pay_core.sql`)
```sql
-- Registered devices: the public half of a hardware key that only unlocks after a biometric.
CREATE TABLE devices (
  id uuid PRIMARY KEY,
  uid text NOT NULL,
  public_key bytea NOT NULL,               -- P-256 SubjectPublicKeyInfo
  attestation jsonb NOT NULL,              -- Play Integrity / App Attest verdict at registration
  platform text NOT NULL CHECK (platform IN ('android','ios')),
  label text NOT NULL DEFAULT '',
  trusted_at timestamptz,                  -- null until step-up passed; cool-down counts from here
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX devices_uid ON devices (uid) WHERE revoked_at IS NULL;

-- A payment someone asked for, or a scan/tap the payer started.
CREATE TABLE payment_requests (
  id uuid PRIMARY KEY,
  kind text NOT NULL CHECK (kind IN ('request','merchant_qr','personal_qr','send','checkout','nfc')),
  payee_account text NOT NULL,             -- ledger account that receives
  payer_uid text,                          -- null for open QR until scanned
  amount bigint NOT NULL CHECK (amount > 0),
  currency text NOT NULL REFERENCES currencies(code),
  memo text NOT NULL DEFAULT '' CHECK (length(memo) <= 140),
  order_id text,                           -- Biz marketplace order (escrow)
  status text NOT NULL CHECK (status IN ('open','approved','declined','expired','held','paid','failed')),
  expires_at timestamptz NOT NULL,
  created_by text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  journal_id uuid REFERENCES journals(id)  -- set once paid
);
CREATE INDEX payment_requests_payer_open ON payment_requests (payer_uid) WHERE status = 'open';

-- The signed approval. One per request; the nonce makes it single-use.
CREATE TABLE approvals (
  request_id uuid PRIMARY KEY REFERENCES payment_requests(id),
  device_id uuid NOT NULL REFERENCES devices(id),
  nonce bytea NOT NULL UNIQUE,
  signed_payload bytea NOT NULL,           -- canonical JSON the device signed
  signature bytea NOT NULL,
  method text NOT NULL CHECK (method IN ('biometric','biometric_pin')),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Server-signed receipts (Ed25519 key in Cloud KMS).
CREATE TABLE receipts (
  id uuid PRIMARY KEY,
  journal_id uuid NOT NULL UNIQUE REFERENCES journals(id),
  body jsonb NOT NULL,                     -- parties (Oneova IDs, never numbers), amount, time, approval method
  key_version text NOT NULL,
  signature bytea NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Sentinel decisions, one per money action, kept for audit and model training.
CREATE TABLE risk_decisions (
  id bigserial PRIMARY KEY,
  subject text NOT NULL,                   -- request id, withdrawal id, …
  uid text NOT NULL,
  decision text NOT NULL CHECK (decision IN ('allow','step_up','review','block')),
  score real,
  rules text[] NOT NULL DEFAULT '{}',      -- rule ids that fired
  model_version text,
  features jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Limits per user (by KYC level), changed only by policy or reviewed admin action.
CREATE TABLE limits (
  uid text PRIMARY KEY,
  kyc_level smallint NOT NULL DEFAULT 0,
  daily_send bigint NOT NULL,
  single_send bigint NOT NULL,
  currency text NOT NULL REFERENCES currencies(code),
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by text NOT NULL
);

-- Merchant staff and roles.
CREATE TABLE merchant_staff (
  business_id text NOT NULL,
  uid text NOT NULL,
  role text NOT NULL CHECK (role IN ('owner','manager','cashier')),
  added_by text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (business_id, uid)
);

-- Linked pay-in / payout methods. The number itself is KMS envelope-encrypted.
CREATE TABLE funding_methods (
  id uuid PRIMARY KEY,
  uid text NOT NULL,
  kind text NOT NULL CHECK (kind IN ('mpesa','mtn_momo','bank','card_token')),
  ciphertext bytea NOT NULL,
  wrapped_dek bytea NOT NULL,
  kms_key_version text NOT NULL,
  display text NOT NULL,                   -- masked, e.g. "M-Pesa ••• 4821"
  verified_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
```
Append-only triggers (as in `001_init.sql`) also apply to `approvals`, `receipts` and `risk_decisions`.
Status changes on `payment_requests` go through one function that checks allowed transitions
(`open → approved → paid`, `open → declined|expired`, `approved → held → paid|failed`).

## 2. Firestore read model (written only by Functions)
| Collection | What the app streams | Notes |
|---|---|---|
| `pay_balances/{uid}`, `pay_business_balances/{uid}` ✅ | balances per currency | mirrors the ledger |
| `pay_requests/{id}` 🔨 | open requests for the payer, sent requests for the requester | countdown from `expiresAt` |
| `pay_receipts/{id}` 🔨 | receipt body + signature | both parties can read |
| `pay_qr/{code}` ✅ | merchant/personal codes | no amounts on static codes |
| `kyc/{uid}`, `kyb/{id}` ✅ | status only, never documents | |
Firestore rules: every `pay_*` collection is read-only for its parties and write-denied for clients.

## 3. API
All app calls are Firebase **callable** functions: Firebase Auth required, App Check enforced on money
calls 🔨, rate limited per user and IP (`guard/protect`) ✅. Money calls also need a device signature.
Errors use `HttpsError` codes with a plain-language message.

### 3.1 Existing ✅
| Callable | Does |
|---|---|
| `payQrCreate`, `payQrResolve`, `payQrList`, `payQrDisable` | Merchant receive codes |
| `payMoveToPersonal` | Business → personal balance |
| `payWithdraw`, `payBalanceReconcile` | Payouts |
| `kycSubmit`, `kycReview`; `kybStart`, `kybSubmit`, `kybOwnerRespond`, `kybReview`, `kybDelete` | Identity and business checks |
| `biometricSignIn` (+ key registration) | Fingerprint/face quick sign-in |

### 3.2 New 🔨
| Callable | Input | Output | Checks |
|---|---|---|---|
| `deviceRegister` | `publicKey`, `attestation`, `label` | `deviceId`, `trustedAt` (null until step-up) | attestation verdict, max 5 devices |
| `deviceStepUp` | `deviceId`, `pin`, `emailCode` | `trustedAt` | Argon2id PIN check, attempt limits |
| `deviceRevoke` | `deviceId` | ok | owner only; alert other devices |
| `payRequestCreate` | `to` (`@handle` or uid), `amount`, `currency`, `memo`, `orderId?` | `requestId`, `expiresAt` | requester verified for business requests, Sentinel pre-check |
| `paySendStart` | `to`, `amount`, `currency`, `memo` | `requestId`, `challenge` | limits, first-payee warning flag |
| `payChallenge` | `requestId` | `challenge` = canonical payload + `nonce` + `exp` (60 s) | payer is the request's payer |
| `payApprove` | `requestId`, `deviceId`, `signature` | `status`, `receiptId` | signature, device trusted and not revoked, nonce unused, Sentinel = allow |
| `payDecline` | `requestId` | ok | payer only |
| `payReceiptVerify` | `receiptId` or QR payload | `valid`, `body` | public, rate limited |
| `merchantStaffSet` | `businessId`, `uid`, `role` | ok | owner only |
| `merchantStatement` | `businessId`, `from`, `to`, `format` | signed download URL | owner/manager |

### 3.3 pay-core (internal, IAM only)
Existing ledger ✅: `POST /v1/journals`, `POST /v1/wallet/{template}`, `GET /v1/accounts/{id}`,
`GET /v1/accounts/{id}/entries`, `POST /v1/fees/quote`, `GET /v1/reconcile`, `GET /health`.
New 🔨: `POST /v1/requests/{id}/settle` (verifies approval → journal → receipt, one transaction),
`POST /v1/risk/decide`, `POST /v1/receipts/sign`, `GET /v1/merchants/{id}/sales`.

### 3.4 Canonical approval payload
```json
{"v":1,"requestId":"…","payee":"biz:shop_123","amount":10000,"currency":"KES",
 "nonce":"base64url-16-bytes","exp":1763112000}
```
Keys sorted, no spaces, UTF-8; the device signs SHA-256 of these bytes with ECDSA P-256.
