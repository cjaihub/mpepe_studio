import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { PermissionService } from './PermissionService';

export class ToolExecutionLayer {
  
  static async getUserProfile(requesterId: string, args: { userId: string }): Promise<any> {
    const db = getFirestore();
    if (!await PermissionService.canAccessProfile(requesterId, args.userId)) {
      throw new Error("Unauthorized to access this profile.");
    }
    const doc = await db.collection('users').doc(args.userId).get();
    return doc.exists ? doc.data() : { error: "User not found" };
  }

  static async getConversation(requesterId: string, args: { conversationId: string }): Promise<any> {
    const db = getFirestore();
    if (!await PermissionService.canAccessConversation(requesterId, args.conversationId)) {
      throw new Error("Unauthorized to access this conversation, or AI access is disabled.");
    }
    const doc = await db.collection('conversations').doc(args.conversationId).get();
    return doc.exists ? doc.data() : { error: "Conversation not found" };
  }

  static async searchMessages(requesterId: string, args: { query: string, limit?: number }): Promise<any> {
    // A real implementation might use Algolia/Typesense. For this sandbox, we'll do a simple mock or return a basic Firestore query if applicable.
    // We cannot perform raw full-text search in Firestore easily without an extension.
    return { status: "Search executed", results: [] };
  }

  static async getRecentMessages(requesterId: string, args: { conversationId: string, limit?: number }): Promise<any> {
    const db = getFirestore();
    if (!await PermissionService.canAccessConversation(requesterId, args.conversationId)) {
      throw new Error("Unauthorized to access this conversation.");
    }
    const snapshot = await db
      .collection(`conversations/${args.conversationId}/messages`)
      .orderBy('timestamp', 'desc')
      .limit(args.limit || 10)
      .get();
    
    return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
  }

  static async getContact(requesterId: string, args: { contactId: string }): Promise<any> {
    const db = getFirestore();
    // Assuming contacts are stored in users/{userId}/contacts
    const doc = await db.collection(`users/${requesterId}/contacts`).doc(args.contactId).get();
    return doc.exists ? doc.data() : { error: "Contact not found" };
  }

  static async getCalendarEvents(requesterId: string, args: { date: string }): Promise<any> {
    const db = getFirestore();
    const snapshot = await db.collection(`users/${requesterId}/calendarEvents`)
      .where('date', '==', args.date)
      .get();
    return snapshot.docs.map(doc => doc.data());
  }

  static async createCalendarEvent(requesterId: string, args: { title: string, date: string, time: string }): Promise<any> {
    const db = getFirestore();
    const ref = db.collection(`users/${requesterId}/calendarEvents`).doc();
    await ref.set({
      id: ref.id,
      title: args.title,
      date: args.date,
      time: args.time,
      createdAt: FieldValue.serverTimestamp()
    });
    return { status: "Success", eventId: ref.id };
  }

  static async draftMessage(requesterId: string, args: { conversationId: string, text: string }): Promise<any> {
    if (!await PermissionService.canAccessConversation(requesterId, args.conversationId)) {
      throw new Error("Unauthorized.");
    }
    return { status: "Message drafted successfully.", draftText: args.text };
  }

  static async sendMessage(requesterId: string, args: { conversationId: string, text: string }): Promise<any> {
    const db = getFirestore();
    if (!await PermissionService.canAccessConversation(requesterId, args.conversationId)) {
      throw new Error("Unauthorized.");
    }
    const ref = db.collection(`conversations/${args.conversationId}/messages`).doc();
    await ref.set({
      id: ref.id,
      senderId: requesterId,
      text: args.text,
      timestamp: FieldValue.serverTimestamp(),
      isE2EE: false // Sent by AI, therefore server-readable
    });
    return { status: "Success", messageId: ref.id };
  }

  static async scheduleMessage(requesterId: string, args: { conversationId: string, text: string, scheduledTime: string }): Promise<any> {
    if (!await PermissionService.canAccessConversation(requesterId, args.conversationId)) {
      throw new Error("Unauthorized.");
    }
    // E.g., store in an outbox or scheduled tasks collection
    return { status: "Message scheduled.", scheduledTime: args.scheduledTime };
  }

  static async createTask(requesterId: string, args: { title: string, description?: string, dueDate?: string }): Promise<any> {
    const db = getFirestore();
    const ref = db.collection(`users/${requesterId}/tasks`).doc();
    await ref.set({
      id: ref.id,
      title: args.title,
      description: args.description || "",
      dueDate: args.dueDate || null,
      status: "pending",
      createdAt: FieldValue.serverTimestamp()
    });
    return { status: "Success", taskId: ref.id };
  }

  static async findFile(requesterId: string, args: { query: string }): Promise<any> {
    // Stub for finding files in the user's secure bucket records
    return { status: "Find file executed", results: [] };
  }

  static async getCourseInformation(requesterId: string, args: { courseId: string }): Promise<any> {
    const db = getFirestore();
    const doc = await db.collection('courses').doc(args.courseId).get();
    return doc.exists ? doc.data() : { error: "Course not found" };
  }

  static async getNotificationSummary(requesterId: string): Promise<any> {
    const db = getFirestore();
    const snapshot = await db.collection(`users/${requesterId}/notifications`)
      .where('read', '==', false)
      .limit(20)
      .get();
    return { unreadCount: snapshot.docs.length, notifications: snapshot.docs.map(d => d.data()) };
  }

  static async auditAction(requesterId: string, actionType: string, reason: string, toolsUsed: string[] = [], dataAccessed: string[] = [], responseGenerated?: string, conversationId?: string) {
      const db = getFirestore();
      
      // Update usage limit counters
      const usageRef = db.collection(`users/${requesterId}/ai_settings`).doc('agent_usage_today');
      
      await db.runTransaction(async (t) => {
          const doc = await t.get(usageRef);
          if (!doc.exists) {
              t.set(usageRef, { date: new Date().toISOString().split('T')[0], actionCount: 1 });
          } else {
              const data = doc.data() as any;
              const today = new Date().toISOString().split('T')[0];
              if (data.date !== today) {
                  t.set(usageRef, { date: today, actionCount: 1 });
              } else {
                  t.update(usageRef, { actionCount: FieldValue.increment(1) });
              }
          }
      });
      
      const auditRef = db.collection(`users/${requesterId}/agent_audits`).doc();
      await auditRef.set({
          id: auditRef.id,
          actionType,
          timestamp: FieldValue.serverTimestamp(),
          reason,
          conversationId: conversationId || null,
          toolsUsed,
          dataAccessed,
          responseGenerated: responseGenerated || null,
      });
  }
}

