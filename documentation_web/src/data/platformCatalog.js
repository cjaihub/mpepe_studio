/**
 * Authoritative baseline catalog of Oneova's Real Platform Features
 * and Official Rules, Safety & African/Global Regulatory Frameworks.
 */

export const PLATFORM_BASELINE_DOCS = [
  // ══════════════════════════════════════════════════════════════════════════
  // TRACK 1: ONEOVA PLATFORM FEATURES & CREATOR ECONOMY GUIDES
  // ══════════════════════════════════════════════════════════════════════════
  {
    id: 'wallet-biz-commerce',
    docType: 'feature',
    category: 'Wallet, Shops & Global ID',
    policyTab: '',
    title: 'Oneova Wallet, Mobile Money & Creator Payouts',
    badge: 'ONEOVA PAY',
    isAccentBadge: true,
    readTime: '5 min read',
    version: 'v2.0',
    effectiveDate: 'November 17, 2026',
    order: 1,
    isPublished: true,
    inShort:
      'Manage Personal and Business balances in local African & global currencies, accept Scan-to-Pay QR and mobile money, and withdraw earnings with published transparent fees.',
    sections: [
      {
        heading: '1. Personal & Business Balances on an Immutable Ledger',
        summary:
          'Every gift share, shop sale, and customer QR payment settles into an append-only double-entry ledger with strict non-overdraft and biometric verification.',
        callout:
          'Move settled store revenue from your Business Balance (`biz:`) to your Personal Balance anytime with device biometrics, or withdraw directly to mobile money and bank rails.',
        bullets: [
          'Native African mobile-money support: M-Pesa STK Push, MTN MoMo, Airtel Money, Orange Money, Telecel Cash, and Wave via central-bank-licensed partners.',
          'Personal & Merchant Scan-to-Pay QR codes for in-person events, markets, and pop-ups.',
          'Biometric confirmation (fingerprint or Face ID stored in hardware Keystore / Secure Enclave) before approving transfers or withdrawals.',
        ],
      },
      {
        heading: '2. Published, Predictable Fee Rules',
        summary:
          'No hidden spreads or surprise deductions—exact integer-math fee quotes are shown before you confirm any withdrawal or order.',
        callout: '',
        bullets: [
          'Creator & Merchant Mobile-Money Payouts: 1.5% deducted in your local currency.',
          'Bank Account Payouts: 1% deducted in your payout currency.',
          'Oneova Shop Orders: 10% platform commission on items; delivery fees pass to the rider in full.',
        ],
      },
    ],
    htmlOverride: '',
  },
  {
    id: 'biz-3d-shops',
    docType: 'feature',
    category: 'Wallet, Shops & Global ID',
    policyTab: '',
    title: 'Oneova 3D Shops, Presenter’s Goods & Biz Storefronts',
    badge: '3D SHOPS',
    isAccentBadge: true,
    readTime: '5 min read',
    version: 'v2.0',
    effectiveDate: 'November 17, 2026',
    order: 2,
    isPublished: true,
    inShort:
      'Open a verified African business storefront in minutes without payout blockers, display interactive 3D products right on your Live stage, and fulfill orders with server-backed escrow.',
    sections: [
      {
        heading: '1. Zero-Blocker Shop Setup & 24/7 3D Showrooms',
        summary:
          'Sellers open their store immediately after adding a shop name, location, and first product—payout verification can be completed later whenever you are ready to cash out.',
        callout:
          'Your 3D Shop keeps selling even when your livestream ends: buyers rotate interactive products, compare variants in local currency, and pay safely into order escrow.',
        bullets: [
          'Full-screen swipeable Biz & Shop discovery stage (`/shops`), putting live sellers first.',
          'Automatic local currency approximations powered by hourly synced FX rates (`KES`, `NGN`, `GHS`, `UGX`, `TZS`, `ZAR`, `XOF`, `USD`).',
          'Real-time merchant Portal (`/business`) for packing, tracking order status (`new → packed → ready → shipped`), low-stock alerts, and promo codes.',
        ],
      },
      {
        heading: '2. Live Commerce & Presenter’s Goods',
        summary:
          'Pin any product onto your Live broadcast stage so viewers tap `View item`, ask questions in live chat, and purchase without leaving the broadcast.',
        callout: '',
        bullets: [
          'Interactive `Presenter’s Goods` 3D card overlaid cleanly above live audience comments.',
          'Server-side stock & variant validation prevents overselling the final unit during flash drops.',
          'Automated Ova Store Assistant answers catalog questions directly on your storefront when you step away.',
        ],
      },
    ],
    htmlOverride: '',
  },
  {
    id: 'global-id',
    docType: 'feature',
    category: 'Wallet, Shops & Global ID',
    policyTab: '',
    title: 'Oneova Global ID (Personal KYC & Business KYB)',
    badge: 'GLOBAL ID',
    isAccentBadge: false,
    readTime: '4 min read',
    version: 'v2.0',
    effectiveDate: 'November 17, 2026',
    order: 3,
    isPublished: true,
    inShort:
      'Carry one verified digital identity for African & global creators and businesses—unlocking instant payout trust, verified shop badges, and SIM-recycle defense.',
    sections: [
      {
        heading: '1. Built for African Creators & Businesses',
        summary:
          'Legacy platforms routinely lock African creators out of verification and payments. Oneova Global ID supports national IDs, passports, and driver licenses across African and global corridors.',
        callout:
          'Each verified human owner can also link up to 3 of their own creator or business accounts under a single trusted credential.',
        bullets: [
          'Personal Verification (`Identity KYC`) pairs ID photo + live face liveness check with human review.',
          'Business Verification (`Business KYB`) registers shop owners, beneficial directors, and merchant payouts cleanly.',
          'Hardware-bound credential vault stores signed proof strictly inside your phone—Share QR proof anytime without exposing raw document photos.',
        ],
      },
    ],
    htmlOverride: '',
  },
  {
    id: 'live-studio',
    docType: 'feature',
    category: 'Live, Reels & Social',
    policyTab: '',
    title: 'Oneova Live Stage, Multi-Guest Panels & Fan Gifts',
    badge: 'LIVE STAGE',
    isAccentBadge: true,
    readTime: '5 min read',
    version: 'v1.5',
    effectiveDate: 'November 17, 2026',
    order: 4,
    isPublished: true,
    inShort:
      'Host solo shows, 4-panel guest stages, live product demos, polls, countdowns, and raffles where fans support creators directly with Coins & Gifts.',
    sections: [
      {
        heading: '1. Unified Live Setup & Multi-Guest Stage',
        summary:
          'Every Go Live action uses the same 6-step wizard and interactive stage with host video, guest join panels, Presenter’s Goods shopping card, and clean audience view.',
        callout:
          'Viewers support hosts directly with Coins and animated Fan Gifts (Roses, Stars, Crowns, Rockets, Diamonds)—and creators earn real Wallet income from fan appreciation.',
        bullets: [
          'Solo, Studio Multi-Guest (up to 4 co-hosts on stage), and Screen/Game layouts.',
          'Live polls, countdown timers, spotlight comments, raffles, and celebratory effects.',
          'Instant host moderation tools to mute guests or manage stage requests in 1 tap.',
        ],
      },
    ],
    htmlOverride: '',
  },
  {
    id: 'reels-feed',
    docType: 'feature',
    category: 'Live, Reels & Social',
    policyTab: '',
    title: 'Creator Feed, 24h Stories & Remix Attribution',
    badge: 'FEED & REMIX',
    isAccentBadge: false,
    readTime: '4 min read',
    version: 'v1.5',
    effectiveDate: 'November 17, 2026',
    order: 5,
    isPublished: true,
    inShort:
      'Discover Following, For You, and Biz feeds built for low-data mobile bundles—with 24-hour Stories, shoppable tags, and permanent original-creator Remix attribution.',
    sections: [
      {
        heading: '1. Built for Everyday African Mobile Data Bundles',
        summary:
          'Smart adaptive caching delivers smooth vertical video playback without chewing through precious mobile data allowances.',
        callout:
          'Hold the right edge for fast-forward speed or left edge to scrub smoothly—and tap REMIX to build on trending creator sounds with guaranteed credit back to the original creator.',
        bullets: [
          'Locked home experience unifying Following, For You, and Biz streams with 24h Stories.',
          'Shop tags connect Reels directly to an item in the creator’s Oneova 3D Shop.',
          'Original audio attribution and Remix tracking protect creator credit every time a sound goes viral.',
        ],
      },
    ],
    htmlOverride: '',
  },
  {
    id: 'translated-chat',
    docType: 'feature',
    category: 'Live, Reels & Social',
    policyTab: '',
    title: 'Encrypted Chat & Real-Time Translated Calls',
    badge: 'E2EE CHAT',
    isAccentBadge: false,
    readTime: '4 min read',
    version: 'v1.4',
    effectiveDate: 'November 17, 2026',
    order: 6,
    isPublished: true,
    inShort:
      'Communicate privately with end-to-end encrypted 1:1/group chats, disappearing messages, and real-time voice translation on calls and voice notes.',
    sections: [
      {
        heading: '1. Borderless Cross-Language Conversations',
        summary:
          'Collaborate with buyers, suppliers, and creators speaking Swahili, Yoruba, Zulu, French, Arabic, or English inside private encrypted rooms.',
        callout:
          'Safety Numbers and Oneova Shield verification let any two people verify their encrypted media & voice calls.',
        bullets: [
          'Private 1:1 chats, group rooms, disappearing timers, message editing, and shared media galleries.',
          'Real-time AI voice & call interpreter breaks language barriers during live voice/video calls.',
          'Blocked-pair enforcement ensures blocked accounts cannot call or message you.',
        ],
      },
    ],
    htmlOverride: '',
  },
  {
    id: 'ova-ai-lab',
    docType: 'feature',
    category: 'Ova AI & Security',
    policyTab: '',
    title: 'Ova Personal AI, Live Help & Desktop Agent',
    badge: 'OVA AI AGENT',
    isAccentBadge: true,
    readTime: '5 min read',
    version: 'v2.0',
    effectiveDate: 'November 17, 2026',
    order: 7,
    isPublished: true,
    inShort:
      'Summon Ova with your phone’s power button for instant highlight & screen translation, ask the Live Web Support Agent to diagnose real account issues, or run Oneova Desktop on Mac & Windows.',
    sections: [
      {
        heading: '1. Live Problem-Solving on Your Real Data',
        summary:
          'On the web portal and inside Oneova, our AI Support Agent runs secure checks on your signed-in Wallet, Global ID, and 3D Shop status—repairing missing shop links automatically or escalating to a live human admin in `/admin`.',
        callout:
          'Human admins join your escalated support thread in real time so complex payout or verification reviews never stall.',
        bullets: [
          'Android Power-Button Default Assistant: highlight any screen area or translate foreign text in place without switching apps.',
          'Conversational voice mode with natural human tone across African & global languages.',
          'Paired Mac & Windows Desktop Agent (`⌥Space` / `Alt+Space`) with startup launch, permission shield, and multi-screen control.',
        ],
      },
    ],
    htmlOverride: '',
  },
  {
    id: 'security-desktop-ecosystem',
    docType: 'feature',
    category: 'Ova AI & Security',
    policyTab: '',
    title: 'Account Safety, SIM-Recycle Shield & Device Advisor',
    badge: 'SECURITY FIRST',
    isAccentBadge: false,
    readTime: '4 min read',
    version: 'v1.5',
    effectiveDate: 'November 17, 2026',
    order: 8,
    isPublished: true,
    inShort:
      'Defend creator accounts against SIM-card recycling, verify payouts with hardware biometrics, and tune app performance for affordable Android phones to flagship devices.',
    sections: [
      {
        heading: '1. Zero-Trust Creator & Device Protection',
        summary:
          'Security comes first across every Oneova account, payment device, and paired computer.',
        callout:
          'Oneova staff NEVER ask for your password, App PIN, OTP codes, or mobile-money PIN.',
        bullets: [
          'SIM-Recycle Protection: link a passkey or recovery email + App PIN so recycled mobile numbers cannot hijack your account.',
          'Hardware Keystore / Secure Enclave binding approves high-value Wallet and payout actions.',
          'Adaptive Device Advisor optimizes memory & thermal performance on everyday smartphones without crashes.',
        ],
      },
    ],
    htmlOverride: '',
  },

  // ══════════════════════════════════════════════════════════════════════════
  // TRACK 2: RULES, POLICIES & AFRICAN/GLOBAL REGULATIONS
  // ══════════════════════════════════════════════════════════════════════════
  {
    id: 'policy-community-guidelines',
    docType: 'policy',
    category: 'Community & Safety',
    policyTab: 'guidelines',
    title: 'Community Guidelines & Anti-Scam Rules',
    badge: 'ANTI-FRAUD & SAFETY',
    isAccentBadge: true,
    readTime: '5 min read',
    version: 'v1.1',
    effectiveDate: 'November 17, 2026',
    order: 11,
    isPublished: true,
    inShort:
      'Be real, be respectful, be safe. Zero tolerance for mobile-money scams, hate speech, non-consensual imagery, or child exploitation—with transparent strikes and human appeals.',
    sections: [
      {
        heading: '1. Financial Integrity & Mobile-Money Scam Bans',
        summary:
          'We actively defend African and global creators and shoppers against mobile-money fraud, fake receipts, and impersonation.',
        callout:
          'Official Safety Rule: Oneova will NEVER ask for your password, OTP, or mobile-money PIN.',
        bullets: [
          'Strictly banned: Fake M-Pesa, MTN MoMo, Airtel Money, Orange, or Wave reversal messages, doctored payment screenshots, SIM-swap phishing, and Ponzi/advance-fee schemes.',
          'No impersonating creators, verified Biz Shops, telecom operators, banks, or public officials.',
          'Honest disclosure of sponsored posts (`#ad` / `#sponsored`) and realistic AI-generated media labels.',
        ],
      },
      {
        heading: '2. Graduated 3-Strike Ladder & Human Appeals',
        summary: '',
        callout: '',
        bullets: [
          'Educational Warning → 7-day limit → 30-day limit → Suspension (clear strikes expire after 90 clean days). Severe harm triggers immediate permanent removal.',
          'Tap Report in 2 taps on any Reel, Live stage, Shop, or message. Every enforcement decision includes a free review by a human specialist.',
        ],
      },
    ],
    htmlOverride: '',
  },
  {
    id: 'policy-terms-of-service',
    docType: 'policy',
    category: 'Legal & Privacy',
    policyTab: 'terms',
    title: 'Terms of Service & Creator Ownership',
    badge: '100% CREATOR IP',
    isAccentBadge: false,
    readTime: '6 min read',
    version: 'v1.1',
    effectiveDate: 'November 17, 2026',
    order: 12,
    isPublished: true,
    inShort:
      'You keep 100% copyright over your content and store assets, protected by SIM-recycle safeguards, transparent fee notices, and your statutory consumer rights.',
    sections: [
      {
        heading: '1. 100% Creator Intellectual Property Ownership',
        summary: '',
        callout:
          'You own 100% of what you create. Private Chats and unpublished drafts are never used to train external public AI models.',
        bullets: [
          'Oneova receives only a limited operational license to host and stream your content at your direction—ending when you delete it.',
          'At least 14–30 days advance notice before material updates to Terms or Wallet fees.',
          'Mandatory local consumer and data rights in Kenya, Nigeria, South Africa, Ghana, Tanzania, Uganda, Rwanda, EU, UK, and worldwide remain fully intact.',
        ],
      },
    ],
    htmlOverride: '',
  },
  {
    id: 'policy-privacy',
    docType: 'policy',
    category: 'Legal & Privacy',
    policyTab: 'privacy',
    title: 'Privacy Policy & Data Protection Charter',
    badge: 'ZERO DATA SALES',
    isAccentBadge: true,
    readTime: '6 min read',
    version: 'v1.1',
    effectiveDate: 'November 17, 2026',
    order: 13,
    isPublished: true,
    inShort:
      'We never sell your personal data, never store mobile-money PINs, and give you 2-tap Export & Delete controls across every region.',
    sections: [
      {
        heading: '1. Strict Data Minimization & User Controls',
        summary: '',
        callout:
          'Oneova NEVER sells personal data and NEVER asks for or stores M-Pesa, MoMo, Airtel, Orange, or bank PINs.',
        bullets: [
          'Contacts sync and GPS location stay strictly OFF unless you opt in.',
          'Biometric unlock stays inside your device hardware Keystore / Secure Enclave.',
          'Export a full archive or request full deletion anytime in Settings or via dpo@oneova.app (free response within 21 days).',
        ],
      },
    ],
    htmlOverride: '',
  },
  {
    id: 'policy-child-safety',
    docType: 'policy',
    category: 'Community & Safety',
    policyTab: 'safety',
    title: 'Child & Teen Safety Policy (CSAE Zero Tolerance)',
    badge: 'ZERO TOLERANCE CSAE',
    isAccentBadge: true,
    readTime: '5 min read',
    version: 'v1.1',
    effectiveDate: 'November 17, 2026',
    order: 14,
    isPublished: true,
    inShort:
      'Zero tolerance for any child harm, strict under-13 block, teen privacy defaults (13–17), under-18 payout/commerce restrictions, and toll-free Pan-African 116 helplines.',
    sections: [
      {
        heading: '1. Teen Safe Defaults & Pan-African 116 Helplines',
        summary: '',
        callout:
          '24/7 Urgent Child Safety Escalation: childsafety@oneova.app · Victims are always supported and never punished.',
        bullets: [
          'Under-18 accounts are blocked from hosting Live broadcasts, buying Coins/Gifts, or operating Biz storefronts.',
          'Free confidential helplines: Call 116 across Kenya, South Africa, Tanzania, Uganda, Rwanda, Ghana, Zambia, Malawi & Zimbabwe · Nigeria 0800 800 8001 · Egypt 16000.',
        ],
      },
    ],
    htmlOverride: '',
  },
  {
    id: 'policy-biz-monetization',
    docType: 'policy',
    category: 'Commerce & Law Enforcement',
    policyTab: 'biz',
    title: 'Oneova Shops, Wallet & Monetization Rules',
    badge: 'SHOPS & PAYOUTS',
    isAccentBadge: false,
    readTime: '5 min read',
    version: 'v1.1',
    effectiveDate: 'November 17, 2026',
    order: 15,
    isPublished: true,
    inShort:
      'Honest local-currency pricing, order escrow, KYC/AML payout checks for 18+ creators & merchants, and prohibited-goods protections.',
    sections: [
      {
        heading: '1. Creator Payouts & Escrow Integrity',
        summary: '',
        callout: '',
        bullets: [
          '18+ verified creators and Biz merchants withdraw earnings to M-Pesa, MTN MoMo, Airtel Money, Orange, Wave, or bank accounts via central-bank-licensed payment partners.',
          'Buyers are protected by Oneova order escrow until delivery confirmation; stock is deducted atomically server-side.',
          'Prohibited goods: counterfeits, weapons, illegal drugs, unapproved medical products, poached wildlife, and personal data dumps.',
        ],
      },
    ],
    htmlOverride: '',
  },
  {
    id: 'policy-data-deletion',
    docType: 'policy',
    category: 'Legal & Privacy',
    policyTab: 'deletion',
    title: 'Self-Service Data Deletion & Account Export',
    badge: '2-TAP DELETION',
    isAccentBadge: false,
    readTime: '3 min read',
    version: 'v1.1',
    effectiveDate: 'November 17, 2026',
    order: 16,
    isPublished: true,
    inShort:
      'Export a portable copy of your data, revoke connected external tokens, or delete your Oneova account in 2 taps.',
    sections: [
      {
        heading: '1. Complete Control Over Your Account Data',
        summary: '',
        callout: '',
        bullets: [
          'In-App Deletion: Me → Settings → Privacy & Security → Delete Account & Purge Data.',
          'Data Portability Archive: Me → Settings → Privacy & Security → Export My Data.',
          'Email Backup: privacy@oneova.app with subject "Account Deletion Request — @username".',
        ],
      },
    ],
    htmlOverride: '',
  },
  {
    id: 'policy-law-enforcement',
    docType: 'regulation',
    category: 'Commerce & Law Enforcement',
    policyTab: 'law_enforcement',
    title: 'Law Enforcement & Due Process Guidelines',
    badge: 'DUE PROCESS',
    isAccentBadge: false,
    readTime: '4 min read',
    version: 'v1.0',
    effectiveDate: 'November 17, 2026',
    order: 17,
    isPublished: true,
    inShort:
      'Strict judicial court-order standards, rejection of bulk demands, human-rights scrutiny, and prior user notice where legally permitted.',
    sections: [
      {
        heading: '1. Judicial Review & User Protections',
        summary: '',
        callout:
          'Official Government Intake: lawenforcement@oneova.app (official judicial domain required).',
        bullets: [
          'Private encrypted chats require a valid judicial search warrant; informal requests are declined.',
          'Human-rights legal review applies under the African Charter on Human and Peoples’ Rights & ICCPR.',
        ],
      },
    ],
    htmlOverride: '',
  },
  {
    id: 'regulation-african-global-compliance',
    docType: 'regulation',
    category: 'African & Global Regulations',
    policyTab: 'africa',
    title: 'African & Global Regulatory Compliance',
    badge: 'AU · ODPC · NDPA · POPIA · GDPR',
    isAccentBadge: true,
    readTime: '5 min read',
    version: 'v1.1',
    effectiveDate: 'November 17, 2026',
    order: 18,
    isPublished: true,
    inShort:
      'Built from day one for East, West, Southern, Central & North African data, fintech, and AfCFTA digital-trade laws alongside GDPR & global standards.',
    sections: [
      {
        heading: '1. Pan-African & International Legal Alignment',
        summary:
          'Oneova satisfies statutory privacy, payments, and creator protections across African and global markets.',
        callout: '',
        bullets: [
          'East & Central Africa: Kenya DPA 2019 (ODPC) & CBK NPS rules, Tanzania PDPA 2022, Uganda DPPA 2019, Rwanda Law No. 058/2021, Ethiopia Proclamation 1321/2024.',
          'West & Southern Africa: Nigeria NDPA 2023 (NDPC) & CBN rules, Ghana DPA 843, South Africa POPIA & FICA, Côte d’Ivoire, Senegal & BCEAO e-money rules.',
          'Continental & Global: AU Malabo Convention, AfCFTA Digital Trade Protocol, EU GDPR/DSA, and international child-safety commitments.',
        ],
      },
    ],
    htmlOverride: '',
  },
];

