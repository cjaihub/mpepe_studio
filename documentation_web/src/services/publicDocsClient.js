import { useEffect, useState } from 'react';
import { initializeApp, getApps, getApp } from 'firebase/app';
import {
  getFirestore,
  collection,
  query,
  where,
  limit,
  orderBy,
  onSnapshot,
} from 'firebase/firestore';
import { getFunctions, httpsCallable } from 'firebase/functions';
import { PLATFORM_BASELINE_DOCS } from '../data/platformCatalog';

/**
 * Public Firebase Web Configuration (`mpepe-2b4bd`) for published docs, live
 * showcase data, and real-time support agent sessions.
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
 * Strips any legacy third-party brand hashtags or test placeholders from live
 * public strings rendered inside the homepage demo.
 */
export function sanitizePublicCopy(rawText) {
  return String(rawText ?? '')
    .replace(/#(tiktok|instagram|youtubeshorts|youtube|facebook|meta|capcut)\b/gi, '')
    .replace(/\b(TikTok|Instagram|YouTube Shorts|YouTube|Facebook|Meta|CapCut|Stripe)\b/gi, 'Creator Channels')
    .replace(/\s{2,}/g, ' ')
    .trim();
}

/**
 * Defense-in-depth HTML sanitizer for optional CMS `htmlOverride` content.
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

/**
 * Real-time public Firestore showcase reader for Open 3D Shops, Products & Creators.
 * Filters out test placeholders, third-party hashtags, and private owner contact details.
 */
export function useLiveShowcaseData() {
  const [shops, setShops] = useState([]);
  const [products, setProducts] = useState([]);
  const [reels, setReels] = useState([]);
  const [liveConnected, setLiveConnected] = useState(false);

  useEffect(() => {
    const unsubShops = onSnapshot(
      query(
        collection(publicDb, 'biz_shops'),
        where('status', '==', 'open'),
        limit(6)
      ),
      (snap) => {
        const clean = snap.docs
          .map((d) => {
            const x = d.data() || {};
            const name = sanitizePublicCopy(x.name || '');
            if (!name || /^(sample|test)/i.test(name)) return null;
            return {
              id: d.id,
              name,
              tagline: sanitizePublicCopy(x.tagline || 'Verified Creator Store'),
              bio: sanitizePublicCopy(x.bio || ''),
              verified: Boolean(x.verified),
              categories: Array.isArray(x.categories) ? x.categories.slice(0, 3) : [],
              avatarUrl: String(x.avatarUrl || ''),
              bannerUrl: String(x.bannerUrl || ''),
            };
          })
          .filter(Boolean);
        setShops(clean);
        setLiveConnected(true);
      },
      () => {}
    );

    const unsubProducts = onSnapshot(
      query(collection(publicDb, 'products'), limit(12)),
      (snap) => {
        const clean = snap.docs
          .map((d) => {
            const x = d.data() || {};
            const title = sanitizePublicCopy(x.title || x.name || '');
            if (
              !title ||
              x.active === false ||
              /^(sample|test)/i.test(title)
            ) {
              return null;
            }
            return {
              id: d.id,
              title,
              price: Number(x.price || 0),
              currency: String(x.currency || 'KES').toUpperCase(),
              category: sanitizePublicCopy(x.category || 'Creator Goods'),
              imageUrl: String(
                x.imageUrl || (Array.isArray(x.imageUrls) ? x.imageUrls[0] : '') || ''
              ),
              inStock: x.inStock !== false,
              has3d: Boolean(x.model3dUrl),
              shopId: String(x.shopId || x.ownerId || ''),
            };
          })
          .filter(Boolean);
        setProducts(clean);
        setLiveConnected(true);
      },
      () => {}
    );

    const unsubContent = onSnapshot(
      query(
        collection(publicDb, 'content'),
        where('visibility', '==', 'public'),
        limit(8)
      ),
      (snap) => {
        const clean = snap.docs
          .map((d) => {
            const x = d.data() || {};
            const title = sanitizePublicCopy(x.title || '');
            const desc = sanitizePublicCopy(x.description || x.caption || '');
            if (
              !title ||
              /^media\s+[0-9a-f]/i.test(title) ||
              title.toLowerCase().includes('test_')
            ) {
              return null;
            }
            return {
              id: d.id,
              title: title.slice(0, 88),
              description: desc.slice(0, 150),
              likeCount: Number(x.likeCount || 0),
            };
          })
          .filter(Boolean);
        setReels(clean);
      },
      () => {}
    );

    return () => {
      unsubShops();
      unsubProducts();
      unsubContent();
    };
  }, []);

  return { shops, products, reels, liveConnected };
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

export async function runSupportAgentTurn(payload) {
  const fn = httpsCallable(getFunctions(app, 'us-central1'), 'supportAgentTurn');
  const res = await fn(payload);
  return res.data;
}

export async function sendSupportSessionMessage(payload) {
  const fn = httpsCallable(
    getFunctions(app, 'us-central1'),
    'supportSessionSendMessage'
  );
  const res = await fn(payload);
  return res.data;
}

export async function pollSupportSessionMessages(payload) {
  const fn = httpsCallable(getFunctions(app, 'us-central1'), 'pollSupportSession');
  const res = await fn(payload);
  return res.data;
}

export async function subscribeOneovaAuth(onUser) {
  const { getAuth, onAuthStateChanged } = await import('firebase/auth');
  const auth = getAuth(app);
  return onAuthStateChanged(auth, (u) => {
    if (!u || u.isAnonymous) {
      onUser(null);
    } else {
      onUser({
        uid: u.uid,
        displayName: u.displayName || u.email || 'Oneova Creator',
        photoURL: u.photoURL || '',
      });
    }
  });
}

export async function signInOneovaSupportUser() {
  const { getAuth, GoogleAuthProvider, signInWithPopup } = await import(
    'firebase/auth'
  );
  const auth = getAuth(app);
  const res = await signInWithPopup(auth, new GoogleAuthProvider());
  return res.user;
}

export async function signOutOneovaSupportUser() {
  const { getAuth, signOut } = await import('firebase/auth');
  await signOut(getAuth(app));
}

export function subscribeSignedInTicketMessages(ticketId, onUpdate) {
  if (!ticketId) return () => {};
  const q = query(
    collection(publicDb, 'support_tickets', ticketId, 'messages'),
    orderBy('createdAt', 'asc'),
    limit(60)
  );
  return onSnapshot(
    q,
    (snap) => {
      const msgs = snap.docs.map((d) => {
        const m = d.data() || {};
        return {
          id: d.id,
          senderRole: String(m.senderRole || 'user'),
          senderName: String(m.senderName || ''),
          text: String(m.text || ''),
          actionTaken: String(m.actionTaken || ''),
        };
      });
      onUpdate(msgs);
    },
    () => {}
  );
}
