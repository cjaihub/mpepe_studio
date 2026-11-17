import * as crypto from 'crypto';
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { FieldValue, getFirestore, Timestamp } from 'firebase-admin/firestore';
import { Type } from '@google/genai';
import * as logger from 'firebase-functions/logger';
import { callerIp, limit } from './guard/protect';
import { generateVertexContent } from './vertexAi';

const db = () => getFirestore();

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

function sha256Hex(value: string): string {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function generateTrackingCode(): string {
  const num = crypto.randomInt(100000, 999999);
  return `OVA-${num}`;
}

function generateAccessPin(): string {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let out = '';
  for (let i = 0; i < 6; i++) {
    out += alphabet[crypto.randomInt(0, alphabet.length)];
  }
  return out;
}

function getVerifiedUid(request: CallableRequest<unknown>): string {
  const auth = request.auth;
  if (!auth) return '';
  if (auth.token?.firebase?.sign_in_provider === 'anonymous') return '';
  return auth.uid;
}

function verifyTicketPin(
  expectedHash: string,
  trackingCode: string,
  accessPin: string,
): boolean {
  const cleanCode = trackingCode.trim().toUpperCase();
  const cleanPin = accessPin.trim().toUpperCase();
  if (!/^OVA-\d{6}$/.test(cleanCode) || !/^[A-Z0-9]{6}$/.test(cleanPin)) {
    return false;
  }
  const providedHash = sha256Hex(`${cleanCode}:${cleanPin}`);
  if (expectedHash.length !== providedHash.length) return false;
  return crypto.timingSafeEqual(
    Buffer.from(expectedHash),
    Buffer.from(providedHash),
  );
}

async function authorizeTicketSession(
  request: CallableRequest<unknown>,
  raw: Record<string, unknown>,
): Promise<{
  ticketRef: FirebaseFirestore.DocumentReference;
  data: FirebaseFirestore.DocumentData;
}> {
  const authUid = getVerifiedUid(request);
  const ticketId = String(raw.ticketId ?? '').trim();
  const trackingCode = String(raw.trackingCode ?? '').trim().toUpperCase();
  const accessPin = String(raw.accessPin ?? '').trim().toUpperCase();

  let snap: FirebaseFirestore.DocumentSnapshot | null = null;
  if (ticketId && /^[A-Za-z0-9_-]{6,128}$/.test(ticketId)) {
    const candidate = await db().collection('support_tickets').doc(ticketId).get();
    if (candidate.exists) snap = candidate;
  } else if (/^OVA-\d{6}$/.test(trackingCode)) {
    const q = await db()
      .collection('support_tickets')
      .where('trackingCode', '==', trackingCode)
      .limit(1)
      .get();
    if (!q.empty) snap = q.docs[0];
  }

  if (!snap || !snap.exists) {
    throw new HttpsError('not-found', 'Support session not found.');
  }

  const data = snap.data() || {};
  const isOwner = Boolean(authUid && data.uid && data.uid === authUid);
  const pinValid = Boolean(
    data.pinHash &&
      data.trackingCode &&
      verifyTicketPin(String(data.pinHash), String(data.trackingCode), accessPin),
  );

  if (!isOwner && !pinValid) {
    throw new HttpsError(
      'permission-denied',
      'Invalid tracking credentials or account session.',
    );
  }
  return { ticketRef: snap.ref, data };
}

function isoTimestamp(v: unknown): string | null {
  if (!v) return null;
  if (v instanceof Timestamp) return v.toDate().toISOString();
  if (typeof (v as { toDate?: () => Date }).toDate === 'function') {
    return (v as { toDate: () => Date }).toDate().toISOString();
  }
  return null;
}

async function createTicketRecord(params: {
  authUid: string;
  category: string;
  subject: string;
  message: string;
  contactEmail?: string;
  needsHuman?: boolean;
  aiSummary?: string;
  initialAiNote?: string;
}) {
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
    lastMessageAt: FieldValue.serverTimestamp(),
    unreadByAdmin: true,
    unreadByUser: false,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  const msgRef = ref.collection('messages').doc();
  batch.set(msgRef, {
    senderRole: 'user',
    senderUid: params.authUid,
    senderName: params.authUid ? 'Verified Member' : 'Guest Visitor',
    text: params.message.slice(0, 2000),
    actionTaken: '',
    createdAt: FieldValue.serverTimestamp(),
  });

  if (params.initialAiNote) {
    const aiMsgRef = ref.collection('messages').doc();
    batch.set(aiMsgRef, {
      senderRole: 'ai',
      senderUid: 'ova-support-ai',
      senderName: 'Oneova AI Specialist',
      text: params.initialAiNote.slice(0, 2000),
      actionTaken: params.needsHuman ? 'escalated_to_human_admin' : 'ticket_created',
      createdAt: FieldValue.serverTimestamp(),
    });
  }

  await batch.commit();
  return { ticketId: ref.id, trackingCode, accessPin, status };
}

export const submitSupportTicket = onCall(async (request) => {
  const ip = callerIp(request);
  await limit(ip, 'support_ticket_ip', 8, 60 * 60000);

  const authUid = getVerifiedUid(request);
  if (authUid) {
    await limit(authUid, 'support_ticket_uid', 15, 24 * 3600000);
  }

  const raw = (request.data ?? {}) as Record<string, unknown>;
  const categoryRaw = String(raw.category ?? 'other').trim().toLowerCase();
  const subject = String(raw.subject ?? '').trim();
  const message = String(raw.message ?? '').trim();
  const contactEmail = String(raw.contactEmail ?? '').trim().slice(0, 120);

  if (subject.length < 3 || subject.length > 140) {
    throw new HttpsError(
      'invalid-argument',
      'Subject must be between 3 and 140 characters.',
    );
  }
  if (message.length < 10 || message.length > 2000) {
    throw new HttpsError(
      'invalid-argument',
      'Message must be between 10 and 2000 characters.',
    );
  }
  if (contactEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(contactEmail)) {
    throw new HttpsError('invalid-argument', 'Please provide a valid email address.');
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

  return { ok: true, ...created };
});

export const lookupSupportTicket = onCall(async (request) => {
  const ip = callerIp(request);
  await limit(ip, 'support_lookup_ip', 20, 10 * 60000);

  const raw = (request.data ?? {}) as Record<string, unknown>;
  const trackingCode = String(raw.trackingCode ?? '').trim().toUpperCase();
  const accessPin = String(raw.accessPin ?? '').trim().toUpperCase();

  if (!/^OVA-\d{6}$/.test(trackingCode) || !/^[A-Z0-9]{6}$/.test(accessPin)) {
    throw new HttpsError(
      'invalid-argument',
      'Enter a valid tracking code and 6-character PIN.',
    );
  }

  const snap = await db()
    .collection('support_tickets')
    .where('trackingCode', '==', trackingCode)
    .limit(1)
    .get();

  if (snap.empty) {
    throw new HttpsError('not-found', 'Ticket not found or PIN mismatch.');
  }

  const data = snap.docs[0].data();
  if (!verifyTicketPin(String(data.pinHash ?? ''), trackingCode, accessPin)) {
    throw new HttpsError('not-found', 'Ticket not found or PIN mismatch.');
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

async function runAgentTool(
  name: string,
  args: Record<string, unknown>,
  ctx: {
    authUid: string;
    userMessage: string;
    activeTicket?: { ticketId: string; trackingCode: string; accessPin?: string };
    liveChecksRun: string[];
    suggestedDocIds: Set<string>;
    createdEscalation: { value: null | { ticketId: string; trackingCode: string; accessPin: string; status: string } };
  },
): Promise<Record<string, unknown>> {
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
        activeRestrictions: Object.keys((sec.restrictions as Record<string, unknown>) || {}),
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
        kycVerified: (kycSnap.data()?.status ?? '') === 'verified',
        personalCurrency: String(personal.currency || 'USD').toUpperCase(),
        personalAvailableMinor: Number(personal.availableMinor ?? 0),
        personalLockedMinor: Number(personal.lockedMinor ?? 0),
        businessCurrency: String(business.currency || personal.currency || 'USD').toUpperCase(),
        businessAvailableMinor: Number(business.availableMinor ?? 0),
        payoutMethodsConfigured: methodsSnap.size,
        payoutRails: methodsSnap.docs.map((m) => String(m.data()?.rail || m.data()?.provider || 'method')),
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
      const activeProducts = productsSnap.docs.filter((d) => d.data()?.active !== false);
      const activeIds = new Set(activeProducts.map((d) => d.id));
      let autoFixed = '';
      if (
        repairFeatured &&
        activeProducts.length > 0 &&
        (!shop.featuredProductId || !activeIds.has(String(shop.featuredProductId)))
      ) {
        await shopSnap.ref.update({
          featuredProductId: activeProducts[0].id,
          updatedAt: FieldValue.serverTimestamp(),
        });
        autoFixed = `Linked your active product "${activeProducts[0].data()?.title || activeProducts[0].id}" as your shop featured item.`;
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

      const matches: Array<{ docId: string; title: string; summary: string }> = [];
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
      const code = String(args.trackingCode || ctx.activeTicket?.trackingCode || '')
        .trim()
        .toUpperCase();
      const pin = String(args.accessPin || ctx.activeTicket?.accessPin || '')
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
      if (q.empty) return { found: false, reason: 'No ticket matches that tracking code.' };
      const t = q.docs[0];
      const td = t.data();
      if (!verifyTicketPin(String(td.pinHash ?? ''), code, pin)) {
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
      const aiSummary = String(
        args.aiSummary ||
          `AI Checks Run: ${ctx.liveChecksRun.join(', ') || 'Initial triage'}. User request: ${ctx.userMessage}`,
      ).trim();

      if (ctx.activeTicket?.ticketId) {
        const ref = db().collection('support_tickets').doc(ctx.activeTicket.ticketId);
        await ref.set(
          {
            status: 'escalated_human',
            needsHuman: true,
            aiSummary: aiSummary.slice(0, 3000),
            unreadByAdmin: true,
            lastMessagePreview: ctx.userMessage.slice(0, 260),
            lastMessageAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        await ref.collection('messages').add({
          senderRole: 'ai',
          senderUid: 'ova-support-ai',
          senderName: 'Oneova AI Specialist',
          text: aiSummary.slice(0, 2000),
          actionTaken: 'escalated_to_human_admin',
          createdAt: FieldValue.serverTimestamp(),
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
      return {
        escalated: true,
        ...created,
      };
    }

    default:
      return { error: `Unknown tool ${name}` };
  }
}

const SUPPORT_AGENT_TOOLS: any = [
  {
    functionDeclarations: [
      {
        name: 'check_my_account_id_status',
        description:
          'Check live signed-in user account status, Oneova Global ID / KYC verification status, business ID status, and active security restrictions.',
        parameters: { type: Type.OBJECT, properties: {} },
      },
      {
        name: 'check_my_wallet_payouts',
        description:
          'Check live Oneova Wallet personal/business balances, M-Pesa/MoMo/bank payout readiness, and recent payout status or failure reasons for the signed-in user.',
        parameters: { type: Type.OBJECT, properties: {} },
      },
      {
        name: 'inspect_or_fix_my_shop',
        description:
          'Inspect the signed-in user Oneova 3D Shop storefront and catalog, and optionally auto-repair missing featured product linkage.',
        parameters: {
          type: Type.OBJECT,
          properties: {
            repairFeaturedProduct: {
              type: Type.BOOLEAN,
              description: 'Set true to link an active product automatically if featuredProductId is missing or broken.',
            },
          },
        },
      },
      {
        name: 'search_oneova_guides',
        description:
          'Search live published Oneova guides and policies stored in Firestore platform_cms_docs.',
        parameters: {
          type: Type.OBJECT,
          properties: { query: { type: Type.STRING } },
          required: ['query'],
        },
      },
      {
        name: 'check_support_ticket_status',
        description:
          'Look up a support ticket using trackingCode (OVA-xxxxxx) and 6-char accessPin.',
        parameters: {
          type: Type.OBJECT,
          properties: {
            trackingCode: { type: Type.STRING },
            accessPin: { type: Type.STRING },
          },
        },
      },
      {
        name: 'escalate_to_human_admin',
        description:
          'Escalate this live conversation to a human Oneova Admin inside the /admin dashboard so a human agent can join the live thread immediately. Use when manual review, payout investigation, KYC appeal, or explicit human help is requested.',
        parameters: {
          type: Type.OBJECT,
          properties: {
            category: {
              type: Type.STRING,
              description: 'One of: account, wallet, shops, identity, live, desktop, reels, privacy, other',
            },
            subject: { type: Type.STRING, description: 'Clear 4-12 word ticket summary' },
            aiSummary: {
              type: Type.STRING,
              description: 'Concise diagnostic summary for the human admin including checks run and next action.',
            },
          },
          required: ['category', 'subject', 'aiSummary'],
        },
      },
    ],
  },
];

export const supportAgentTurn = onCall(
  { timeoutSeconds: 60, memory: '512MiB' },
  async (request) => {
    const ip = callerIp(request);
    await limit(ip, 'support_ai_ip', 25, 10 * 60000);

    const authUid = getVerifiedUid(request);
    if (authUid) {
      await limit(authUid, 'support_ai_uid', 80, 24 * 3600000);
    }

    const raw = (request.data ?? {}) as Record<string, unknown>;
    const userMessage = String(raw.message ?? '').trim().slice(0, 1500);
    if (!userMessage) {
      throw new HttpsError('invalid-argument', 'Message cannot be empty.');
    }

    const requestHuman = Boolean(raw.requestHuman);
    const rawHistory = Array.isArray(raw.history) ? raw.history.slice(-10) : [];
    const activeTicketId = String(raw.ticketId ?? '').trim();
    const activeTrackingCode = String(raw.trackingCode ?? '').trim().toUpperCase();
    const activeAccessPin = String(raw.accessPin ?? '').trim().toUpperCase();

    const liveChecksRun: string[] = [];
    const suggestedDocIds = new Set<string>();
    const createdEscalation: {
      value: null | {
        ticketId: string;
        trackingCode: string;
        accessPin: string;
        status: string;
      };
    } = { value: null };

    const activeTicket =
      activeTicketId && activeTrackingCode
        ? {
            ticketId: activeTicketId,
            trackingCode: activeTrackingCode,
            accessPin: activeAccessPin,
          }
        : undefined;

    // Fast path if the user explicitly clicked "Connect Human Admin"
    if (requestHuman) {
      await runAgentTool(
        'escalate_to_human_admin',
        {
          category: String(raw.category || 'other'),
          subject: userMessage.slice(0, 80) || 'Live Human Support Request',
          aiSummary: `User requested live human admin takeover: "${userMessage}". Session is ${authUid ? 'authenticated Oneova user' : 'guest visitor'}.`,
        },
        {
          authUid,
          userMessage,
          activeTicket,
          liveChecksRun,
          suggestedDocIds,
          createdEscalation,
        },
      );
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

    const contents: any[] = [];
    for (const turn of rawHistory) {
      const role = turn?.sender === 'user' ? 'user' : 'model';
      const txt = String(turn?.text ?? '').trim().slice(0, 900);
      if (txt) contents.push({ role, parts: [{ text: txt }] });
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
        const res = await generateVertexContent({
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
            parts: calls.map((c: any) => ({ functionCall: c })),
          });

          const responseParts = [];
          for (const call of calls) {
            const out = await runAgentTool(
              String(call.name || ''),
              (call.args || {}) as Record<string, unknown>,
              {
                authUid,
                userMessage,
                activeTicket,
                liveChecksRun,
                suggestedDocIds,
                createdEscalation,
              },
            );
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
        skillUsed:
          liveChecksRun.length > 0 ? liveChecksRun[liveChecksRun.length - 1] : 'Oneova Live AI',
        liveChecksRun,
        suggestedDocIds: Array.from(suggestedDocIds).slice(0, 3),
        escalation: createdEscalation.value,
        signedIn: Boolean(authUid),
      };
    } catch (err: any) {
      logger.warn('supportAgentTurn fallback activated', err?.message || err);
      const guideOut = await runAgentTool(
        'search_oneova_guides',
        { query: userMessage },
        {
          authUid,
          userMessage,
          activeTicket,
          liveChecksRun,
          suggestedDocIds,
          createdEscalation,
        },
      );
      const matches = (guideOut.matches as Array<{ docId: string; title: string; summary: string }>) || [];
      return {
        ok: true,
        reply:
          matches.length > 0
            ? `Here is what our live guides cover for "${matches[0].title}": ${matches[0].summary} Need live human review? Tap "Talk to Human" to connect directly with our admin team.`
            : 'I could not reach the live reasoning model right now, so I checked our live docs. Tap "Talk to Human" below to open a real-time support session with an admin.',
        skillUsed: 'Live Docs Fallback',
        liveChecksRun,
        suggestedDocIds: Array.from(suggestedDocIds).slice(0, 3),
        escalation: createdEscalation.value,
        signedIn: Boolean(authUid),
      };
    }
  },
);

export const supportSessionSendMessage = onCall(async (request) => {
  const ip = callerIp(request);
  await limit(ip, 'support_msg_ip', 40, 10 * 60000);

  const raw = (request.data ?? {}) as Record<string, unknown>;
  const text = String(raw.text ?? '').trim();
  if (!text || text.length > 2000) {
    throw new HttpsError(
      'invalid-argument',
      'Message must be between 1 and 2000 characters.',
    );
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
      createdAt: FieldValue.serverTimestamp(),
    });
    tx.update(ticketRef, {
      status:
        data.status === 'resolved' || data.status === 'closed'
          ? 'escalated_human'
          : data.status || 'escalated_human',
      needsHuman: true,
      unreadByAdmin: true,
      unreadByUser: false,
      lastMessagePreview: text.slice(0, 260),
      lastMessageAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  return { ok: true };
});

export const pollSupportSession = onCall(async (request) => {
  const ip = callerIp(request);
  await limit(ip, 'support_poll_ip', 60, 5 * 60000);

  const raw = (request.data ?? {}) as Record<string, unknown>;
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
