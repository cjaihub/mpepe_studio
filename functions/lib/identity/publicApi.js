"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.idPublic = void 0;
/**
 * Public, account-free checks used by oneova.web.app/verify (and anyone):
 *   GET /idPublic/jwks             the issuer's public key
 *   GET /idPublic/status?c=&s=     is this credential / share still valid?
 * Returns no personal data; the claims travel only inside the signed token.
 */
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const common_1 = require("./common");
const credentials_1 = require("./credentials");
const ID = /^[0-9a-f-]{36}$/;
exports.idPublic = (0, https_1.onRequest)({ secrets: [credentials_1.signingJwk], cors: true, memory: '256MiB' }, async (req, res) => {
    var _a;
    var _b, _c, _d;
    res.set('Cache-Control', 'no-store');
    const path = req.path.replace(/\/+$/, '');
    if (req.method !== 'GET') {
        res.status(405).json({ error: 'GET only' });
        return;
    }
    if (path.endsWith('/jwks')) {
        res.set('Cache-Control', 'public, max-age=3600');
        res.json((0, credentials_1.publicJwks)());
        return;
    }
    if (path.endsWith('/status')) {
        const c = String((_b = req.query.c) !== null && _b !== void 0 ? _b : '');
        const s = String((_c = req.query.s) !== null && _c !== void 0 ? _c : '');
        if (!ID.test(c)) {
            res.status(400).json({ error: 'bad id' });
            return;
        }
        const st = await (0, common_1.db)().doc(`identityStatus/${c}`).get();
        if (!st.exists) {
            res.json({ credential: 'unknown' });
            return;
        }
        const exp = (_d = (_a = st.get('expiresAt')) === null || _a === void 0 ? void 0 : _a.toMillis()) !== null && _d !== void 0 ? _d : 0;
        const credential = st.get('status') === 'valid' && exp > Date.now() ? 'valid' : st.get('status') === 'valid' ? 'expired' : String(st.get('status'));
        let share;
        if (ID.test(s)) {
            const ref = (0, common_1.db)().doc(`identity/${st.get('uid')}/shares/${s}`);
            const sh = await ref.get();
            if (!sh.exists || sh.get('credentialId') !== c)
                share = 'unknown';
            else if (sh.get('revokedAt'))
                share = 'revoked';
            else if (sh.get('expiresAt').toMillis() < Date.now())
                share = 'expired';
            else {
                share = 'valid';
                await ref.update({ views: firestore_1.FieldValue.increment(1), lastViewedAt: firestore_1.FieldValue.serverTimestamp() });
            }
        }
        res.json({ credential, share, kind: st.get('kind') });
        return;
    }
    res.status(404).json({ error: 'not found' });
});
//# sourceMappingURL=publicApi.js.map