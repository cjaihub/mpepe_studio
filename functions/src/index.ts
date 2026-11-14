import './globalOptions';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import * as admin from 'firebase-admin';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import axios from 'axios';
import { google } from 'googleapis';
import { limit } from './guard/protect';

const openRouterSecret = defineSecret('OPENROUTER_API_KEY');

admin.initializeApp();
const db = getFirestore();

export const processAiCommand = onCall({ secrets: [openRouterSecret] }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be logged in.');
  }

  await limit(request.auth.uid, 'ai_command', 30, 10 * 60000);
  const { transcript } = request.data;
  if (!transcript || typeof transcript !== 'string' || transcript.length > 4000) {
    throw new HttpsError('invalid-argument', 'Missing transcript.');
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
    const response = await axios.post('https://openrouter.ai/api/v1/chat/completions', {
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
  } catch (error: any) {
    console.error("OpenRouter Error: ", error.response?.data || error.message);
    throw new HttpsError('internal', 'Failed to process AI command.');
  }
});

export const publishToSocials = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be logged in.');
  }

  const userId = request.auth.uid;
  const { taskId, destinations, storageUrl, metadata, platformTokens } = request.data;

  if (!taskId || !destinations || !storageUrl || !platformTokens) {
    throw new HttpsError('invalid-argument', 'Missing required fields.');
  }
  // Only our own Storage files may be fetched and re-uploaded (no SSRF).
  if (typeof taskId !== 'string' || !/^[A-Za-z0-9_-]{1,80}$/.test(taskId) || !Array.isArray(destinations) || destinations.length > 5 ||
      typeof storageUrl !== 'string' || !/^https:\/\/firebasestorage\.googleapis\.com\/v0\/b\/mpepe-2b4bd\./.test(storageUrl)) {
    throw new HttpsError('invalid-argument', 'Invalid upload.');
  }
  await limit(userId, 'publish_socials', 10, 3600000);

  const taskRef = db.collection(`users/${userId}/uploadTasks`).doc(taskId);

  await taskRef.set({
    taskId,
    status: 'uploading',
    progress: 0.1,
    createdAt: FieldValue.serverTimestamp(),
    destinations,
    metadata
  });

  // Background processing
  setTimeout(async () => {
    try {
      await taskRef.update({ progress: 0.2, status: 'uploading' });
      
      const publishedLinks: any = {};
      
      for (const dest of destinations) {
        if (dest.platform === 'youtube') {
          try {
            const ytToken = platformTokens['youtube'];
            if (!ytToken) throw new Error("Missing YouTube token");

            const oauth2Client = new google.auth.OAuth2();
            oauth2Client.setCredentials({ access_token: ytToken });
            const youtube = google.youtube({ version: 'v3', auth: oauth2Client });
            
            // Download video stream from Firebase Storage public URL
            const fileStream = (await axios({ url: storageUrl, method: 'GET', responseType: 'stream' })).data;
            
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
          } catch (e: any) {
             console.error("YouTube Error: ", e.message);
             publishedLinks['youtube_error'] = e.message;
          }
        } 
        else if (dest.platform === 'facebook') {
          try {
            const fbToken = platformTokens['facebook'];
            if (!fbToken) throw new Error("Missing Facebook token");
            
            const pageId = dest.pageId; 
            const res = await axios.post(`https://graph.facebook.com/v19.0/${pageId}/videos`, {
              file_url: storageUrl,
              title: metadata.title,
              description: metadata.description,
              access_token: fbToken
            });
            publishedLinks['facebook'] = `https://facebook.com/${res.data.id}`;
          } catch (e: any) {
             console.error("Facebook Error: ", e.response?.data || e.message);
             publishedLinks['facebook_error'] = e.message;
          }
        }
        else if (dest.platform === 'instagram') {
           try {
            const igToken = platformTokens['instagram'];
            if (!igToken) throw new Error("Missing Instagram token");
            
            const igUserId = dest.metaUserId; 
            const containerRes = await axios.post(`https://graph.facebook.com/v19.0/${igUserId}/media`, {
              video_url: storageUrl,
              media_type: 'REELS',
              caption: metadata.description,
              access_token: igToken
            });
            const creationId = containerRes.data.id;

            // Simple wait logic for IG video processing
            await new Promise(resolve => setTimeout(resolve, 8000));

            const publishRes = await axios.post(`https://graph.facebook.com/v19.0/${igUserId}/media_publish`, {
              creation_id: creationId,
              access_token: igToken
            });
            publishedLinks['instagram'] = `https://instagram.com/p/${publishRes.data.id}`;
          } catch (e: any) {
             console.error("Instagram Error: ", e.response?.data || e.message);
             publishedLinks['instagram_error'] = e.message;
          }
        }
      }

      await taskRef.update({
        progress: 1.0,
        status: 'completed',
        publishedLinks
      });
      
    } catch (e: any) {
      await taskRef.update({
        status: 'failed',
        errorMessage: e.message
      });
    }
  }, 100); 

  return { success: true, taskId };
});



