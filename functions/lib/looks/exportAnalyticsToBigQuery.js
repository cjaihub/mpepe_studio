"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.scheduledFeedbackBigQueryExport = exports.bigQuerySchemas = exports.TABLE_COMPUTE_METRICS = exports.TABLE_LOOK_EVENTS = exports.TABLE_AI_FEEDBACK = exports.BIGQUERY_DATASET = void 0;
exports.exportFeedbackBatchToBigQuery = exportFeedbackBatchToBigQuery;
const googleapis_1 = require("googleapis");
const firestore_1 = require("firebase-admin/firestore");
const scheduler_1 = require("firebase-functions/v2/scheduler");
exports.BIGQUERY_DATASET = 'looks_analytics';
exports.TABLE_AI_FEEDBACK = 'ai_skill_feedback';
exports.TABLE_LOOK_EVENTS = 'look_events';
exports.TABLE_COMPUTE_METRICS = 'compute_job_metrics';
/**
 * BigQuery Table Schemas.
 */
exports.bigQuerySchemas = {
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
async function exportFeedbackBatchToBigQuery(projectId, batchSize = 500) {
    const db = (0, firestore_1.getFirestore)();
    const auth = new googleapis_1.google.auth.GoogleAuth({
        scopes: ['https://www.googleapis.com/auth/bigquery'],
    });
    const bigquery = googleapis_1.google.bigquery({ version: 'v2', auth });
    const querySnap = await db
        .collection('aiSkillFeedback')
        .where('exportedToBigQuery', '==', false)
        .limit(batchSize)
        .get();
    if (querySnap.empty) {
        return { exportedCount: 0 };
    }
    const rows = [];
    const docRefs = [];
    querySnap.forEach((doc) => {
        var _a, _b;
        var _c, _d;
        const data = doc.data();
        rows.push({
            insertId: doc.id,
            json: {
                id: doc.id,
                userId: data.userId || 'anonymous',
                skillId: data.skillId || 'unknown',
                skillVersion: data.skillVersion || '1.0.0',
                action: data.action || 'grade',
                accepted: (_c = data.accepted) !== null && _c !== void 0 ? _c : true,
                userAdjustmentsJson: JSON.stringify(data.userAdjustments || {}),
                undoOccurred: (_d = data.undoOccurred) !== null && _d !== void 0 ? _d : false,
                latencyMs: data.latencyMs || 0,
                createdAt: ((_b = (_a = data.createdAt) === null || _a === void 0 ? void 0 : _a.toDate) === null || _b === void 0 ? void 0 : _b.call(_a)) ? data.createdAt.toDate().toISOString() : new Date().toISOString(),
            },
        });
        docRefs.push(doc.ref);
    });
    try {
        await bigquery.tabledata.insertAll({
            projectId,
            datasetId: exports.BIGQUERY_DATASET,
            tableId: exports.TABLE_AI_FEEDBACK,
            requestBody: { rows },
        });
        // Mark as exported in a batched write
        const batch = db.batch();
        for (const ref of docRefs) {
            batch.update(ref, { exportedToBigQuery: true, exportedAt: firestore_1.Timestamp.now() });
        }
        await batch.commit();
        console.log(`[BigQueryExport] Successfully exported ${rows.length} rows to ${exports.BIGQUERY_DATASET}.${exports.TABLE_AI_FEEDBACK}`);
        return { exportedCount: rows.length };
    }
    catch (err) {
        console.warn(`[BigQueryExport] BigQuery insertAll skipped or failed (table may need provisioning): ${err}`);
        return { exportedCount: 0 };
    }
}
/**
 * Scheduled function running nightly at 03:00 UTC to offload feedback to BigQuery.
 */
exports.scheduledFeedbackBigQueryExport = (0, scheduler_1.onSchedule)('0 3 * * *', async () => {
    const projectId = process.env.GCLOUD_PROJECT || 'mpepe-2b4bd';
    await exportFeedbackBatchToBigQuery(projectId, 1000);
});
//# sourceMappingURL=exportAnalyticsToBigQuery.js.map