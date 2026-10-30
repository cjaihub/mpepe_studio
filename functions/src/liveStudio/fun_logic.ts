/**
 * LIVE STUDIO v2 — host entertainment tools (pure; no Firebase imports).
 * Polls, countdown timers, spotlight (pin a message on stage), celebrations
 * and a comment raffle. State lives in `live_streams/{id}/studio/fun`.
 */

export const FUN_LIMITS = {
  questionMax: 120,
  optionMax: 40,
  optionsMin: 2,
  optionsMax: 4,
  pollSecondsMin: 15,
  pollSecondsMax: 600,
  timerLabelMax: 40,
  timerSecondsMin: 5,
  timerSecondsMax: 3600,
  spotlightMax: 200,
  raffleWindowMs: 10 * 60 * 1000,
} as const;

export const CELEBRATIONS = ['confetti', 'hearts', 'fireworks'] as const;
export type Celebration = (typeof CELEBRATIONS)[number];

export const MANAGER_OPS = [
  'pollStart',
  'pollEnd',
  'timerStart',
  'timerStop',
  'spotlight',
  'spotlightClear',
  'celebrate',
  'raffle',
] as const;
export type ManagerOp = (typeof MANAGER_OPS)[number];
export type FunOp = ManagerOp | 'pollVote';

export interface Poll {
  id: string;
  question: string;
  options: string[];
  counts: number[];
  startedAtMs: number;
  endsAtMs: number;
  open: boolean;
}

export interface FunState {
  poll: Poll | null;
  timer: { label: string; startedAtMs: number; endsAtMs: number } | null;
  spotlight: { text: string; uid: string; name: string; avatarUrl: string; atMs: number } | null;
  celebrate: { kind: Celebration; atMs: number } | null;
  raffle: { winnerUid: string; winnerName: string; winnerAvatarUrl: string; entrants: number; atMs: number } | null;
}

export const emptyFun = (): FunState => ({ poll: null, timer: null, spotlight: null, celebrate: null, raffle: null });

export class FunError extends Error {}

const CONTROL = /[\u0000-\u0008\u000b-\u001f\u007f]/;

function text(v: unknown, name: string, max: number): string {
  if (typeof v !== 'string') throw new FunError(`${name} is required.`);
  const t = v.trim();
  if (!t || t.length > max || CONTROL.test(t)) throw new FunError(`${name} must be 1–${max} characters.`);
  return t;
}

function int(v: unknown, name: string, min: number, max: number): number {
  if (typeof v !== 'number' || !Number.isFinite(v)) throw new FunError(`${name} must be a number.`);
  return Math.min(max, Math.max(min, Math.round(v)));
}

export function parseOp(v: unknown): FunOp {
  if (v === 'pollVote' || (MANAGER_OPS as readonly string[]).includes(v as string)) return v as FunOp;
  throw new FunError('Unknown op.');
}

export function newPoll(data: Record<string, unknown>, id: string, nowMs: number): Poll {
  const question = text(data.question, 'question', FUN_LIMITS.questionMax);
  const raw = Array.isArray(data.options) ? data.options : [];
  const options = raw.map((o, i) => text(o, `option ${i + 1}`, FUN_LIMITS.optionMax));
  if (options.length < FUN_LIMITS.optionsMin || options.length > FUN_LIMITS.optionsMax) {
    throw new FunError(`A poll needs ${FUN_LIMITS.optionsMin}–${FUN_LIMITS.optionsMax} options.`);
  }
  if (new Set(options.map((o) => o.toLowerCase())).size !== options.length) throw new FunError('Options must be different.');
  const seconds = int(data.seconds ?? 60, 'seconds', FUN_LIMITS.pollSecondsMin, FUN_LIMITS.pollSecondsMax);
  return { id, question, options, counts: options.map(() => 0), startedAtMs: nowMs, endsAtMs: nowMs + seconds * 1000, open: true };
}

/** A poll accepts votes while open and before its end time. */
export const pollAccepting = (p: Poll | null, nowMs: number): p is Poll => !!p && p.open && nowMs < p.endsAtMs;

/** Moves one vote: [prev] (null = first vote) → [next]. Counts never go below 0. */
export function applyVote(p: Poll, prev: number | null, next: number): Poll {
  if (!Number.isInteger(next) || next < 0 || next >= p.options.length) throw new FunError('Pick one of the options.');
  if (prev === next) return p;
  const counts = [...p.counts];
  if (prev !== null && prev >= 0 && prev < counts.length) counts[prev] = Math.max(0, counts[prev] - 1);
  counts[next] += 1;
  return { ...p, counts };
}

export function newTimer(data: Record<string, unknown>, nowMs: number): NonNullable<FunState['timer']> {
  const label = typeof data.label === 'string' && data.label.trim() ? text(data.label, 'label', FUN_LIMITS.timerLabelMax) : 'Countdown';
  const seconds = int(data.seconds, 'seconds', FUN_LIMITS.timerSecondsMin, FUN_LIMITS.timerSecondsMax);
  return { label, startedAtMs: nowMs, endsAtMs: nowMs + seconds * 1000 };
}

export function parseCelebration(v: unknown): Celebration {
  return (CELEBRATIONS as readonly string[]).includes(v as string) ? (v as Celebration) : 'confetti';
}

export const parseSpotlightText = (v: unknown) => text(v, 'text', FUN_LIMITS.spotlightMax);

/** Distinct commenters (not [excludeUid]) in comment order, newest window only. */
export function raffleEntrants(
  comments: { uid: string; name: string; avatarUrl: string; ts: number }[],
  nowMs: number,
  excludeUids: string[],
): { uid: string; name: string; avatarUrl: string }[] {
  const seen = new Map<string, { uid: string; name: string; avatarUrl: string }>();
  for (const c of comments) {
    if (!c.uid || excludeUids.includes(c.uid) || nowMs - c.ts > FUN_LIMITS.raffleWindowMs) continue;
    if (!seen.has(c.uid)) seen.set(c.uid, { uid: c.uid, name: c.name, avatarUrl: c.avatarUrl });
  }
  return [...seen.values()];
}

/** Uniform pick with [random] in [0, 1). */
export function pickWinner<T>(entrants: T[], random: number): T | null {
  if (!entrants.length) return null;
  return entrants[Math.min(entrants.length - 1, Math.floor(random * entrants.length))];
}
