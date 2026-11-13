"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.db = void 0;
exports.callerUid = callerUid;
exports.requireAdmin = requireAdmin;
exports.cleanUid = cleanUid;
exports.audit = audit;
exports.adminAudit = adminAudit;
exports.deleteFolder = deleteFolder;
exports.notify = notify;
exports.syncBadges = syncBadges;
/**
 * Oneova ID shared helpers: caller checks, the audit trail, folder cleanup
 * and the badge fields on users/{uid} and biz_shops/{uid}.
 *
 * Everything under identity/, business_identity/ and kyb_requirements/ is
 * written only from here (see firestore.rules).
 */
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const storage_1 = require("firebase-admin/storage");
const db = () => (0, firestore_1.getFirestore)();
exports.db = db;
function callerUid(req) {
    var _a;
    const id = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!id)
        throw new https_1.HttpsError('unauthenticated', 'Sign in first.');
    return id;
}
async function requireAdmin(req) {
    var _a;
    const uid = callerUid(req);
    const role = String((_a = (await (0, exports.db)().doc(`users/${uid}`).get()).get('role')) !== null && _a !== void 0 ? _a : '');
    if (!['admin', 'owner', 'founder'].includes(role))
        throw new https_1.HttpsError('permission-denied', 'Admins only.');
    return uid;
}
function cleanUid(v) {
    const s = String(v !== null && v !== void 0 ? v : '');
    if (!s || s.length > 128 || s.includes('/'))
        throw new https_1.HttpsError('invalid-argument', 'Missing user.');
    return s;
}
/** One line in the user's own audit log. Never holds document numbers or images. */
async function audit(uid, type, actor, detail = '') {
    await (0, exports.db)().collection(`identity/${uid}/audit`).add({
        type, actor, detail: detail.slice(0, 200), at: firestore_1.FieldValue.serverTimestamp(),
    });
}
/** Reviewer actions also go to the dashboard's audit log. */
async function adminAudit(actorUid, action, targetId, reason = '', details = {}) {
    await (0, exports.db)().collection('admin_audit').add({
        actorUid, action, targetType: action.split('.')[0], targetId, reason: reason.slice(0, 300), details, via: 'identity',
        at: firestore_1.FieldValue.serverTimestamp(),
    });
}
async function deleteFolder(prefix) {
    const bucket = (0, storage_1.getStorage)().bucket();
    const [files] = await bucket.getFiles({ prefix });
    await Promise.all(files.map((f) => f.delete({ ignoreNotFound: true })));
    return files.length;
}
async function notify(uid, id, title, body, deepLink) {
    await (0, exports.db)().collection('notifications').doc(id).set({
        userId: uid, recipientId: uid, category: 'system', priority: 'high', type: 'identity',
        title, body, deepLink, isRead: false, createdAt: firestore_1.FieldValue.serverTimestamp(),
    });
}
/**
 * Recomputes the public badge fields from the two sources of truth
 * (kyc/{uid} and business_identity/{uid}). The tick is only removed when
 * Oneova ID set it, so ticks granted by the team before Oneova ID stay.
 */
async function syncBadges(uid) {
    var _a;
    const [kyc, biz, user] = await Promise.all([
        (0, exports.db)().doc(`kyc/${uid}`).get(), (0, exports.db)().doc(`business_identity/${uid}`).get(), (0, exports.db)().doc(`users/${uid}`).get(),
    ]);
    const personal = kyc.get('status') === 'verified' ? 2 : 0;
    const bizVerified = biz.get('status') === 'verified';
    const bizLevel = bizVerified ? Number((_a = biz.get('level')) !== null && _a !== void 0 ? _a : 1) : 0;
    const ours = !user.get('verifiedBy') || user.get('verifiedBy') === 'oneova_id';
    if (user.exists) {
        const patch = { identityLevel: personal, businessLevel: bizLevel };
        if (personal > 0 || bizVerified) {
            patch.isVerified = true;
            if (ours)
                patch.verifiedBy = 'oneova_id';
        }
        else if (ours && user.get('isVerified') === true) {
            patch.isVerified = false;
            patch.verifiedBy = firestore_1.FieldValue.delete();
        }
        await user.ref.set(patch, { merge: true });
    }
    const shop = (0, exports.db)().doc(`biz_shops/${uid}`);
    if ((await shop.get()).exists)
        await shop.update({ verified: bizVerified, verifiedLevel: bizLevel });
}
//# sourceMappingURL=common.js.map