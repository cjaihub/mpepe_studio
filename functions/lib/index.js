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
exports.insightsOnView = exports.playBillingNotifications = exports.verifySubscriptionPurchase = exports.voiceStreamToken = exports.voiceConvertOwn = exports.voiceSpeakOwn = exports.voiceDisable = exports.voiceEnrollFinish = exports.voiceEnrollStart = exports.voiceStatus = exports.kycLinkAccount = exports.kycReview = exports.kycRefresh = exports.kycSubmit = exports.kycStart = exports.paystackWebhook = exports.flutterwaveWebhook = exports.reviewWithdrawal = exports.cancelWithdrawal = exports.requestWithdrawal = exports.deletePayoutMethod = exports.savePayoutMethod = exports.payoutBanks = exports.payoutOptions = exports.walletSync = exports.remixOnDelete = exports.remixOnCreate = exports.sendUserGift = exports.verifyCoinPurchase = exports.connectorStatus = exports.shareToAudience = exports.onAppReleasePublished = exports.onFeedTuned = exports.suggestProfileDetails = exports.chatAssist = exports.generateLiveApiToken = exports.aiGateway = exports.guardBackfillContacts = exports.accountLookup = exports.guardSweep = exports.guardReverseAction = exports.guardCheckLinks = exports.guardOnProfileWrite = exports.guardScanContentComment = exports.guardScanPostComment = exports.contentOpenDestination = exports.contentSetDestination = exports.generateAbTests = exports.publishToSocials = exports.processAiCommand = void 0;
exports.tiktokCreatorInfo = exports.tiktokVideos = exports.tiktokProfile = exports.tiktokDisconnect = exports.tiktokExchangeCode = exports.arMakeupSuggest = exports.arEffectFavoriteRemoved = exports.arEffectFavoriteAdded = exports.arEffectUse = exports.arEffectCreateFromUpload = exports.arEffectGenerate = exports.reelTranslate = exports.studioTranslate = exports.studioCaptions = exports.aiProxy = exports.payDeviceRevoke = exports.payDeviceList = exports.payDeviceVerify = exports.payDeviceTrust = exports.payDeviceRegister = exports.payDeviceChallenge = exports.payMoveToPersonal = exports.payQrDisable = exports.payQrList = exports.payQrResolve = exports.payQrCreate = exports.payBalanceReconcile = exports.payWithdraw = exports.payReturn = exports.payWebhookMomo = exports.payWebhookMpesa = exports.payReconcileIntents = exports.payCancel = exports.payStatus = exports.payCreate = exports.payMethods = exports.payPayoutStatus = exports.cancelOrder = exports.confirmDelivery = exports.startJourney = exports.acceptDelivery = exports.createOrderCheckout = exports.quoteDelivery = exports.recordWatchTime = exports.insightsOnEarning = exports.insightsOnFollow = exports.insightsOnComment = exports.insightsOnShare = exports.insightsOnUnlike = exports.insightsOnLike = void 0;
exports.wishSummarizeNow = exports.wishSummarize = exports.wishOnReactionDeleted = exports.wishOnReactionCreated = exports.wishOnCommentDeleted = exports.wishOnCommentCreated = exports.wishOnIdeaUpdated = exports.wishOnIdeaDeleted = exports.wishOnIdeaCreated = exports.lsPool = exports.lsYouTubeSearch = exports.lsWatch = exports.lsGifSearch = exports.lsLivekitWebhook = exports.lsShare = exports.lsReact = exports.lsMuteChat = exports.lsDeleteComment = exports.lsComment = exports.lsSetJoinRequests = exports.lsSetChatMode = exports.lsSecOnMemberWrite = exports.lsSecOnBlock = exports.lsSecOnIncident = exports.lsMediaKey = exports.lsPlayback = exports.lsSetTable = exports.lsLeaveStage = exports.lsModerate = exports.lsRespondRequest = exports.lsCancelRequest = exports.lsRequestJoin = exports.lsSetLayout = exports.lsRecordingDecision = exports.lsBroadcast = exports.lsDestinations = exports.lsGift = exports.lsFun = exports.lsSweepOrphanLives = exports.lsHeartbeat = exports.lsSetSettings = exports.lsSetOwnMedia = exports.lsStateFull = exports.lsTime = exports.lsEnd = exports.lsToken = exports.lsStart = exports.globalSemanticSearch = exports.tiktokWebhook = exports.tiktokPublish = void 0;
exports.sweepExpiredChatMessages = exports.onChatMessagePush = exports.mapsGateway = exports.ledgerOutboxRetry = exports.ledgerOutboxDeliver = exports.shopChatSend = exports.shareLinkOpen = exports.shareLinkEvent = exports.shareLinkCreate = exports.fxRefresh = exports.shopListingDraft = exports.model3dSweep = exports.model3dWorker = exports.model3dEngineStatus = exports.model3dUnlinkProvider = exports.model3dLinkProvider = exports.model3dDelete = exports.model3dAttach = exports.model3dResume = exports.model3dGenerate = exports.model3dCreate = exports.textureCreate = exports.textureLibrary = exports.bizCheckCode = exports.bizTrackEvent = exports.bizSubmitReview = exports.bizSetFulfilment = exports.payoutReconcile = exports.coinVoidSweep = void 0;
require("./globalOptions");
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-admin/firestore");
const axios_1 = __importDefault(require("axios"));
const googleapis_1 = require("googleapis");
const protect_1 = require("./guard/protect");
const openRouterSecret = (0, params_1.defineSecret)('OPENROUTER_API_KEY');
admin.initializeApp();
const db = (0, firestore_1.getFirestore)();
exports.processAiCommand = (0, https_1.onCall)({ secrets: [openRouterSecret] }, async (request) => {
    var _a;
    if (!request.auth) {
        throw new https_1.HttpsError('unauthenticated', 'User must be logged in.');
    }
    await (0, protect_1.limit)(request.auth.uid, 'ai_command', 30, 10 * 60000);
    const { transcript } = request.data;
    if (!transcript || typeof transcript !== 'string' || transcript.length > 4000) {
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
    // Only our own Storage files may be fetched and re-uploaded (no SSRF).
    if (typeof taskId !== 'string' || !/^[A-Za-z0-9_-]{1,80}$/.test(taskId) || !Array.isArray(destinations) || destinations.length > 5 ||
        typeof storageUrl !== 'string' || !/^https:\/\/firebasestorage\.googleapis\.com\/v0\/b\/mpepe-2b4bd\./.test(storageUrl)) {
        throw new https_1.HttpsError('invalid-argument', 'Invalid upload.');
    }
    await (0, protect_1.limit)(userId, 'publish_socials', 10, 3600000);
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
    await (0, protect_1.limit)(request.auth.uid, 'ab_tests', 20, 10 * 60000);
    const { contextPrompt } = request.data;
    if (typeof contextPrompt !== 'string' || !contextPrompt.trim() || contextPrompt.length > 2000) {
        throw new https_1.HttpsError('invalid-argument', 'Describe the video in up to 2000 characters.');
    }
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
__exportStar(require("./desktopAgent"), exports);
__exportStar(require("./turnRelay"), exports);
__exportStar(require("./ovaAgentBridge"), exports);
__exportStar(require("./security"), exports);
var destinationLinks_1 = require("./feed/destinationLinks");
Object.defineProperty(exports, "contentSetDestination", { enumerable: true, get: function () { return destinationLinks_1.contentSetDestination; } });
Object.defineProperty(exports, "contentOpenDestination", { enumerable: true, get: function () { return destinationLinks_1.contentOpenDestination; } });
var monitor_1 = require("./guard/monitor");
Object.defineProperty(exports, "guardScanPostComment", { enumerable: true, get: function () { return monitor_1.guardScanPostComment; } });
Object.defineProperty(exports, "guardScanContentComment", { enumerable: true, get: function () { return monitor_1.guardScanContentComment; } });
Object.defineProperty(exports, "guardOnProfileWrite", { enumerable: true, get: function () { return monitor_1.guardOnProfileWrite; } });
Object.defineProperty(exports, "guardCheckLinks", { enumerable: true, get: function () { return monitor_1.guardCheckLinks; } });
Object.defineProperty(exports, "guardReverseAction", { enumerable: true, get: function () { return monitor_1.guardReverseAction; } });
Object.defineProperty(exports, "guardSweep", { enumerable: true, get: function () { return monitor_1.guardSweep; } });
Object.defineProperty(exports, "accountLookup", { enumerable: true, get: function () { return monitor_1.accountLookup; } });
Object.defineProperty(exports, "guardBackfillContacts", { enumerable: true, get: function () { return monitor_1.guardBackfillContacts; } });
__exportStar(require("./securityMail"), exports);
__exportStar(require("./emailCodes"), exports);
__exportStar(require("./metaOAuth"), exports);
__exportStar(require("./gmailUser"), exports);
__exportStar(require("./googleLink"), exports);
__exportStar(require("./voiceTidy"), exports);
__exportStar(require("./inbox"), exports);
var aiGateway_1 = require("./aiGateway");
Object.defineProperty(exports, "aiGateway", { enumerable: true, get: function () { return aiGateway_1.aiGateway; } });
Object.defineProperty(exports, "generateLiveApiToken", { enumerable: true, get: function () { return aiGateway_1.generateLiveApiToken; } });
var chatAssist_1 = require("./chatAssist");
Object.defineProperty(exports, "chatAssist", { enumerable: true, get: function () { return chatAssist_1.chatAssist; } });
var profileAssist_1 = require("./profileAssist");
Object.defineProperty(exports, "suggestProfileDetails", { enumerable: true, get: function () { return profileAssist_1.suggestProfileDetails; } });
Object.defineProperty(exports, "onFeedTuned", { enumerable: true, get: function () { return profileAssist_1.onFeedTuned; } });
Object.defineProperty(exports, "onAppReleasePublished", { enumerable: true, get: function () { return profileAssist_1.onAppReleasePublished; } });
var shareAudience_1 = require("./shareAudience");
Object.defineProperty(exports, "shareToAudience", { enumerable: true, get: function () { return shareAudience_1.shareToAudience; } });
var connectorStatus_1 = require("./connectorStatus");
Object.defineProperty(exports, "connectorStatus", { enumerable: true, get: function () { return connectorStatus_1.connectorStatus; } });
var coinEconomy_1 = require("./coins/coinEconomy");
Object.defineProperty(exports, "verifyCoinPurchase", { enumerable: true, get: function () { return coinEconomy_1.verifyCoinPurchase; } });
Object.defineProperty(exports, "sendUserGift", { enumerable: true, get: function () { return coinEconomy_1.sendUserGift; } });
var remix_1 = require("./remix");
Object.defineProperty(exports, "remixOnCreate", { enumerable: true, get: function () { return remix_1.remixOnCreate; } });
Object.defineProperty(exports, "remixOnDelete", { enumerable: true, get: function () { return remix_1.remixOnDelete; } });
var payouts_1 = require("./creator/payouts");
Object.defineProperty(exports, "walletSync", { enumerable: true, get: function () { return payouts_1.walletSync; } });
Object.defineProperty(exports, "payoutOptions", { enumerable: true, get: function () { return payouts_1.payoutOptions; } });
Object.defineProperty(exports, "payoutBanks", { enumerable: true, get: function () { return payouts_1.payoutBanks; } });
Object.defineProperty(exports, "savePayoutMethod", { enumerable: true, get: function () { return payouts_1.savePayoutMethod; } });
Object.defineProperty(exports, "deletePayoutMethod", { enumerable: true, get: function () { return payouts_1.deletePayoutMethod; } });
Object.defineProperty(exports, "requestWithdrawal", { enumerable: true, get: function () { return payouts_1.requestWithdrawal; } });
Object.defineProperty(exports, "cancelWithdrawal", { enumerable: true, get: function () { return payouts_1.cancelWithdrawal; } });
Object.defineProperty(exports, "reviewWithdrawal", { enumerable: true, get: function () { return payouts_1.reviewWithdrawal; } });
Object.defineProperty(exports, "flutterwaveWebhook", { enumerable: true, get: function () { return payouts_1.flutterwaveWebhook; } });
Object.defineProperty(exports, "paystackWebhook", { enumerable: true, get: function () { return payouts_1.paystackWebhook; } });
var kyc_1 = require("./creator/kyc");
Object.defineProperty(exports, "kycStart", { enumerable: true, get: function () { return kyc_1.kycStart; } });
Object.defineProperty(exports, "kycSubmit", { enumerable: true, get: function () { return kyc_1.kycSubmit; } });
Object.defineProperty(exports, "kycRefresh", { enumerable: true, get: function () { return kyc_1.kycRefresh; } });
Object.defineProperty(exports, "kycReview", { enumerable: true, get: function () { return kyc_1.kycReview; } });
var kycIdentity_1 = require("./creator/kycIdentity");
Object.defineProperty(exports, "kycLinkAccount", { enumerable: true, get: function () { return kycIdentity_1.kycLinkAccount; } });
var voice_1 = require("./voice/voice");
Object.defineProperty(exports, "voiceStatus", { enumerable: true, get: function () { return voice_1.voiceStatus; } });
Object.defineProperty(exports, "voiceEnrollStart", { enumerable: true, get: function () { return voice_1.voiceEnrollStart; } });
Object.defineProperty(exports, "voiceEnrollFinish", { enumerable: true, get: function () { return voice_1.voiceEnrollFinish; } });
Object.defineProperty(exports, "voiceDisable", { enumerable: true, get: function () { return voice_1.voiceDisable; } });
Object.defineProperty(exports, "voiceSpeakOwn", { enumerable: true, get: function () { return voice_1.voiceSpeakOwn; } });
Object.defineProperty(exports, "voiceConvertOwn", { enumerable: true, get: function () { return voice_1.voiceConvertOwn; } });
Object.defineProperty(exports, "voiceStreamToken", { enumerable: true, get: function () { return voice_1.voiceStreamToken; } });
__exportStar(require("./identity"), exports);
var planSubscriptions_1 = require("./creator/planSubscriptions");
Object.defineProperty(exports, "verifySubscriptionPurchase", { enumerable: true, get: function () { return planSubscriptions_1.verifySubscriptionPurchase; } });
Object.defineProperty(exports, "playBillingNotifications", { enumerable: true, get: function () { return planSubscriptions_1.playBillingNotifications; } });
var insights_1 = require("./creator/insights");
Object.defineProperty(exports, "insightsOnView", { enumerable: true, get: function () { return insights_1.insightsOnView; } });
Object.defineProperty(exports, "insightsOnLike", { enumerable: true, get: function () { return insights_1.insightsOnLike; } });
Object.defineProperty(exports, "insightsOnUnlike", { enumerable: true, get: function () { return insights_1.insightsOnUnlike; } });
Object.defineProperty(exports, "insightsOnShare", { enumerable: true, get: function () { return insights_1.insightsOnShare; } });
Object.defineProperty(exports, "insightsOnComment", { enumerable: true, get: function () { return insights_1.insightsOnComment; } });
Object.defineProperty(exports, "insightsOnFollow", { enumerable: true, get: function () { return insights_1.insightsOnFollow; } });
Object.defineProperty(exports, "insightsOnEarning", { enumerable: true, get: function () { return insights_1.insightsOnEarning; } });
Object.defineProperty(exports, "recordWatchTime", { enumerable: true, get: function () { return insights_1.recordWatchTime; } });
var orderEscrow_1 = require("./commerce/orderEscrow");
Object.defineProperty(exports, "quoteDelivery", { enumerable: true, get: function () { return orderEscrow_1.quoteDelivery; } });
Object.defineProperty(exports, "createOrderCheckout", { enumerable: true, get: function () { return orderEscrow_1.createOrderCheckout; } });
Object.defineProperty(exports, "acceptDelivery", { enumerable: true, get: function () { return orderEscrow_1.acceptDelivery; } });
Object.defineProperty(exports, "startJourney", { enumerable: true, get: function () { return orderEscrow_1.startJourney; } });
Object.defineProperty(exports, "confirmDelivery", { enumerable: true, get: function () { return orderEscrow_1.confirmDelivery; } });
Object.defineProperty(exports, "cancelOrder", { enumerable: true, get: function () { return orderEscrow_1.cancelOrder; } });
Object.defineProperty(exports, "payPayoutStatus", { enumerable: true, get: function () { return orderEscrow_1.payPayoutStatus; } });
// Oneova Pay: pay-ins (phone prompt / partner page / balance), balance payouts.
var intents_1 = require("./pay/intents");
Object.defineProperty(exports, "payMethods", { enumerable: true, get: function () { return intents_1.payMethods; } });
Object.defineProperty(exports, "payCreate", { enumerable: true, get: function () { return intents_1.payCreate; } });
Object.defineProperty(exports, "payStatus", { enumerable: true, get: function () { return intents_1.payStatus; } });
Object.defineProperty(exports, "payCancel", { enumerable: true, get: function () { return intents_1.payCancel; } });
Object.defineProperty(exports, "payReconcileIntents", { enumerable: true, get: function () { return intents_1.payReconcileIntents; } });
Object.defineProperty(exports, "payWebhookMpesa", { enumerable: true, get: function () { return intents_1.payWebhookMpesa; } });
Object.defineProperty(exports, "payWebhookMomo", { enumerable: true, get: function () { return intents_1.payWebhookMomo; } });
Object.defineProperty(exports, "payReturn", { enumerable: true, get: function () { return intents_1.payReturn; } });
var balancePayouts_1 = require("./pay/balancePayouts");
Object.defineProperty(exports, "payWithdraw", { enumerable: true, get: function () { return balancePayouts_1.payWithdraw; } });
Object.defineProperty(exports, "payBalanceReconcile", { enumerable: true, get: function () { return balancePayouts_1.payBalanceReconcile; } });
// Scan to pay: merchant QR codes (pay with payCreate purpose 'merchant').
var merchantQr_1 = require("./pay/merchantQr");
Object.defineProperty(exports, "payQrCreate", { enumerable: true, get: function () { return merchantQr_1.payQrCreate; } });
Object.defineProperty(exports, "payQrResolve", { enumerable: true, get: function () { return merchantQr_1.payQrResolve; } });
Object.defineProperty(exports, "payQrList", { enumerable: true, get: function () { return merchantQr_1.payQrList; } });
Object.defineProperty(exports, "payQrDisable", { enumerable: true, get: function () { return merchantQr_1.payQrDisable; } });
// Business balance: shop sales and scan to pay, apart from the personal balance.
var businessBalance_1 = require("./pay/businessBalance");
Object.defineProperty(exports, "payMoveToPersonal", { enumerable: true, get: function () { return businessBalance_1.payMoveToPersonal; } });
var devices_1 = require("./pay/devices");
Object.defineProperty(exports, "payDeviceChallenge", { enumerable: true, get: function () { return devices_1.payDeviceChallenge; } });
Object.defineProperty(exports, "payDeviceRegister", { enumerable: true, get: function () { return devices_1.payDeviceRegister; } });
Object.defineProperty(exports, "payDeviceTrust", { enumerable: true, get: function () { return devices_1.payDeviceTrust; } });
Object.defineProperty(exports, "payDeviceVerify", { enumerable: true, get: function () { return devices_1.payDeviceVerify; } });
Object.defineProperty(exports, "payDeviceList", { enumerable: true, get: function () { return devices_1.payDeviceList; } });
Object.defineProperty(exports, "payDeviceRevoke", { enumerable: true, get: function () { return devices_1.payDeviceRevoke; } });
var aiProxy_1 = require("./aiProxy");
Object.defineProperty(exports, "aiProxy", { enumerable: true, get: function () { return aiProxy_1.aiProxy; } });
var studioAi_1 = require("./studioAi");
Object.defineProperty(exports, "studioCaptions", { enumerable: true, get: function () { return studioAi_1.studioCaptions; } });
Object.defineProperty(exports, "studioTranslate", { enumerable: true, get: function () { return studioAi_1.studioTranslate; } });
var reelTranslate_1 = require("./reelTranslate");
Object.defineProperty(exports, "reelTranslate", { enumerable: true, get: function () { return reelTranslate_1.reelTranslate; } });
var arEffects_1 = require("./arEffects");
Object.defineProperty(exports, "arEffectGenerate", { enumerable: true, get: function () { return arEffects_1.arEffectGenerate; } });
Object.defineProperty(exports, "arEffectCreateFromUpload", { enumerable: true, get: function () { return arEffects_1.arEffectCreateFromUpload; } });
Object.defineProperty(exports, "arEffectUse", { enumerable: true, get: function () { return arEffects_1.arEffectUse; } });
Object.defineProperty(exports, "arEffectFavoriteAdded", { enumerable: true, get: function () { return arEffects_1.arEffectFavoriteAdded; } });
Object.defineProperty(exports, "arEffectFavoriteRemoved", { enumerable: true, get: function () { return arEffects_1.arEffectFavoriteRemoved; } });
Object.defineProperty(exports, "arMakeupSuggest", { enumerable: true, get: function () { return arEffects_1.arMakeupSuggest; } });
var tiktokOAuth_1 = require("./tiktokOAuth");
Object.defineProperty(exports, "tiktokExchangeCode", { enumerable: true, get: function () { return tiktokOAuth_1.tiktokExchangeCode; } });
Object.defineProperty(exports, "tiktokDisconnect", { enumerable: true, get: function () { return tiktokOAuth_1.tiktokDisconnect; } });
Object.defineProperty(exports, "tiktokProfile", { enumerable: true, get: function () { return tiktokOAuth_1.tiktokProfile; } });
Object.defineProperty(exports, "tiktokVideos", { enumerable: true, get: function () { return tiktokOAuth_1.tiktokVideos; } });
Object.defineProperty(exports, "tiktokCreatorInfo", { enumerable: true, get: function () { return tiktokOAuth_1.tiktokCreatorInfo; } });
Object.defineProperty(exports, "tiktokPublish", { enumerable: true, get: function () { return tiktokOAuth_1.tiktokPublish; } });
Object.defineProperty(exports, "tiktokWebhook", { enumerable: true, get: function () { return tiktokOAuth_1.tiktokWebhook; } });
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
var lifecycle_1 = require("./liveStudio/lifecycle");
Object.defineProperty(exports, "lsHeartbeat", { enumerable: true, get: function () { return lifecycle_1.lsHeartbeat; } });
Object.defineProperty(exports, "lsSweepOrphanLives", { enumerable: true, get: function () { return lifecycle_1.lsSweepOrphanLives; } });
var fun_1 = require("./liveStudio/fun");
Object.defineProperty(exports, "lsFun", { enumerable: true, get: function () { return fun_1.lsFun; } });
var gifts_1 = require("./liveStudio/gifts");
Object.defineProperty(exports, "lsGift", { enumerable: true, get: function () { return gifts_1.lsGift; } });
var broadcast_1 = require("./liveStudio/broadcast");
Object.defineProperty(exports, "lsDestinations", { enumerable: true, get: function () { return broadcast_1.lsDestinations; } });
Object.defineProperty(exports, "lsBroadcast", { enumerable: true, get: function () { return broadcast_1.lsBroadcast; } });
Object.defineProperty(exports, "lsRecordingDecision", { enumerable: true, get: function () { return broadcast_1.lsRecordingDecision; } });
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
Object.defineProperty(exports, "lsGifSearch", { enumerable: true, get: function () { return social_1.lsGifSearch; } });
var watch_1 = require("./liveStudio/watch");
Object.defineProperty(exports, "lsWatch", { enumerable: true, get: function () { return watch_1.lsWatch; } });
Object.defineProperty(exports, "lsYouTubeSearch", { enumerable: true, get: function () { return watch_1.lsYouTubeSearch; } });
var pool_1 = require("./liveStudio/pool");
Object.defineProperty(exports, "lsPool", { enumerable: true, get: function () { return pool_1.lsPool; } });
// Oneova Looks & Visual Intelligence (§4.5, §8, §10)
__exportStar(require("./looks"), exports);
var wishIdeas_1 = require("./wishIdeas");
Object.defineProperty(exports, "wishOnIdeaCreated", { enumerable: true, get: function () { return wishIdeas_1.wishOnIdeaCreated; } });
Object.defineProperty(exports, "wishOnIdeaDeleted", { enumerable: true, get: function () { return wishIdeas_1.wishOnIdeaDeleted; } });
Object.defineProperty(exports, "wishOnIdeaUpdated", { enumerable: true, get: function () { return wishIdeas_1.wishOnIdeaUpdated; } });
Object.defineProperty(exports, "wishOnCommentCreated", { enumerable: true, get: function () { return wishIdeas_1.wishOnCommentCreated; } });
Object.defineProperty(exports, "wishOnCommentDeleted", { enumerable: true, get: function () { return wishIdeas_1.wishOnCommentDeleted; } });
Object.defineProperty(exports, "wishOnReactionCreated", { enumerable: true, get: function () { return wishIdeas_1.wishOnReactionCreated; } });
Object.defineProperty(exports, "wishOnReactionDeleted", { enumerable: true, get: function () { return wishIdeas_1.wishOnReactionDeleted; } });
Object.defineProperty(exports, "wishSummarize", { enumerable: true, get: function () { return wishIdeas_1.wishSummarize; } });
Object.defineProperty(exports, "wishSummarizeNow", { enumerable: true, get: function () { return wishIdeas_1.wishSummarizeNow; } });
// Oneova Pay hardening: refunded coin packs and payouts with unclear provider replies.
var voidedPurchases_1 = require("./coins/voidedPurchases");
Object.defineProperty(exports, "coinVoidSweep", { enumerable: true, get: function () { return voidedPurchases_1.coinVoidSweep; } });
var payouts_2 = require("./creator/payouts");
Object.defineProperty(exports, "payoutReconcile", { enumerable: true, get: function () { return payouts_2.payoutReconcile; } });
// Business portal: fulfilment, reviews, store counters, discount codes.
var storeTools_1 = require("./commerce/storeTools");
Object.defineProperty(exports, "bizSetFulfilment", { enumerable: true, get: function () { return storeTools_1.bizSetFulfilment; } });
Object.defineProperty(exports, "bizSubmitReview", { enumerable: true, get: function () { return storeTools_1.bizSubmitReview; } });
Object.defineProperty(exports, "bizTrackEvent", { enumerable: true, get: function () { return storeTools_1.bizTrackEvent; } });
Object.defineProperty(exports, "bizCheckCode", { enumerable: true, get: function () { return storeTools_1.bizCheckCode; } });
// Hosted texture library for 3D products and live stages.
var textures_1 = require("./commerce/textures");
Object.defineProperty(exports, "textureLibrary", { enumerable: true, get: function () { return textures_1.textureLibrary; } });
Object.defineProperty(exports, "textureCreate", { enumerable: true, get: function () { return textures_1.textureCreate; } });
// 3D model service: private library, mobile optimizer, photo → 3D, AI listing drafts.
var models3d_1 = require("./models3d");
Object.defineProperty(exports, "model3dCreate", { enumerable: true, get: function () { return models3d_1.model3dCreate; } });
Object.defineProperty(exports, "model3dGenerate", { enumerable: true, get: function () { return models3d_1.model3dGenerate; } });
Object.defineProperty(exports, "model3dResume", { enumerable: true, get: function () { return models3d_1.model3dResume; } });
Object.defineProperty(exports, "model3dAttach", { enumerable: true, get: function () { return models3d_1.model3dAttach; } });
Object.defineProperty(exports, "model3dDelete", { enumerable: true, get: function () { return models3d_1.model3dDelete; } });
Object.defineProperty(exports, "model3dLinkProvider", { enumerable: true, get: function () { return models3d_1.model3dLinkProvider; } });
Object.defineProperty(exports, "model3dUnlinkProvider", { enumerable: true, get: function () { return models3d_1.model3dUnlinkProvider; } });
Object.defineProperty(exports, "model3dEngineStatus", { enumerable: true, get: function () { return models3d_1.model3dEngineStatus; } });
Object.defineProperty(exports, "model3dWorker", { enumerable: true, get: function () { return models3d_1.model3dWorker; } });
Object.defineProperty(exports, "model3dSweep", { enumerable: true, get: function () { return models3d_1.model3dSweep; } });
var listing_1 = require("./models3d/listing");
Object.defineProperty(exports, "shopListingDraft", { enumerable: true, get: function () { return listing_1.shopListingDraft; } });
// World exchange rates (hourly) and tracked share links.
var fx_1 = require("./commerce/fx");
Object.defineProperty(exports, "fxRefresh", { enumerable: true, get: function () { return fx_1.fxRefresh; } });
var shareLinks_1 = require("./commerce/shareLinks");
Object.defineProperty(exports, "shareLinkCreate", { enumerable: true, get: function () { return shareLinks_1.shareLinkCreate; } });
Object.defineProperty(exports, "shareLinkEvent", { enumerable: true, get: function () { return shareLinks_1.shareLinkEvent; } });
Object.defineProperty(exports, "shareLinkOpen", { enumerable: true, get: function () { return shareLinks_1.shareLinkOpen; } });
var shopChat_1 = require("./commerce/shopChat");
Object.defineProperty(exports, "shopChatSend", { enumerable: true, get: function () { return shopChat_1.shopChatSend; } });
// Postgres ledger shadow mode (services/ledger); off unless LEDGER_OUTBOX=on.
var outbox_1 = require("./ledger/outbox");
Object.defineProperty(exports, "ledgerOutboxDeliver", { enumerable: true, get: function () { return outbox_1.ledgerOutboxDeliver; } });
Object.defineProperty(exports, "ledgerOutboxRetry", { enumerable: true, get: function () { return outbox_1.ledgerOutboxRetry; } });
// Google Maps Server Gateway (Places, Directions, Geocoding with GOOGLE_MAPS_SERVER_KEY).
var mapsGateway_1 = require("./mapsGateway");
Object.defineProperty(exports, "mapsGateway", { enumerable: true, get: function () { return mapsGateway_1.mapsGateway; } });
// Chat message push notifications and disappearing message expiry sweep.
var chatMessaging_1 = require("./chatMessaging");
Object.defineProperty(exports, "onChatMessagePush", { enumerable: true, get: function () { return chatMessaging_1.onChatMessagePush; } });
Object.defineProperty(exports, "sweepExpiredChatMessages", { enumerable: true, get: function () { return chatMessaging_1.sweepExpiredChatMessages; } });
//# sourceMappingURL=index.js.map