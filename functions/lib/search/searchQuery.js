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
var __rest = (this && this.__rest) || function (s, e) {
    var t = {};
    for (var p in s) if (Object.prototype.hasOwnProperty.call(s, p) && e.indexOf(p) < 0)
        t[p] = s[p];
    if (s != null && typeof Object.getOwnPropertySymbols === "function")
        for (var i = 0, p = Object.getOwnPropertySymbols(s); i < p.length; i++) {
            if (e.indexOf(p[i]) < 0 && Object.prototype.propertyIsEnumerable.call(s, p[i]))
                t[p[i]] = s[p[i]];
        }
    return t;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.globalSemanticSearch = void 0;
const https_1 = require("firebase-functions/v2/https");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_1 = require("firebase-admin/firestore");
const vertexAi_1 = require("../vertexAi");
const db = (0, firestore_1.getFirestore)();
/**
 * Smart search: Gemini (Vertex AI, the function's service account) turns a
 * natural-language query ("funny cooking videos in swahili") into a few short
 * search terms and hashtags. The app runs its normal Firestore search for
 * each term (people, hashtags, posts) and merges the results, so everything
 * shown is real content the person is allowed to see. Any entries in
 * `search_index` that match a term (and pass their ACL) are returned too.
 */
async function expandQuery(query) {
    var _a;
    var _b, _c, _d;
    try {
        const res = await (0, vertexAi_1.vertexAi)().models.generateContent({
            model: 'gemini-2.5-flash',
            contents: [{ role: 'user', parts: [{ text: query.slice(0, 300) }] }],
            config: {
                systemInstruction: 'You turn a search on a social video app into search terms. Reply ONLY with JSON {"terms":["..."]}: ' +
                    'up to 5 short terms (1-2 words, lowercase), most specific first, including likely hashtags without "#" ' +
                    'and the key words of the query itself. Keep the language of the query. No explanations.',
                responseMimeType: 'application/json',
                temperature: 0.2,
                maxOutputTokens: 120,
                thinkingConfig: { thinkingBudget: 0 },
            },
        });
        const parsed = JSON.parse((_c = (_a = ((_b = res.text) !== null && _b !== void 0 ? _b : '').match(/\{[\s\S]*\}/)) === null || _a === void 0 ? void 0 : _a[0]) !== null && _c !== void 0 ? _c : '{}');
        const terms = Array.isArray(parsed.terms) ? parsed.terms : [];
        return [...new Set(terms.filter((t) => typeof t === 'string').map((t) => t.trim().toLowerCase().replace(/^#/, '')).filter(Boolean))]
            .slice(0, 5);
    }
    catch (e) {
        logger.warn('query expansion failed', (_d = e === null || e === void 0 ? void 0 : e.message) !== null && _d !== void 0 ? _d : e);
        return [];
    }
}
exports.globalSemanticSearch = (0, https_1.onCall)(async (request) => {
    var _a;
    if (!request.auth) {
        throw new https_1.HttpsError('unauthenticated', 'You must be logged in to search.');
    }
    const userId = request.auth.uid;
    const { query, limit = 20, type } = (_a = request.data) !== null && _a !== void 0 ? _a : {};
    if (!query || typeof query !== 'string') {
        throw new https_1.HttpsError('invalid-argument', 'A valid query string is required.');
    }
    try {
        const words = query.toLowerCase().split(/\s+/).filter(Boolean);
        const expanded = await expandQuery(query);
        const terms = [...new Set([...expanded, ...words])].slice(0, 6);
        let baseQuery = db.collection('search_index');
        if (type)
            baseQuery = baseQuery.where('type', '==', type);
        const searchResults = [];
        if (terms.length > 0) {
            const results = await baseQuery
                .where('keywords', 'array-contains-any', terms.slice(0, 10))
                .limit(Math.min(Number(limit) || 20, 50))
                .get();
            results.forEach((doc) => {
                const docData = doc.data();
                const canAccess = docData.acl_public === true || (docData.acl_users && docData.acl_users.includes(userId));
                if (canAccess) {
                    // eslint-disable-next-line @typescript-eslint/no-unused-vars
                    const { embedding, keywords, acl_public, acl_users } = docData, safeData = __rest(docData, ["embedding", "keywords", "acl_public", "acl_users"]);
                    searchResults.push(Object.assign({ id: doc.id }, safeData));
                }
            });
        }
        return { results: searchResults, count: searchResults.length, terms: expanded };
    }
    catch (error) {
        logger.error('Search failed', error);
        throw new https_1.HttpsError('internal', 'An error occurred while searching.');
    }
});
//# sourceMappingURL=searchQuery.js.map