export const generateAbTests = onCall({ secrets: [openRouterSecret] }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'User must be logged in.');
  
  await limit(request.auth.uid, 'ab_tests', 20, 10 * 60000);
  const { contextPrompt } = request.data;
  if (typeof contextPrompt !== 'string' || !contextPrompt.trim() || contextPrompt.length > 2000) {
    throw new HttpsError('invalid-argument', 'Describe the video in up to 2000 characters.');
  }
  const openrouterKey = openRouterSecret.value();
  
  if (!openrouterKey) {
    throw new HttpsError('internal', 'API key not configured.');
  }

  const prompt = `You are a master social media copywriter. Generate 3 highly viral, distinct A/B test variations for a video with the following context: "${contextPrompt}". 
Return ONLY a strictly valid JSON array of 3 objects with properties: "title" (string), "description" (string), "hashtags" (array of strings). Do not use markdown blocks, just return the raw JSON array.`;

  try {
    const response = await axios.post('https://openrouter.ai/api/v1/chat/completions', {
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
    } catch (e) {
      console.error('Failed to parse JSON from AI:', content);
      throw new HttpsError('internal', 'AI returned malformed JSON.');
    }
    
    return { variations: parsed };
  } catch (err: any) {
    console.error('generateAbTests error:', err.response?.data || err.message);
    throw new HttpsError('internal', 'AI request failed.');
  }
});

export * from './calls';
export * from './notifications';
export * from './biometric';
export * from './desktopAgent';
export * from './turnRelay';
export * from './ovaAgentBridge';
export * from './security';
export { contentSetDestination, contentOpenDestination } from './feed/destinationLinks';
export { guardScanPostComment, guardScanContentComment, guardOnProfileWrite, guardCheckLinks, guardReverseAction, guardSweep, accountLookup, guardBackfillContacts } from './guard/monitor';
export * from './securityMail';
export * from './emailCodes';
export * from './metaOAuth';
export * from './gmailUser';
export * from './googleLink';
export * from './voiceTidy';
export * from './inbox';
export { aiGateway, generateLiveApiToken } from './aiGateway';
export { chatAssist } from './chatAssist';
export { suggestProfileDetails, onFeedTuned, onAppReleasePublished } from './profileAssist';
export { shareToAudience } from './shareAudience';
export { connectorStatus } from './connectorStatus';
export { verifyCoinPurchase, sendUserGift } from './coins/coinEconomy';
export { remixOnCreate, remixOnDelete } from './remix';
export { walletSync, payoutOptions, payoutBanks, savePayoutMethod, deletePayoutMethod, requestWithdrawal, cancelWithdrawal, reviewWithdrawal, flutterwaveWebhook, paystackWebhook } from './creator/payouts';
export { kycStart, kycSubmit, kycRefresh, kycReview } from './creator/kyc';
export * from './identity';
export { verifySubscriptionPurchase, playBillingNotifications } from './creator/planSubscriptions';
export { insightsOnView, insightsOnLike, insightsOnUnlike, insightsOnShare, insightsOnComment, insightsOnFollow, insightsOnEarning, recordWatchTime } from './creator/insights';
export { quoteDelivery, createOrderCheckout, acceptDelivery, startJourney, confirmDelivery, cancelOrder, payPayoutStatus } from './commerce/orderEscrow';
// Oneova Pay: pay-ins (phone prompt / partner page / balance), balance payouts.
export { payMethods, payCreate, payStatus, payCancel, payReconcileIntents, payWebhookMpesa, payWebhookMomo, payReturn } from './pay/intents';
export { payWithdraw, payBalanceReconcile } from './pay/balancePayouts';
// Scan to pay: merchant QR codes (pay with payCreate purpose 'merchant').
export { payQrCreate, payQrResolve, payQrList, payQrDisable } from './pay/merchantQr';
// Business balance: shop sales and scan to pay, apart from the personal balance.
export { payMoveToPersonal } from './pay/businessBalance';
export { payDeviceChallenge, payDeviceRegister, payDeviceTrust, payDeviceVerify, payDeviceList, payDeviceRevoke } from './pay/devices';
export { aiProxy } from './aiProxy';
export { studioCaptions, studioTranslate } from './studioAi';
export { arEffectGenerate, arEffectCreateFromUpload, arEffectUse, arEffectFavoriteAdded, arEffectFavoriteRemoved, arMakeupSuggest } from './arEffects';
export { tiktokExchangeCode, tiktokDisconnect, tiktokProfile, tiktokVideos, tiktokCreatorInfo, tiktokPublish, tiktokWebhook } from './tiktokOAuth';
export { globalSemanticSearch } from './search/searchQuery';

