/**
 * Applies like and view counts from feed telemetry.
 *
 * The app only writes telemetry_events (rules force userId == the caller).
 * Counts on content docs are changed here, never by the app, and are
 * de-duplicated so they cannot be inflated by repeating an event:
 *  - like: once per user per video (content/{id}/likes/{uid})
 *  - viewCompletion: once per user per video per 30 minutes
 *    (content/{id}/views/{uid}); reels loop, so every loop must not count.
 * These marker subcollections are not readable or writable by the app.
 */
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';

const VIEW_WINDOW_MS = 30 * 60 * 1000;

export const onTelemetryEvent = onDocumentCreated(
  { document: 'telemetry_events/{eventId}', region: 'us-central1', memory: '256MiB' },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;
    const { userId, contentId, eventType } = data as {
      userId?: string; contentId?: string; eventType?: string;
    };
    if (!userId || !contentId || contentId === 'system') return;
    if (eventType !== 'like' && eventType !== 'viewCompletion') return;

    const db = getFirestore();
    const contentRef = db.collection('content').doc(contentId);

    try {
      await db.runTransaction(async (tx) => {
        const content = await tx.get(contentRef);
        if (!content.exists) return;

        if (eventType === 'like') {
          const likeRef = contentRef.collection('likes').doc(userId);
          if ((await tx.get(likeRef)).exists) return;
          tx.set(likeRef, { at: FieldValue.serverTimestamp() });
          tx.update(contentRef, { likeCount: FieldValue.increment(1) });
          return;
        }

        const viewRef = contentRef.collection('views').doc(userId);
        const last = (await tx.get(viewRef)).get('at') as Timestamp | undefined;
        if (last && Date.now() - last.toMillis() < VIEW_WINDOW_MS) return;
        tx.set(viewRef, { at: FieldValue.serverTimestamp() });
        tx.update(contentRef, { viewCount: FieldValue.increment(1) });
      });
    } catch (err) {
      logger.error('Could not apply telemetry count', { contentId, eventType, err: String(err) });
    }
  },
);
