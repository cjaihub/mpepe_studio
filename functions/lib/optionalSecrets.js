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
exports.optionalSecret = optionalSecret;
/**
 * Secrets that are read at run time instead of being bound to a function.
 *
 * A secret bound with `secrets: [defineSecret(...)]` must exist before
 * `firebase deploy` will run at all, so one missing optional secret blocks
 * every deploy in the codebase. Features that can simply switch themselves off
 * (Oneova's security-email sender, per-user Gmail) read their secrets here and
 * get `null` when the secret is missing or not readable.
 *
 * Access: the functions' runtime service account needs Secret Accessor on
 * each secret, once:
 *   gcloud secrets add-iam-policy-binding NAME --project mpepe-2b4bd \
 *     --member serviceAccount:90836164478-compute@developer.gserviceaccount.com \
 *     --role roles/secretmanager.secretAccessor
 */
const googleapis_1 = require("googleapis");
const logger = __importStar(require("firebase-functions/logger"));
const cache = new Map();
const TTL_MS = 10 * 60 * 1000;
function projectId() {
    var _a, _b;
    if (process.env.GCLOUD_PROJECT)
        return process.env.GCLOUD_PROJECT;
    try {
        return (_b = JSON.parse((_a = process.env.FIREBASE_CONFIG) !== null && _a !== void 0 ? _a : '{}').projectId) !== null && _b !== void 0 ? _b : '';
    }
    catch (_c) {
        return '';
    }
}
/** Latest value of secret [name], or null when it's missing, "unset" or unreadable. */
async function optionalSecret(name) {
    var _a;
    const hit = cache.get(name);
    if (hit && Date.now() - hit.at < TTL_MS)
        return hit.value;
    let value = null;
    try {
        const auth = new googleapis_1.google.auth.GoogleAuth({ scopes: ['https://www.googleapis.com/auth/cloud-platform'] });
        const sm = googleapis_1.google.secretmanager({ version: 'v1', auth });
        const res = await sm.projects.secrets.versions.access({ name: `projects/${projectId()}/secrets/${name}/versions/latest` });
        const data = (_a = res.data.payload) === null || _a === void 0 ? void 0 : _a.data;
        const text = data ? Buffer.from(data, 'base64').toString('utf8').trim() : '';
        value = text && text.toLowerCase() !== 'unset' ? text : null;
    }
    catch (e) {
        const code = e.code;
        logger.warn(`[optionalSecret] ${name} not available (${code !== null && code !== void 0 ? code : e}); the feature that needs it is off.`);
    }
    cache.set(name, { value, at: Date.now() });
    return value;
}
//# sourceMappingURL=optionalSecrets.js.map