/**
 * Ova Guard — automatic action-taker.
 *
 * The only things it can do are in ACTIONS below (a fixed allow-list). There
 * is no ban, delete or suspend action: the strongest steps are temporary and
 * every one is
 *   - recorded in `security_actions/{id}` (admin-readable) with a plain
 *     reason and an expiry,
 *   - shown to the affected user as an event in
 *     `security_events/{uid}/events` (type `guard_action`),
 *   - reversible by an admin with `guardReverseAction`.
 * Anything that needs more than this is escalated to a human
 * (`moderation_cases`, source "ova_guard").
 *
 * Enforcement:
 *   rate_limit          security_state/{uid}.restrictions.{scope} = until;
 *                       firestore.rules refuse new chat messages / comments /
 *                       follows while it is in the future.
 *   hide_content        sets isModerated / safety.hidden on the doc, which the
 *                       app already filters out, "pending review".
 *   force_reauth        revokeRefreshTokens + sessionsRevokedAt, which every
 *                       signed-in device watches and signs out on.
 *   freeze_withdrawals  security_state/{uid}.withdrawalsFrozenUntil. Only taken
 *                       when GUARD_WITHDRAWAL_FREEZE=true, which is set once
 *                       requestWithdrawal checks that field (it does not yet).
 *   notify_user         an in-app + push notification.
 *   escalate_admin      a moderation case for a human reviewer.
 */
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
import * as logger from 'firebase-functions/logger';

const db = () => getFirestore();

export const ACTIONS = ['rate_limit', 'hide_content', 'force_reauth', 'freeze_withdrawals', 'notify_user', 'escalate_admin'] as const;
export type GuardAction = (typeof ACTIONS)[number];
export type RestrictionScope = 'messaging' | 'comments' | 'follows';

const MAX_MS: Record<GuardAction, number> = {
  rate_limit: 24 * 3600000,
  hide_content: 0,
  force_reauth: 0,
  freeze_withdrawals: 72 * 3600000,
  notify_user: 0,
  escalate_admin: 0,
};

const LABEL: Record<GuardAction, string> = {
  rate_limit: 'Sending paused for a while',
  hide_content: 'Content hidden until reviewed',
  force_reauth: 'Signed out everywhere for safety',
  freeze_withdrawals: 'Withdrawals paused for safety',
  notify_user: 'Safety notice sent',
  escalate_admin: 'Sent to the Oneova safety team',
};

export interface ActionRequest {
  uid: string;
  action: GuardAction;
  /** Plain-language reason the user and the reviewer both see. */
  reason: string;
  /** Why the guard acted: the event or scan that triggered it. */
  source: string;
  durationMs?: number;
  scope?: RestrictionScope;
  /** Firestore path of the content for hide_content / escalate_admin. */
  targetPath?: string;
  eventId?: string | null;
  notifyTitle?: string;
}

function untilFor(req: ActionRequest): Timestamp | null {
  const max = MAX_MS[req.action];
  if (!max) return null;
  return Timestamp.fromMillis(Date.now() + Math.min(max, Math.max(60000, req.durationMs ?? max)));
}

/** Runs one allow-listed action. Never throws: guard work must not break the app. */
export async function takeAction(req: ActionRequest): Promise<string | null> {
  if (!(ACTIONS as readonly string[]).includes(req.action) || !req.uid) return null;
  // Never show a freeze that the withdrawal flow does not enforce.
  if (req.action === 'freeze_withdrawals' && process.env.GUARD_WITHDRAWAL_FREEZE !== 'true') return null;
  try {
    const until = untilFor(req);
    const ref = db().collection('security_actions').doc();
    const state = db().collection('security_state').doc(req.uid);

    switch (req.action) {
      case 'rate_limit':
        await state.set({ restrictions: { [req.scope ?? 'messaging']: until } }, { merge: true });
        break;
      case 'freeze_withdrawals':
        await state.set({ withdrawalsFrozenUntil: until, withdrawalsFrozenReason: req.reason }, { merge: true });
        break;
      case 'hide_content':
        if (!req.targetPath) return null;
        await db().doc(req.targetPath).set(
          {
            isModerated: true,
            safety: { hidden: true, state: 'pending_review', by: 'ova_guard', reason: req.reason, actionId: ref.id },
          },
          { merge: true },
        );
        break;
      case 'force_reauth':
        await getAuth().revokeRefreshTokens(req.uid);
        await state.set({ sessionsRevokedAt: FieldValue.serverTimestamp(), sessions: {} }, { merge: true });
        // Keep the snapshot in step so the revoke isn't reported as a password change.
        {
          const after = await getAuth().getUser(req.uid);
          await state.set({ authSnapshot: { email: after.email ?? null, phone: after.phoneNumber ?? null, validAfter: after.tokensValidAfterTime ?? null } }, { merge: true });
        }
        break;
      case 'notify_user':
        await db().collection('notifications').add({
          userId: req.uid,
          category: 'security',
          type: 'security_notice',
          priority: 'high',
          title: req.notifyTitle ?? 'Ova Guard',
          body: req.reason.slice(0, 240),
          deepLink: '/profile/security',
          payload: { route: '/profile/security', actionId: ref.id },
          isRead: false,
          timestamp: FieldValue.serverTimestamp(),
          createdAt: FieldValue.serverTimestamp(),
        });
        break;
      case 'escalate_admin':
        await db().collection('moderation_cases').add({
          source: 'ova_guard',
          subjectUid: req.uid,
          targetPath: req.targetPath ?? null,
          reason: req.reason,
          trigger: req.source,
          state: 'open',
          createdAt: FieldValue.serverTimestamp(),
        });
        break;
    }

    await ref.set({
      uid: req.uid,
      action: req.action,
      label: LABEL[req.action],
      reason: req.reason,
      source: req.source,
      scope: req.scope ?? null,
      targetPath: req.targetPath ?? null,
      eventId: req.eventId ?? null,
      status: until ? 'active' : 'done',
      expiresAt: until,
      reversible: req.action !== 'notify_user',
      createdAt: FieldValue.serverTimestamp(),
    });
    if (req.action !== 'notify_user') {
      await db().collection('security_events').doc(req.uid).collection('events').add({
        type: 'guard_action',
        title: LABEL[req.action],
        score: 0,
        risk: 'low',
        reasons: [req.reason],
        status: 'closed',
        actionId: ref.id,
        action: req.action,
        expiresAt: until,
        details: { source: req.source },
        at: FieldValue.serverTimestamp(),
      });
    }
    return ref.id;
  } catch (e) {
    logger.error('guard action failed', { action: req.action, uid: req.uid, error: String(e) });
    return null;
  }
}

