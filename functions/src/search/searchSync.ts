import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { SearchIndexDocument } from '../types/search';
import { generateKeywords } from './searchUtils';

const db = getFirestore();
const searchIndexRef = db.collection('search_index');

/**
 * Triggers when a new User profile is created/updated.
 * Indexes the user for global people search.
 */
export const onUserIndexUpdate = onDocumentWritten('users/{userId}', async (event) => {
    const userId = event.params.userId;
    const change = event.data;
    if (!change) return;

    if (!change.after.exists) {
      // User was deleted
      await searchIndexRef.doc(userId).delete();
      return;
    }

    const userData = change.after.data();
    if (!userData) return;

    const displayName = userData.displayName || '';
    const username = userData.username || '';
    const bio = userData.bio || '';
    
    const contentToEmbed = `${displayName} @${username} ${bio}`;
    
    // For people, we might allow everyone to see them, or rely on specific ACLs.
    // Assuming public visibility for basic profiles.
    const searchDoc: SearchIndexDocument = {
      id: userId,
      type: 'person',
      title: displayName,
      subtitle: `@${username}`,
      content: bio,
      keywords: generateKeywords(contentToEmbed),
      metadata: {
        avatarUrl: userData.avatarUrl || null,
      },
      createdAt: userData.createdAt || FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp() as any,
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
export const onMessageIndexUpdate = onDocumentWritten('conversations/{conversationId}/messages/{messageId}', async (event) => {
    const { conversationId, messageId } = event.params;
    const change = event.data;
    if (!change) return;

    if (!change.after.exists) {
      await searchIndexRef.doc(messageId).delete();
      return;
    }

    const msgData = change.after.data();
    if (!msgData) return;

    // Fetch conversation participants for ACL
    const convDoc = await db.collection('conversations').doc(conversationId).get();
    const participants: string[] = convDoc.data()?.participants || [];

    const text = msgData.text || '';
    const senderId = msgData.senderId;
    const hasAttachment = (msgData.attachments && msgData.attachments.length > 0) || !!msgData.mediaUrl;

    const searchDoc: SearchIndexDocument = {
      id: messageId,
      type: 'message',
      title: 'Message',
      content: text,
      keywords: generateKeywords(text),
      metadata: {
        conversationId,
        senderId,
        hasAttachment,
      },
      createdAt: msgData.timestamp || FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp() as any,
      acl_users: participants, // STRICT PERMISSIONS: Only participants can see this result
      acl_public: false,
    };

    // Note: Generating embeddings for EVERY message can be expensive.
    // Let's assume we do exact keyword matching for messages for now.
    
    await searchIndexRef.doc(messageId).set(searchDoc, { merge: true });
  });
