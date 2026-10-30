import { useEffect, useState } from 'react';
import { initializeApp, getApps, getApp } from 'firebase/app';
import {
  getFirestore,
  collection,
  doc,
  query,
  where,
  orderBy,
  limit,
  onSnapshot,
  getDocs,
  writeBatch,
  deleteDoc,
  serverTimestamp,
} from 'firebase/firestore';
import {
  getAuth,
  onAuthStateChanged,
  signInWithEmailAndPassword,
  GoogleAuthProvider,
  signInWithPopup,
  signOut,
} from 'firebase/auth';
import { PLATFORM_BASELINE_DOCS } from '../data/platformCatalog';

/**
 * Official Oneova Firebase Web Configuration (matches `lib/firebase_options.dart`).
 * Connects the live React website directly to the exact same Firestore database
 * (`mpepe-2b4bd`) used by the Oneova Flutter mobile & desktop apps.
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
export const cmsDb = getFirestore(app);
export const cmsAuth = getAuth(app);

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

function parseFirestoreDoc(snap) {
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
    isPublished: d.isPublished !== false,
    sections: Array.isArray(d.sections) ? d.sections.map(normalizeSection) : [],
    htmlOverride: String(d.htmlOverride || '').trim(),
    updatedAt: ts && typeof ts.toDate === 'function' ? ts.toDate() : null,
    updatedByUid: String(d.updatedByUid || '').trim(),
    updatedByName: String(d.updatedByName || 'Oneova Admin').trim(),
    changeNote: String(d.changeNote || '').trim(),
    isLiveFromCloud: true,
  };
}

function mergeWithBaseline(liveMap, includeDrafts) {
  const merged = [];
  const seen = new Set();

  for (const base of PLATFORM_BASELINE_DOCS) {
    seen.add(base.id);
    const chosen = liveMap.get(base.id) || { ...base, isLiveFromCloud: false };
    if (includeDrafts || chosen.isPublished !== false) {
      merged.push(chosen);
    }
  }

  for (const [id, liveDoc] of liveMap.entries()) {
    if (!seen.has(id)) {
      if (includeDrafts || liveDoc.isPublished !== false) {
        merged.push(liveDoc);
      }
    }
  }

  merged.sort((a, b) => {
    const orderDiff = (a.order ?? 10) - (b.order ?? 10);
    return orderDiff !== 0 ? orderDiff : a.title.localeCompare(b.title);
  });

  return merged;
}

/**
 * Real-time React hook streaming Oneova's Feature Documentation, Rules & Regulations.
 * Updates live within milliseconds whenever edited from the Oneova App or Web Admin CMS.
 */
export function usePlatformDocs({ includeDrafts = false } = {}) {
  const [state, setState] = useState(() => ({
    docs: mergeWithBaseline(new Map(), includeDrafts),
    isLiveConnected: false,
    liveOverrideCount: 0,
    lastSyncAt: null,
  }));

  useEffect(() => {
    const colRef = collection(cmsDb, CMS_COLLECTION);
    const q = includeDrafts ? colRef : query(colRef, where('isPublished', '==', true));

    const unsubscribe = onSnapshot(
      q,
      (snapshot) => {
        const liveMap = new Map();
        snapshot.docs.forEach((docSnap) => {
          const parsed = parseFirestoreDoc(docSnap);
          liveMap.set(parsed.id, parsed);
        });
        setState({
          docs: mergeWithBaseline(liveMap, includeDrafts),
          isLiveConnected: true,
          liveOverrideCount: liveMap.size,
          lastSyncAt: new Date(),
        });
      },
      () => {
        // Graceful offline/restricted fallback: baseline catalog stays 100% available
        setState((prev) => ({
          ...prev,
          docs: mergeWithBaseline(new Map(), includeDrafts),
          isLiveConnected: false,
        }));
      }
    );

    return () => unsubscribe();
  }, [includeDrafts]);

  return state;
}

