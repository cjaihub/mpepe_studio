# Oneova backend endpoints

Generated on 2026-11-02 from `functions/src/index.ts` exports (compiled) and `firebase functions:list --project mpepe-2b4bd`.
Region: every function runs in the default region (`us-central1`) except Firestore triggers, which Firebase places next to the database (`europe-west1`). The app calls `FirebaseFunctions.instance` (us-central1), which matches.

Totals: **144** functions in source, **138** deployed (100% of app-used endpoints), **6** future Looks batch/compute functions not yet deployed (`generateCatalogBundles`, `onBillingBudgetNotification`, `scheduledFeedbackBigQueryExport`, `createLookOptimized`, `enqueueComputeJobCallable`, `getComputeJobStatusCallable`).

## How endpoints are protected

- **Auth**: every callable checks `request.auth` (anonymous guests are refused where an account is needed). The few that run before sign-in (`accountLookup`, `guardReportAuthFailure`, `checkLegacyPassword`, `biometricSignIn`, e-mail codes) are rate-limited per IP and return only what the sign-in screen needs.
- **Webhooks** are public by necessity and verify the sender's signature (Stripe, Flutterwave, Paystack, LiveKit, Meta) or a single-use token (`securityLink`).
- **App Check**: the app activates App Check (Play Integrity / DeviceCheck, `lib/backend/firebase_service.dart`). `functions/src/globalOptions.ts` turns on `enforceAppCheck` for every callable when `APP_CHECK_ENFORCE=true` is in `functions/.env.mpepe-2b4bd`. Leave it off until the App Check console shows nearly all requests as verified, or older builds and debug builds will be refused. `aiProxy` follows the same switch through the `X-Firebase-AppCheck` header.
- **Rate limits**: `functions/src/guard/protect.ts` `limit()` (fixed window in `security_rate`, deny-all to clients); Live Studio uses its own per-stream limiter.
- **Ova Guard pauses**: `firestore.rules` `guardPaused()` refuses new chat messages, comments and follows while an automatic pause is active.

## Endpoints

