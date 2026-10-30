"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.DEFAULT_NUM_SHARDS = void 0;
exports.incrementShardedCounter = incrementShardedCounter;
exports.getShardedCount = getShardedCount;
const firestore_1 = require("firebase-admin/firestore");
exports.DEFAULT_NUM_SHARDS = 10;
/**
 * Server-side Firestore sharded counter increment.
 * Distributes write traffic randomly across N shards to prevent hot document contention.
 */
async function incrementShardedCounter(collectionPath, docId, counterName, numShards = exports.DEFAULT_NUM_SHARDS, amount = 1) {
    const db = (0, firestore_1.getFirestore)();
    const shardId = `shard_${Math.floor(Math.random() * numShards)}`;
    const shardRef = db
        .collection(collectionPath)
        .doc(docId)
        .collection('shards')
        .doc(shardId);
    await shardRef.set({
        [counterName]: firestore_1.FieldValue.increment(amount),
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
}
/**
 * Computes aggregate sum across all shards for a given counter.
 */
async function getShardedCount(collectionPath, docId, counterName) {
    const db = (0, firestore_1.getFirestore)();
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
//# sourceMappingURL=shardedCounter.js.map