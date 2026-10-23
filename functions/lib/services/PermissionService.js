"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.PermissionService = void 0;
const firestore_1 = require("firebase-admin/firestore");
class PermissionService {
    /**
     * Validates if a user can access a specific conversation.
     * Enforces AIAccessMode and standard participants checks.
     */
    static async canAccessConversation(userId, conversationId) {
        const db = (0, firestore_1.getFirestore)();
        const doc = await db.collection('conversations').doc(conversationId).get();
        if (!doc.exists) {
            return false;
        }
        const data = doc.data();
        // Check AI Access Mode constraint
        if ((data === null || data === void 0 ? void 0 : data.aiAccessMode) === 'never') {
            return false;
        }
        // Check participation
        const participants = (data === null || data === void 0 ? void 0 : data.participants) || [];
        if (!participants.includes(userId)) {
            return false;
        }
        return true;
    }
    /**
     * Validates if a user can read another user's profile.
     * Right now, this assumes basic profiles are public, but we can extend this.
     */
    static async canAccessProfile(requesterId, targetUserId) {
        // Basic logic: users can read profiles, but private data should be stripped by the caller.
        return true;
    }
}
exports.PermissionService = PermissionService;
//# sourceMappingURL=PermissionService.js.map