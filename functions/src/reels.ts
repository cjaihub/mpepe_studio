/**
 * Reels upload trigger.
 *
 * Flow:
 *  1. The app creates content/{contentId} with status "uploading".
 *  2. The app uploads reels/uploads/{uid}/{contentId}/original.<ext>.
 *  3. This trigger checks ownership, marks the doc "processing" and starts
 *     the `reels-transcode` Cloud Run Job (our own FFmpeg container in
 *     /reels_worker), passing the object path as env overrides.
 *  4. The job writes the HLS ladder to the public reels bucket and sets the
 *     doc to "ready" (or "failed").
 *
 * The job does the heavy work so this function stays small and cheap.
 */
import { onObjectFinalized } from 'firebase-functions/v2/storage';
import { defineString } from 'firebase-functions/params';
import { logger } from 'firebase-functions';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { google } from 'googleapis';

const reelsJobName = defineString('REELS_JOB_NAME', { default: 'reels-transcode' });
const reelsJobRegion = defineString('REELS_JOB_REGION', { default: 'us-central1' });

const UPLOAD_PATH = /^reels\/uploads\/([^/]+)\/([^/]+)\/original\.[A-Za-z0-9]+$/;

export const onReelUploaded = onObjectFinalized(
  { region: 'us-central1', memory: '256MiB', timeoutSeconds: 60 },
  async (event) => {
    const objectName = event.data.name ?? '';
    const match = UPLOAD_PATH.exec(objectName);
    if (!match) return; // Not a reel upload.

    const [, uid, contentId] = match;
    const db = getFirestore();
    const ref = db.collection('content').doc(contentId);

    // Ownership check: storage rules guarantee the path uid is the uploader,
    // and the doc must belong to that same user. Stops anyone from pointing
    // their upload at someone else's post.
    const claimed = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) {
        logger.warn('Reel upload with no content doc', { contentId, uid });
        return false;
      }
      const data = snap.data()!;
      if (data.authorId !== uid) {
        logger.warn('Reel upload author mismatch', { contentId, uid });
        return false;
      }
      if (data.status !== 'uploading') {
        // Duplicate trigger delivery or re-upload: process once only.
        logger.info('Reel already claimed', { contentId, status: data.status });
        return false;
      }
      tx.update(ref, {
        status: 'processing',
        processingStartedAt: FieldValue.serverTimestamp(),
      });
      return true;
    });
    if (!claimed) return;

    try {
      const project = process.env.GCLOUD_PROJECT ?? process.env.GCP_PROJECT;
      const auth = new google.auth.GoogleAuth({
        scopes: ['https://www.googleapis.com/auth/cloud-platform'],
      });
      const run = google.run({ version: 'v2', auth });
      await run.projects.locations.jobs.run({
        name: `projects/${project}/locations/${reelsJobRegion.value()}/jobs/${reelsJobName.value()}`,
        requestBody: {
          overrides: {
            containerOverrides: [
              {
                env: [
                  { name: 'SOURCE_BUCKET', value: event.data.bucket },
                  { name: 'SOURCE_OBJECT', value: objectName },
                  { name: 'CONTENT_ID', value: contentId },
                ],
              },
            ],
          },
        },
      });
      logger.info('Reel transcode started', { contentId });
    } catch (err) {
      logger.error('Could not start reel transcode', { contentId, err: String(err) });
      await ref.update({ status: 'failed', processingError: 'could_not_start' });
    }
  },
);
