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
exports.idReviewFiles = exports.idRetention = exports.kybExpiry = exports.kybRequirementsSave = exports.kybDelete = exports.kybReview = exports.kybOwnerRespond = exports.kybSubmit = exports.kybStart = exports.kybRequirements = void 0;
/**
 * Verified Business (business identity). One status for the profile, the
 * store portal and the 3D shops: business_identity/{uid}, mirrored to
 * biz_shops/{uid}.verified / verifiedLevel by syncBadges.
 *
 *   app → kybRequirements  what this country usually needs
 *   app → kybStart         opens a check; private folder kyb/{uid}/{sessionId}/
 *   app                    uploads {documentKey}.jpg|png|pdf
 *   app → kybSubmit        details + owners → "review" (+ AI pre-check for the reviewer)
 *   owner → kybOwnerRespond confirms or declines being listed as an owner
 *   admin → kybReview      level 1 (registered) or 2 (verified business) / reject
 *   app → kybDelete        deletes documents and the record, removes the badge
 *   daily kybExpiry        yearly re-check; badge drops when it lapses
 */
const crypto = __importStar(require("crypto"));
const https_1 = require("firebase-functions/v2/https");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const storage_1 = require("firebase-admin/storage");
const vertexAi_1 = require("../vertexAi");
const common_1 = require("./common");
const credentials_1 = require("./credentials");
const requirements_1 = require("./requirements");
const cc = (v) => {
    const s = String(v !== null && v !== void 0 ? v : '').toUpperCase();
    if (!/^[A-Z]{2}$/.test(s))
        throw new https_1.HttpsError('invalid-argument', 'Choose a country.');
    return s;
};
const btype = (v) => {
    if (!requirements_1.BUSINESS_TYPES.includes(v))
        throw new https_1.HttpsError('invalid-argument', 'Choose a business type.');
    return v;
};
const text = (v, max) => String(v !== null && v !== void 0 ? v : '').trim().replace(/\s+/g, ' ').slice(0, max);
async function requirementsFor(country) {
    const stored = (await (0, common_1.db)().doc(`kyb_requirements/${country}`).get()).data();
    return (0, requirements_1.mergeRequirements)(country, stored);
}
exports.kybRequirements = (0, https_1.onCall)(async (req) => {
    var _a, _b;
    (0, common_1.callerUid)(req);
    const country = cc((_a = req.data) === null || _a === void 0 ? void 0 : _a.country);
    const type = ((_b = req.data) === null || _b === void 0 ? void 0 : _b.businessType) ? btype(req.data.businessType) : 'company';
    const r = await requirementsFor(country);
    return Object.assign(Object.assign({}, r), { documents: (0, requirements_1.docsFor)(r, type) });
});
exports.kybStart = (0, https_1.onCall)(async (req) => {
    var _a, _b;
    const uid = (0, common_1.callerUid)(req);
    const country = cc((_a = req.data) === null || _a === void 0 ? void 0 : _a.country);
    const businessType = btype((_b = req.data) === null || _b === void 0 ? void 0 : _b.businessType);
    const ref = (0, common_1.db)().doc(`business_identity/${uid}`);
    const cur = (await ref.get()).data();
    if ((cur === null || cur === void 0 ? void 0 : cur.status) === 'review')
        return { status: 'review' };
    if ((cur === null || cur === void 0 ? void 0 : cur.status) === 'verified')
        return { status: 'verified' };
    const sessionId = (cur === null || cur === void 0 ? void 0 : cur.status) === 'collecting' && cur.sessionId && cur.country === country ? String(cur.sessionId) : crypto.randomUUID();
    await ref.set({
        uid, status: 'collecting', sessionId, country, businessType, level: 0,
        startedAt: firestore_1.FieldValue.serverTimestamp(), updatedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    await (0, common_1.audit)(uid, 'business.started', 'you', `${country} · ${businessType}`);
    const r = await requirementsFor(country);
    return { status: 'collecting', sessionId, path: `kyb/${uid}/${sessionId}`, requirements: Object.assign(Object.assign({}, r), { documents: (0, requirements_1.docsFor)(r, businessType) }) };
});
async function uploadedKeys(path) {
    const [files] = await (0, storage_1.getStorage)().bucket().getFiles({ prefix: `${path}/` });
    const m = new Map();
    for (const f of files) {
        const name = f.name.slice(path.length + 1);
        const stem = name.replace(/\.(jpg|png|pdf)$/, '');
        m.set(stem, name);
    }
    return m;
}
/** Reads the documents for the reviewer. Never decides. Best effort. */
async function aiPreCheck(path, files, typed) {
    var _a, _b;
    try {
        const bucket = (0, storage_1.getStorage)().bucket();
        const parts = [{ text: `Typed by the applicant: ${JSON.stringify(typed)}. The files below are business documents, in this order: ${[...files.keys()].join(', ')}.` }];
        for (const [, name] of [...files.entries()].slice(0, 5)) {
            const [buf] = await bucket.file(`${path}/${name}`).download();
            if (buf.length > 7 * 1024 * 1024)
                continue;
            const mimeType = name.endsWith('.pdf') ? 'application/pdf' : name.endsWith('.png') ? 'image/png' : 'image/jpeg';
            parts.push({ inlineData: { mimeType, data: buf.toString('base64') } });
        }
        const res = await (0, vertexAi_1.generateVertexContent)({
            contents: [{ role: 'user', parts }],
            config: {
                systemInstruction: 'You help a human reviewer check business registration documents. Reply ONLY with JSON: ' +
                    '{"readable":true|false,"legalNameOnDocs":"name as printed or empty","nameMatches":"yes|no|unclear",' +
                    '"registrationNumberMatches":"yes|no|unclear","taxIdMatches":"yes|no|unclear","addressRecent":"yes|no|unclear",' +
                    '"ownersOnDocs":["names as printed"],"concerns":["short notes, e.g. edited, expired, screenshot, different company"]}. ' +
                    'Never guess text you cannot read.',
                responseMimeType: 'application/json',
                temperature: 0,
                maxOutputTokens: 600,
                thinkingConfig: { thinkingBudget: 0 },
            },
        });
        return JSON.parse((_a = res.text) !== null && _a !== void 0 ? _a : '{}');
    }
    catch (e) {
        logger.warn('kyb pre-check failed', (_b = e === null || e === void 0 ? void 0 : e.message) !== null && _b !== void 0 ? _b : e);
        return null;
    }
}
exports.kybSubmit = (0, https_1.onCall)({ timeoutSeconds: 120, memory: '512MiB' }, async (req) => {
    var _a, _b, _c, _d, _e, _f;
    var _g;
    const uid = (0, common_1.callerUid)(req);
    const ref = (0, common_1.db)().doc(`business_identity/${uid}`);
    const cur = (await ref.get()).data();
    const sessionId = String((_g = (_a = req.data) === null || _a === void 0 ? void 0 : _a.sessionId) !== null && _g !== void 0 ? _g : '');
    if (!cur || cur.status !== 'collecting' || cur.sessionId !== sessionId)
        throw new https_1.HttpsError('failed-precondition', 'Start the business check again.');
    if ((await (0, common_1.db)().doc(`kyc/${uid}`).get()).get('status') !== 'verified') {
        throw new https_1.HttpsError('failed-precondition', 'Verify your own identity first. A business is verified through its owner.');
    }
    const r = await requirementsFor(cur.country);
    const type = cur.businessType;
    const legalName = text((_b = req.data) === null || _b === void 0 ? void 0 : _b.legalName, 140);
    const registrationNumber = text((_c = req.data) === null || _c === void 0 ? void 0 : _c.registrationNumber, 40).toUpperCase();
    const taxId = text((_d = req.data) === null || _d === void 0 ? void 0 : _d.taxId, 40).toUpperCase();
    const address = text((_e = req.data) === null || _e === void 0 ? void 0 : _e.address, 240);
    if (legalName.length < 2)
        throw new https_1.HttpsError('invalid-argument', 'Enter the registered business name.');
    if (!(0, requirements_1.matches)(r.registrationNumber, registrationNumber))
        throw new https_1.HttpsError('invalid-argument', `Check the ${r.registrationNumber.label}.`);
    if (!(0, requirements_1.matches)(r.taxId, taxId))
        throw new https_1.HttpsError('invalid-argument', `Check the ${r.taxId.label}.`);
    if (address.length < 5)
        throw new https_1.HttpsError('invalid-argument', 'Enter the registered address.');
    const path = `kyb/${uid}/${sessionId}`;
    const files = await uploadedKeys(path);
    const missing = (0, requirements_1.docsFor)(r, type).filter((d) => d.required && !files.has(d.key)).map((d) => d.label);
    if (missing.length)
        throw new https_1.HttpsError('failed-precondition', `Still needed: ${missing.join(', ')}.`);
    // Owners: Oneova usernames + share. Each one confirms and verifies themselves.
    const rawOwners = Array.isArray((_f = req.data) === null || _f === void 0 ? void 0 : _f.owners) ? req.data.owners.slice(0, 10) : [];
    const owners = [];
    for (const o of rawOwners) {
        const username = text(o === null || o === void 0 ? void 0 : o.username, 40).replace(/^@/, '').toLowerCase();
        const share = Math.min(Math.max(Number(o === null || o === void 0 ? void 0 : o.share) || 0, 0), 100);
        if (!username)
            continue;
        const q = await (0, common_1.db)().collection('users').where('username', '==', username).limit(1).get();
        if (q.empty)
            throw new https_1.HttpsError('not-found', `No Oneova account @${username}.`);
        const ownerUid = q.docs[0].id;
        if (!owners.some((x) => x.uid === ownerUid))
            owners.push({ uid: ownerUid, username, share });
    }
    const batch = (0, common_1.db)().batch();
    const existing = await ref.collection('owners').get();
    existing.docs.forEach((d) => batch.delete(d.ref));
    for (const o of owners) {
        const self = o.uid === uid;
        batch.set(ref.collection('owners').doc(o.uid), {
            ownerUid: o.uid, username: o.username, share: o.share, status: self ? 'confirmed' : 'pending', idVerified: self, updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
        if (!self) {
            batch.set((0, common_1.db)().doc(`identity/${o.uid}/ownerInvites/${uid}`), {
                bizUid: uid, legalName, country: cur.country, share: o.share, status: 'pending', createdAt: firestore_1.FieldValue.serverTimestamp(),
            });
        }
    }
    batch.set(ref, {
        status: 'review', legalName, registrationNumber, taxIdLast4: taxId.slice(-4), taxId, address,
        files: [...files.values()], ownerCount: owners.length, submittedAt: firestore_1.FieldValue.serverTimestamp(), updatedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    await batch.commit();
    for (const o of owners.filter((x) => x.uid !== uid)) {
        await (0, common_1.notify)(o.uid, `kyb_owner_${uid}_${o.uid}`, 'Confirm business ownership', `${legalName} listed you as an owner. Confirm it in Oneova ID.`, '/id');
    }
    await (0, common_1.audit)(uid, 'business.submitted', 'you', `${files.size} documents, ${owners.length} owners`);
    const ai = await aiPreCheck(path, files, { legalName, registrationNumber, taxId, address });
    if (ai)
        await ref.set({ aiCheck: ai, aiCheckedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
    return { status: 'review' };
});
exports.kybOwnerRespond = (0, https_1.onCall)(async (req) => {
    var _a, _b;
    const uid = (0, common_1.callerUid)(req);
    const bizUid = (0, common_1.cleanUid)((_a = req.data) === null || _a === void 0 ? void 0 : _a.bizUid);
    const accept = ((_b = req.data) === null || _b === void 0 ? void 0 : _b.accept) === true;
    const invite = (0, common_1.db)().doc(`identity/${uid}/ownerInvites/${bizUid}`);
    if (!(await invite.get()).exists)
        throw new https_1.HttpsError('not-found', 'No such request.');
    const idVerified = (await (0, common_1.db)().doc(`kyc/${uid}`).get()).get('status') === 'verified';
    await invite.update({ status: accept ? 'confirmed' : 'declined', respondedAt: firestore_1.FieldValue.serverTimestamp() });
    await (0, common_1.db)().doc(`business_identity/${bizUid}/owners/${uid}`).set({
        status: accept ? 'confirmed' : 'declined', idVerified: accept && idVerified, updatedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    await (0, common_1.audit)(uid, accept ? 'business.owner_confirmed' : 'business.owner_declined', 'you');
    return { ok: true, idVerified };
});
exports.kybReview = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c, _d, _e;
    var _f, _g;
    const admin = await (0, common_1.requireAdmin)(req);
    const uid = (0, common_1.cleanUid)((_a = req.data) === null || _a === void 0 ? void 0 : _a.uid);
    const ref = (0, common_1.db)().doc(`business_identity/${uid}`);
    const b = (await ref.get()).data();
    if (!b || b.status !== 'review')
        throw new https_1.HttpsError('failed-precondition', 'Nothing to review for this business.');
    if (((_b = req.data) === null || _b === void 0 ? void 0 : _b.approve) === true) {
        const level = Number((_c = req.data) === null || _c === void 0 ? void 0 : _c.level) === 2 ? 2 : 1;
        if (level === 2) {
            // Refresh each owner's ID status, then require all confirmed + verified.
            const owners = await ref.collection('owners').get();
            for (const o of owners.docs) {
                const v = (await (0, common_1.db)().doc(`kyc/${o.id}`).get()).get('status') === 'verified';
                if (o.get('status') === 'confirmed' && o.get('idVerified') !== v)
                    await o.ref.update({ idVerified: v });
                if (o.get('status') !== 'confirmed' || !v)
                    throw new https_1.HttpsError('failed-precondition', `@${o.get('username')} hasn’t confirmed or isn’t ID-verified yet. Approve as level 1, or wait.`);
            }
        }
        const legalName = text((_f = (_d = req.data) === null || _d === void 0 ? void 0 : _d.legalName) !== null && _f !== void 0 ? _f : b.legalName, 140);
        const expiresAt = firestore_1.Timestamp.fromDate(new Date(Date.now() + 365 * 86400000));
        await ref.set({
            status: 'verified', level, legalName, reviewedBy: admin, verifiedAt: firestore_1.FieldValue.serverTimestamp(), expiresAt,
            updatedAt: firestore_1.FieldValue.serverTimestamp(), rejectReason: firestore_1.FieldValue.delete(),
        }, { merge: true });
        await (0, common_1.syncBadges)(uid);
        await (0, common_1.audit)(uid, 'business.verified', 'reviewer', level === 2 ? 'Verified Business' : 'Registered business');
        await (0, common_1.adminAudit)(admin, 'business.approve', uid, '', { level });
        await (0, common_1.notify)(uid, `kyb_ok_${uid}`, level === 2 ? 'Your business is verified ✅' : 'Your business is registered ✅', 'The badge now shows on your profile and your store.', '/id/business');
    }
    else {
        const reason = text((_g = (_e = req.data) === null || _e === void 0 ? void 0 : _e.reason) !== null && _g !== void 0 ? _g : 'We couldn’t confirm your business documents.', 240);
        await ref.set({ status: 'rejected', rejectReason: reason, reviewedBy: admin, updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
        await (0, common_1.syncBadges)(uid);
        await (0, common_1.audit)(uid, 'business.rejected', 'reviewer', reason);
        await (0, common_1.adminAudit)(admin, 'business.reject', uid, reason);
        await (0, common_1.notify)(uid, `kyb_no_${uid}_${Date.now()}`, 'Business check needs another try', reason, '/id/business');
    }
    return { ok: true };
});
exports.kybDelete = (0, https_1.onCall)({ timeoutSeconds: 120 }, async (req) => {
    var _a;
    const uid = (0, common_1.callerUid)(req);
    if (((_a = req.data) === null || _a === void 0 ? void 0 : _a.confirm) !== true)
        throw new https_1.HttpsError('failed-precondition', 'Confirm first.');
    const removed = await (0, common_1.deleteFolder)(`kyb/${uid}/`);
    await (0, credentials_1.revokeCredential)(uid, 'business');
    const ref = (0, common_1.db)().doc(`business_identity/${uid}`);
    const owners = await ref.collection('owners').get();
    const batch = (0, common_1.db)().batch();
    owners.docs.forEach((o) => {
        batch.delete(o.ref);
        if (o.id !== uid)
            batch.delete((0, common_1.db)().doc(`identity/${o.id}/ownerInvites/${uid}`));
    });
    batch.delete(ref);
    await batch.commit();
    await (0, common_1.syncBadges)(uid);
    await (0, common_1.audit)(uid, 'business.deleted', 'you', `Business data deleted (${removed} documents)`);
    return { ok: true, documentsDeleted: removed };
});
/** Admin: save a country's requirements (merged over the built-in ones). */
exports.kybRequirementsSave = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c;
    const admin = await (0, common_1.requireAdmin)(req);
    const country = ((_a = req.data) === null || _a === void 0 ? void 0 : _a.country) === 'default' ? 'default' : cc((_b = req.data) === null || _b === void 0 ? void 0 : _b.country);
    const r = (_c = req.data) === null || _c === void 0 ? void 0 : _c.requirements;
    if (!r || typeof r !== 'object')
        throw new https_1.HttpsError('invalid-argument', 'Missing requirements.');
    for (const f of [r.registrationNumber, r.taxId].filter(Boolean)) {
        try {
            new RegExp(String(f.pattern));
        }
        catch (_d) {
            throw new https_1.HttpsError('invalid-argument', `Bad pattern: ${f.pattern}`);
        }
    }
    await (0, common_1.db)().doc(`kyb_requirements/${country}`).set(Object.assign(Object.assign({}, r), { updatedBy: admin, updatedAt: firestore_1.FieldValue.serverTimestamp() }));
    await (0, common_1.adminAudit)(admin, 'kyb_requirements.save', country);
    return { ok: true };
});
/** Yearly re-check: the badge drops when a verification lapses. */
exports.kybExpiry = (0, scheduler_1.onSchedule)({ schedule: 'every day 03:10', timeZone: 'Africa/Nairobi' }, async () => {
    const due = await (0, common_1.db)().collection('business_identity').where('expiresAt', '<', firestore_1.Timestamp.now()).limit(300).get();
    for (const d of due.docs.filter((x) => x.get('status') === 'verified')) {
        await d.ref.set({ status: 'expired', expiredReason: 'Yearly re-check due.', updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
        await (0, credentials_1.revokeCredential)(d.id, 'business');
        await (0, common_1.syncBadges)(d.id);
        await (0, common_1.audit)(d.id, 'business.expired', 'system', 'Yearly re-check due');
        await (0, common_1.notify)(d.id, `kyb_exp_${d.id}_${Date.now()}`, 'Renew your business verification', 'It’s been a year. Upload fresh documents to keep the badge.', '/id/business');
    }
});
/** Retention: ID photos and business documents are deleted 30 days after a decision. */
exports.idRetention = (0, scheduler_1.onSchedule)({ schedule: 'every day 03:40', timeZone: 'Africa/Nairobi', timeoutSeconds: 540 }, async () => {
    var _a;
    var _b;
    const cutoff = Date.now() - 30 * 86400000;
    for (const [col, folder] of [['kyc', 'kyc'], ['business_identity', 'kyb']]) {
        for (const status of ['verified', 'rejected']) {
            const snap = await (0, common_1.db)().collection(col).where('status', '==', status).limit(300).get();
            for (const d of snap.docs) {
                if (d.get('filesPurgedAt'))
                    continue;
                const decided = (_b = (_a = d.get('updatedAt')) === null || _a === void 0 ? void 0 : _a.toMillis()) !== null && _b !== void 0 ? _b : Date.now();
                if (decided > cutoff)
                    continue;
                const n = await (0, common_1.deleteFolder)(`${folder}/${d.id}/`);
                await d.ref.set({ filesPurgedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
                if (n)
                    await (0, common_1.audit)(d.id, `${col === 'kyc' ? 'id' : 'business'}.files_deleted`, 'system', `${n} files deleted after 30 days`);
            }
        }
    }
});
/** Admin: lists, then fetches, the files of a check for review. Every view is logged. */
exports.idReviewFiles = (0, https_1.onCall)({ memory: '512MiB' }, async (req) => {
    var _a, _b, _c;
    const admin = await (0, common_1.requireAdmin)(req);
    const uid = (0, common_1.cleanUid)((_a = req.data) === null || _a === void 0 ? void 0 : _a.uid);
    const kind = ((_b = req.data) === null || _b === void 0 ? void 0 : _b.kind) === 'business' ? 'business' : 'person';
    const doc = (await (0, common_1.db)().doc(kind === 'person' ? `kyc/${uid}` : `business_identity/${uid}`).get()).data();
    if (!(doc === null || doc === void 0 ? void 0 : doc.sessionId))
        throw new https_1.HttpsError('not-found', 'No files.');
    const path = `${kind === 'person' ? 'kyc' : 'kyb'}/${uid}/${doc.sessionId}`;
    const name = ((_c = req.data) === null || _c === void 0 ? void 0 : _c.name) ? String(req.data.name) : null;
    if (!name) {
        const [files] = await (0, storage_1.getStorage)().bucket().getFiles({ prefix: `${path}/` });
        return { files: files.map((f) => f.name.slice(path.length + 1)) };
    }
    if (!/^[a-z0-9_]{2,40}\.(jpg|png|pdf)$/.test(name))
        throw new https_1.HttpsError('invalid-argument', 'Bad file.');
    const [buf] = await (0, storage_1.getStorage)().bucket().file(`${path}/${name}`).download();
    await (0, common_1.adminAudit)(admin, `${kind === 'person' ? 'kyc' : 'business'}.view_file`, uid, '', { name });
    const mime = name.endsWith('.pdf') ? 'application/pdf' : name.endsWith('.png') ? 'image/png' : 'image/jpeg';
    return { name, mime, b64: buf.toString('base64') };
});
//# sourceMappingURL=business.js.map