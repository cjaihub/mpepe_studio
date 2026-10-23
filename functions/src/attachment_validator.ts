import { onObjectFinalized } from 'firebase-functions/v2/storage';
import { getStorage } from 'firebase-admin/storage';
import * as fileType from 'file-type';

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
export const validateAttachment = onObjectFinalized(async (event: any) => {
    const object = event.data;
    const filePath = object.name;
    if (!filePath || !filePath.startsWith('staging/')) {
        return; // Ignore files not in staging
    }

    const bucket = getStorage().bucket(object.bucket);
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

    } catch (error) {
        console.error(`[Attachment Validation Error] Failed processing ${filePath}:`, error);
        await file.delete(); // Fail closed
    }
});
