"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.enqueueComputeJob = enqueueComputeJob;
exports.leaseNextComputeJob = leaseNextComputeJob;
exports.updateComputeJobProgress = updateComputeJobProgress;
exports.completeComputeJob = completeComputeJob;
exports.handlePreemptionOrFailure = handlePreemptionOrFailure;
const firestore_1 = require("firebase-admin/firestore");
const crypto = __importStar(require("crypto"));
/**
 * Enqueues a new compute job in `computeJobs/{jobId}` with priority lane and 72-hour TTL.
 */
async function enqueueComputeJob(userId, userTier, taskType, inputPayload, options) {
    var _a, _b;
    const db = (0, firestore_1.getFirestore)();
    const jobId = (options === null || options === void 0 ? void 0 : options.jobId) || `cjob_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;
    const now = firestore_1.Timestamp.now();
    const ttlHours = (_a = options === null || options === void 0 ? void 0 : options.ttlHours) !== null && _a !== void 0 ? _a : 72;
    const expiresAt = firestore_1.Timestamp.fromMillis(now.toMillis() + ttlHours * 60 * 60 * 1000);
    // Map userTier to Priority Lane (Biz -> biz lane, Pro -> pro lane, Free -> free lane)
    const priorityLane = userTier === 'biz' ? 'biz' : userTier === 'pro' ? 'pro' : 'free';
    const job = {
        id: jobId,
        userId,
        userTier,
        taskType,
        priorityLane,
        status: 'queued',
        progress: 0.0,
        inputPayload,
        retryCount: 0,
        maxRetries: (_b = options === null || options === void 0 ? void 0 : options.maxRetries) !== null && _b !== void 0 ? _b : 3,
        createdAt: now,
        updatedAt: now,
        expiresAt,
    };
    await db.collection('computeJobs').doc(jobId).set(job);
    return job;
}
/**
 * Leases the next available compute job honoring strict priority order (biz > pro > free).
 * Used by Cloud Run GPU interactive workers and GKE Spot GPU batch workers.
 */
async function leaseNextComputeJob(workerId, allowedLanes = ['biz', 'pro', 'free']) {
    const db = (0, firestore_1.getFirestore)();
    // Try each priority lane in strict priority sequence
    for (const lane of allowedLanes) {
        const query = db
            .collection('computeJobs')
            .where('status', '==', 'queued')
            .where('priorityLane', '==', lane)
            .orderBy('createdAt', 'asc')
            .limit(1);
        const snapshot = await query.get();
        if (!snapshot.empty) {
            const doc = snapshot.docs[0];
            const jobRef = doc.ref;
            // Atomic transaction to secure lease
            const leasedJob = await db.runTransaction(async (tx) => {
                var _a;
                const freshSnap = await tx.get(jobRef);
                if (!freshSnap.exists || ((_a = freshSnap.data()) === null || _a === void 0 ? void 0 : _a.status) !== 'queued') {
                    return null;
                }
                const now = firestore_1.Timestamp.now();
                const updateData = {
                    status: 'leased',
                    workerId,
                    leasedAt: now,
                    updatedAt: now,
                };
                tx.update(jobRef, updateData);
                return Object.assign(Object.assign({}, freshSnap.data()), updateData);
            });
            if (leasedJob) {
                return leasedJob;
            }
        }
    }
    return null;
}
/**
 * Updates execution progress of an active compute job.
 */
async function updateComputeJobProgress(jobId, progress, status = 'processing') {
    const db = (0, firestore_1.getFirestore)();
    const clampedProgress = Math.max(0.0, Math.min(1.0, progress));
    await db.collection('computeJobs').doc(jobId).update({
        progress: clampedProgress,
        status,
        updatedAt: firestore_1.Timestamp.now(),
    });
}
/**
 * Marks a compute job as successfully completed with output payload.
 */
async function completeComputeJob(jobId, resultPayload) {
    const db = (0, firestore_1.getFirestore)();
    const now = firestore_1.Timestamp.now();
    await db.collection('computeJobs').doc(jobId).update({
        status: 'completed',
        progress: 1.0,
        resultPayload,
        completedAt: now,
        updatedAt: now,
    });
}
/**
 * Handles Spot GPU node preemption or transient failures by incrementing retry count
 * and returning the job to the 'queued' state if retries remain.
 */
async function handlePreemptionOrFailure(jobId, errorReason, isPreemption = false) {
    const db = (0, firestore_1.getFirestore)();
    const jobRef = db.collection('computeJobs').doc(jobId);
    return db.runTransaction(async (tx) => {
        const snap = await tx.get(jobRef);
        if (!snap.exists) {
            return { reQueued: false, finalStatus: 'failed' };
        }
        const job = snap.data();
        const now = firestore_1.Timestamp.now();
        if (job.retryCount < job.maxRetries) {
            // Re-queue with incremented retry count
            tx.update(jobRef, {
                status: 'queued',
                workerId: null,
                leasedAt: null,
                retryCount: job.retryCount + 1,
                error: isPreemption ? `Spot node preempted; retrying (${job.retryCount + 1}/${job.maxRetries})` : errorReason,
                updatedAt: now,
            });
            return { reQueued: true, finalStatus: 'queued' };
        }
        else {
            // Retries exhausted
            tx.update(jobRef, {
                status: 'failed',
                error: `Exceeded max retries (${job.maxRetries}). Last error: ${errorReason}`,
                updatedAt: now,
            });
            return { reQueued: false, finalStatus: 'failed' };
        }
    });
}
//# sourceMappingURL=computeJobSystem.js.map