| Endpoint | Type | Purpose | Auth | App Check | Rate limit | Used by app | Deployed |
|---|---|---|---|---|---|---|---|
| `processAiCommand` | Callable | Legacy upload-manager intent parser (OpenRouter) | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | 30 / 10 min per user | yes | yes (us-central1) |
| `publishToSocials` | Callable | Legacy cross-post to YouTube/Facebook/Instagram | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | 10 / h per user | no | yes (us-central1) |
| `generateAbTests` | Callable | Legacy A/B caption ideas (OpenRouter) | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | 20 / 10 min per user | yes | yes (us-central1) |
| `guardScanPostComment` | Trigger | Ova Guard: link/scam scan of new post comments | n/a (server) | n/a | — | server | **no** |
| `guardScanContentComment` | Trigger | Ova Guard: link/scam scan of new content comments | n/a (server) | n/a | — | server | **no** |
| `guardOnProfileWrite` | Trigger | Ova Guard: bio links, profile-change bursts, impersonation, contact index / private-field split | n/a (server) | n/a | — | server | **no** |
| `guardCheckLinks` | Callable | Ova Guard: link reputation for links the server cannot see (E2E chats) | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | 120 / 10 min per user | yes | **no** |
| `guardReverseAction` | Callable | Ova Guard: admin undo of an automatic action | Admin only | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | no | **no** |
| `guardSweep` | Schedule | Ova Guard: lifts expired pauses/freezes | n/a (server) | n/a | — | server | **no** |
| `accountLookup` | Callable | Sign-in account lookup by phone/e-mail without reading profiles | Optional (sign-in screen) | Verified; enforced when APP_CHECK_ENFORCE=true | 60 / 15 min per IP, 40 / 15 min per user | yes | **no** |
| `guardBackfillContacts` | Callable | Admin one-off: fill contact_index (+ move private fields when enabled) | Admin only | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | no | **no** |
| `aiGateway` | Callable | Ova assistant (Gemini on Vertex, tools) | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | 60 / 10 min per user | yes | yes (us-central1) |
| `generateLiveApiToken` | Callable | Retired voice token (always tells old apps to update) | n/a (always errors) | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | no | yes (us-central1) |
| `chatAssist` | Callable | Chat translate / smart replies (Vertex) | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | 120 / 10 min per user | yes | yes (us-central1) |
| `suggestProfileDetails` | Callable | Profile bio/name ideas (Vertex) | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Daily cap per user | yes | yes (us-central1) |
| `onFeedTuned` | Trigger | Feed-tuning event processor | n/a (server) | n/a | — | server | yes (europe-west1) |
| `onAppReleasePublished` | Trigger | Release announcement fan-out | n/a (server) | n/a | — | server | yes (europe-west1) |
| `shareToAudience` | Callable | Share a post to followers | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-user cap | yes | yes (us-central1) |
| `connectorStatus` | Callable | Which linked accounts are connected | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | yes (us-central1) |
| `verifyCoinPurchase` | Callable | Verify a Play coin purchase | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | **no** |
| `sendUserGift` | Callable | Send coins as a gift | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | **no** |
| `walletSync` | Callable | Wallet balances / hold release | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | **no** |
| `payoutOptions` | Callable | Payout rails for a country | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | **no** |
| `payoutBanks` | Callable | Bank list for a rail | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | **no** |
| `savePayoutMethod` | Callable | Save a payout method | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | **no** |
| `deletePayoutMethod` | Callable | Delete a payout method | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | **no** |
| `requestWithdrawal` | Callable | Request a withdrawal | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | 3/day, one open at a time | yes | **no** |
| `cancelWithdrawal` | Callable | Cancel a pending withdrawal | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | **no** |
| `reviewWithdrawal` | Callable | Admin approve/reject a held withdrawal | Admin only | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | no | **no** |
| `flutterwaveWebhook` | HTTPS | Flutterwave transfer webhook | Public; verif-hash header (timing-safe) | n/a (server-to-server) | — | server | **no** |
| `paystackWebhook` | HTTPS | Paystack transfer webhook | Public; x-paystack-signature HMAC-SHA512 | n/a (server-to-server) | — | server | **no** |
| `kycStart` | Callable | Start Stripe Identity check | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | **no** |
| `kycRefresh` | Callable | Refresh KYC status | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | **no** |
| `creatorStripeWebhook` | HTTPS | Stripe Identity + transfer.reversed webhook | Public; Stripe signature | n/a (server-to-server) | — | server | **no** |
| `verifySubscriptionPurchase` | Callable | Verify a Play subscription | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | **no** |
| `playBillingNotifications` | Pub/Sub | Play RTDN (Pub/Sub play-billing) | n/a (server) | n/a | — | server | **no** |
| `insightsOnView` | Trigger | Creator insights counter | n/a (server) | n/a | — | server | **no** |
| `insightsOnLike` | Trigger | Creator insights counter | n/a (server) | n/a | — | server | **no** |
| `insightsOnUnlike` | Trigger | Creator insights counter | n/a (server) | n/a | — | server | **no** |
| `insightsOnShare` | Trigger | Creator insights counter | n/a (server) | n/a | — | server | **no** |
| `insightsOnComment` | Trigger | Creator insights counter | n/a (server) | n/a | — | server | **no** |
| `insightsOnFollow` | Trigger | Creator insights counter | n/a (server) | n/a | — | server | **no** |
| `insightsOnEarning` | Trigger | Creator insights counter | n/a (server) | n/a | — | server | **no** |
| `recordWatchTime` | Callable | Watch-time for creator insights | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | **no** |
| `stripeConfig` | Callable | Stripe publishable config | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | **no** |
| `stripeConnectOnboard` | Callable | Stripe Connect onboarding link | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | **no** |
| `stripePayoutStatus` | Callable | Stripe Connect status | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | **no** |
| `quoteDelivery` | Callable | Marketplace delivery quote | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | **no** |
| `createOrderCheckout` | Callable | Marketplace checkout (escrow) | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | **no** |
| `stripeWebhook` | HTTPS | Marketplace Stripe webhook | Public; Stripe signature | n/a (server-to-server) | — | server | **no** |
| `acceptDelivery` | Callable | Courier accepts a delivery | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | **no** |
| `startJourney` | Callable | Courier starts a delivery | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | **no** |
| `confirmDelivery` | Callable | Buyer confirms delivery (releases escrow) | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | **no** |
| `cancelOrder` | Callable | Cancel an order | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | **no** |
| `aiProxy` | HTTPS | OpenRouter-compatible AI proxy (no key in the app) | Firebase ID token (Bearer) | Verified + flag (X-Firebase-AppCheck) | 400/day per user | yes | **no** |
| `arEffectGenerate` | Callable | Create an AR effect with AI | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Daily cap per user | yes | yes (us-central1) |
| `arEffectCreateFromUpload` | Callable | Create an AR effect from an upload | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Daily cap per user | yes | yes (us-central1) |
| `arEffectUse` | Callable | Count an AR effect use | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | yes (us-central1) |
| `arEffectFavoriteAdded` | Trigger | AR favourite counter +1 | n/a (server) | n/a | — | server | yes (europe-west1) |
| `arEffectFavoriteRemoved` | Trigger | AR favourite counter -1 | n/a (server) | n/a | — | server | yes (europe-west1) |
| `tiktokExchangeCode` | Callable | TikTok OAuth code exchange | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | 10 / 10 min per user | yes | yes (us-central1) |
| `globalSemanticSearch` | Callable | App-wide search (Vertex embeddings) | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | 60 / min per user | yes | yes (us-central1) |
| `lsStart` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsToken` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsEnd` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsTime` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsStateFull` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsSetOwnMedia` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsSetSettings` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsHeartbeat` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsSweepOrphanLives` | Schedule | Ends abandoned lives | n/a (server) | n/a | — | server | yes (us-central1) |
| `lsFun` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsGift` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsDestinations` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsBroadcast` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsRecordingDecision` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsSetLayout` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsRequestJoin` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsCancelRequest` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsRespondRequest` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsModerate` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsLeaveStage` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsSetTable` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsPlayback` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsMediaKey` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsSecOnIncident` | Trigger | Live AI health monitor (allow-listed advice) | n/a (server) | n/a | — | server | yes (europe-west1) |
| `lsSecOnBlock` | Trigger | Live media key rotation on block | n/a (server) | n/a | — | server | yes (europe-west1) |
| `lsSecOnMemberWrite` | Trigger | Live media key rotation on stage change | n/a (server) | n/a | — | server | yes (europe-west1) |
| `lsSetChatMode` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsSetJoinRequests` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsComment` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsDeleteComment` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsMuteChat` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsReact` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsShare` | Callable | Live Studio | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsLivekitWebhook` | HTTPS | LiveKit room/egress webhook | Public; LiveKit signed JWT (WebhookReceiver) | n/a (server-to-server) | — | server | yes (us-central1) |
| `lsGifSearch` | Callable | Live Studio trusted GIF search | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsWatch` | Callable | Live Studio Watch Together state & sync | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsYouTubeSearch` | Callable | Live Studio Watch Together YouTube search | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `lsPool` | Callable | Live Studio multiplayer 3D 8-Ball Pool & server physics | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-stream/per-user (liveStudio/shared rateLimit) | yes | yes (us-central1) |
| `contentSetDestination` | Callable | Author sets/clears Ova Guard-checked reel destination/product link | Signed in (author) | Verified; enforced when APP_CHECK_ENFORCE=true | 30 / 10 min per user | yes | yes (us-central1) |
| `contentOpenDestination` | Callable | Opens reel destination link, re-verifies Web Risk & counts unique clicks | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | 120 / 10 min per user | yes | yes (us-central1) |
| `voiceTidy` | Callable | Cleans dictated text (punctuation, capitals, filler removal) on Vertex AI | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | Per-user | yes | yes (us-central1) |
| `onCallParticipantWritten` | Trigger | Call participant state | n/a (server) | n/a | — | server | yes (europe-west1) |
| `onCallFinished` | Trigger | Call summary / missed-call | n/a (server) | n/a | — | server | yes (europe-west1) |
| `sweepStaleCalls` | Schedule | Ends stale calls | n/a (server) | n/a | — | server | yes (us-central1) |
| `onNotificationCreated` | Trigger | Sends FCM push for a notification doc | n/a (server) | n/a | — | server | yes (europe-west1) |
| `registerBiometricKey` | Callable | Enroll fingerprint sign-in key | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | yes (us-central1) |
| `biometricSignIn` | Callable | Fingerprint sign-in (custom token) | None; device key secret (hashed) | Verified; enforced when APP_CHECK_ENFORCE=true | 30 / 15 min per IP | yes | yes (us-central1) |
| `revokeBiometricKey` | Callable | Remove a fingerprint key | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | yes (us-central1) |
| `loginContext` | Callable | Masked IP/region for login history | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | yes (us-central1) |
| `guardReportSession` | Callable | Ova Guard: session/device/location report | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | yes (us-central1) |
| `guardReportAuthFailure` | Callable | Ova Guard: failed sign-in report (signed out) | None (signed out by design) | Verified; enforced when APP_CHECK_ENFORCE=true | 30 / 15 min per IP | yes | yes (us-central1) |
| `checkLegacyPassword` | Callable | Server check of old in-profile password hashes | Optional (signed out allowed) | Verified; enforced when APP_CHECK_ENFORCE=true | 20 / 15 min per IP + 10 failures per account | yes | yes (us-central1) |
| `guardRespond` | Callable | Answer an alert / secure my account | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | yes (us-central1) |
| `guardRevokeDevice` | Callable | Log out one device | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | yes (us-central1) |
| `guardExplainEvent` | Callable | Plain-language explanation of an event (Vertex) | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | 20 / h per user (cached per event) | yes | yes (us-central1) |
| `guardOnMessage` | Trigger | Ova Guard: message bursts + link/scam scan of readable chat messages | n/a (server) | n/a | — | server | **no** |
| `guardOnRelationship` | Trigger | Ova Guard: follow bursts | n/a (server) | n/a | — | server | **no** |
| `moveLegacyPasswordHashesDaily` | Schedule | Moves old password hashes off profiles | n/a (server) | n/a | — | server | **no** |
| `moveLegacyPasswordHashesNow` | Callable | Admin: run that move now | Admin only | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | no | **no** |
| `guardEmailOnEvent` | Trigger | E-mails high-risk alerts | n/a (server) | n/a | — | server | **no** |
| `securityLink` | HTTPS | One-time e-mail link (confirm / secure) | Public; single-use hashed token, 30 min, POST to act | n/a (server-to-server) | — | server | **no** |
| `sendEmailCode` | Callable | Send an e-mail code | Optional (sign-in) | Verified; enforced when APP_CHECK_ENFORCE=true | Per IP per hour + resend wait | yes | yes (us-central1) |
| `verifyEmailCode` | Callable | Check an e-mail code | Optional (sign-in) | Verified; enforced when APP_CHECK_ENFORCE=true | Locks after wrong tries | yes | yes (us-central1) |
| `metaExchangeCode` | Callable | Meta (FB/IG/WA) OAuth exchange | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | 10 / 10 min per user | yes | yes (us-central1) |
| `metaDataDeletion` | HTTPS | Meta data-deletion callback | Public; Meta signed_request HMAC | n/a (server-to-server) | — | server | **no** |
| `metaDeauthorize` | HTTPS | Meta deauthorize callback | Public; Meta signed_request HMAC | n/a (server-to-server) | — | server | **no** |
| `metaDeletionStatus` | HTTPS | Meta deletion status page | Public read-only status page (confirmation code) | n/a (server-to-server) | — | server | **no** |
| `gmailConnect` | Callable | Connect user Gmail | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | **no** |
| `gmailStatus` | Callable | Gmail connection status | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | no | **no** |
| `gmailDisconnect` | Callable | Disconnect Gmail | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | **no** |
| `gmailCall` | Callable | Gmail read/send proxy | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | **no** |
| `inboxSendMessage` | Callable | Unified inbox send | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | yes (us-central1) |
| `markConversationRead` | Callable | Unified inbox read marker | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | yes (us-central1) |
| `requestSecureAttachmentUpload` | Callable | Signed upload for inbox attachments | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | yes (us-central1) |
| `revokeAllSessions` | Callable | Sign out every session | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | yes (us-central1) |
| `searchMessages` | Callable | Inbox search | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | yes | yes (us-central1) |
| `generateCatalogBundles` | Callable | Looks catalog bundles | Signed in | Verified; enforced when APP_CHECK_ENFORCE=true | none yet | no | **no** |
| `onBillingBudgetNotification` | Pub/Sub | Cloud budget alerts → spend levels | n/a (server) | n/a | — | server | **no** |
| `scheduledFeedbackBigQueryExport` | Schedule | Looks feedback → BigQuery | n/a (server) | n/a | — | server | **no** |
| `createLookOptimized` | Callable | Looks: create a look (quota) | Signed in | Enforced (always) | Token bucket + daily quota (tier) | no | **no** |
| `enqueueComputeJobCallable` | Callable | Looks: queue a compute job | Signed in | Enforced (always) | Token bucket + daily quota (tier) | no | **no** |
| `getComputeJobStatusCallable` | Callable | Looks: compute job status | Signed in | Enforced (always) | none yet | no | **no** |

## Deployed but not in this source (46)

These come from another codebase that shares the project (the `oc*` functions and `api`). **Never run an unscoped `firebase deploy --only functions`**: it would delete them. Always deploy by name (`--only functions:NAME,...`).

`api`, `ocActivatePreviewPlan`, `ocAgentTool`, `ocAggregateEvent`, `ocAnalyzeBookDocument`, `ocAppStoreNotifications`, `ocBootstrapUser`, `ocClaimBookSerial`, `ocCoachAutoAssist`, `ocCoachReply`, `ocCoachSweep`, `ocCoachTurn`, `ocConvertBookToAudiobook`, `ocCreateAccessCodes`, `ocDailyBrief`, `ocDeleteAccount`, `ocDeleteBook`, `ocDispatchNudges`, `ocDraftReply`, `ocEnrollUserPhone`, `ocFinishSession`, `ocGenerateBookSerials`, `ocGetBookAccess`, `ocGetBookAnalytics`, `ocInterventionLines`, `ocLiveSetup`, `ocLiveTranscript`, `ocNarratePassage`, `ocOnCheckIn`, `ocParseTodo`, `ocPlayBillingNotifications`, `ocRecordBookActivity`, `ocRecountMetrics`, `ocRedeemAccessCode`, `ocRunPlanAgent`, `ocSaveBook`, `ocSetAdmin`, `ocStripeBuyBook`, `ocStripeConfig`, `ocStripePortal`, `ocStripeSubscribe`, `ocStripeWebhook`, `ocSyncCoachKnowledge`, `ocTranslate`, `ocTranslateBookPassage`, `ocVerifyPurchase`

## Firestore and Storage paths the guard adds

| Path | Who can read | Who can write |
|---|---|---|
| `security_events/{uid}/events` | owner, admin | functions |
| `security_state/{uid}` (`restrictions`, `withdrawalsFrozenUntil`) | owner, admin | functions |
| `security_actions/{id}` | the affected user, admin | functions |
| `users/{uid}/private/contact` | owner, admin | owner, functions |
| `contact_index`, `link_reputation`, `guard_ai_cache`, `guard_budget`, `guard_verified_names`, `security_rate`, `security_counters` | nobody (deny-all) | functions |
| `moderation_cases` (source `ova_guard`) | admin | signed-in create (existing), functions |

TTL: set Firestore TTL policies on `expiresAt` for `security_rate`, `link_reputation`, `guard_ai_cache` and `guard_budget` so they clean themselves up.