// Live Studio v2 (docs/live-studio/ARCHITECTURE.md §5)
export { lsStart, lsToken, lsEnd, lsTime, lsStateFull, lsSetOwnMedia } from './liveStudio/media';
export { lsSetSettings } from './liveStudio/settings';
export { lsHeartbeat, lsSweepOrphanLives } from './liveStudio/lifecycle';
export { lsFun } from './liveStudio/fun';
export { lsGift } from './liveStudio/gifts';
export { lsDestinations, lsBroadcast, lsRecordingDecision } from './liveStudio/broadcast';
export { lsSetLayout } from './liveStudio/layout';
export { lsRequestJoin, lsCancelRequest, lsRespondRequest, lsModerate, lsLeaveStage } from './liveStudio/roles';
export { lsSetTable, lsPlayback } from './liveStudio/table';
export { lsMediaKey, lsSecOnIncident, lsSecOnBlock, lsSecOnMemberWrite } from './liveStudio/security';
export { lsSetChatMode, lsSetJoinRequests } from './liveStudio/controls';
export { lsComment, lsDeleteComment, lsMuteChat, lsReact, lsShare, lsLivekitWebhook, lsGifSearch } from './liveStudio/social';
export { lsWatch, lsYouTubeSearch } from './liveStudio/watch';
export { lsPool } from './liveStudio/pool';

// Oneova Looks & Visual Intelligence (§4.5, §8, §10)
export * from './looks';
export { wishOnIdeaCreated, wishOnIdeaDeleted, wishOnIdeaUpdated, wishOnCommentCreated, wishOnCommentDeleted, wishOnReactionCreated, wishOnReactionDeleted, wishSummarize, wishSummarizeNow } from './wishIdeas';

// Oneova Pay hardening: refunded coin packs and payouts with unclear provider replies.
export { coinVoidSweep } from './coins/voidedPurchases';
export { payoutReconcile } from './creator/payouts';

// Business portal: fulfilment, reviews, store counters, discount codes.
export { bizSetFulfilment, bizSubmitReview, bizTrackEvent, bizCheckCode } from './commerce/storeTools';
// Hosted texture library for 3D products and live stages.
export { textureLibrary, textureCreate } from './commerce/textures';
// 3D model service: private library, mobile optimizer, photo → 3D, AI listing drafts.
export { model3dCreate, model3dGenerate, model3dResume, model3dAttach, model3dDelete, model3dLinkProvider, model3dUnlinkProvider, model3dEngineStatus, model3dWorker, model3dSweep } from './models3d';
export { shopListingDraft } from './models3d/listing';
// World exchange rates (hourly) and tracked share links.
export { fxRefresh } from './commerce/fx';
export { shareLinkCreate, shareLinkEvent, shareLinkOpen } from './commerce/shareLinks';
export { shopChatSend } from './commerce/shopChat';
// Postgres ledger shadow mode (services/ledger); off unless LEDGER_OUTBOX=on.
export { ledgerOutboxDeliver, ledgerOutboxRetry } from './ledger/outbox';
