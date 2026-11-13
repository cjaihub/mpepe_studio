# Oneova ledger (Phase 1)

A double-entry ledger in PostgreSQL, served by a small Python (FastAPI) service on Cloud Run.
Code: `services/ledger/`. Status: built and tested locally. **Not deployed** (Firebase/GCP billing
for mpepe-2b4bd is suspended, and deploys need your OK).

## What makes it safe

| Rule | Where it's enforced |
|---|---|
| Integer minor units only (no floats) | Python rejects non-integers; DB columns are `bigint` |
| Every journal sums to 0 per currency, ≥ 2 postings | Python check, plus a deferred constraint trigger in Postgres (checked at commit) |
| Entries can't be edited or deleted | Triggers block UPDATE, DELETE and TRUNCATE on journals, postings and audit_log |
| Balances come only from entries | A trigger maintains `balances`; direct writes are refused; `reconcile` re-sums everything |
| No overdraft | The balance trigger refuses negatives except on source and debt accounts (`OL001`) |
| Exactly once | A unique `idempotency_key`. The same key with the same body replays; with a different body it's refused (409) |
| Tamper evidence | `audit_log` is hash-chained; `GET /v1/reconcile` reports the first broken row |
| Coins can never become cash | Coins (`XCN`) and Diamonds (`XDM`) are separate currencies; no journal turns one into the other |
| No deadlocks under load | Postings are written in sorted account order |

Accounts and currencies are listed in `services/ledger/ledger/policy.py`. The wallet movements
(`coin_purchase`, `coin_void`, `gift`, `release`, `withdrawal_lock`, `withdrawal_paid`,
`withdrawal_returned`, `opening_balance`) are in `ledger/templates.py`.

## API (internal only)
`POST /v1/wallet/{template}` · `POST /v1/journals` · `GET /v1/accounts/{id}` ·
`GET /v1/accounts/{id}/entries` · `GET /v1/reconcile` · `GET /health`

Auth works in two layers. First, Cloud Run allows no unauthenticated access (IAM invoker only).
Second, every request needs a Google ID token for `LEDGER_AUDIENCE` from an email listed in
`LEDGER_ALLOWED_CALLERS` (the functions service account). `LEDGER_AUTH=off` only works together with
`LEDGER_ENV=local`.

## How the app's money reaches it: shadow mode
`functions/src/ledger/outbox.ts`:
- Every wallet change in Cloud Functions also writes `ledger_outbox/{id}` **inside the same Firestore
  transaction**. This covers coin purchases, coin refunds, live and person-to-person gifts, releases,
  withdrawal lock, paid and returned.
- `ledgerOutboxDeliver` posts each one to the ledger; `ledgerOutboxRetry` retries with backoff.
- Entries the ledger can never accept are marked `dead` for a person to look at.
- This is off until `LEDGER_OUTBOX=on` and `LEDGER_URL` are set.

Cut-over, one step at a time, each with your approval:
1. Deploy the ledger and turn the outbox on. Firestore stays the source of truth.
2. Backfill opening balances from the Firestore counters using `opening_balance` journals. Do a dry-run report first; this is the step the rules call a migration.
3. Compare daily: Firestore counters against ledger balances, plus `reconcile`. Run like this for about two weeks with zero differences.
4. Switch the reads: the wallet screens get balances from the ledger, through a function.
5. Switch the writes: functions post to the ledger first and Firestore becomes a read projection.

## Run and test locally
```bash
cd services/ledger
uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python --only-binary cryptography -r requirements-dev.txt
.venv/bin/python -m pytest -q          # 26 tests: Postgres from pgserver, no Docker needed
.venv/bin/python scripts/dev.py 8099   # local service, auth off
```
Contract test, from the functions side against that local service:
`cd functions && LEDGER_URL=http://localhost:8099 npm run test:pay`

## Deploy (needs your OK; nothing here has been run)
1. Cloud SQL for PostgreSQL 16, private IP, smallest tier. Create a database `ledger` and an app user.
2. Store the `DATABASE_URL` secret in Secret Manager.
3. Deploy to Cloud Run with `--no-allow-unauthenticated` and these env vars:
   - `LEDGER_AUDIENCE=<service url>`
   - `LEDGER_ALLOWED_CALLERS=90836164478-compute@developer.gserviceaccount.com`
   - `LEDGER_MIGRATE_ON_START=true` for the first deploy only

   Mount `DATABASE_URL` from Secret Manager.
4. Grant the functions service account `roles/run.invoker` on the service.
5. In `functions/.env.mpepe-2b4bd`: `LEDGER_URL=<service url>`, `LEDGER_OUTBOX=on`.
6. Deploy the functions and the new Firestore indexes (`ledger_outbox`).

## Needs human or legal review
- The cut-over steps above, especially the opening-balance backfill.
- Data retention for ledger and audit data (a legal hold may require keeping years of history), and backups and point-in-time recovery on Cloud SQL.
- Who may read `reconcile` and the audit log, and the access logging for that.
- Fiat accounts (USD and local currencies) arrive with the fees engine in Phase 2. Holding real customer money in them still depends on the licensing questions in `docs/AUDIT.md`.