export function getStandaloneLegalHref(doc) {
  if (!doc) return '/legal.html';
  switch (doc.policyTab) {
    case 'guidelines':
      return '/guidelines.html';
    case 'terms':
      return '/terms.html';
    case 'privacy':
      return '/privacy.html';
    case 'safety':
      return '/child-safety.html';
    case 'biz':
      return '/biz-policy.html';
    case 'deletion':
      return '/deletion.html';
    case 'law_enforcement':
      return '/law-enforcement.html';
    case 'africa':
      return '/legal.html';
    default:
      return doc.docType === 'feature' ? null : '/legal.html';
  }
}

export function getOfficialPdfHref(doc) {
  if (!doc) return null;
  switch (doc.policyTab) {
    case 'terms':
      return '/docs/pdf/01_Oneova_Terms_of_Service.pdf';
    case 'privacy':
      return '/docs/pdf/02_Oneova_Privacy_Policy.pdf';
    case 'guidelines':
      return '/docs/pdf/03_Oneova_Community_Guidelines.pdf';
    case 'safety':
      return '/docs/pdf/04_Oneova_Child_and_Teen_Safety_Policy.pdf';
    case 'biz':
      return '/docs/pdf/05_Oneova_Biz_and_Creator_Monetization_Policy.pdf';
    case 'deletion':
      return '/docs/pdf/06_Oneova_Data_Deletion_and_Rights_Guide.pdf';
    case 'law_enforcement':
      return '/docs/pdf/07_Oneova_Law_Enforcement_Guidelines.pdf';
    default:
      return null;
  }
}
