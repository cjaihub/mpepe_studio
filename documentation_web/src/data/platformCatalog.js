/**
 * Authoritative baseline catalog of Oneova's 10 Advanced Platform Feature Docs
 * and 8 Rules, Safety & African/Global Regulatory Frameworks.
 *
 * Mirrors `OneovaPlatformDocsCatalog.defaults` in the Oneova Flutter app
 * (`lib/settings/services/platform_docs_cms_service.dart`) 1-for-1 so:
 *  1. Initial page load & offline/slow-network browsing render instantaneously.
 *  2. Real-time Firestore `platform_cms_docs` listeners seamlessly override any
 *     document edited in either the Oneova Flutter App or the Website Admin CMS.
 */

export const PLATFORM_BASELINE_DOCS = [
  // ══════════════════════════════════════════════════════════════════════════
  // TRACK 1: ADVANCED PLATFORM FEATURE DOCUMENTATION (10 GUIDES)
  // ══════════════════════════════════════════════════════════════════════════
  {
    id: 'live-studio',
    docType: 'feature',
    category: 'Live & Broadcasting',
    policyTab: '',
    title: 'Live Studio',
    badge: 'LIVE',
    isAccentBadge: true,
    readTime: '6 min read',
    version: 'v1.1',
    effectiveDate: 'October 30, 2026',
    order: 1,
    isPublished: true,
    inShort:
      'One setup wizard and one Live Studio for every live: polls, countdowns, spotlight, celebrations and raffles, 1080p recording you choose to keep, and real-time restream to Facebook, YouTube and TikTok.',
    sections: [
      {
        heading: '1. One setup wizard, one Live Studio',
        summary:
          'Every Go live button opens the same six-step wizard (mode, details, camera & mic, layout, audience, review), each step with a live preview, then the same Live Studio.',
        callout: 'Solo, Studio (guests on video panels, viewers can request to join) or Game (your game in the center, camera in a bubble).',
        bullets: [
          'Title, cover photo and category, previewed as your followers\' feed card.',
          'Real camera preview, mic level meter and natural beauty before you go live.',
          'Dark or light studio, guest panel size, who holds the center screen, name tags.',
          'Everyone or followers-only audience; open, slow-mode or followers-only comments; join requests.',
        ],
      },
      {
        heading: '2. Entertainment tools for hosts and moderators',
        summary:
          'Live controls (the tune button on stage) gives hosts and co-hosts polls, countdowns, spotlight pins, celebrations and a raffle. Everyone sees them at the same moment.',
        callout: '',
        bullets: [
          'Polls with 2–4 options and live animated results; one vote per person.',
          'Countdown timer on stage; spotlight pins a message or a viewer comment.',
          'Confetti, hearts or fireworks for everyone; raffle draws a random recent commenter.',
          'Viewers get clean view (hide comments and buttons) and can switch effects off.',
          'Gifts: viewers send Roses, Hearts, Stars, Crowns, Rockets and Diamonds with coins; big gifts get a full-screen reveal, and the host earns half as pending earnings.',
          'Voice presets for anyone on stage: Natural, Clear voice, Studio and Music.',
          'Moderators can mute every guest at once from Live controls.',
        ],
      },
      {
        heading: '3. 1080p recording and real-time restream',
        summary:
          'The stage is rendered in the cloud at 1080p (9:16 or 16:9) without comments or likes, recorded and pushed live to your other platforms.',
        callout: 'Restream to Facebook Live, YouTube Live, TikTok LIVE, Twitch, Instagram Live, Kick or any RTMP server; stream keys stay on the server.',
        bullets: [
          'Add platforms once in Settings → Camera & Live → Live destinations.',
          'When the live ends, choose Keep (saved to Live recordings, ready to share or download) or Delete.',
          'Fast join, automatic reconnect with a Reconnecting banner, and no hanging lives: a live closes when the host ends it, closes the app or stays offline ~90 s.',
        ],
      },
    ],
    htmlOverride: '',
  },
  {
    id: 'creator-rooms',
    docType: 'feature',
    category: 'Live & Broadcasting',
    policyTab: '',
    title: 'Interactive Creator Collaboration Rooms',
    badge: 'COLLAB STAGE',
    isAccentBadge: false,
    readTime: '4 min read',
    version: 'v1.0',
    effectiveDate: 'October 25, 2026',
    order: 2,
    isPublished: true,
    inShort:
      'Drop-in spatial audio and video stages featuring speaker seats, private backstage greenrooms, hand-raise queues, and synchronized media review.',
    sections: [
      {
        heading: '1. Stage, Backstage Greenroom & Audience Architecture',
        summary:
          'Creator Rooms bridge spontaneous voice spaces and structured production war-rooms, scaling effortlessly from intimate co-writing sessions to town-hall creator panels.',
        callout:
          'Co-hosts and producers can coordinate privately inside the Backstage Greenroom audio channel without interrupting the live public stage.',
        bullets: [
          'Dedicated Speaker Stage with instant 1-tap hand-raise promotion and demotion from the listener gallery.',
          'Private Backstage Greenroom channel for pre-show soundchecks, guest prep, and live producer cues.',
          'Synchronized rough-cut video, moodboard, and audio stem scrubbing directly inside the room.',
          'Neural noise cancellation and voice isolation engineered for crisp audio on everyday mobile microphones.',
        ],
      },
    ],
    htmlOverride: '',
  },
  {
    id: 'looks-color-engine',
    docType: 'feature',
    category: 'Studio, AI & Color Engine',
    policyTab: '',
    title: 'GPU Looks Engine, AI Color Grader & Scope Sentinel',
    badge: 'GLSL COLOR',
    isAccentBadge: true,
    readTime: '6 min read',
    version: 'v1.0',
    effectiveDate: 'October 25, 2026',
    order: 3,
    isPublished: true,
    inShort:
      'One unified GLSL shader graph powering Live, Camera, Photo, and Video—paired with conversational AI Color Grading and broadcast GPU scopes.',
    sections: [
      {
        heading: '1. Unified Cross-Surface Color Science (OneovaLook v2)',
        summary:
          'A Look crafted in Photo Studio or Video Timeline renders identically in Live Broadcasts and Capture Camera with verified golden ΔE color parity.',
        callout:
          'Describe any grade naturally by voice or text—online via Gemini Live streaming tool calls or 100% offline via on-device AI models—with full parameter diff reports and instant undo.',
        bullets: [
          'Native Android OpenGL ES, iOS Metal, and Flutter FragmentProgram pipeline supporting 3D LUT stacks, tone curves, HSL qualifiers, split-toning, halation, and film grain.',
          'Conversational AI Color Grader with region-aware edits (sky, skin, foliage, background) and non-destructive version history.',
          'Server-driven 100+ Looks Catalog plus commercial `.oneovapack` bundles created by verified Biz colorists.',
        ],
      },
      {
        heading: '2. Broadcast GPU Scopes & AI Scope Sentinel',
        summary:
          'Hollywood-grade diagnostic scopes run on the GPU at 60 FPS alongside an autonomous AI quality monitor.',
        callout: '',
        bullets: [
          'Real-time GPU Waveform, RGB Parade, Vectorscope with calibrated skin-tone line (calibrated across diverse African and global skin tones), Histogram, CIE chromaticity, False Color, and Zebras.',
          'Scope Sentinel silently monitors clipped highlights, crushed shadows, gamut violations, color cast, face exposure, and shot-to-shot mismatch—offering 1-tap automatic fixes.',
        ],
      },
    ],
    htmlOverride: '',
  },
  {
    id: 'mobile-editor',
    docType: 'feature',
    category: 'Studio, AI & Color Engine',
    policyTab: '',
    title: 'Pro Video Timeline, Photo Studio & AI Rotoscoping',
    badge: 'PRO STUDIO',
    isAccentBadge: false,
    readTime: '5 min read',
    version: 'v1.0',
    effectiveDate: 'October 25, 2026',
    order: 4,
    isPublished: true,
    inShort:
      'Frame-accurate multi-layer video editing, Simple/Pro photo grading, natural-language AI subject cutouts, and lossless hardware export.',
    sections: [
      {
        heading: '1. Multi-Layer Timeline & Natural-Language Rotoscoping',
        summary:
          'Edit cinema-ready Reels, documentaries, and commercial showcases directly on your phone without desktop round-trips.',
        callout:
          'Place bold animated kinetic typography behind moving subjects in seconds using AI Rotoscoping—no green screen required.',
        bullets: [
          'Magnetic multi-track timeline with per-clip color grades, adjustment layers, keyframed Look transitions, tracked masks, and automatic shot-matching.',
          'Natural-Language Rotoscoping (Gemini detection + SAM 2 tracking): isolate people, clothing, products, or skies via tap or text prompt.',
          'Word-by-word karaoke auto-captions, beat-transient snapping, and vocal/instrumental stem separation.',
          'Hardware-accelerated Media3 Transformer (Android) and AVFoundation + Metal (iOS) export preserving exact source resolution, FPS, bit depth, and HDR—plus optional Cloud Render offload.',
        ],
      },
    ],
    htmlOverride: '',
  },
  {
    id: 'reels-feed',
    docType: 'feature',
    category: 'Reels, Feed & Social',
    policyTab: '',
    title: 'High-Velocity Reels, 24h Stories & Triple-Stream Feed',
    badge: '60 FPS FEED',
    isAccentBadge: false,
    readTime: '4 min read',
    version: 'v1.0',
    effectiveDate: 'October 25, 2026',
    order: 5,
    isPublished: true,
    inShort:
      'Zero-buffering vertical video feed uniting Following, For You, and Biz streams with 24-hour Stories, audio-disc Remixing, and low-data caching.',
    sections: [
      {
        heading: '1. Triple-Stream Discovery & Low-Bandwidth Engineering',
        summary:
          'Oneova’s locked home experience delivers instantaneous vertical video playback while respecting mobile data bundles.',
        callout: '',
        bullets: [
          'Instant top-bar switching between Following, For You, and Biz social-commerce streams, with interactive 24-hour Stories right below.',
          'Adaptive pre-caching engineered for silky 60 FPS playback on high-speed networks and thrifty data usage on 3G/4G mobile bundles.',
          '1-Tap REMIX button, spinning Audio Discs with permanent original-creator attribution, Focus Mode, and direct Shop product chips.',
        ],
      },
    ],
    htmlOverride: '',
  },
  {
    id: 'ova-ai-lab',
    docType: 'feature',
    category: 'Studio, AI & Color Engine',
    policyTab: '',
    title: 'AI Lab, Ova Voice Assistant & Post Intelligence',
    badge: 'AI LAB',
    isAccentBadge: true,
    readTime: '5 min read',
    version: 'v1.0',
    effectiveDate: 'October 25, 2026',
    order: 6,
    isPublished: true,
    inShort:
      'Hands-free voice camera control, smart post titles/hashtags/cover scrubbing, offline AI fallback, and AiSecurityGateway prompt-injection defense.',
    sections: [
      {
        heading: '1. Creator-First AI With Strict Privacy Boundaries',
        summary:
          'Every AI capability in Oneova amplifies human creativity while keeping your unpublished work and private conversations strictly off-limits to model training.',
        callout:
          'Protected by AiSecurityGateway delimiter isolation: untrusted inputs can never hijack studio tools or leak account data.',
        bullets: [
          'Ova Voice Assistant executes hands-free camera capture, Quick Settings / Control Center launches, and studio commands by voice.',
          'Advanced Post Studio analyzes video frames to recommend high-retention titles, captions, niche keywords, collaborators, and crisp cover frames—backed by debounced Firestore draft autosave.',
          'Hybrid Cloud + On-Device AI (Gemini Nano / Apple Foundation Models / LiteRT fallback) keeps core grading and Sentinel tools working offline.',
        ],
      },
    ],
    htmlOverride: '',
  },
  {
    id: 'device-thermal-advisor',
    docType: 'feature',
    category: 'Hardware, Security & Desktop',
    policyTab: '',
    title: 'AI Device Advisor & Predictive Thermal Governor',
    badge: 'THERMAL SHIELD',
    isAccentBadge: false,
    readTime: '4 min read',
    version: 'v1.0',
    effectiveDate: 'October 25, 2026',
    order: 7,
    isPublished: true,
    inShort:
      'Benchmarks GPU/CPU/RAM capabilities and predicts thermal load so entry-level to flagship phones run smoothly without overheating.',
    sections: [
      {
        heading: '1. Engineered for Every Phone Tier Across Africa & Worldwide',
        summary:
          'Great creators use everything from budget Android devices in warm climates to flagship iPhones. Oneova adapts automatically to every chipset.',
        callout: '',
        bullets: [
          'AI Device Advisor benchmarks shader throughput, encoder ceilings, and RAM to set safe default resolution/FPS limits (with optional Pro Override).',
          'Predictive Thermal Governor monitors Android ADPF and iOS thermalState in real time, gracefully scaling effect passes before frame drops or thermal shutdowns occur.',
          'Smart Compute Router shifts heavy rotoscoping, upscaling, or rendering to Cloud GPU queues when local battery or thermal headroom is tight.',
        ],
      },
    ],
    htmlOverride: '',
  },
  {
    id: 'wallet-biz-commerce',
    docType: 'feature',
    category: 'Wallet, Biz & Growth',
    policyTab: '',
    title: 'Oneova Wallet, Coins & Biz Marketplace',
    badge: 'MOBILE MONEY & BIZ',
    isAccentBadge: true,
    readTime: '5 min read',
    version: 'v1.0',
    effectiveDate: 'October 25, 2026',
    order: 8,
    isPublished: true,
    inShort:
      'Double-entry local-currency Wallet, Live Coins/Gifts, M-Pesa/MoMo/card payouts, `.oneovapack` digital Look stores, and direct Biz social commerce.',
    sections: [
      {
        heading: '1. Africa-First & Global Creator Economy Infrastructure',
        summary:
          'Creators and businesses earn in transparent local currencies with native mobile-money and global card rails built directly into the platform.',
        callout:
          'Every Wallet & Coin transaction is recorded on an immutable server-only double-entry ledger verified by cryptographic PSP webhook signatures.',
        bullets: [
          'Native African mobile-money support (M-Pesa, MTN MoMo, Airtel Money, Orange Money, Telecel/Vodafone, Wave via Flutterwave) alongside global cards, Apple Pay, Google Pay, Stripe, and required App Store / Play Billing.',
          'Biz Marketplace lets verified businesses attach interactive product chips to Reels and Live streams or sell `.oneovapack` LUT & Look bundles with showcase videos.',
          'Transparent upfront fee breakdowns, automated KYC/AML verification for 18+ payouts, and anti-wash-trading protection.',
        ],
      },
    ],
    htmlOverride: '',
  },
  {
    id: 'universal-sharing',
    docType: 'feature',
    category: 'Wallet, Biz & Growth',
    policyTab: '',
    title: 'Universal 1-Tap Cross-Platform Sharing & Analytics',
    badge: 'OMNICHANNEL',
    isAccentBadge: false,
    readTime: '4 min read',
    version: 'v1.0',
    effectiveDate: 'October 25, 2026',
    order: 9,
    isPublished: true,
    inShort:
      'Publish simultaneously to TikTok, YouTube Shorts, Instagram Reels, Facebook, and X with smart aspect-ratio reframing and unified analytics.',
    sections: [
      {
        heading: '1. Encrypted OAuth Publishing & Unified Command Center',
        summary:
          'Create once inside Oneova Studio and distribute everywhere in a single tap without watermark penalties or manual re-uploads.',
        callout: '',
        bullets: [
          '1-Tap Simultaneous Export to TikTok, YouTube Shorts, Instagram Reels, Facebook, and WhatsApp Business via revocable OAuth 2.0 tokens.',
          'Smart subject-aware reframing across 9:16, 1:1, and 16:9 aspect ratios plus synchronized `#ad` / `#sponsored` commercial disclosures.',
          'Unified Analytics Command Center & Omnichannel Inbox aggregating cross-platform view velocity, comments, and messages.',
        ],
      },
    ],
    htmlOverride: '',
  },
  {
    id: 'security-desktop-ecosystem',
    docType: 'feature',
    category: 'Hardware, Security & Desktop',
    policyTab: '',
    title: 'Account Health Diagnostics, Biometric Lock & Desktop Agent',
    badge: 'ZERO-TRUST SECURITY',
    isAccentBadge: false,
    readTime: '4 min read',
    version: 'v1.0',
    effectiveDate: 'October 25, 2026',
    order: 10,
    isPublished: true,
    inShort:
      'Autonomous Account Health scoring with 1-tap AI Auto-Fix, Passkeys/2FA, SIM-recycle protection, Private Chat & Calls, and paired Desktop Studio Agent.',
    sections: [
      {
        heading: '1. End-to-End Account, Chat & Workstation Protection',
        summary:
          'Enterprise-grade security protects your creator identity, private conversations, and multi-device studio sessions.',
        callout: '',
        bullets: [
          'Autonomous Account Health Diagnostics continuously audits 2FA, App PIN, hardware biometric lock, and session hygiene—with 1-Tap AI Auto-Fix.',
          'Oneova Shield E2EE safety-number verification, encrypted WebRTC voice/video calls, SIM-recycle protection, and 1-tap remote device sign-out.',
          'QR/PIN-paired macOS & Windows Desktop Agent for multi-cam monitoring, workstation rendering, and remote studio control.',
        ],
      },
    ],
    htmlOverride: '',
  },

  // ══════════════════════════════════════════════════════════════════════════
  // TRACK 2: RULES, POLICIES & AFRICAN/GLOBAL REGULATIONS (8 FRAMEWORKS)
  // ══════════════════════════════════════════════════════════════════════════
  {
    id: 'policy-community-guidelines',
    docType: 'policy',
    category: 'Community & Safety',
    policyTab: 'guidelines',
    title: 'Community Guidelines & Anti-Scam Rules',
    badge: 'ANTI-FRAUD & SAFETY',
    isAccentBadge: true,
    readTime: '6 min read',
    version: 'v1.0',
    effectiveDate: 'October 25, 2026',
    order: 11,
    isPublished: true,
    inShort:
      'Be real, be respectful, be safe. Zero tolerance for mobile-money scams, hate speech, trafficking, non-consensual imagery, or child exploitation—with transparent strikes and human appeals.',
    sections: [
      {
        heading: '1. Financial Integrity & Mobile-Money Scam Bans',
        summary:
          'We actively protect African and global users against mobile-money social engineering, impersonation, and deceptive schemes.',
        callout:
          'Official Safety Rule: Oneova staff will NEVER ask for your password, 2FA OTP, or mobile-money PIN.',
        bullets: [
          'Strictly banned: Fake M-Pesa, MTN MoMo, Airtel Money, Orange Money, Telecel, or Wave reversal/confirmation SMS messages, doctored payment screenshots, SIM-swap phishing, and "419" advance-fee fraud.',
          'Strictly banned: Ponzi/"double your money" schemes, fake overseas jobs/visas/scholarships, national exam-paper leak rings (KCSE, WAEC, NECO, Matric, UNEB, NECTA), and romance/sextortion scams.',
          'No impersonating creators, businesses, banks, telecoms, or public officials, and no fake bot engagement manipulation.',
        ],
      },
      {
        heading: '2. Human Dignity, Public Safety & Cultural Context',
        summary: '',
        callout: '',
        bullets: [
          'Zero hate speech or ethnic, tribal, clan, religious, national, racial, gender, caste, or disability-based incitement or dehumanization.',
          'Zero cyberbullying, doxxing (leaking phone numbers, national IDs, or home addresses), non-consensual intimate images (NCII), sexualized deepfakes, terrorism, human trafficking, or illegal weapons/narcotics/wildlife trade.',
          'Traditional African and global cultural attire, breastfeeding, health education, and legitimate journalism are protected; pornography and sexual solicitation are prohibited.',
          'Realistic AI-generated media must carry Oneova’s AI-Generated disclosure badge; false instructions on when, where, or how to vote are banned.',
        ],
      },
      {
        heading: '3. Graduated 3-Strike System, 2-Tap Reporting & Human Appeals',
        summary: '',
        callout: '',
        bullets: [
          'Graduated Ladder: Educational Warning (0 strikes) → Strike 1 (7-day feature limit) → Strike 2 (30-day feature & monetization limit) → Strike 3 (account suspension). Strikes expire after 90 clean days.',
          'Immediate Permanent Ban: CSAM/CSAE, terrorism, human trafficking, NCII/sextortion, and severe financial fraud.',
          'Tap ⋯ → Report anonymously in 2 taps on any Reel, Live, Room, Chat, or Biz listing. Every moderation notice states the exact rule and includes a free Appeal reviewed by an independent human specialist.',
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
    readTime: '7 min read',
    version: 'v1.0',
    effectiveDate: 'October 25, 2026',
    order: 12,
    isPublished: true,
    inShort:
      'You retain 100% ownership of your original creations, protected by SIM-recycle safeguards, transparent Wallet/Biz rules, 14–30 day change notice, and preserved local consumer rights.',
    sections: [
      {
        heading: '1. Age Eligibility (13+ / 18+) & SIM-Recycle Safeguards',
        summary: '',
        callout: '',
        bullets: [
          'Minimum age is 13 (or higher digital consent age under your local law). Hosting Live streams, purchasing/withdrawing Wallet/Coins, and selling on Biz Marketplace require age 18+.',
          'SIM-Recycle Safeguard: Because mobile carriers reassign inactive numbers after 90–180 days, link a recovery email/passkey and App PIN so reassigned SIM cards cannot access your account or chats.',
        ],
      },
      {
        heading: '2. 100% Creator Intellectual Property Ownership',
        summary: '',
        callout:
          'You own 100% of what you create. Private Chats and unpublished Studio drafts are never licensed publicly or used to train public AI models.',
        bullets: [
          'You retain full copyright and ownership over your videos, music, photos, voice recordings, and custom Studio Looks.',
          'You grant Oneova only a non-exclusive, revocable operational license to host, transcode (including low-data mobile bitrates), and display posts according to your audience and Remix settings—ending upon deletion.',
        ],
      },
      {
        heading: '3. Advance Notice of Updates & Local Consumer Rights',
        summary: '',
        callout: '',
        bullets: [
          'At least 14 days advance notice before material Terms changes (30 days for creator revenue-share or Wallet fee updates).',
          'Nothing in our Terms waives mandatory consumer or data-protection rights under the laws of Kenya, Nigeria, South Africa, Tanzania, Uganda, Rwanda, Ghana, Egypt, the EU, UK, or your home jurisdiction.',
          '30-day zero-cost informal dispute resolution via disputes@oneova.app without stripping access to local consumer courts or tribunals.',
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
    readTime: '7 min read',
    version: 'v1.0',
    effectiveDate: 'October 25, 2026',
    order: 13,
    isPublished: true,
    inShort:
      'We never sell your personal data, never store mobile-money PINs, isolate AI prompts, encrypt cross-border transfers, and give you 2-tap Export & Delete controls.',
    sections: [
      {
        heading: '1. Data Minimization & Strict Exclusions',
        summary: '',
        callout:
          'Oneova NEVER sells personal data and NEVER asks for or stores mobile-money PINs (M-Pesa, MTN MoMo, Airtel, Orange, Wave) or raw card CVVs.',
        bullets: [
          'Collected strictly to operate Oneova: account profile, content you share, message routing metadata, licensed payment transaction IDs, device/thermal capability tier, and explicit opt-in permissions.',
          'Contacts sync and precise GPS location are strictly OFF by default until you explicitly opt in.',
          'AR camera lenses process face/hand landmarks transiently in volatile memory; fingerprint/Face ID app unlock stays strictly inside Android Keystore / Apple Secure Enclave.',
        ],
      },
      {
        heading: '2. Retention Schedule, 72-Hour Breach SLA & Data Subject Rights',
        summary: '',
        callout: '',
        bullets: [
          'Deleted posts and accounts vanish from public view immediately, purge from active databases within 24h–30 days, and rotate out of encrypted backups within 90 days (statutory tax/AML payout ledgers retained 5–7 years).',
          '72-hour breach notification commitment to competent Data Protection Authorities (ODPC, NDPC, Information Regulator, EDPB, ICO) and affected individuals.',
          'Exercise Access, Portability Export, Correction, Consent Withdrawal, and Erasure directly in Settings → Privacy & Security or via dpo@oneova.app (free response within 21 days).',
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
    version: 'v1.0',
    effectiveDate: 'October 25, 2026',
    order: 14,
    isPublished: true,
    inShort:
      'Instant permanent ban and NCMEC/INTERPOL reporting for any child sexual exploitation, strict under-13 prohibition, automatic teen privacy defaults (13–17), and free 116 helplines.',
    sections: [
      {
        heading: '1. Zero Tolerance for CSAM, Grooming & Youth Sextortion',
        summary: '',
        callout:
          '24/7 Urgent Child Safety Escalation: childsafety@oneova.app · Teen victims of sextortion are ALWAYS protected and supported, never punished.',
        bullets: [
          'Any real, edited, or AI-generated sexual content involving minors (<18), grooming, solicitation, or child trafficking triggers immediate quarantine, permanent account/device ban, evidence preservation, and mandatory reporting to NCMEC, INTERPOL, and national child-protection units.',
        ],
      },
      {
        heading: '2. Built-In Teen Safe Defaults (13–17) & Pan-African 116 Helplines',
        summary: '',
        callout: '',
        bullets: [
          'Ages 13–15: Private account by default, DMs restricted to mutual followers, video downloads OFF, strict mature filter locked ON, nighttime quiet hours 21:00–06:00.',
          'All under-18s: Blocked from hosting Live streams, purchasing Coins/Gifts, selling on Biz, and behavioral ad profiling.',
          'Free Confidential Helplines: Call 116 toll-free across Kenya, South Africa, Tanzania, Uganda, Rwanda, Ghana, Zambia, Malawi & Zimbabwe · Nigeria Cece Yara 0800 800 8001 · Egypt 16000 · UK 0800 1111 · EU 116 111 · US/CA 988.',
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
    title: 'Biz Marketplace & Creator Monetization Rules',
    badge: 'MOBILE MONEY & KYC',
    isAccentBadge: false,
    readTime: '5 min read',
    version: 'v1.0',
    effectiveDate: 'October 25, 2026',
    order: 15,
    isPublished: true,
    inShort:
      'Transparent local-currency Coins, Live Gifts, `.oneovapack` licensing, licensed PSP mobile-money/bank payouts with 18+ KYC/AML, and honest Biz merchant obligations.',
    sections: [
      {
        heading: '1. Creator Payouts, Coins & Anti-Wash-Trading Rules',
        summary: '',
        callout: '',
        bullets: [
          'Oneova Coins are closed-loop virtual tokens priced transparently in local currency inclusive of applicable VAT/DST.',
          '18+ creators withdraw verified earnings to M-Pesa, MTN MoMo, Airtel Money, Orange Money, Wave, or bank accounts via central-bank-licensed PSPs following KYC & AML/CTF verification.',
          'Wash-gifting, stolen payment credentials, or chargeback cycling freezes tainted credits while legitimate creator balances remain protected.',
        ],
      },
      {
        heading: '2. Biz Merchant Standards & Prohibited Goods',
        summary: '',
        callout: '',
        bullets: [
          'Biz Sellers must display authentic product media, full local-currency prices, clear delivery fees, `#ad` sponsorship disclosures, and statutory consumer refunds.',
          'Prohibited goods: Counterfeits, firearms/explosives, illegal drugs/unlicensed medicines, mercury/hydroquinone bleaching hazards, poached wildlife, adult services, Ponzi packages, and leaked personal data.',
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
    title: 'Self-Service Data Deletion, Export & OAuth Revocation',
    badge: '2-TAP DELETION',
    isAccentBadge: false,
    readTime: '3 min read',
    version: 'v1.0',
    effectiveDate: 'October 25, 2026',
    order: 16,
    isPublished: true,
    inShort:
      'Delete your account in 2 taps in-app, export a portable archive of your data, revoke TikTok/Meta/YouTube OAuth tokens instantly, or request erasure via email.',
    sections: [
      {
        heading: '1. Four Immediate Ways to Control or Erase Your Data',
        summary: '',
        callout: '',
        bullets: [
          'In-App Instant Deletion: Me → Settings → Privacy & Security → Delete Account & Purge Data (verified via PIN/biometrics/2FA).',
          'Data Portability Archive: Me → Settings → Privacy & Security → Export My Data.',
          'Revoke Connected Social OAuth Tokens: Me → Settings → Social Accounts → Disconnect (TikTok, YouTube, Instagram, Facebook tokens deleted immediately).',
          'Low-Data Web/Email Request: Email privacy@oneova.app with subject "Account Deletion Request — @username" if you no longer have your phone.',
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
    title: 'Law Enforcement & Government Request Guidelines',
    badge: 'DUE PROCESS',
    isAccentBadge: false,
    readTime: '5 min read',
    version: 'v1.0',
    effectiveDate: 'October 25, 2026',
    order: 17,
    isPublished: true,
    inShort:
      'Strict judicial warrant/court-order standards, rejection of bulk fishing demands, human-rights review, 90-day preservation, 24/7 emergency life-safety intake, and user notice.',
    sections: [
      {
        heading: '1. Valid Legal Process, Human Rights & User Notice',
        summary: '',
        callout:
          'Official Government Intake: lawenforcement@oneova.app (verified official government/judicial domain required). Informal or bulk requests are rejected.',
        bullets: [
          'Basic subscriber registration records require a valid subpoena or court order; private Chat messages or unpublished Studio drafts require a Judicial Search Warrant.',
          'Cross-border requests require MLAT, domesticated court orders, or applicable international treaty process.',
          'Requests implicating peaceful civic speech or journalism undergo Senior Legal Counsel human-rights review under the African Charter on Human and Peoples’ Rights & ICCPR.',
          'Oneova notifies affected users prior to disclosure unless prohibited by a valid court seal order or imminent risk to child/human life.',
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
    title: 'African & Global Regulatory Compliance Framework',
    badge: 'AU · ODPC · NDPA · POPIA · GDPR',
    isAccentBadge: true,
    readTime: '6 min read',
    version: 'v1.0',
    effectiveDate: 'October 25, 2026',
    order: 18,
    isPublished: true,
    inShort:
      'Comprehensive statutory compliance across East, West, Southern, Central & North Africa, AU Malabo & AfCFTA Digital Trade, EU GDPR/DSA/AI Act, UK OSA, US COPPA/DMCA & App Stores.',
    sections: [
      {
        heading: '1. African National Data, Consumer, Cyber & Fintech Laws',
        summary:
          'Oneova is engineered from day one to satisfy national statutory frameworks across the African continent alongside international digital standards.',
        callout: '',
        bullets: [
          'East Africa: Kenya Data Protection Act 2019 (ODPC), Computer Misuse & Cybercrimes Act, Consumer Protection Act & CBK NPS rules; Tanzania PDPA 2022 (PDPC) & EPOCA; Uganda DPPA 2019 (PDPO); Rwanda Law No. 058/2021 (NCSA); Ethiopia Personal Data Protection Proclamation 1321/2024.',
          'West Africa: Nigeria Data Protection Act 2023 (NDPC), FCCPA, Cybercrimes Act, CBN PSSP & ARCON rules; Ghana Data Protection Act 843 (DPC) & Cybersecurity Act 2020; Côte d’Ivoire ARTCI, Senegal CDP & BCEAO regional e-money regulations.',
          'Southern, Central & North Africa + Continental: South Africa POPIA (Information Regulator), ECTA, CPA & FICA; Egypt PDPL 151/2020; Morocco Law 09-08 (CNDP); AU Malabo Convention & AfCFTA Digital Trade Protocol.',
        ],
      },
      {
        heading: '2. International Laws, App Store Mandates & Enterprise Data Shield',
        summary: '',
        callout: '',
        bullets: [
          'European Union & UK: EU GDPR, Digital Services Act (DSA Statements of Reasons, notice-and-action, human appeals, minor ad-profiling ban), EU AI Act Art. 50 synthetic media transparency, UK Online Safety Act & Age Appropriate Design Code.',
          'United States & Global: COPPA (15 U.S.C. § 6501), 18 U.S.C. § 2258A (NCMEC reporting), DMCA 17 U.S.C. § 512 safe harbor, FTC Endorsement Guides & CCPA/CPRA.',
          'Mobile App Stores: Apple App Store Review Guidelines (§ 1.2 UGC, § 3.1.1 IAP, § 5.1.1v Account Deletion) & Google Play UGC + Child Safety Standards.',
          'Enterprise Project & Code Shield: 5-tier asset security, Cloud Secret Manager isolation, Passkey/Hardware MFA, permissive-only OSS license firewall, zero standing staff DM access, and 15-minute offboarding revocation.',
        ],
      },
    ],
    htmlOverride: '',
  },
];

/**
 * Resolves the standalone printable legal HTML URL for any policy/regulation doc.
 */
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

/**
 * Maps a `policyTab` or `doc.id` to its official printable vector PDF URL
 * hosted at `/docs/pdf/...` (public policies 01–07 only).
 */
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
