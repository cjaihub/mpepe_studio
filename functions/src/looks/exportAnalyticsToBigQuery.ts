import { google } from 'googleapis';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';

export const BIGQUERY_DATASET = 'looks_analytics';
export const TABLE_AI_FEEDBACK = 'ai_skill_feedback';
export const TABLE_LOOK_EVENTS = 'look_events';
export const TABLE_COMPUTE_METRICS = 'compute_job_metrics';

export interface AiSkillFeedbackRecord {
  id: string;
  userId: string;
  skillId: string;
  skillVersion: string;
  action: string;
  accepted: boolean;
  userAdjustmentsJson: string;
  undoOccurred: boolean;
  latencyMs: number;
  createdAt: string;
}

export interface ComputeJobMetricRecord {
  jobId: string;
  userId: string;
  taskType: string;
  priorityLane: string;
  durationMs: number;
  status: string;
  retryCount: number;
  workerId: string;
  completedAt: string;
}

/**
 * BigQuery Table Schemas.
 */
export const bigQuerySchemas = {
  aiSkillFeedback: [
    { name: 'id', type: 'STRING', mode: 'REQUIRED' },
    { name: 'userId', type: 'STRING', mode: 'REQUIRED' },
    { name: 'skillId', type: 'STRING', mode: 'REQUIRED' },
    { name: 'skillVersion', type: 'STRING', mode: 'REQUIRED' },
    { name: 'action', type: 'STRING', mode: 'NULLABLE' },
    { name: 'accepted', type: 'BOOLEAN', mode: 'REQUIRED' },
    { name: 'userAdjustmentsJson', type: 'STRING', mode: 'NULLABLE' },
    { name: 'undoOccurred', type: 'BOOLEAN', mode: 'NULLABLE' },
    { name: 'latencyMs', type: 'INTEGER', mode: 'NULLABLE' },
    { name: 'createdAt', type: 'TIMESTAMP', mode: 'REQUIRED' },
  ],
  computeJobMetrics: [
    { name: 'jobId', type: 'STRING', mode: 'REQUIRED' },
    { name: 'userId', type: 'STRING', mode: 'REQUIRED' },
    { name: 'taskType', type: 'STRING', mode: 'REQUIRED' },
    { name: 'priorityLane', type: 'STRING', mode: 'REQUIRED' },
    { name: 'durationMs', type: 'INTEGER', mode: 'NULLABLE' },
    { name: 'status', type: 'STRING', mode: 'REQUIRED' },
    { name: 'retryCount', type: 'INTEGER', mode: 'NULLABLE' },
    { name: 'workerId', type: 'STRING', mode: 'NULLABLE' },
    { name: 'completedAt', type: 'TIMESTAMP', mode: 'REQUIRED' },
  ],
};

/**
 * Exports un-exported feedback signals from Firestore `aiSkillFeedback` collection to BigQuery.
 * Runs nightly or periodically to prevent Firestore collection growth while powering the
 * self-learning feedback loop (§8.4).
 */
export async function exportFeedbackBatchToBigQuery(
  projectId: string,
  batchSize: number = 500,
): Promise<{ exportedCount: number }> {
  const db = getFirestore();
  const auth = new google.auth.GoogleAuth({
    scopes: ['https://www.googleapis.com/auth/bigquery'],
  });
  const bigquery = google.bigquery({ version: 'v2', auth });

  const querySnap = await db
    .collection('aiSkillFeedback')
    .where('exportedToBigQuery', '==', false)
    .limit(batchSize)
    .get();

  if (querySnap.empty) {
    return { exportedCount: 0 };
  }

  const rows: any[] = [];
  const docRefs: FirebaseFirestore.DocumentReference[] = [];

  querySnap.forEach((doc) => {
    const data = doc.data();
    rows.push({
      insertId: doc.id,
      json: {
        id: doc.id,
        userId: data.userId || 'anonymous',
        skillId: data.skillId || 'unknown',
        skillVersion: data.skillVersion || '1.0.0',
        action: data.action || 'grade',
        accepted: data.accepted ?? true,
        userAdjustmentsJson: JSON.stringify(data.userAdjustments || {}),
        undoOccurred: data.undoOccurred ?? false,
        latencyMs: data.latencyMs || 0,
        createdAt: data.createdAt?.toDate?.() ? data.createdAt.toDate().toISOString() : new Date().toISOString(),
      },
    });
    docRefs.push(doc.ref);
  });

  try {
    await bigquery.tabledata.insertAll({
      projectId,
      datasetId: BIGQUERY_DATASET,
      tableId: TABLE_AI_FEEDBACK,
      requestBody: { rows },
    });

    // Mark as exported in a batched write
    const batch = db.batch();
    for (const ref of docRefs) {
      batch.update(ref, { exportedToBigQuery: true, exportedAt: Timestamp.now() });
    }
    await batch.commit();

    console.log(`[BigQueryExport] Successfully exported ${rows.length} rows to ${BIGQUERY_DATASET}.${TABLE_AI_FEEDBACK}`);
    return { exportedCount: rows.length };
  } catch (err) {
    console.warn(`[BigQueryExport] BigQuery insertAll skipped or failed (table may need provisioning): ${err}`);
    return { exportedCount: 0 };
  }
}

/**
 * Scheduled function running nightly at 03:00 UTC to offload feedback to BigQuery.
 */
export const scheduledFeedbackBigQueryExport = onSchedule('0 3 * * *', async () => {
  const projectId = process.env.GCLOUD_PROJECT || 'mpepe-2b4bd';
  await exportFeedbackBatchToBigQuery(projectId, 1000);
});
