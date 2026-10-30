"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.readAccountSettings = readAccountSettings;
/**
 * Per-account settings, read the way the app writes them.
 *
 * The app keeps every setting in one doc, `user_settings/{uid}`, one map per
 * category (lib/backend/settings/account_settings_schema.dart). Until this
 * build is deployed, it also mirrors the categories the functions read
 * (notifications, aiAgent) to their old docs; this helper reads the canonical
 * category first and falls back to the old doc, so either source works.
 */
const firestore_1 = require("firebase-admin/firestore");
async function readAccountSettings(uid, category, legacyPath) {
    var _a;
    const db = (0, firestore_1.getFirestore)();
    const [canonical, legacy] = await Promise.all([
        db.collection('user_settings').doc(uid).get(),
        db.doc(`users/${uid}/${legacyPath}`).get(),
    ]);
    const section = canonical.get(category);
    const current = section && typeof section === 'object' ? section : {};
    return Object.assign(Object.assign({}, ((_a = legacy.data()) !== null && _a !== void 0 ? _a : {})), current);
}
//# sourceMappingURL=accountSettings.js.map