/**
 * Real-time Admin Auth + Role verification hook (`users/{uid}.role` in ['admin','owner','founder']
 * or custom token claim `admin === true`).
 */
export function useCmsAdminAuth() {
  const [user, setUser] = useState(null);
  const [isAdmin, setIsAdmin] = useState(false);
  const [roleLabel, setRoleLabel] = useState('');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let unsubUserDoc = null;

    const unsubAuth = onAuthStateChanged(cmsAuth, async (firebaseUser) => {
      if (unsubUserDoc) {
        unsubUserDoc();
        unsubUserDoc = null;
      }

      if (!firebaseUser || firebaseUser.isAnonymous) {
        setUser(null);
        setIsAdmin(false);
        setRoleLabel('');
        setLoading(false);
        return;
      }

      setUser(firebaseUser);

      let claimAdmin = false;
      try {
        const tokenRes = await firebaseUser.getIdTokenResult();
        claimAdmin = tokenRes?.claims?.admin === true;
      } catch {
        claimAdmin = false;
      }

      if (claimAdmin) {
        setIsAdmin(true);
        setRoleLabel('admin');
        setLoading(false);
        return;
      }

      const userRef = doc(cmsDb, 'users', firebaseUser.uid);
      unsubUserDoc = onSnapshot(
        userRef,
        (snap) => {
          const data = snap.data() || {};
          const rawRole = String(data.role || '').toLowerCase().trim();
          const granted =
            rawRole === 'admin' ||
            rawRole === 'owner' ||
            rawRole === 'founder' ||
            data.isAdmin === true;
          setIsAdmin(granted);
          setRoleLabel(rawRole || (granted ? 'admin' : 'member'));
          setLoading(false);
        },
        () => {
          setIsAdmin(false);
          setRoleLabel('member');
          setLoading(false);
        }
      );
    });

    return () => {
      if (unsubUserDoc) unsubUserDoc();
      unsubAuth();
    };
  }, []);

  const signInEmail = async (email, password) => {
    return signInWithEmailAndPassword(cmsAuth, email.trim(), password);
  };

  const signInGoogle = async () => {
    const provider = new GoogleAuthProvider();
    return signInWithPopup(cmsAuth, provider);
  };

  const signOutAdmin = async () => {
    return signOut(cmsAuth);
  };

  return {
    user,
    isAdmin,
    roleLabel,
    loading,
    signInEmail,
    signInGoogle,
    signOutAdmin,
  };
}

/**
 * Sanitizes and writes a document + immutable revision record atomically,
 * strictly obeying `isValidPlatformCmsDoc` and `isValidPlatformCmsRevision` in `firestore.rules`.
 */
