import { getFirestore, FieldValue } from 'firebase-admin/firestore';

export const DEFAULT_NUM_SHARDS = 10;

/**
 * Server-side Firestore sharded counter increment.
 * Distributes write traffic randomly across N shards to prevent hot document contention.
 */
export async function incrementShardedCounter(
  collectionPath: string,
  docId: string,
  counterName: string,
  numShards: number = DEFAULT_NUM_SHARDS,
  amount: number = 1,
): Promise<void> {
  const db = getFirestore();
  const shardId = `shard_${Math.floor(Math.random() * numShards)}`;
  const shardRef = db
    .collection(collectionPath)
    .doc(docId)
    .collection('shards')
    .doc(shardId);

  await shardRef.set(
    {
      [counterName]: FieldValue.increment(amount),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

/**
 * Computes aggregate sum across all shards for a given counter.
 */
export async function getShardedCount(
  collectionPath: string,
  docId: string,
  counterName: string,
): Promise<number> {
  const db = getFirestore();
  const shardsSnap = await db
    .collection(collectionPath)
    .doc(docId)
    .collection('shards')
    .get();

  let total = 0;
  shardsSnap.forEach((doc) => {
    const val = doc.data()[counterName];
    if (typeof val === 'number') {
      total += val;
    }
  });

  return total;
}
