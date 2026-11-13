/**
 * Shadow mode for the Postgres ledger (services/ledger).
 *
 *   money function's Firestore transaction → also writes ledger_outbox/{id}
 *   ledgerOutboxDeliver (on create)       → POST {LEDGER_URL}/v1/wallet/{template}
 *   ledgerOutboxRetry (every 10 min)      → re-sends pending/failed ones with backoff
 *
 * The outbox write is inside the same transaction as the wallet change, so the
 * ledger gets every movement exactly once (its idempotency key = the outbox key).
 * Firestore stays the source of truth until reconciliation is green; then the
 * functions read balances from the ledger instead (cut-over, with approval).
 *
 * Off unless LEDGER_OUTBOX=on (functions/.env.<project>). LEDGER_URL is the
 * Cloud Run URL; calls carry a Google ID token for that audience.
 */
import * as crypto from 'crypto';
import { GoogleAuth } from 'google-auth-library';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as logger from 'firebase-functions/logger';
import { getFirestore, FieldValue, Timestamp, Transaction } from 'firebase-admin/firestore';

const db = () => getFirestore();
const MAX_ATTEMPTS = 12;

export type LedgerTemplate =
  | 'coin_purchase' | 'coin_void' | 'gift' | 'release'
  | 'withdrawal_lock' | 'withdrawal_paid' | 'withdrawal_returned' | 'opening_balance'
  | 'payout_cash' | 'biz_order_paid' | 'biz_order_release';

export const outboxEnabled = () => process.env.LEDGER_OUTBOX === 'on';

export const outboxId = (key: string) => crypto.createHash('sha256').update(key).digest('hex').slice(0, 40);

/** Queues one ledger movement inside the caller's transaction (no-op when off). */
export function ledgerOutbox(tx: Transaction, key: string, template: LedgerTemplate, args: Record<string, unknown>): void {
  if (!outboxEnabled()) return;
  tx.set(db().doc(`ledger_outbox/${outboxId(key)}`), {
    key, template, args, status: 'pending', attempts: 0, createdAt: FieldValue.serverTimestamp(),
  });
}

/** Backoff before attempt n (1-based): 1, 2, 4 ... minutes, capped at 6 h. */
export function nextDelayMs(attempts: number): number {
  return Math.min(6 * 3600_000, 60_000 * 2 ** Math.max(0, attempts - 1));
}

/** 4xx other than "insufficient funds" won't succeed on retry. */
export function isPermanent(status: number): boolean {
  return status >= 400 && status < 500 && status !== 422 && status !== 429 && status !== 408;
}

let client: Awaited<ReturnType<GoogleAuth['getIdTokenClient']>> | null = null;

export async function send(template: string, key: string, args: unknown): Promise<{ status: number; body: any }> {
  const base = (process.env.LEDGER_URL ?? '').replace(/\/$/, '');
  if (base.startsWith('http://localhost')) {
    // Local service with LEDGER_AUTH=off (emulator / tests): no ID token.
    const res = await fetch(`${base}/v1/wallet/${template}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ idempotency_key: key, args }),
    });
    return { status: res.status, body: await res.json().catch(() => null) };
  }
  if (!base.startsWith('https://')) throw new Error('LEDGER_URL is not set');
  if (!client) client = await new GoogleAuth().getIdTokenClient(base);
  const res = await client.request({
    url: `${base}/v1/wallet/${template}`, method: 'POST', data: { idempotency_key: key, args },
    validateStatus: () => true, timeout: 15_000,
  });
  return { status: res.status, body: res.data };
}

async function deliver(ref: FirebaseFirestore.DocumentReference): Promise<void> {
  const snap = await ref.get();
  const o = snap.data();
  if (!o || o.status === 'done' || o.status === 'dead') return;
  const attempts = Number(o.attempts ?? 0) + 1;
  try {
    const r = await send(o.template, o.key, o.args);
    if (r.status === 200) {
      await ref.update({ status: 'done', attempts, journalId: r.body?.journalId ?? null, replayed: r.body?.replayed === true, doneAt: FieldValue.serverTimestamp() });
      return;
    }
    const error = String(r.body?.detail?.message ?? r.body?.detail ?? `HTTP ${r.status}`).slice(0, 300);
    const dead = isPermanent(r.status) || attempts >= MAX_ATTEMPTS;
    await ref.update({
      status: dead ? 'dead' : 'failed', attempts, lastStatus: r.status, lastError: error,
      retryAt: Timestamp.fromMillis(Date.now() + nextDelayMs(attempts)),
    });
    if (dead) logger.error('ledger outbox entry needs a person', ref.id, o.template, error);
  } catch (e: any) {
    await ref.update({
      status: attempts >= MAX_ATTEMPTS ? 'dead' : 'failed', attempts, lastError: String(e?.message ?? e).slice(0, 300),
      retryAt: Timestamp.fromMillis(Date.now() + nextDelayMs(attempts)),
    });
  }
}

export const ledgerOutboxDeliver = onDocumentCreated('ledger_outbox/{id}', async (event) => {
  if (!outboxEnabled() || !event.data) return;
  await deliver(event.data.ref);
});

export const ledgerOutboxRetry = onSchedule('every 10 minutes', async () => {
  if (!outboxEnabled()) return;
  const due = await db().collection('ledger_outbox').where('status', '==', 'failed')
    .where('retryAt', '<=', Timestamp.now()).orderBy('retryAt').limit(200).get();
  // Oldest first, so a purchase lands before the gift that spends it.
  for (const d of due.docs) await deliver(d.ref);
  // Anything stuck in pending (the trigger didn't run) for over 5 minutes.
  const stuck = await db().collection('ledger_outbox').where('status', '==', 'pending')
    .where('createdAt', '<=', Timestamp.fromMillis(Date.now() - 5 * 60_000)).limit(200).get();
  for (const d of stuck.docs) await deliver(d.ref);
});
