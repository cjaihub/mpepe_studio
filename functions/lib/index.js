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
var __exportStar = (this && this.__exportStar) || function(m, exports) {
    for (var p in m) if (p !== "default" && !Object.prototype.hasOwnProperty.call(exports, p)) __createBinding(exports, m, p);
};
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.lsLivekitWebhook = exports.lsShare = exports.lsReact = exports.lsMuteChat = exports.lsDeleteComment = exports.lsComment = exports.lsSetJoinRequests = exports.lsSetChatMode = exports.lsSecOnMemberWrite = exports.lsSecOnBlock = exports.lsSecOnIncident = exports.lsMediaKey = exports.lsPlayback = exports.lsSetTable = exports.lsLeaveStage = exports.lsModerate = exports.lsRespondRequest = exports.lsCancelRequest = exports.lsRequestJoin = exports.lsSetLayout = exports.lsSetSettings = exports.lsSetOwnMedia = exports.lsStateFull = exports.lsTime = exports.lsEnd = exports.lsToken = exports.lsStart = exports.globalSemanticSearch = exports.generateLiveApiToken = exports.aiGateway = exports.generateAbTests = exports.publishToSocials = exports.processAiCommand = void 0;
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-admin/firestore");
const axios_1 = __importDefault(require("axios"));
const googleapis_1 = require("googleapis");
const openRouterSecret = (0, params_1.defineSecret)('OPENROUTER_API_KEY');
admin.initializeApp();
const db = (0, firestore_1.getFirestore)();
exports.processAiCommand = (0, https_1.onCall)({ secrets: [openRouterSecret] }, async (request) => {
    var _a;
    if (!request.auth) {
        throw new https_1.HttpsError('unauthenticated', 'User must be logged in.');
    }
    const { transcript } = request.data;
    if (!transcript) {
        throw new https_1.HttpsError('invalid-argument', 'Missing transcript.');
    }
    const openrouterKey = openRouterSecret.value();
    if (!openrouterKey) {
        console.warn("OPENROUTER_API_KEY secret is not set. The call will fail.");
    }
    const isComplex = transcript.toLowerCase().includes('title') ||
        transcript.toLowerCase().includes('description') ||
        transcript.toLowerCase().includes('viral') ||
        transcript.toLowerCase().includes('share');
    const model = isComplex ? 'openai/gpt-4o' : 'openai/gpt-4o-mini';
    const systemPrompt = `
You are an AI Upload Manager for MPEPE Studio, a multi-platform video management tool.
Determine the user's intent from the following types:
- generateMetadata
- checkStatus
- publish
- crossPromote
- unknown

Return a JSON object matching this exact structure (no markdown):
{
  "intent": "generateMetadata" | "checkStatus" | "publish" | "crossPromote" | "unknown",
  "actionable_response": "A conversational response to speak back to the user",
  "metadata": {
     "title": "optional generated title",
     "description": "optional generated description",
     "tags": ["optional", "tags"],
     "share_text": "optional share caption"
  }
}
  `;
    try {
        const response = await axios_1.default.post('https://openrouter.ai/api/v1/chat/completions', {
            model: model,
            messages: [
                { role: 'system', content: systemPrompt },
                { role: 'user', content: transcript }
            ],
            response_format: { type: "json_object" }
        }, {
            headers: {
                'Authorization': `Bearer ${openrouterKey}`,
                'Content-Type': 'application/json'
            }
        });
        const aiContent = response.data.choices[0].message.content;
        const parsed = JSON.parse(aiContent);
        return { success: true, result: parsed };
    }
    catch (error) {
        console.error("OpenRouter Error: ", ((_a = error.response) === null || _a === void 0 ? void 0 : _a.data) || error.message);
        throw new https_1.HttpsError('internal', 'Failed to process AI command.');
    }
});
exports.publishToSocials = (0, https_1.onCall)(async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError('unauthenticated', 'User must be logged in.');
    }
    const userId = request.auth.uid;
    const { taskId, destinations, storageUrl, metadata, platformTokens } = request.data;
    if (!taskId || !destinations || !storageUrl || !platformTokens) {
        throw new https_1.HttpsError('invalid-argument', 'Missing required fields.');
    }
    const taskRef = db.collection(`users/${userId}/uploadTasks`).doc(taskId);
    await taskRef.set({
        taskId,
        status: 'uploading',
        progress: 0.1,
        createdAt: firestore_1.FieldValue.serverTimestamp(),
        destinations,
        metadata
    });
    // Background processing
    setTimeout(async () => {
        var _a, _b;
        try {
            await taskRef.update({ progress: 0.2, status: 'uploading' });
            const publishedLinks = {};
            for (const dest of destinations) {
                if (dest.platform === 'youtube') {
                    try {
                        const ytToken = platformTokens['youtube'];
                        if (!ytToken)
                            throw new Error("Missing YouTube token");
                        const oauth2Client = new googleapis_1.google.auth.OAuth2();
                        oauth2Client.setCredentials({ access_token: ytToken });
                        const youtube = googleapis_1.google.youtube({ version: 'v3', auth: oauth2Client });
                        // Download video stream from Firebase Storage public URL
                        const fileStream = (await (0, axios_1.default)({ url: storageUrl, method: 'GET', responseType: 'stream' })).data;
                        const ytMeta = metadata.ytMetadata || {};
                        const res = await youtube.videos.insert({
                            part: ['snippet', 'status'],
                            requestBody: {
                                snippet: {
                                    title: metadata.title || 'Untitled',
                                    description: metadata.description || '',
                                    tags: metadata.tags || [],
                                    categoryId: ytMeta.categoryId || '22',
                                    defaultLanguage: ytMeta.defaultLanguage,
                                    defaultAudioLanguage: ytMeta.defaultAudioLanguage,
                                },
                                status: {
                                    privacyStatus: ytMeta.privacyStatus || 'public',
                                    madeForKids: ytMeta.madeForKids || false,
                                    embeddable: ytMeta.embeddable !== false,
                                    publicStatsViewable: ytMeta.publicStatsViewable !== false,
                                }
                            },
                            media: {
                                body: fileStream
                            }
                        });
                        publishedLinks['youtube'] = `https://youtube.com/watch?v=${res.data.id}`;
                    }
                    catch (e) {
                        console.error("YouTube Error: ", e.message);
                        publishedLinks['youtube_error'] = e.message;
                    }
                }
                else if (dest.platform === 'facebook') {
                    try {
                        const fbToken = platformTokens['facebook'];
                        if (!fbToken)
                            throw new Error("Missing Facebook token");
                        const pageId = dest.pageId;
                        const res = await axios_1.default.post(`https://graph.facebook.com/v19.0/${pageId}/videos`, {
                            file_url: storageUrl,
                            title: metadata.title,
                            description: metadata.description,
                            access_token: fbToken
                        });
                        publishedLinks['facebook'] = `https://facebook.com/${res.data.id}`;
                    }
                    catch (e) {
                        console.error("Facebook Error: ", ((_a = e.response) === null || _a === void 0 ? void 0 : _a.data) || e.message);
                        publishedLinks['facebook_error'] = e.message;
                    }
                }
                else if (dest.platform === 'instagram') {
                    try {
                        const igToken = platformTokens['instagram'];
                        if (!igToken)
                            throw new Error("Missing Instagram token");
                        const igUserId = dest.metaUserId;
                        const containerRes = await axios_1.default.post(`https://graph.facebook.com/v19.0/${igUserId}/media`, {
                            video_url: storageUrl,
                            media_type: 'REELS',
                            caption: metadata.description,
                            access_token: igToken
                        });
                        const creationId = containerRes.data.id;
                        // Simple wait logic for IG video processing
                        await new Promise(resolve => setTimeout(resolve, 8000));
                        const publishRes = await axios_1.default.post(`https://graph.facebook.com/v19.0/${igUserId}/media_publish`, {
                            creation_id: creationId,
                            access_token: igToken
                        });
                        publishedLinks['instagram'] = `https://instagram.com/p/${publishRes.data.id}`;
                    }
                    catch (e) {
                        console.error("Instagram Error: ", ((_b = e.response) === null || _b === void 0 ? void 0 : _b.data) || e.message);
                        publishedLinks['instagram_error'] = e.message;
                    }
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
    }, 100);
    return { success: true, taskId };
});
exports.generateAbTests = (0, https_1.onCall)({ secrets: [openRouterSecret] }, async (request) => {
    var _a;
    if (!request.auth)
        throw new https_1.HttpsError('unauthenticated', 'User must be logged in.');
    const { contextPrompt } = request.data;
    const openrouterKey = openRouterSecret.value();
    if (!openrouterKey) {
        throw new https_1.HttpsError('internal', 'API key not configured.');
    }
    const prompt = `You are a master social media copywriter. Generate 3 highly viral, distinct A/B test variations for a video with the following context: "${contextPrompt}". 
Return ONLY a strictly valid JSON array of 3 objects with properties: "title" (string), "description" (string), "hashtags" (array of strings). Do not use markdown blocks, just return the raw JSON array.`;
    try {
        const response = await axios_1.default.post('https://openrouter.ai/api/v1/chat/completions', {
            model: 'google/gemini-pro',
            messages: [{ role: 'user', content: prompt }]
        }, {
            headers: {
                'Authorization': `Bearer ${openrouterKey}`,
                'Content-Type': 'application/json'
            }
        });
        const content = response.data.choices[0].message.content.trim();
        let parsed;
        try {
            parsed = JSON.parse(content.replace(/```json/g, '').replace(/```/g, '').trim());
        }
        catch (e) {
            console.error('Failed to parse JSON from AI:', content);
            throw new https_1.HttpsError('internal', 'AI returned malformed JSON.');
        }
        return { variations: parsed };
    }
    catch (err) {
        console.error('generateAbTests error:', ((_a = err.response) === null || _a === void 0 ? void 0 : _a.data) || err.message);
        throw new https_1.HttpsError('internal', 'AI request failed.');
    }
});
__exportStar(require("./calls"), exports);
__exportStar(require("./notifications"), exports);
__exportStar(require("./biometric"), exports);
__exportStar(require("./security"), exports);
__exportStar(require("./securityMail"), exports);
__exportStar(require("./emailCodes"), exports);
__exportStar(require("./metaOAuth"), exports);
__exportStar(require("./gmailUser"), exports);
__exportStar(require("./inbox"), exports);
var aiGateway_1 = require("./aiGateway");
Object.defineProperty(exports, "aiGateway", { enumerable: true, get: function () { return aiGateway_1.aiGateway; } });
Object.defineProperty(exports, "generateLiveApiToken", { enumerable: true, get: function () { return aiGateway_1.generateLiveApiToken; } });
var searchQuery_1 = require("./search/searchQuery");
Object.defineProperty(exports, "globalSemanticSearch", { enumerable: true, get: function () { return searchQuery_1.globalSemanticSearch; } });
// Live Studio v2 (docs/live-studio/ARCHITECTURE.md §5)
var media_1 = require("./liveStudio/media");
Object.defineProperty(exports, "lsStart", { enumerable: true, get: function () { return media_1.lsStart; } });
Object.defineProperty(exports, "lsToken", { enumerable: true, get: function () { return media_1.lsToken; } });
Object.defineProperty(exports, "lsEnd", { enumerable: true, get: function () { return media_1.lsEnd; } });
Object.defineProperty(exports, "lsTime", { enumerable: true, get: function () { return media_1.lsTime; } });
Object.defineProperty(exports, "lsStateFull", { enumerable: true, get: function () { return media_1.lsStateFull; } });
Object.defineProperty(exports, "lsSetOwnMedia", { enumerable: true, get: function () { return media_1.lsSetOwnMedia; } });
var settings_1 = require("./liveStudio/settings");
Object.defineProperty(exports, "lsSetSettings", { enumerable: true, get: function () { return settings_1.lsSetSettings; } });
var layout_1 = require("./liveStudio/layout");
Object.defineProperty(exports, "lsSetLayout", { enumerable: true, get: function () { return layout_1.lsSetLayout; } });
var roles_1 = require("./liveStudio/roles");
Object.defineProperty(exports, "lsRequestJoin", { enumerable: true, get: function () { return roles_1.lsRequestJoin; } });
Object.defineProperty(exports, "lsCancelRequest", { enumerable: true, get: function () { return roles_1.lsCancelRequest; } });
Object.defineProperty(exports, "lsRespondRequest", { enumerable: true, get: function () { return roles_1.lsRespondRequest; } });
Object.defineProperty(exports, "lsModerate", { enumerable: true, get: function () { return roles_1.lsModerate; } });
Object.defineProperty(exports, "lsLeaveStage", { enumerable: true, get: function () { return roles_1.lsLeaveStage; } });
var table_1 = require("./liveStudio/table");
Object.defineProperty(exports, "lsSetTable", { enumerable: true, get: function () { return table_1.lsSetTable; } });
Object.defineProperty(exports, "lsPlayback", { enumerable: true, get: function () { return table_1.lsPlayback; } });
var security_1 = require("./liveStudio/security");
Object.defineProperty(exports, "lsMediaKey", { enumerable: true, get: function () { return security_1.lsMediaKey; } });
Object.defineProperty(exports, "lsSecOnIncident", { enumerable: true, get: function () { return security_1.lsSecOnIncident; } });
Object.defineProperty(exports, "lsSecOnBlock", { enumerable: true, get: function () { return security_1.lsSecOnBlock; } });
Object.defineProperty(exports, "lsSecOnMemberWrite", { enumerable: true, get: function () { return security_1.lsSecOnMemberWrite; } });
var controls_1 = require("./liveStudio/controls");
Object.defineProperty(exports, "lsSetChatMode", { enumerable: true, get: function () { return controls_1.lsSetChatMode; } });
Object.defineProperty(exports, "lsSetJoinRequests", { enumerable: true, get: function () { return controls_1.lsSetJoinRequests; } });
var social_1 = require("./liveStudio/social");
Object.defineProperty(exports, "lsComment", { enumerable: true, get: function () { return social_1.lsComment; } });
Object.defineProperty(exports, "lsDeleteComment", { enumerable: true, get: function () { return social_1.lsDeleteComment; } });
Object.defineProperty(exports, "lsMuteChat", { enumerable: true, get: function () { return social_1.lsMuteChat; } });
Object.defineProperty(exports, "lsReact", { enumerable: true, get: function () { return social_1.lsReact; } });
Object.defineProperty(exports, "lsShare", { enumerable: true, get: function () { return social_1.lsShare; } });
Object.defineProperty(exports, "lsLivekitWebhook", { enumerable: true, get: function () { return social_1.lsLivekitWebhook; } });
// Oneova Looks & Visual Intelligence (§4.5, §8, §10)
__exportStar(require("./looks"), exports);
//# sourceMappingURL=index.js.map