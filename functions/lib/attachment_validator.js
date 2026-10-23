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
exports.validateAttachment = void 0;
const storage_1 = require("firebase-functions/v2/storage");
const storage_2 = require("firebase-admin/storage");
const fileType = __importStar(require("file-type"));
// Ensure Firebase admin is initialized in index.ts
/**
 * Validates uploaded attachments in the staging bucket.
 *
 * 1. Triggers when a new file hits /staging/{conversationId}/{userId}/{fileName}
 * 2. Downloads the first few bytes of the file.
 * 3. Uses `file-type` to verify the magic bytes.
 * 4. Rejects if it doesn't match the allowed extensions or claimed extension.
 * 5. Moves to /secure_attachments/{conversationId}/{fileName} if valid.
 */
exports.validateAttachment = (0, storage_1.onObjectFinalized)(async (event) => {
    const object = event.data;
    const filePath = object.name;
    if (!filePath || !filePath.startsWith('staging/')) {
        return; // Ignore files not in staging
    }
    const bucket = (0, storage_2.getStorage)().bucket(object.bucket);
    const file = bucket.file(filePath);
    try {
        // Download first chunk to read magic bytes (e.g. 4100 bytes is usually enough)
        const [buffer] = await file.download({ start: 0, end: 4100 });
        const type = await fileType.fromBuffer(buffer);
        if (!type) {
            console.warn(`[Attachment Validation Failed] Could not determine file type for ${filePath}`);
            await file.delete();
            return;
        }
        // List of strictly allowed safe MIME types for production
        const allowedMimes = [
            'image/jpeg', 'image/png', 'image/webp', 'image/gif',
            'video/mp4', 'video/quicktime',
            'audio/mpeg', 'audio/aac', 'audio/ogg',
            'application/pdf'
        ];
        if (!allowedMimes.includes(type.mime)) {
            console.warn(`[Attachment Validation Failed] Invalid MIME type ${type.mime} for ${filePath}`);
            await file.delete();
            return;
        }
        // Move to secure_attachments
        const pathSegments = filePath.split('/');
        // path: staging / {conversationId} / {userId} / {fileName}
        if (pathSegments.length >= 4) {
            const conversationId = pathSegments[1];
            const fileName = pathSegments[3];
            const securePath = `secure_attachments/${conversationId}/${fileName}`;
            const secureFile = bucket.file(securePath);
            await file.move(secureFile);
            console.log(`[Attachment Validation Success] Moved ${fileName} to ${securePath}`);
            // Note: Cloud Function could also update the Firestore `Attachment` document 
            // here to set status = 'ready' and inject the final storagePath.
        }
    }
    catch (error) {
        console.error(`[Attachment Validation Error] Failed processing ${filePath}:`, error);
        await file.delete(); // Fail closed
    }
});
//# sourceMappingURL=attachment_validator.js.map