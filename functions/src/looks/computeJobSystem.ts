import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import * as crypto from 'crypto';

export type PriorityLane = 'biz' | 'pro' | 'free';

export type ComputeTaskType =
  | 'cloud_render'
  | 'rotoscope'
  | 'ai_enhance'
  | 'sky_replace'
  | 'relight'
  | 'batch_grade';

export type JobStatus =
  | 'queued'
  | 'leased'
  | 'processing'
  | 'completed'
  | 'failed'
  | 'cancelled';

export interface ComputeJob {
  id: string;
  userId: string;
  userTier: 'free' | 'pro' | 'biz';
  taskType: ComputeTaskType;
  priorityLane: PriorityLane;
  status: JobStatus;
  progress: number; // 0.0 to 1.0
  inputPayload: Record<string, any>;
  resultPayload?: Record<string, any>;
  error?: string | null;
  workerId?: string | null;
  retryCount: number;
  maxRetries: number;
  createdAt: Timestamp;
  updatedAt: Timestamp;
  leasedAt?: Timestamp | null;
  completedAt?: Timestamp | null;
  expiresAt: Timestamp; // Firestore TTL policy automatically purges old jobs
}

/**
 * Enqueues a new compute job in `computeJobs/{jobId}` with priority lane and 72-hour TTL.
 */
export async function enqueueComputeJob(
  userId: string,
  userTier: 'free' | 'pro' | 'biz',
  taskType: ComputeTaskType,
  inputPayload: Record<string, any>,
  options?: {
    jobId?: string;
    maxRetries?: number;
    ttlHours?: number;
  },
): Promise<ComputeJob> {
  const db = getFirestore();
  const jobId = options?.jobId || `cjob_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;
  const now = Timestamp.now();
  const ttlHours = options?.ttlHours ?? 72;
  const expiresAt = Timestamp.fromMillis(now.toMillis() + ttlHours * 60 * 60 * 1000);

  // Map userTier to Priority Lane (Biz -> biz lane, Pro -> pro lane, Free -> free lane)
  const priorityLane: PriorityLane = userTier === 'biz' ? 'biz' : userTier === 'pro' ? 'pro' : 'free';

  const job: ComputeJob = {
    id: jobId,
    userId,
    userTier,
    taskType,
    priorityLane,
    status: 'queued',
    progress: 0.0,
    inputPayload,
    retryCount: 0,
    maxRetries: options?.maxRetries ?? 3,
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
export async function leaseNextComputeJob(
  workerId: string,
  allowedLanes: PriorityLane[] = ['biz', 'pro', 'free'],
): Promise<ComputeJob | null> {
  const db = getFirestore();

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
        const freshSnap = await tx.get(jobRef);
        if (!freshSnap.exists || freshSnap.data()?.status !== 'queued') {
          return null;
        }

        const now = Timestamp.now();
        const updateData = {
          status: 'leased' as JobStatus,
          workerId,
          leasedAt: now,
          updatedAt: now,
        };

        tx.update(jobRef, updateData);
        return { ...(freshSnap.data() as ComputeJob), ...updateData };
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
export async function updateComputeJobProgress(
  jobId: string,
  progress: number,
  status: JobStatus = 'processing',
): Promise<void> {
  const db = getFirestore();
  const clampedProgress = Math.max(0.0, Math.min(1.0, progress));

  await db.collection('computeJobs').doc(jobId).update({
    progress: clampedProgress,
    status,
    updatedAt: Timestamp.now(),
  });
}

/**
 * Marks a compute job as successfully completed with output payload.
 */
export async function completeComputeJob(
  jobId: string,
  resultPayload: Record<string, any>,
): Promise<void> {
  const db = getFirestore();
  const now = Timestamp.now();

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
export async function handlePreemptionOrFailure(
  jobId: string,
  errorReason: string,
  isPreemption: boolean = false,
): Promise<{ reQueued: boolean; finalStatus: JobStatus }> {
  const db = getFirestore();
  const jobRef = db.collection('computeJobs').doc(jobId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(jobRef);
    if (!snap.exists) {
      return { reQueued: false, finalStatus: 'failed' };
    }

    const job = snap.data() as ComputeJob;
    const now = Timestamp.now();

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
    } else {
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