/** Undoes one action (admin), or lets it lapse (sweep). */
export async function reverseAction(actionId: string, by: string, why: string, status: 'reversed' | 'expired' = 'reversed'): Promise<boolean> {
  const ref = db().collection('security_actions').doc(actionId);
  const snap = await ref.get();
  if (!snap.exists || !['active', 'done'].includes(String(snap.get('status')))) return false;
  const a = snap.data() as { uid: string; action: GuardAction; scope?: string; targetPath?: string; label?: string };
  const state = db().collection('security_state').doc(a.uid);
  switch (a.action) {
    case 'rate_limit':
      await state.set({ restrictions: { [a.scope ?? 'messaging']: FieldValue.delete() } }, { merge: true });
      break;
    case 'freeze_withdrawals':
      await state.set({ withdrawalsFrozenUntil: FieldValue.delete(), withdrawalsFrozenReason: FieldValue.delete() }, { merge: true });
      break;
    case 'hide_content':
      if (a.targetPath && status === 'reversed') {
        await db().doc(a.targetPath).set({ isModerated: false, safety: { hidden: false, state: 'restored', reviewedBy: by } }, { merge: true }).catch(() => undefined);
      }
      break;
    default:
      break; // force_reauth / escalate / notify have nothing to undo
  }
  await ref.update({ status, reversedBy: by, reversedReason: why.slice(0, 300), reversedAt: FieldValue.serverTimestamp() });
  if (status === 'reversed') {
    await db().collection('security_events').doc(a.uid).collection('events').add({
      type: 'guard_action_reversed',
      title: 'Safety step removed',
      score: 0,
      risk: 'low',
      reasons: [`The Oneova team removed “${a.label ?? a.action}”${why ? `: ${why.slice(0, 160)}` : ''}`],
      status: 'closed',
      actionId,
      at: FieldValue.serverTimestamp(),
    });
  }
  return true;
}

/** How many actions of this kind this user got in the last `ms`. */
export async function recentActions(uid: string, source: string, ms: number): Promise<number> {
  const q = await db()
    .collection('security_actions')
    .where('uid', '==', uid)
    .where('createdAt', '>=', Timestamp.fromMillis(Date.now() - ms))
    .limit(50)
    .get();
  return q.docs.filter((d) => d.get('source') === source).length;
}

// ─────────────── Policy: which events lead to which actions ───────────────

/**
 * Called by recordSecurityEvent for every new account event. Fixed rules;
 * the AI never picks actions.
 */
export async function applyEventPolicy(uid: string, type: string, score: number, reasons: string[], eventId: string, details: Record<string, unknown>) {
  const reason = reasons[0] ?? 'Unusual activity on your account';
  const run = (action: GuardAction, extra: Partial<ActionRequest> = {}) =>
    takeAction({ uid, action, reason, source: `event:${type}`, eventId, ...extra });

  switch (type) {
    case 'session_reuse':
      // A copied sign-in token: end every session and protect the money.
      await run('force_reauth');
      await run('freeze_withdrawals', { durationMs: 48 * 3600000 });
      break;
    case 'impossible_travel':
      await run('freeze_withdrawals', { durationMs: 48 * 3600000 });
      if (score >= 90) await run('escalate_admin');
      break;
    case 'email_changed':
    case 'phone_changed':
    case 'password_changed':
      if (details.newDevice) await run('freeze_withdrawals', { durationMs: 48 * 3600000 });
      break;
    case 'profile_change_spike':
      await run('freeze_withdrawals', { durationMs: 24 * 3600000 });
      break;
    case 'message_spike':
      if (score >= 70) {
        await run('rate_limit', { scope: 'messaging', durationMs: 3600000 });
        await run('notify_user', { notifyTitle: 'Messaging paused for 1 hour', reason: `${reason}. If this wasn’t you, open Security and tap “Secure my account”.` });
      }
      break;
    case 'follow_spike':
      if (score >= 70) await run('rate_limit', { scope: 'follows', durationMs: 3600000 });
      break;
    case 'auth_failures':
      // Only server-checked failures: signed-out reports could be forged to freeze someone else.
      if (score >= 70 && details.verified) await run('freeze_withdrawals', { durationMs: 24 * 3600000 });
      break;
    default:
      break;
  }
}
