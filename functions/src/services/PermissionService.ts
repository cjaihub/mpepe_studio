import { getFirestore } from 'firebase-admin/firestore';

export class PermissionService {
  /**
   * Validates if a user can access a specific conversation.
   * Enforces AIAccessMode and standard participants checks.
   */
  static async canAccessConversation(userId: string, conversationId: string): Promise<boolean> {
    const db = getFirestore();
    const doc = await db.collection('conversations').doc(conversationId).get();
    
    if (!doc.exists) {
      return false;
    }

    const data = doc.data();
    
    // Check AI Access Mode constraint
    if (data?.aiAccessMode === 'never') {
      return false;
    }
    
    // Check participation
    const participants = data?.participants || [];
    if (!participants.includes(userId)) {
      return false;
    }

    return true;
  }

  /**
   * Validates if a user can read another user's profile.
   * Right now, this assumes basic profiles are public, but we can extend this.
   */
  static async canAccessProfile(requesterId: string, targetUserId: string): Promise<boolean> {
    // Basic logic: users can read profiles, but private data should be stripped by the caller.
    return true; 
  }
}
