/**
 * "My voice": the person's own voice for translated voice notes and calls,
 * built on Oneova's own GPU server (services/voice). Plan and safety rules:
 * docs/architecture/voice_cloning_selfhosted.md.
 *
 * The server only ever speaks in the CALLER's own voice: every callable uses
 * request.auth.uid, never a uid from the request.
 *
 *   voiceStatus()                       → { available, profile }
 *   voiceEnrollStart({ consent: true }) → { path, prompts }   (uploads go to voice_profiles/{uid}/clips/)
 *   voiceEnrollFinish()                 → build report (enough? which clips to retake)
 *   voiceDisable()                      → deletes recordings, voice and record
 *   voiceSpeakOwn({ text, language })   → { audioBase64 } 24 kHz PCM16 in my voice
 *   voiceStreamToken({ callId })        → { url, token } for the call stream (15 min)
 *
 * Off until the VOICE_SERVER_URL secret is set (after the GPU is approved).
 * `voice_profiles/{uid}` is read-only to its owner; only these functions write it.
 */
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { GoogleAuth } from 'google-auth-library';
import { optionalSecret } from '../optionalSecrets';
import { limit } from '../guard/protect';
import { CONSENT_VERSION, ENROLL_PROMPTS, MAX_SPEAK_CHARS, engineFor, signStreamToken, validVoiceUrl } from './voiceLogic';

const db = () => getFirestore();
const auth = new GoogleAuth();

function me(req: CallableRequest): string {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  return uid;
}

async function serverUrl(): Promise<string | null> {
  return validVoiceUrl(await optionalSecret('VOICE_SERVER_URL'));
}

async function callServer(path: string, method: 'POST' | 'DELETE', data?: unknown, binary = false): Promise<any> {
  const url = await serverUrl();
  if (!url) throw new HttpsError('unavailable', 'My voice isn’t switched on yet.');
  const client = await auth.getIdTokenClient(url);
  try {
    const res = await client.request({ url: `${url}${path}`, method, data, timeout: 120000, responseType: binary ? 'arraybuffer' : 'json' });
    return res.data;
  } catch (e: any) {
    const status = Number(e?.response?.status ?? 0);
    if (status === 404) throw new HttpsError('not-found', 'Set up your voice first.');
    throw new HttpsError('unavailable', 'The voice server is busy. Try again in a minute.');
  }
}

const profileRef = (uid: string) => db().collection('voice_profiles').doc(uid);

export const voiceStatus = onCall(async (req) => {
  const uid = me(req);
  const p = (await profileRef(uid).get()).data() ?? null;
  return {
    available: !!(await serverUrl()),
    profile: p ? { status: p.status ?? 'none', seconds: p.seconds ?? 0, retake: p.retake ?? [], builtAt: p.builtAt?.toMillis?.() ?? null } : null,
    prompts: ENROLL_PROMPTS,
  };
});

