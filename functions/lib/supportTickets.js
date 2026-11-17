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
exports.pollSupportSession = exports.supportSessionSendMessage = exports.supportAgentTurn = exports.lookupSupportTicket = exports.submitSupportTicket = void 0;
const crypto = __importStar(require("crypto"));
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const genai_1 = require("@google/genai");
const logger = __importStar(require("firebase-functions/logger"));
const protect_1 = require("./guard/protect");
const vertexAi_1 = require("./vertexAi");
const db = () => (0, firestore_1.getFirestore)();
const ALLOWED_CATEGORIES = new Set([
    'account',
    'wallet',
    'shops',
    'identity',
    'live',
    'desktop',
    'reels',
    'privacy',
    'other',
]);
function sha256Hex(value) {
    return crypto.createHash('sha256').update(value).digest('hex');
}
function generateTrackingCode() {
    const num = crypto.randomInt(100000, 999999);
    return `OVA-${num}`;
}
function generateAccessPin() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    let out = '';
    for (let i = 0; i < 6; i++) {
        out += alphabet[crypto.randomInt(0, alphabet.length)];
    }
    return out;
}
function getVerifiedUid(request) {
    var _a, _b;
    const auth = request.auth;
    if (!auth)
        return '';
    if (((_b = (_a = auth.token) === null || _a === void 0 ? void 0 : _a.firebase) === null || _b === void 0 ? void 0 : _b.sign_in_provider) === 'anonymous')
        return '';
    return auth.uid;
}
function verifyTicketPin(expectedHash, trackingCode, accessPin) {
    const cleanCode = trackingCode.trim().toUpperCase();
    const cleanPin = accessPin.trim().toUpperCase();
    if (!/^OVA-\d{6}$/.test(cleanCode) || !/^[A-Z0-9]{6}$/.test(cleanPin)) {
        return false;
    }
    const providedHash = sha256Hex(`${cleanCode}:${cleanPin}`);
    if (expectedHash.length !== providedHash.length)
        return false;
    return crypto.timingSafeEqual(Buffer.from(expectedHash), Buffer.from(providedHash));
}
async function authorizeTicketSession(request, raw) {
    var _a, _b, _c;
    const authUid = getVerifiedUid(request);
    const ticketId = String((_a = raw.ticketId) !== null && _a !== void 0 ? _a : '').trim();
    const trackingCode = String((_b = raw.trackingCode) !== null && _b !== void 0 ? _b : '').trim().toUpperCase();
    const accessPin = String((_c = raw.accessPin) !== null && _c !== void 0 ? _c : '').trim().toUpperCase();
    let snap = null;
    if (ticketId && /^[A-Za-z0-9_-]{6,128}$/.test(ticketId)) {
        const candidate = await db().collection('support_tickets').doc(ticketId).get();
        if (candidate.exists)
            snap = candidate;
    }
    else if (/^OVA-\d{6}$/.test(trackingCode)) {
        const q = await db()
            .collection('support_tickets')
            .where('trackingCode', '==', trackingCode)
            .limit(1)
            .get();
        if (!q.empty)
            snap = q.docs[0];
    }
    if (!snap || !snap.exists) {
        throw new https_1.HttpsError('not-found', 'Support session not found.');
    }
    const data = snap.data() || {};
    const isOwner = Boolean(authUid && data.uid && data.uid === authUid);
    const pinValid = Boolean(data.pinHash &&
        data.trackingCode &&
        verifyTicketPin(String(data.pinHash), String(data.trackingCode), accessPin));
    if (!isOwner && !pinValid) {
        throw new https_1.HttpsError('permission-denied', 'Invalid tracking credentials or account session.');
    }
    return { ticketRef: snap.ref, data };
}
function isoTimestamp(v) {
    if (!v)
        return null;
    if (v instanceof firestore_1.Timestamp)
        return v.toDate().toISOString();
    if (typeof v.toDate === 'function') {
        return v.toDate().toISOString();
    }
    return null;
}
async function createTicketRecord(params) {
    const trackingCode = generateTrackingCode();
    const accessPin = generateAccessPin();
    const ref = db().collection('support_tickets').doc();
    const category = ALLOWED_CATEGORIES.has(params.category)
        ? params.category
        : 'other';
    const status = params.needsHuman ? 'escalated_human' : 'open';
    const batch = db().batch();
    batch.set(ref, {
        uid: params.authUid,
        trackingCode,
        pinHash: sha256Hex(`${trackingCode}:${accessPin}`),
        category,
        subject: params.subject.slice(0, 140),
        message: params.message.slice(0, 2000),
        contactEmail: (params.contactEmail || '').slice(0, 120),
        status,
        needsHuman: Boolean(params.needsHuman),
        aiSummary: (params.aiSummary || '').slice(0, 3000),
        adminReply: '',
        repliedByUid: '',
        repliedByName: '',
        handledByUid: '',
        handledByName: '',
        lastMessagePreview: params.message.slice(0, 260),
        lastMessageAt: firestore_1.FieldValue.serverTimestamp(),
        unreadByAdmin: true,
        unreadByUser: false,
        createdAt: firestore_1.FieldValue.serverTimestamp(),
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    });
    const msgRef = ref.collection('messages').doc();
    batch.set(msgRef, {
        senderRole: 'user',
        senderUid: params.authUid,
        senderName: params.authUid ? 'Verified Member' : 'Guest Visitor',
        text: params.message.slice(0, 2000),
        actionTaken: '',
        createdAt: firestore_1.FieldValue.serverTimestamp(),
    });
    if (params.initialAiNote) {
        const aiMsgRef = ref.collection('messages').doc();
        batch.set(aiMsgRef, {
            senderRole: 'ai',
            senderUid: 'ova-support-ai',
            senderName: 'Oneova AI Specialist',
            text: params.initialAiNote.slice(0, 2000),
            actionTaken: params.needsHuman ? 'escalated_to_human_admin' : 'ticket_created',
            createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
    }
    await batch.commit();
    return { ticketId: ref.id, trackingCode, accessPin, status };
}
exports.submitSupportTicket = (0, https_1.onCall)(async (request) => {
    var _a, _b, _c, _d, _e;
    const ip = (0, protect_1.callerIp)(request);
    await (0, protect_1.limit)(ip, 'support_ticket_ip', 8, 60 * 60000);
    const authUid = getVerifiedUid(request);
    if (authUid) {
        await (0, protect_1.limit)(authUid, 'support_ticket_uid', 15, 24 * 3600000);
    }
    const raw = ((_a = request.data) !== null && _a !== void 0 ? _a : {});
    const categoryRaw = String((_b = raw.category) !== null && _b !== void 0 ? _b : 'other').trim().toLowerCase();
    const subject = String((_c = raw.subject) !== null && _c !== void 0 ? _c : '').trim();
    const message = String((_d = raw.message) !== null && _d !== void 0 ? _d : '').trim();
    const contactEmail = String((_e = raw.contactEmail) !== null && _e !== void 0 ? _e : '').trim().slice(0, 120);
    if (subject.length < 3 || subject.length > 140) {
        throw new https_1.HttpsError('invalid-argument', 'Subject must be between 3 and 140 characters.');
    }
    if (message.length < 10 || message.length > 2000) {
        throw new https_1.HttpsError('invalid-argument', 'Message must be between 10 and 2000 characters.');
    }
    if (contactEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(contactEmail)) {
        throw new https_1.HttpsError('invalid-argument', 'Please provide a valid email address.');
    }
    const created = await createTicketRecord({
        authUid,
        category: categoryRaw,
        subject,
        message,
        contactEmail,
        needsHuman: Boolean(raw.needsHuman),
        aiSummary: raw.aiSummary ? String(raw.aiSummary) : '',
    });
    return Object.assign({ ok: true }, created);
});
exports.lookupSupportTicket = (0, https_1.onCall)(async (request) => {
    var _a, _b, _c, _d;
    const ip = (0, protect_1.callerIp)(request);
    await (0, protect_1.limit)(ip, 'support_lookup_ip', 20, 10 * 60000);
    const raw = ((_a = request.data) !== null && _a !== void 0 ? _a : {});
    const trackingCode = String((_b = raw.trackingCode) !== null && _b !== void 0 ? _b : '').trim().toUpperCase();
    const accessPin = String((_c = raw.accessPin) !== null && _c !== void 0 ? _c : '').trim().toUpperCase();
    if (!/^OVA-\d{6}$/.test(trackingCode) || !/^[A-Z0-9]{6}$/.test(accessPin)) {
        throw new https_1.HttpsError('invalid-argument', 'Enter a valid tracking code and 6-character PIN.');
    }
    const snap = await db()
        .collection('support_tickets')
        .where('trackingCode', '==', trackingCode)
        .limit(1)
        .get();
    if (snap.empty) {
        throw new https_1.HttpsError('not-found', 'Ticket not found or PIN mismatch.');
    }
    const data = snap.docs[0].data();
    if (!verifyTicketPin(String((_d = data.pinHash) !== null && _d !== void 0 ? _d : ''), trackingCode, accessPin)) {
        throw new https_1.HttpsError('not-found', 'Ticket not found or PIN mismatch.');
    }
    return {
        ok: true,
        ticketId: snap.docs[0].id,
        trackingCode: data.trackingCode,
        category: data.category,
        subject: data.subject,
        status: data.status,
        needsHuman: Boolean(data.needsHuman),
        handledByName: data.handledByName || data.repliedByName || '',
        adminReply: data.adminReply || '',
        updatedAt: isoTimestamp(data.updatedAt),
    };
});
async function runAgentTool(name, args, ctx) {
    var _a, _b, _c, _d, _e;
    var _f, _g, _h, _j, _k;
    const { authUid } = ctx;
    switch (name) {
        case 'check_my_account_id_status': {
            if (!authUid) {
                return {
                    signedIn: false,
                    note: 'Visitor is not signed in. Ask if they want to click "Sign in with Oneova" in this window to inspect live account, Global ID KYC, Wallet, or Shop status, or offer to connect a human admin.',
                };
            }
            ctx.liveChecksRun.push('Account & Global ID Check');
            const [userSnap, kycSnap, idSnap, bizIdSnap, secSnap] = await Promise.all([
                db().doc(`users/${authUid}`).get(),
                db().doc(`kyc/${authUid}`).get(),
                db().doc(`identity/${authUid}`).get(),
                db().doc(`business_identity/${authUid}`).get(),
                db().doc(`security_state/${authUid}`).get(),
            ]);
            const u = userSnap.data() || {};
            const k = kycSnap.data() || {};
            const id = idSnap.data() || {};
            const b = bizIdSnap.data() || {};
            const sec = secSnap.data() || {};
            const withdrawalsFrozenUntil = isoTimestamp(sec.withdrawalsFrozenUntil);
            return {
                signedIn: true,
                accountFound: userSnap.exists,
                username: String(u.username || ''),
                accountStatus: String(u.status || 'active'),
                globalIdStatus: String(id.status || k.status || 'unverified'),
                kycDocumentType: String(k.documentType || ''),
                kycReviewNote: String(k.rejectionReason || k.note || ''),
                businessIdStatus: String(b.status || 'none'),
                hasSecurityHold: Boolean(withdrawalsFrozenUntil),
                withdrawalsFrozenUntil,
                activeRestrictions: Object.keys(sec.restrictions || {}),
            };
        }
        case 'check_my_wallet_payouts': {
            if (!authUid) {
                return {
                    signedIn: false,
                    note: 'Wallet balances and payouts require signing in with Oneova first.',
                };
            }
            ctx.liveChecksRun.push('Wallet & Payouts Check');
            const [balSnap, bizBalSnap, methodsSnap, payoutsSnap, kycSnap] = await Promise.all([
                db().doc(`pay_balances/${authUid}`).get(),
                db().doc(`pay_business_balances/${authUid}`).get(),
                db().collection(`payout_methods/${authUid}/methods`).limit(5).get(),
                db()
                    .collection('pay_payouts')
                    .where('uid', '==', authUid)
                    .limit(5)
                    .get(),
                db().doc(`kyc/${authUid}`).get(),
            ]);
            const personal = balSnap.data() || {};
            const business = bizBalSnap.data() || {};
            return {
                signedIn: true,
                kycVerified: ((_f = (_a = kycSnap.data()) === null || _a === void 0 ? void 0 : _a.status) !== null && _f !== void 0 ? _f : '') === 'verified',
                personalCurrency: String(personal.currency || 'USD').toUpperCase(),
                personalAvailableMinor: Number((_g = personal.availableMinor) !== null && _g !== void 0 ? _g : 0),
                personalLockedMinor: Number((_h = personal.lockedMinor) !== null && _h !== void 0 ? _h : 0),
                businessCurrency: String(business.currency || personal.currency || 'USD').toUpperCase(),
                businessAvailableMinor: Number((_j = business.availableMinor) !== null && _j !== void 0 ? _j : 0),
                payoutMethodsConfigured: methodsSnap.size,
                payoutRails: methodsSnap.docs.map((m) => { var _a, _b; return String(((_a = m.data()) === null || _a === void 0 ? void 0 : _a.rail) || ((_b = m.data()) === null || _b === void 0 ? void 0 : _b.provider) || 'method'); }),
                recentPayouts: payoutsSnap.docs.map((p) => {
                    const pd = p.data();
                    return {
                        status: String(pd.status || 'unknown'),
                        rail: String(pd.rail || ''),
                        currency: String(pd.currency || ''),
                        failureReason: String(pd.failureReason || pd.errorMessage || ''),
                    };
                }),
            };
        }
        case 'inspect_or_fix_my_shop': {
            if (!authUid) {
                return {
                    signedIn: false,
                    note: '3D Shop diagnostics and automated storefront repair require signing in with Oneova.',
                };
            }
            ctx.liveChecksRun.push('3D Shop Diagnostics');
            const repairFeatured = Boolean(args.repairFeaturedProduct);
            const [shopSnap, productsSnap] = await Promise.all([
                db().doc(`biz_shops/${authUid}`).get(),
                db()
                    .collection('products')
                    .where('ownerId', '==', authUid)
                    .limit(20)
                    .get(),
            ]);
            if (!shopSnap.exists) {
                return {
                    signedIn: true,
                    hasShop: false,
                    productCount: productsSnap.size,
                    nextStep: 'Open Oneova → Biz / Studio → Open 3D Shop wizard to publish your storefront.',
                };
            }
            const shop = shopSnap.data() || {};
            const activeProducts = productsSnap.docs.filter((d) => { var _a; return ((_a = d.data()) === null || _a === void 0 ? void 0 : _a.active) !== false; });
            const activeIds = new Set(activeProducts.map((d) => d.id));
            let autoFixed = '';
            if (repairFeatured &&
                activeProducts.length > 0 &&
                (!shop.featuredProductId || !activeIds.has(String(shop.featuredProductId)))) {
                await shopSnap.ref.update({
                    featuredProductId: activeProducts[0].id,
                    updatedAt: firestore_1.FieldValue.serverTimestamp(),
                });
                autoFixed = `Linked your active product "${((_b = activeProducts[0].data()) === null || _b === void 0 ? void 0 : _b.title) || activeProducts[0].id}" as your shop featured item.`;
                ctx.liveChecksRun.push('Auto-Repaired Featured Shop Product');
            }
            return {
                signedIn: true,
                hasShop: true,
                shopName: String(shop.name || ''),
                shopStatus: String(shop.status || 'draft'),
                verified: Boolean(shop.verified),
                totalProducts: productsSnap.size,
                activeProducts: activeProducts.length,
                hasFeaturedProduct: Boolean(shop.featuredProductId && activeIds.has(String(shop.featuredProductId))) || Boolean(autoFixed),
                autoFixed,
            };
        }
        case 'search_oneova_guides': {
            ctx.liveChecksRun.push('Live Platform Docs Lookup');
            const queryStr = String(args.query || ctx.userMessage).toLowerCase();
            const tokens = queryStr.split(/\s+/).filter((t) => t.length > 2).slice(0, 5);
            const snap = await db()
                .collection('platform_cms_docs')
                .where('isPublished', '==', true)
                .limit(20)
                .get();
            const matches = [];
            for (const docSnap of snap.docs) {
                const d = docSnap.data();
                const blob = `${d.title || ''} ${d.category || ''} ${d.inShort || ''}`.toLowerCase();
                const hit = tokens.length === 0 || tokens.some((tk) => blob.includes(tk));
                if (hit) {
                    ctx.suggestedDocIds.add(docSnap.id);
                    matches.push({
                        docId: docSnap.id,
                        title: String(d.title || docSnap.id),
                        summary: String(d.inShort || '').slice(0, 260),
                    });
                }
            }
            return {
                guidesFound: matches.length,
                matches: matches.slice(0, 4),
            };
        }
        case 'check_support_ticket_status': {
            const code = String(args.trackingCode || ((_c = ctx.activeTicket) === null || _c === void 0 ? void 0 : _c.trackingCode) || '')
                .trim()
                .toUpperCase();
            const pin = String(args.accessPin || ((_d = ctx.activeTicket) === null || _d === void 0 ? void 0 : _d.accessPin) || '')
                .trim()
                .toUpperCase();
            if (!code || !pin) {
                return { found: false, reason: 'Tracking code and 6-character PIN required.' };
            }
            ctx.liveChecksRun.push('Live Ticket Status Lookup');
            const q = await db()
                .collection('support_tickets')
                .where('trackingCode', '==', code)
                .limit(1)
                .get();
            if (q.empty)
                return { found: false, reason: 'No ticket matches that tracking code.' };
            const t = q.docs[0];
            const td = t.data();
            if (!verifyTicketPin(String((_k = td.pinHash) !== null && _k !== void 0 ? _k : ''), code, pin)) {
                return { found: false, reason: 'Access PIN did not match.' };
            }
            return {
                found: true,
                ticketId: t.id,
                trackingCode: code,
                status: String(td.status || 'open'),
                handledByName: String(td.handledByName || td.repliedByName || ''),
                adminReply: String(td.adminReply || ''),
            };
        }
        case 'escalate_to_human_admin': {
            ctx.liveChecksRun.push('Escalated to Live Human Admin (/admin)');
            const subject = String(args.subject || 'Live Support Assistance Needed').trim();
            const category = String(args.category || 'other').trim().toLowerCase();
            const aiSummary = String(args.aiSummary ||
                `AI Checks Run: ${ctx.liveChecksRun.join(', ') || 'Initial triage'}. User request: ${ctx.userMessage}`).trim();
            if ((_e = ctx.activeTicket) === null || _e === void 0 ? void 0 : _e.ticketId) {
                const ref = db().collection('support_tickets').doc(ctx.activeTicket.ticketId);
                await ref.set({
                    status: 'escalated_human',
                    needsHuman: true,
                    aiSummary: aiSummary.slice(0, 3000),
                    unreadByAdmin: true,
                    lastMessagePreview: ctx.userMessage.slice(0, 260),
                    lastMessageAt: firestore_1.FieldValue.serverTimestamp(),
                    updatedAt: firestore_1.FieldValue.serverTimestamp(),
                }, { merge: true });
                await ref.collection('messages').add({
                    senderRole: 'ai',
                    senderUid: 'ova-support-ai',
                    senderName: 'Oneova AI Specialist',
                    text: aiSummary.slice(0, 2000),
                    actionTaken: 'escalated_to_human_admin',
                    createdAt: firestore_1.FieldValue.serverTimestamp(),
                });
                return {
                    escalated: true,
                    ticketId: ctx.activeTicket.ticketId,
                    trackingCode: ctx.activeTicket.trackingCode,
                };
            }
            const created = await createTicketRecord({
                authUid,
                category,
                subject,
                message: ctx.userMessage,
                needsHuman: true,
                aiSummary,
                initialAiNote: aiSummary,
            });
            ctx.createdEscalation.value = created;
            return Object.assign({ escalated: true }, created);
        }
        default:
            return { error: `Unknown tool ${name}` };
    }
}
const SUPPORT_AGENT_TOOLS = [
    {
        functionDeclarations: [
            {
                name: 'check_my_account_id_status',
                description: 'Check live signed-in user account status, Oneova Global ID / KYC verification status, business ID status, and active security restrictions.',
                parameters: { type: genai_1.Type.OBJECT, properties: {} },
            },
            {
                name: 'check_my_wallet_payouts',
                description: 'Check live Oneova Wallet personal/business balances, M-Pesa/MoMo/bank payout readiness, and recent payout status or failure reasons for the signed-in user.',
                parameters: { type: genai_1.Type.OBJECT, properties: {} },
            },
            {
                name: 'inspect_or_fix_my_shop',
                description: 'Inspect the signed-in user Oneova 3D Shop storefront and catalog, and optionally auto-repair missing featured product linkage.',
                parameters: {
                    type: genai_1.Type.OBJECT,
                    properties: {
                        repairFeaturedProduct: {
                            type: genai_1.Type.BOOLEAN,
                            description: 'Set true to link an active product automatically if featuredProductId is missing or broken.',
                        },
                    },
                },
            },
            {
                name: 'search_oneova_guides',
                description: 'Search live published Oneova guides and policies stored in Firestore platform_cms_docs.',
                parameters: {
                    type: genai_1.Type.OBJECT,
                    properties: { query: { type: genai_1.Type.STRING } },
                    required: ['query'],
                },
            },
            {
                name: 'check_support_ticket_status',
                description: 'Look up a support ticket using trackingCode (OVA-xxxxxx) and 6-char accessPin.',
                parameters: {
                    type: genai_1.Type.OBJECT,
                    properties: {
                        trackingCode: { type: genai_1.Type.STRING },
                        accessPin: { type: genai_1.Type.STRING },
                    },
                },
            },
            {
                name: 'escalate_to_human_admin',
                description: 'Escalate this live conversation to a human Oneova Admin inside the /admin dashboard so a human agent can join the live thread immediately. Use when manual review, payout investigation, KYC appeal, or explicit human help is requested.',
                parameters: {
                    type: genai_1.Type.OBJECT,
                    properties: {
                        category: {
                            type: genai_1.Type.STRING,
                            description: 'One of: account, wallet, shops, identity, live, desktop, reels, privacy, other',
                        },
                        subject: { type: genai_1.Type.STRING, description: 'Clear 4-12 word ticket summary' },
                        aiSummary: {
                            type: genai_1.Type.STRING,
                            description: 'Concise diagnostic summary for the human admin including checks run and next action.',
                        },
                    },
                    required: ['category', 'subject', 'aiSummary'],
                },
            },
        ],
    },
];
exports.supportAgentTurn = (0, https_1.onCall)({ timeoutSeconds: 60, memory: '512MiB' }, async (request) => {
    var _a, _b, _c, _d, _e, _f;
    const ip = (0, protect_1.callerIp)(request);
    await (0, protect_1.limit)(ip, 'support_ai_ip', 25, 10 * 60000);
    const authUid = getVerifiedUid(request);
    if (authUid) {
        await (0, protect_1.limit)(authUid, 'support_ai_uid', 80, 24 * 3600000);
    }
    const raw = ((_a = request.data) !== null && _a !== void 0 ? _a : {});
    const userMessage = String((_b = raw.message) !== null && _b !== void 0 ? _b : '').trim().slice(0, 1500);
    if (!userMessage) {
        throw new https_1.HttpsError('invalid-argument', 'Message cannot be empty.');
    }
    const requestHuman = Boolean(raw.requestHuman);
    const rawHistory = Array.isArray(raw.history) ? raw.history.slice(-10) : [];
    const activeTicketId = String((_c = raw.ticketId) !== null && _c !== void 0 ? _c : '').trim();
    const activeTrackingCode = String((_d = raw.trackingCode) !== null && _d !== void 0 ? _d : '').trim().toUpperCase();
    const activeAccessPin = String((_e = raw.accessPin) !== null && _e !== void 0 ? _e : '').trim().toUpperCase();
    const liveChecksRun = [];
    const suggestedDocIds = new Set();
    const createdEscalation = { value: null };
    const activeTicket = activeTicketId && activeTrackingCode
        ? {
            ticketId: activeTicketId,
            trackingCode: activeTrackingCode,
            accessPin: activeAccessPin,
        }
        : undefined;
    // Fast path if the user explicitly clicked "Connect Human Admin"
    if (requestHuman) {
        await runAgentTool('escalate_to_human_admin', {
            category: String(raw.category || 'other'),
            subject: userMessage.slice(0, 80) || 'Live Human Support Request',
            aiSummary: `User requested live human admin takeover: "${userMessage}". Session is ${authUid ? 'authenticated Oneova user' : 'guest visitor'}.`,
        }, {
            authUid,
            userMessage,
            activeTicket,
            liveChecksRun,
            suggestedDocIds,
            createdEscalation,
        });
        return {
            ok: true,
            reply: createdEscalation.value
                ? `Connected you to the live Oneova Support queue. Ticket ${createdEscalation.value.trackingCode} (PIN: ${createdEscalation.value.accessPin}) is now flagged for a human admin in real time — keep this window open to chat live when an admin joins.`
                : 'Escalated this session to a human Oneova admin in real time. Stay here to receive their live reply.',
            skillUsed: 'Live Human Handoff',
            liveChecksRun,
            suggestedDocIds: Array.from(suggestedDocIds),
            escalation: createdEscalation.value,
            signedIn: Boolean(authUid),
        };
    }
    const systemInstruction = `You are the Oneova Live Support AI Specialist on https://oneova.web.app.
Oneova empowers African and global creators to monetize their creativity through Oneova Wallet & Mobile Money (M-Pesa, MTN MoMo, Airtel Money, Orange, Wave), Oneova 3D Shops & Live Commerce, Oneova Global ID verification, Live Stage & Gifts, Reels, and Ova Desktop Assistant.

Rules you MUST follow:
1. Work LIVE with tools whenever possible. If the user asks about their account, Global ID KYC, Wallet/payouts, or 3D Shop setup, call the live diagnostic tools first before answering.
2. If the user is a Guest (signedIn=false) and asks to inspect or fix personal account/wallet/shop/ID data, tell them warmly they can click "Sign in with Oneova" right inside this window for instant live diagnostics & auto-fixes, OR you can escalate directly to a human admin.
3. Never mention competitor social apps or retired providers (never say Stripe; Stripe was replaced by Oneova Pay).
4. Escalate immediately via escalate_to_human_admin if:
   - the user asks for a human admin/person/agent, OR
   - a payout/balance is stuck/frozen, KYC needs manual review, or a suspended account appeals.
5. Keep replies concise, practical, natural human tone (under 110 words), referencing any live findings cleanly.`;
    const contents = [];
    for (const turn of rawHistory) {
        const role = (turn === null || turn === void 0 ? void 0 : turn.sender) === 'user' ? 'user' : 'model';
        const txt = String((_f = turn === null || turn === void 0 ? void 0 : turn.text) !== null && _f !== void 0 ? _f : '').trim().slice(0, 900);
        if (txt)
            contents.push({ role, parts: [{ text: txt }] });
    }
    contents.push({
        role: 'user',
        parts: [
            {
                text: `[Session State: ${authUid ? 'SIGNED_IN_USER' : 'GUEST_VISITOR'}${raw.category ? ` · Topic: ${String(raw.category)}` : ''}] ${userMessage}`,
            },
        ],
    });
    try {
        let replyText = '';
        for (let step = 0; step < 4; step++) {
            const res = await (0, vertexAi_1.generateVertexContent)({
                contents,
                config: {
                    systemInstruction,
                    tools: SUPPORT_AGENT_TOOLS,
                    temperature: 0.25,
                    maxOutputTokens: 500,
                },
            });
            const calls = res.functionCalls;
            if (calls && calls.length > 0) {
                contents.push({
                    role: 'model',
                    parts: calls.map((c) => ({ functionCall: c })),
                });
                const responseParts = [];
                for (const call of calls) {
                    const out = await runAgentTool(String(call.name || ''), (call.args || {}), {
                        authUid,
                        userMessage,
                        activeTicket,
                        liveChecksRun,
                        suggestedDocIds,
                        createdEscalation,
                    });
                    responseParts.push({
                        functionResponse: {
                            name: call.name,
                            response: out,
                        },
                    });
                }
                contents.push({ role: 'user', parts: responseParts });
                continue;
            }
            replyText = String(res.text || '').trim();
            break;
        }
        if (!replyText) {
            replyText = createdEscalation.value
                ? `I’ve escalated your request to our live admin team (${createdEscalation.value.trackingCode}, PIN ${createdEscalation.value.accessPin}). An admin can join right here in real time.`
                : 'I checked your request against Oneova live systems. Could you share a little more detail—or tap "Talk to Human" below so an admin can inspect it with you live?';
        }
        return {
            ok: true,
            reply: replyText,
            skillUsed: liveChecksRun.length > 0 ? liveChecksRun[liveChecksRun.length - 1] : 'Oneova Live AI',
            liveChecksRun,
            suggestedDocIds: Array.from(suggestedDocIds).slice(0, 3),
            escalation: createdEscalation.value,
            signedIn: Boolean(authUid),
        };
    }
    catch (err) {
        logger.warn('supportAgentTurn fallback activated', (err === null || err === void 0 ? void 0 : err.message) || err);
        const guideOut = await runAgentTool('search_oneova_guides', { query: userMessage }, {
            authUid,
            userMessage,
            activeTicket,
            liveChecksRun,
            suggestedDocIds,
            createdEscalation,
        });
        const matches = guideOut.matches || [];
        return {
            ok: true,
            reply: matches.length > 0
                ? `Here is what our live guides cover for "${matches[0].title}": ${matches[0].summary} Need live human review? Tap "Talk to Human" to connect directly with our admin team.`
                : 'I could not reach the live reasoning model right now, so I checked our live docs. Tap "Talk to Human" below to open a real-time support session with an admin.',
            skillUsed: 'Live Docs Fallback',
            liveChecksRun,
            suggestedDocIds: Array.from(suggestedDocIds).slice(0, 3),
            escalation: createdEscalation.value,
            signedIn: Boolean(authUid),
        };
    }
});
exports.supportSessionSendMessage = (0, https_1.onCall)(async (request) => {
    var _a, _b;
    const ip = (0, protect_1.callerIp)(request);
    await (0, protect_1.limit)(ip, 'support_msg_ip', 40, 10 * 60000);
    const raw = ((_a = request.data) !== null && _a !== void 0 ? _a : {});
    const text = String((_b = raw.text) !== null && _b !== void 0 ? _b : '').trim();
    if (!text || text.length > 2000) {
        throw new https_1.HttpsError('invalid-argument', 'Message must be between 1 and 2000 characters.');
    }
    const authUid = getVerifiedUid(request);
    const { ticketRef, data } = await authorizeTicketSession(request, raw);
    await db().runTransaction(async (tx) => {
        const msgRef = ticketRef.collection('messages').doc();
        tx.set(msgRef, {
            senderRole: 'user',
            senderUid: authUid,
            senderName: authUid ? 'Verified Member' : 'Guest Visitor',
            text,
            actionTaken: '',
            createdAt: firestore_1.FieldValue.serverTimestamp(),
        });
        tx.update(ticketRef, {
            status: data.status === 'resolved' || data.status === 'closed'
                ? 'escalated_human'
                : data.status || 'escalated_human',
            needsHuman: true,
            unreadByAdmin: true,
            unreadByUser: false,
            lastMessagePreview: text.slice(0, 260),
            lastMessageAt: firestore_1.FieldValue.serverTimestamp(),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
    });
    return { ok: true };
});
exports.pollSupportSession = (0, https_1.onCall)(async (request) => {
    var _a;
    const ip = (0, protect_1.callerIp)(request);
    await (0, protect_1.limit)(ip, 'support_poll_ip', 60, 5 * 60000);
    const raw = ((_a = request.data) !== null && _a !== void 0 ? _a : {});
    const { ticketRef, data } = await authorizeTicketSession(request, raw);
    const msgsSnap = await ticketRef
        .collection('messages')
        .orderBy('createdAt', 'asc')
        .limit(50)
        .get();
    return {
        ok: true,
        ticketId: ticketRef.id,
        trackingCode: String(data.trackingCode || ''),
        status: String(data.status || 'open'),
        needsHuman: Boolean(data.needsHuman),
        handledByName: String(data.handledByName || data.repliedByName || ''),
        adminReply: String(data.adminReply || ''),
        messages: msgsSnap.docs.map((m) => {
            const md = m.data();
            return {
                id: m.id,
                senderRole: String(md.senderRole || 'user'),
                senderName: String(md.senderName || ''),
                text: String(md.text || ''),
                actionTaken: String(md.actionTaken || ''),
                createdAt: isoTimestamp(md.createdAt),
            };
        }),
    };
});
//# sourceMappingURL=supportTickets.js.map