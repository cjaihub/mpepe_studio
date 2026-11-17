import { useEffect, useState } from 'react';
import { initializeApp, getApps, getApp } from 'firebase/app';
import {
  getFirestore,
  collection,
  query,
  where,
  onSnapshot,
} from 'firebase/firestore';
import { getFunctions, httpsCallable } from 'firebase/functions';
import { PLATFORM_BASELINE_DOCS } from '../data/platformCatalog';

/**
 * Public Firebase Web Configuration (`mpepe-2b4bd`) for published docs & support ticket intake.
 * Contains zero admin auth hooks, draft readers, or admin mutation helpers.
 */
export const firebaseWebConfig = {
  apiKey: 'AIzaSyC7x52ADAM6rJZeiTJAeIYj-jdporiR8oA',
  appId: '1:90836164478:web:023f5e7e784d4968a91d2f',
  messagingSenderId: '90836164478',
  projectId: 'mpepe-2b4bd',
  authDomain: 'mpepe-2b4bd.firebaseapp.com',
  storageBucket: 'mpepe-2b4bd.firebasestorage.app',
  measurementId: 'G-FMTTQLHXCR',
};

const app = getApps().length ? getApp() : initializeApp(firebaseWebConfig);
const publicDb = getFirestore(app);
const CMS_COLLECTION = 'platform_cms_docs';

function normalizeSection(raw) {
  if (!raw || typeof raw !== 'object') {
    return { heading: '', summary: '', callout: '', bullets: [] };
  }
  const bullets = Array.isArray(raw.bullets)
    ? raw.bullets.map((b) => String(b ?? '').trim()).filter(Boolean)
    : [];
  return {
    heading: String(raw.heading ?? '').trim(),
    summary: String(raw.summary ?? '').trim(),
    callout: String(raw.callout ?? '').trim(),
    bullets,
  };
}

/**
 * Defense-in-depth HTML sanitizer for optional CMS `htmlOverride` content.
 * Removes scripts, frames, SVG scripts, inline event handlers, and unsafe URLs.
 */
export function sanitizeHtmlFragment(rawHtml) {
  const html = String(rawHtml ?? '').trim();
  if (!html || typeof DOMParser === 'undefined') return '';
  try {
    const doc = new DOMParser().parseFromString(html, 'text/html');
    const blocked = new Set([
      'SCRIPT',
      'IFRAME',
      'OBJECT',
      'EMBED',
      'FORM',
      'STYLE',
      'LINK',
      'META',
      'BASE',
      'SVG',
    ]);
    const cleanNode = (root) => {
      const children = Array.from(root.childNodes || []);
      for (const node of children) {
        if (node.nodeType === 1) {
          if (blocked.has(node.tagName)) {
            root.removeChild(node);
            continue;
          }
          for (const attr of Array.from(node.attributes || [])) {
            const name = attr.name.toLowerCase();
            const val = String(attr.value || '').trim().toLowerCase();
            if (name.startsWith('on') || name === 'srcdoc') {
              node.removeAttribute(attr.name);
            } else if (
              (name === 'href' || name === 'src') &&
              val &&
              !/^(https?:|mailto:|tel:|\/|#)/.test(val)
            ) {
              node.removeAttribute(attr.name);
            }
          }
          cleanNode(node);
        }
      }
    };
    cleanNode(doc.body);
    return doc.body.innerHTML;
  } catch {
    return '';
  }
}

function parsePublicFirestoreDoc(snap) {
  const d = snap.data() || {};
  const ts = d.updatedAt;
  return {
    id: String(d.id || snap.id).trim(),
    docType: String(d.docType || 'policy').trim(),
    category: String(d.category || 'Community & Safety').trim(),
    policyTab: String(d.policyTab || '').trim(),
    title: String(d.title || snap.id).trim(),
    badge: String(d.badge || 'OFFICIAL').trim(),
    isAccentBadge: Boolean(d.isAccentBadge),
    inShort: String(d.inShort || '').trim(),
    readTime: String(d.readTime || '4 min read').trim(),
    version: String(d.version || 'v1.0').trim(),
    effectiveDate: String(d.effectiveDate || 'October 25, 2026').trim(),
    order: Number.isFinite(Number(d.order)) ? Math.round(Number(d.order)) : 10,
    isPublished: true,
    sections: Array.isArray(d.sections) ? d.sections.map(normalizeSection) : [],
    htmlOverride: sanitizeHtmlFragment(d.htmlOverride || ''),
    updatedAt: ts && typeof ts.toDate === 'function' ? ts.toDate() : null,
    isLiveFromCloud: true,
  };
}

function mergePublicDocs(liveMap) {
  const merged = [];
  const seen = new Set();

  for (const base of PLATFORM_BASELINE_DOCS) {
    seen.add(base.id);
    const chosen = liveMap.get(base.id) || { ...base, isLiveFromCloud: false };
    if (chosen.isPublished !== false) {
      merged.push(chosen);
    }
  }

  for (const [id, liveDoc] of liveMap.entries()) {
    if (!seen.has(id) && liveDoc.isPublished !== false) {
      merged.push(liveDoc);
    }
  }

  merged.sort((a, b) => {
    const orderDiff = (a.order ?? 10) - (b.order ?? 10);
    return orderDiff !== 0 ? orderDiff : a.title.localeCompare(b.title);
  });

  return merged;
}

/**
 * Public-only reader hook subscribing strictly to published `platform_cms_docs`.
 * Never reads drafts, revision history, or admin identity metadata.
 */
export function usePublicPlatformDocs() {
  const [state, setState] = useState(() => ({
    docs: mergePublicDocs(new Map()),
    isLiveConnected: false,
    liveOverrideCount: 0,
  }));

  useEffect(() => {
    const q = query(
      collection(publicDb, CMS_COLLECTION),
      where('isPublished', '==', true)
    );

    const unsubscribe = onSnapshot(
      q,
      (snapshot) => {
        const liveMap = new Map();
        snapshot.docs.forEach((docSnap) => {
          const parsed = parsePublicFirestoreDoc(docSnap);
          liveMap.set(parsed.id, parsed);
        });
        setState({
          docs: mergePublicDocs(liveMap),
          isLiveConnected: true,
          liveOverrideCount: liveMap.size,
        });
      },
      () => {
        setState({
          docs: mergePublicDocs(new Map()),
          isLiveConnected: false,
          liveOverrideCount: 0,
        });
      }
    );

    return () => unsubscribe();
  }, []);

  return state;
}

export async function submitSupportTicketPublic(payload) {
  const fn = httpsCallable(getFunctions(app, 'us-central1'), 'submitSupportTicket');
  const res = await fn(payload);
  return res.data;
}

export async function lookupSupportTicketPublic({ trackingCode, accessPin }) {
  const fn = httpsCallable(getFunctions(app, 'us-central1'), 'lookupSupportTicket');
  const res = await fn({ trackingCode, accessPin });
  return res.data;
}
