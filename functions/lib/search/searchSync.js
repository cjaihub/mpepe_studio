"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onMessageIndexUpdate = exports.onUserIndexUpdate = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const firestore_2 = require("firebase-admin/firestore");
const searchUtils_1 = require("./searchUtils");
const db = (0, firestore_2.getFirestore)();
const searchIndexRef = db.collection('search_index');
/**
 * Triggers when a new User profile is created/updated.
 * Indexes the user for global people search.
 */
exports.onUserIndexUpdate = (0, firestore_1.onDocumentWritten)('users/{userId}', async (event) => {
    const userId = event.params.userId;
    const change = event.data;
    if (!change)
        return;
    if (!change.after.exists) {
        // User was deleted
        await searchIndexRef.doc(userId).delete();
        return;
    }
    const userData = change.after.data();
    if (!userData)
        return;
    const displayName = userData.displayName || '';
    const username = userData.username || '';
    const bio = userData.bio || '';
    const contentToEmbed = `${displayName} @${username} ${bio}`;
    // For people, we might allow everyone to see them, or rely on specific ACLs.
    // Assuming public visibility for basic profiles.
    const searchDoc = {
        id: userId,
        type: 'person',
        title: displayName,
        subtitle: `@${username}`,
        content: bio,
        keywords: (0, searchUtils_1.generateKeywords)(contentToEmbed),
        metadata: {
            avatarUrl: userData.avatarUrl || null,
        },
        createdAt: userData.createdAt || firestore_2.FieldValue.serverTimestamp(),
        updatedAt: firestore_2.FieldValue.serverTimestamp(),
        acl_users: [],
        acl_public: true,
        // embedding: await generateEmbedding(contentToEmbed), // Optional for users
    };
    await searchIndexRef.doc(userId).set(searchDoc, { merge: true });
});
/**
 * Triggers when a Message is created in any conversation.
 * Syncs the message to the search index and restricts it to conversation participants.
 */
exports.onMessageIndexUpdate = (0, firestore_1.onDocumentWritten)('conversations/{conversationId}/messages/{messageId}', async (event) => {
    var _a;
    const { conversationId, messageId } = event.params;
    const change = event.data;
    if (!change)
        return;
    if (!change.after.exists) {
        await searchIndexRef.doc(messageId).delete();
        return;
    }
    const msgData = change.after.data();
    if (!msgData)
        return;
    // Fetch conversation participants for ACL
    const convDoc = await db.collection('conversations').doc(conversationId).get();
    const participants = ((_a = convDoc.data()) === null || _a === void 0 ? void 0 : _a.participants) || [];
    const text = msgData.text || '';
    const senderId = msgData.senderId;
    const hasAttachment = (msgData.attachments && msgData.attachments.length > 0) || !!msgData.mediaUrl;
    const searchDoc = {
        id: messageId,
        type: 'message',
        title: 'Message',
        content: text,
        keywords: (0, searchUtils_1.generateKeywords)(text),
        metadata: {
            conversationId,
            senderId,
            hasAttachment,
        },
        createdAt: msgData.timestamp || firestore_2.FieldValue.serverTimestamp(),
        updatedAt: firestore_2.FieldValue.serverTimestamp(),
        acl_users: participants, // STRICT PERMISSIONS: Only participants can see this result
        acl_public: false,
    };
    // Note: Generating embeddings for EVERY message can be expensive.
    // Let's assume we do exact keyword matching for messages for now.
    await searchIndexRef.doc(messageId).set(searchDoc, { merge: true });
});
//# sourceMappingURL=searchSync.js.map