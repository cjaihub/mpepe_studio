/**
 * aiProxy — OpenRouter-compatible proxy so the app never ships an AI key.
 *
 * The app calls `<fn url>/api/v1/chat/completions` (or `/api/v1/models`) with
 * `Authorization: Bearer <Firebase ID token>`. We verify the token, apply a
 * per-user daily cap, then forward the request to OpenRouter with the
 * OPENROUTER_API_KEY secret and stream the response back unchanged (SSE too).
 */
import { onRequest } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import { getAuth } from 'firebase-admin/auth';
import { getAppCheck } from 'firebase-admin/app-check';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { Readable } from 'stream';

const openRouterSecret = defineSecret('OPENROUTER_API_KEY');

const UPSTREAM = 'https://openrouter.ai/api/v1';
const DAILY_LIMIT = 400;
const MAX_BODY_BYTES = 6 * 1024 * 1024;

async function underDailyCap(uid: string): Promise<boolean> {
  const day = new Date().toISOString().substring(0, 10).replace(/-/g, '');
  const ref = getFirestore().collection('users').doc(uid).collection('quotas').doc(`ai_${day}`);
  return getFirestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const count = (snap.get('count') as number | undefined) ?? 0;
    if (count >= DAILY_LIMIT) return false;
    tx.set(ref, { count: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    return true;
  });
}

export const aiProxy = onRequest(
  { secrets: [openRouterSecret], timeoutSeconds: 300, memory: '512MiB', cors: true },
  async (req, res) => {
    const path = req.path.replace(/^\/api\/v1/, '');
    const isChat = req.method === 'POST' && path === '/chat/completions';
    const isModels = req.method === 'GET' && path === '/models';
    if (!isChat && !isModels) {
      res.status(404).json({ error: { message: 'Not found' } });
      return;
    }

    const token = (req.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
    let uid: string;
    try {
      uid = (await getAuth().verifyIdToken(token)).uid;
    } catch {
      res.status(401).json({ error: { message: 'Sign in to use Oneova AI.' } });
      return;
    }

    // App Check: verified whenever the app sends it; required once
    // APP_CHECK_ENFORCE=true (same switch as the callables, globalOptions.ts).
    const appCheck = req.get('X-Firebase-AppCheck');
    let appVerified = false;
    if (appCheck) {
      try {
        await getAppCheck().verifyToken(appCheck);
        appVerified = true;
      } catch {
        appVerified = false;
      }
    }
    if (!appVerified && process.env.APP_CHECK_ENFORCE === 'true') {
      res.status(401).json({ error: { message: 'Update Oneova to keep using AI.' } });
      return;
    }

    if (isChat) {
      if ((req.rawBody?.length ?? 0) > MAX_BODY_BYTES) {
        res.status(413).json({ error: { message: 'Request too large.' } });
        return;
      }
      if (!(await underDailyCap(uid))) {
        res.status(429).json({ error: { message: 'Daily AI limit reached. Try again tomorrow.' } });
        return;
      }
    }

    const key = openRouterSecret.value();
    if (!key) {
      res.status(503).json({ error: { message: 'AI is not configured.' } });
      return;
    }

    const upstream = await fetch(`${UPSTREAM}${path}`, {
      method: req.method,
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${key}`,
        'HTTP-Referer': 'https://mpepe-2b4bd.web.app',
        'X-Title': 'Oneova',
      },
      body: isChat ? new Uint8Array(req.rawBody) : undefined,
    });

    res.status(upstream.status);
    const type = upstream.headers.get('content-type');
    if (type) res.setHeader('Content-Type', type);
    if (!upstream.body) {
      res.end();
      return;
    }
    Readable.fromWeb(upstream.body as never).pipe(res);
  },
);