export const voiceEnrollStart = onCall(async (req) => {
  const uid = me(req);
  if (req.data?.consent !== true) throw new HttpsError('failed-precondition', 'Agree to the voice terms first.');
  const claims = req.auth?.token as Record<string, unknown> | undefined;
  if (claims?.minor === true) throw new HttpsError('permission-denied', 'My voice is for adults only.');
  await limit(uid, 'voice_enroll', 10, 24 * 3600_000);
  await profileRef(uid).set({
    uid,
    status: 'recording',
    consent: { version: CONSENT_VERSION, at: FieldValue.serverTimestamp() },
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return { path: `voice_profiles/${uid}/clips/`, consentPath: `voice_profiles/${uid}/consent.m4a`, prompts: ENROLL_PROMPTS };
});

export const voiceEnrollFinish = onCall({ timeoutSeconds: 300 }, async (req) => {
  const uid = me(req);
  const cur = (await profileRef(uid).get()).data();
  if (!cur?.consent) throw new HttpsError('failed-precondition', 'Start setting up your voice first.');
  await limit(uid, 'voice_build', 10, 24 * 3600_000);
  await profileRef(uid).set({ status: 'building', updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  const report = await callServer('/v1/profile/build', 'POST', { uid });
  const ok = report?.built === true;
  await profileRef(uid).set({
    status: ok ? 'ready' : 'needs_retake',
    seconds: Number(report?.goodSeconds ?? 0),
    retake: Array.isArray(report?.retake) ? report.retake.slice(0, 20) : [],
    ...(ok ? { builtAt: FieldValue.serverTimestamp() } : {}),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return { ready: ok, seconds: report?.goodSeconds ?? 0, totalSeconds: report?.totalSeconds ?? 0, retake: report?.retake ?? [] };
});

export const voiceDisable = onCall(async (req) => {
  const uid = me(req);
  if (await serverUrl()) {
    try {
      await callServer(`/v1/profile/${uid}`, 'DELETE');
    } catch {
      // The files below are deleted either way.
    }
  }
  await getStorage().bucket().deleteFiles({ prefix: `voice_profiles/${uid}/` }).catch(() => undefined);
  await profileRef(uid).delete();
  return { ok: true };
});

async function requireReady(uid: string): Promise<void> {
  const p = (await profileRef(uid).get()).data();
  if (p?.status !== 'ready') throw new HttpsError('failed-precondition', 'Set up your voice first.');
}

export const voiceSpeakOwn = onCall({ timeoutSeconds: 120 }, async (req) => {
  const uid = me(req);
  const text = String(req.data?.text ?? '').trim().slice(0, MAX_SPEAK_CHARS);
  const language = String(req.data?.language ?? '').slice(0, 12);
  if (!text || !language) throw new HttpsError('invalid-argument', 'Missing text or language.');
  if (engineFor(language) !== 'clone') throw new HttpsError('failed-precondition', 'convert');
  await requireReady(uid);
  await limit(uid, 'voice_speak', 120, 3600_000);
  const pcm = await callServer('/v1/speak', 'POST', { uid, text, language }, true);
  return { audioBase64: Buffer.from(pcm).toString('base64'), sampleRate: 24000, aiVoice: true };
});

/** Converts speech (e.g. a preset voice speaking Yoruba) into my own voice. */
export const voiceConvertOwn = onCall({ timeoutSeconds: 120 }, async (req) => {
  const uid = me(req);
  const audio = String(req.data?.audioBase64 ?? '');
  const sr = Number(req.data?.sampleRate ?? 24000);
  if (!audio || audio.length > 4 * 1024 * 1024 || !(sr >= 8000 && sr <= 48000)) throw new HttpsError('invalid-argument', 'Bad audio.');
  await requireReady(uid);
  await limit(uid, 'voice_convert', 120, 3600_000);
  const pcm = await callServer('/v1/convert', 'POST', { uid, sr, audio }, true);
  return { audioBase64: Buffer.from(pcm).toString('base64'), sampleRate: 24000, aiVoice: true };
});

/**
 * For voice notes: [text] in [uid]'s OWN voice, or null when My voice isn't
 * set up / switched on. Clone languages are spoken directly; others take the
 * preset-voice speech ([preset]) and convert it into the person's voice.
 * Callers must only pass the signed-in caller's own uid.
 */
export async function ownVoicePcm(uid: string, text: string, language: string, preset: { pcm: Buffer; sr: number } | null): Promise<Buffer | null> {
  if (!(await serverUrl())) return null;
  const p = (await profileRef(uid).get()).data();
  if (p?.status !== 'ready') return null;
  try {
    if (engineFor(language) === 'clone') {
      const parts: Buffer[] = [];
      for (const chunk of splitForSpeak(text)) {
        parts.push(Buffer.from(await callServer('/v1/speak', 'POST', { uid, text: chunk, language }, true)));
      }
      return parts.length ? Buffer.concat(parts) : null;
    }
    if (!preset || preset.pcm.length > 3 * 1024 * 1024) return null;
    return Buffer.from(await callServer('/v1/convert', 'POST', { uid, sr: preset.sr, audio: preset.pcm.toString('base64') }, true));
  } catch {
    return null; // fall back to the preset voice
  }
}

/** Sentence-sized chunks of at most MAX_SPEAK_CHARS. */
export function splitForSpeak(text: string): string[] {
  const out: string[] = [];
  let cur = '';
  for (const s of text.replace(/\s+/g, ' ').trim().split(/(?<=[.!?。！？؟])\s+/)) {
    if ((cur + ' ' + s).trim().length > MAX_SPEAK_CHARS && cur) {
      out.push(cur.trim());
      cur = '';
    }
    cur = (cur + ' ' + s).trim();
    while (cur.length > MAX_SPEAK_CHARS) {
      out.push(cur.slice(0, MAX_SPEAK_CHARS));
      cur = cur.slice(MAX_SPEAK_CHARS);
    }
  }
  if (cur) out.push(cur);
  return out.slice(0, 8);
}

export const voiceStreamToken = onCall(async (req) => {
  const uid = me(req);
  const callId = String(req.data?.callId ?? '');
  if (!/^[A-Za-z0-9_-]{4,100}$/.test(callId)) throw new HttpsError('invalid-argument', 'Missing call.');
  const url = await serverUrl();
  const key = await optionalSecret('VOICE_STREAM_KEY');
  if (!url || !key) throw new HttpsError('unavailable', 'My voice isn’t switched on yet.');
  await requireReady(uid);
  await limit(uid, 'voice_stream', 30, 3600_000);
  return { url: url.replace(/^https:/, 'wss:') + '/v1/stream', token: signStreamToken(Buffer.from(key), uid, callId) };
});
