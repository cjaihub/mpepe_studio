import { useEffect, useState } from 'react';
import {
  collection,
  doc,
  query,
  orderBy,
  limit,
  onSnapshot,
  updateDoc,
  addDoc,
  deleteDoc,
  serverTimestamp,
} from 'firebase/firestore';
import { getFunctions, httpsCallable } from 'firebase/functions';
import { getApp } from 'firebase/app';
import { cmsDb, cmsAuth } from '../services/platformCmsClient';

/**
 * Admin data for "What do you wish Oneova had?" (Firestore `wish_*`, see
 * functions/src/wishIdeas.ts). Everything is a live onSnapshot stream.
 */

function useLive(buildQuery, deps) {
  const [state, setState] = useState({ items: [], loading: true, error: '' });
  useEffect(() => {
    const q = buildQuery();
    if (!q) {
      setState({ items: [], loading: false, error: '' });
      return undefined;
    }
    setState((s) => ({ ...s, loading: true }));
    return onSnapshot(
      q,
      (snap) => setState({ items: snap.docs.map((d) => ({ id: d.id, ...d.data() })), loading: false, error: '' }),
      (err) => setState({ items: [], loading: false, error: err?.message || 'Could not load.' })
    );
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
  return state;
}

export function useWishIdeas(sortField) {
  return useLive(
    () => query(collection(cmsDb, 'wish_ideas'), orderBy(sortField, 'desc'), limit(300)),
    [sortField]
  );
}

export function useWishClusters() {
  return useLive(() => query(collection(cmsDb, 'wish_clusters'), orderBy('ideaCount', 'desc'), limit(80)), []);
}

export function useWishComments(ideaId) {
  return useLive(
    () => (ideaId ? query(collection(cmsDb, 'wish_ideas', ideaId, 'comments'), orderBy('createdAt'), limit(300)) : null),
    [ideaId]
  );
}

export function useWishInsights() {
  const [state, setState] = useState({ data: null, loading: true, error: '' });
  useEffect(
    () =>
      onSnapshot(
        doc(cmsDb, 'wish_insights', 'latest'),
        (snap) => setState({ data: snap.exists() ? snap.data() : null, loading: false, error: '' }),
        (err) => setState({ data: null, loading: false, error: err?.message || 'Could not load.' })
      ),
    []
  );
  return state;
}

function adminName() {
  const u = cmsAuth.currentUser;
  return String(u?.displayName || u?.email || 'Oneova team').slice(0, 80);
}

export async function setIdeaStatus(ideaId, status) {
  await updateDoc(doc(cmsDb, 'wish_ideas', ideaId), { status, statusUpdatedAt: serverTimestamp() });
}

export async function setIdeaReply(ideaId, text) {
  const clean = String(text || '').trim().slice(0, 1000);
  await updateDoc(doc(cmsDb, 'wish_ideas', ideaId), {
    adminReply: clean
      ? { text: clean, by: cmsAuth.currentUser?.uid || '', byName: adminName(), at: serverTimestamp() }
      : null,
  });
}

export async function postOfficialComment(ideaId, text) {
  const clean = String(text || '').trim().slice(0, 1000);
  if (!clean) return;
  await addDoc(collection(cmsDb, 'wish_ideas', ideaId, 'comments'), {
    authorId: cmsAuth.currentUser?.uid,
    authorName: 'Oneova team',
    authorPhoto: '',
    text: clean,
    isOfficial: true,
    createdAt: serverTimestamp(),
  });
}

export async function deleteIdea(ideaId) {
  await deleteDoc(doc(cmsDb, 'wish_ideas', ideaId));
}

export async function deleteComment(ideaId, commentId) {
  await deleteDoc(doc(cmsDb, 'wish_ideas', ideaId, 'comments', commentId));
}

export async function refreshSummary() {
  const fn = httpsCallable(getFunctions(getApp()), 'wishSummarizeNow', { timeout: 130000 });
  await fn({});
}

export function toDate(ts) {
  if (!ts) return null;
  if (typeof ts.toDate === 'function') return ts.toDate();
  return null;
}

export function timeAgo(ts) {
  const d = toDate(ts);
  if (!d) return '';
  const s = Math.max(1, Math.round((Date.now() - d.getTime()) / 1000));
  if (s < 60) return `${s}s ago`;
  if (s < 3600) return `${Math.round(s / 60)}m ago`;
  if (s < 86400) return `${Math.round(s / 3600)}h ago`;
  return `${Math.round(s / 86400)}d ago`;
}