export async function saveCmsDoc(docData, changeNote = '') {
  const user = cmsAuth.currentUser;
  if (!user) {
    throw new Error('Sign in with an authorized Oneova Admin account first.');
  }

  const cleanId = String(docData.id || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9-_]/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '')
    .slice(0, 80);

  if (!cleanId) {
    throw new Error('Document slug ID is required.');
  }

  const docType = ['feature', 'policy', 'regulation'].includes(docData.docType)
    ? docData.docType
    : 'policy';

  const actorName = String(user.displayName || user.email || 'Oneova Admin')
    .trim()
    .slice(0, 120);

  const cleanSections = (Array.isArray(docData.sections) ? docData.sections : [])
    .slice(0, 40)
    .map(normalizeSection)
    .filter((s) => s.heading || s.summary || s.callout || s.bullets.length > 0);

  const cleanSnapshot = {
    id: cleanId,
    docType,
    category: String(docData.category || 'Community & Safety').trim().slice(0, 80) || 'General',
    policyTab: String(docData.policyTab || '').trim().slice(0, 80),
    title: String(docData.title || cleanId).trim().slice(0, 160),
    badge: String(docData.badge || 'OFFICIAL').trim().slice(0, 40) || 'OFFICIAL',
    isAccentBadge: Boolean(docData.isAccentBadge),
    inShort:
      String(docData.inShort || docData.title || 'Official Oneova documentation.')
        .trim()
        .slice(0, 800),
    readTime: String(docData.readTime || '4 min read').trim().slice(0, 40),
    version: String(docData.version || 'v1.0').trim().slice(0, 40),
    effectiveDate: String(docData.effectiveDate || 'October 25, 2026').trim().slice(0, 80),
    order: Number.isFinite(Number(docData.order)) ? Math.round(Number(docData.order)) : 10,
    isPublished: docData.isPublished !== false,
    sections: cleanSections,
    htmlOverride: String(docData.htmlOverride || '').trim().slice(0, 80000),
  };

  const note = String(changeNote || docData.changeNote || 'Live web admin update')
    .trim()
    .slice(0, 1000);

  const docRef = doc(cmsDb, CMS_COLLECTION, cleanId);
  const revRef = doc(collection(docRef, 'revisions'));

  const batch = writeBatch(cmsDb);
  batch.set(docRef, {
    ...cleanSnapshot,
    updatedAt: serverTimestamp(),
    updatedByUid: user.uid,
    updatedByName: actorName,
    changeNote: note,
  });

  batch.set(revRef, {
    version: cleanSnapshot.version,
    actorUid: user.uid,
    actorName,
    changeNote: note,
    createdAt: serverTimestamp(),
    snapshot: cleanSnapshot,
  });

  await batch.commit();
  return cleanId;
}

/**
 * Seeds any baseline documents not yet stored in Firestore so mobile & web admins
 * can edit all 18 documents directly in the cloud.
 */
export async function seedMissingCatalogDocs() {
  const user = cmsAuth.currentUser;
  if (!user) {
    throw new Error('Sign in with an Admin account to sync catalog.');
  }
  const snap = await getDocs(collection(cmsDb, CMS_COLLECTION));
  const existingIds = new Set(snap.docs.map((d) => d.id));

  let seeded = 0;
  for (const item of PLATFORM_BASELINE_DOCS) {
    if (!existingIds.has(item.id)) {
      await saveCmsDoc(item, 'Initial baseline sync to live cloud');
      seeded += 1;
    }
  }
  return seeded;
}

/**
 * Streams the latest 25 immutable revisions for a document.
 */
export function subscribeRevisions(docId, onUpdate, onError) {
  if (!docId) return () => {};
  const revCol = collection(doc(cmsDb, CMS_COLLECTION, docId), 'revisions');
  const q = query(revCol, orderBy('createdAt', 'desc'), limit(25));
  return onSnapshot(
    q,
    (snap) => {
      const list = snap.docs.map((d) => {
        const data = d.data() || {};
        return {
          id: d.id,
          version: String(data.version || 'v1.0'),
          actorUid: String(data.actorUid || ''),
          actorName: String(data.actorName || 'Oneova Admin'),
          changeNote: String(data.changeNote || ''),
          createdAt:
            data.createdAt && typeof data.createdAt.toDate === 'function'
              ? data.createdAt.toDate()
              : null,
          snapshot: data.snapshot || null,
        };
      });
      onUpdate(list);
    },
    (err) => {
      if (onError) onError(err);
    }
  );
}

/**
 * Rolls back a document to a previous revision snapshot (writes a new revision audit entry).
 */
export async function rollbackToRevision(docId, revision) {
  if (!revision || !revision.snapshot) {
    throw new Error('Revision snapshot is empty.');
  }
  return saveCmsDoc(
    { ...revision.snapshot, id: docId },
    `Rolled back to ${revision.version}`
  );
}

/**
 * Deletes a cloud override (restores baseline if built-in, or removes custom doc).
 */
export async function deleteCmsDoc(docId) {
  const docRef = doc(cmsDb, CMS_COLLECTION, docId);
  await deleteDoc(docRef);
}
