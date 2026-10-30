/**
 * Per-account settings, read the way the app writes them.
 *
 * The app keeps every setting in one doc, `user_settings/{uid}`, one map per
 * category (lib/backend/settings/account_settings_schema.dart). Until this
 * build is deployed, it also mirrors the categories the functions read
 * (notifications, aiAgent) to their old docs; this helper reads the canonical
 * category first and falls back to the old doc, so either source works.
 */
import { getFirestore } from 'firebase-admin/firestore';

export async function readAccountSettings(
  uid: string,
  category: string,
  legacyPath: string,
): Promise<Record<string, unknown>> {
  const db = getFirestore();
  const [canonical, legacy] = await Promise.all([
    db.collection('user_settings').doc(uid).get(),
    db.doc(`users/${uid}/${legacyPath}`).get(),
  ]);
  const section = canonical.get(category);
  const current = section && typeof section === 'object' ? (section as Record<string, unknown>) : {};
  return { ...(legacy.data() ?? {}), ...current };
}
