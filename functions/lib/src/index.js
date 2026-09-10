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
exports.publishToSocials = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
admin.initializeApp();
const db = admin.firestore();
exports.publishToSocials = functions.https.onCall(async (data, context) => {
    // Enforce authentication
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in.');
    }
    const userId = context.auth.uid;
    const { taskId, destinations, storageUrl, metadata } = data;
    if (!taskId || !destinations || !storageUrl) {
        throw new functions.https.HttpsError('invalid-argument', 'Missing required fields.');
    }
    const taskRef = db.collection(`users/${userId}/uploadTasks`).doc(taskId);
    // Initialize task in Firestore
    await taskRef.set({
        taskId,
        status: 'uploading',
        progress: 0.1,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        destinations,
        metadata
    });
    // Mock Background Process
    // In a real implementation, we would download the file from `storageUrl` 
    // and use axios to push it to the Meta Graph API and YouTube Data API.
    // Simulate processing time
    setTimeout(async () => {
        try {
            await taskRef.update({ progress: 0.5, status: 'uploading' });
            // Simulated processing
            const publishedLinks = {};
            for (const dest of destinations) {
                if (dest.platform === 'youtube') {
                    publishedLinks['youtube'] = 'https://youtube.com/watch?v=sample';
                }
                else if (dest.platform === 'facebook') {
                    publishedLinks['facebook'] = 'https://facebook.com/sample/video';
                }
                else if (dest.platform === 'instagram') {
                    publishedLinks['instagram'] = 'https://instagram.com/p/sample';
                }
                else if (dest.platform === 'tiktok') {
                    publishedLinks['tiktok'] = 'https://tiktok.com/@sample/video/123';
                }
            }
            await taskRef.update({
                progress: 1.0,
                status: 'completed',
                publishedLinks
            });
        }
        catch (e) {
            await taskRef.update({
                status: 'failed',
                errorMessage: e.message
            });
        }
    }, 3000); // Wait 3 seconds to simulate upload
    return { success: true, taskId };
});
//# sourceMappingURL=index.js.map