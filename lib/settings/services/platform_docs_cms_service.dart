import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A structured content block shared identically between the Oneova Flutter app
/// and the live Oneova React web documentation & legal portal (`platform_cms_docs`).
class PlatformDocSection {
  final String heading;
  final String summary;
  final String callout;
  final List<String> bullets;

  const PlatformDocSection({
    required this.heading,
    this.summary = '',
    this.callout = '',
    this.bullets = const <String>[],
  });

  factory PlatformDocSection.fromMap(Map<String, dynamic> map) {
    final rawBullets = map['bullets'];
    return PlatformDocSection(
      heading: (map['heading'] as String? ?? '').trim(),
      summary: (map['summary'] as String? ?? '').trim(),
      callout: (map['callout'] as String? ?? '').trim(),
      bullets: rawBullets is List
          ? rawBullets.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList()
          : const <String>[],
    );
  }

  Map<String, dynamic> toMap() => {
        'heading': heading.trim(),
        'summary': summary.trim(),
        'callout': callout.trim(),
        'bullets': bullets.map((b) => b.trim()).where((b) => b.isNotEmpty).toList(),
      };

  PlatformDocSection copyWith({
    String? heading,
    String? summary,
    String? callout,
    List<String>? bullets,
  }) {
    return PlatformDocSection(
      heading: heading ?? this.heading,
      summary: summary ?? this.summary,
      callout: callout ?? this.callout,
      bullets: bullets ?? this.bullets,
    );
  }
}

/// Real-time synchronized Feature Documentation, Policy, or Regulation document
/// stored in Firestore `platform_cms_docs/{id}`.
class PlatformCmsDoc {
  final String id;
  /// 'feature' | 'policy' | 'regulation'
  final String docType;
  final String category;
  /// Optional tab key ('guidelines' | 'terms' | 'privacy' | 'safety' | 'biz' | 'deletion' | 'law_enforcement' | 'africa')
  final String policyTab;
  final String title;
  final String badge;
  final bool isAccentBadge;
  final String inShort;
  final String readTime;
  final String version;
  final String effectiveDate;
  final int order;
  final bool isPublished;
  final List<PlatformDocSection> sections;
  final String htmlOverride;
  final DateTime? updatedAt;
  final String updatedByUid;
  final String updatedByName;
  final String changeNote;
  final bool isLiveFromCloud;

  const PlatformCmsDoc({
    required this.id,
    required this.docType,
    required this.category,
    this.policyTab = '',
    required this.title,
    required this.badge,
    this.isAccentBadge = false,
    required this.inShort,
    this.readTime = '4 min read',
    this.version = 'v1.0',
    this.effectiveDate = 'October 25, 2026',
    this.order = 10,
    this.isPublished = true,
    required this.sections,
    this.htmlOverride = '',
    this.updatedAt,
    this.updatedByUid = '',
    this.updatedByName = 'Oneova Legal & Product Team',
    this.changeNote = '',
    this.isLiveFromCloud = false,
  });

  factory PlatformCmsDoc.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data() ?? const <String, dynamic>{};
    final rawSections = data['sections'];
    final ts = data['updatedAt'];
    return PlatformCmsDoc(
      id: (data['id'] as String? ?? snap.id).trim(),
      docType: (data['docType'] as String? ?? 'policy').trim(),
      category: (data['category'] as String? ?? 'Community & Safety').trim(),
      policyTab: (data['policyTab'] as String? ?? '').trim(),
      title: (data['title'] as String? ?? snap.id).trim(),
      badge: (data['badge'] as String? ?? 'OFFICIAL').trim(),
      isAccentBadge: data['isAccentBadge'] as bool? ?? false,
      inShort: (data['inShort'] as String? ?? '').trim(),
      readTime: (data['readTime'] as String? ?? '4 min read').trim(),
      version: (data['version'] as String? ?? 'v1.0').trim(),
      effectiveDate: (data['effectiveDate'] as String? ?? 'October 25, 2026').trim(),
      order: (data['order'] as num?)?.toInt() ?? 10,
      isPublished: data['isPublished'] as bool? ?? true,
      sections: rawSections is List
          ? rawSections
              .whereType<Map>()
              .map((m) => PlatformDocSection.fromMap(Map<String, dynamic>.from(m)))
              .toList()
          : const <PlatformDocSection>[],
      htmlOverride: (data['htmlOverride'] as String? ?? '').trim(),
      updatedAt: ts is Timestamp ? ts.toDate() : null,
      updatedByUid: (data['updatedByUid'] as String? ?? '').trim(),
      updatedByName: (data['updatedByName'] as String? ?? 'Oneova Admin').trim(),
      changeNote: (data['changeNote'] as String? ?? '').trim(),
      isLiveFromCloud: true,
    );
  }

  Map<String, dynamic> toFirestoreMap({
    required String actorUid,
    required String actorName,
    String? note,
  }) {
    return <String, dynamic>{
      'id': id.trim(),
      'docType': docType.trim(),
      'category': category.trim(),
      'policyTab': policyTab.trim(),
      'title': title.trim(),
      'badge': badge.trim(),
      'isAccentBadge': isAccentBadge,
      'inShort': inShort.trim(),
      'readTime': readTime.trim(),
      'version': version.trim(),
      'effectiveDate': effectiveDate.trim(),
      'order': order,
      'isPublished': isPublished,
      'sections': sections.map((s) => s.toMap()).toList(),
      'htmlOverride': htmlOverride.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': actorUid,
      'updatedByName': actorName.trim().isEmpty ? 'Oneova Admin' : actorName.trim(),
      'changeNote': (note ?? changeNote).trim(),
    };
  }

  PlatformCmsDoc copyWith({
    String? id,
    String? docType,
    String? category,
    String? policyTab,
    String? title,
    String? badge,
    bool? isAccentBadge,
    String? inShort,
    String? readTime,
    String? version,
    String? effectiveDate,
    int? order,
    bool? isPublished,
    List<PlatformDocSection>? sections,
    String? htmlOverride,
    String? changeNote,
  }) {
    return PlatformCmsDoc(
      id: id ?? this.id,
      docType: docType ?? this.docType,
      category: category ?? this.category,
      policyTab: policyTab ?? this.policyTab,
      title: title ?? this.title,
      badge: badge ?? this.badge,
      isAccentBadge: isAccentBadge ?? this.isAccentBadge,
      inShort: inShort ?? this.inShort,
      readTime: readTime ?? this.readTime,
      version: version ?? this.version,
      effectiveDate: effectiveDate ?? this.effectiveDate,
      order: order ?? this.order,
      isPublished: isPublished ?? this.isPublished,
      sections: sections ?? this.sections,
      htmlOverride: htmlOverride ?? this.htmlOverride,
      updatedAt: updatedAt,
      updatedByUid: updatedByUid,
      updatedByName: updatedByName,
      changeNote: changeNote ?? this.changeNote,
      isLiveFromCloud: isLiveFromCloud,
    );
  }
}

/// Immutable audit revision entry in `platform_cms_docs/{docId}/revisions/{revId}`.
class PlatformDocRevision {
  final String id;
  final String version;
  final String actorUid;
  final String actorName;
  final String changeNote;
  final DateTime? createdAt;
  final Map<String, dynamic> snapshot;

  const PlatformDocRevision({
    required this.id,
    required this.version,
    required this.actorUid,
    required this.actorName,
    required this.changeNote,
    this.createdAt,
    required this.snapshot,
  });

  factory PlatformDocRevision.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final ts = d['createdAt'];
    final snap = d['snapshot'];
    return PlatformDocRevision(
      id: doc.id,
      version: (d['version'] as String? ?? 'v1.0').trim(),
      actorUid: (d['actorUid'] as String? ?? '').trim(),
      actorName: (d['actorName'] as String? ?? 'Oneova Admin').trim(),
      changeNote: (d['changeNote'] as String? ?? '').trim(),
      createdAt: ts is Timestamp ? ts.toDate() : null,
      snapshot: snap is Map ? Map<String, dynamic>.from(snap) : const <String, dynamic>{},
    );
  }
}

/// Authoritative baseline catalog of Oneova's 10 Advanced Platform Feature Docs
/// and 8 Rules, Safety & African/Global Regulatory Frameworks.
/// Used offline and seamlessly overridden in real time by `platform_cms_docs`.
class OneovaPlatformDocsCatalog {
  static const List<PlatformCmsDoc> defaults = [
    // ════════════════════════════════════════════════════════════════════════
    // TRACK 1: ADVANCED PLATFORM FEATURE DOCUMENTATION (10 GUIDES)
    // ════════════════════════════════════════════════════════════════════════
    PlatformCmsDoc(
      id: 'live-studio',
      docType: 'feature',
      category: 'Live & Broadcasting',
      title: 'Live Studio',
      badge: 'LIVE',
      isAccentBadge: true,
      readTime: '6 min read',
      order: 1,
      inShort: 'One setup wizard and one Live Studio for every live: polls, countdowns, spotlight, celebrations and raffles, 1080p recording you choose to keep, and real-time restream to Facebook, YouTube and TikTok.',
      sections: [
        PlatformDocSection(
          heading: '1. One setup wizard, one Live Studio',
          summary: 'Every Go live button opens the same six-step wizard (mode, details, camera & mic, layout, audience, review), each step with a live preview, then the same Live Studio.',
          callout: 'Solo, Studio (guests on video panels, viewers can request to join) or Game (your game in the center, camera in a bubble).',
          bullets: [
            'Title, cover photo and category, previewed as your followers\' feed card.',
            'Real camera preview, mic level meter and natural beauty before you go live.',
            'Dark or light studio, guest panel size, who holds the center screen, name tags.',
            'Everyone or followers-only audience; open, slow-mode or followers-only comments; join requests.',
          ],
        ),
        PlatformDocSection(
          heading: '2. Entertainment tools for hosts and moderators',
          summary: 'Live controls (the tune button on stage) gives hosts and co-hosts polls, countdowns, spotlight pins, celebrations and a raffle. Everyone sees them at the same moment.',
          bullets: [
            'Polls with 2–4 options and live animated results; one vote per person.',
            'Countdown timer on stage; spotlight pins a message or a viewer comment.',
            'Confetti, hearts or fireworks for everyone; raffle draws a random recent commenter.',
            'Viewers get clean view (hide comments and buttons) and can switch effects off.',
            'Gifts: viewers send Roses, Hearts, Stars, Crowns, Rockets and Diamonds with coins; big gifts get a full-screen reveal, and the host earns half as pending earnings.',
            'Voice presets for anyone on stage: Natural, Clear voice, Studio and Music.',
            'Moderators can mute every guest at once from Live controls.',
          ],
        ),
        PlatformDocSection(
          heading: '3. 1080p recording and real-time restream',
          summary: 'The stage is rendered in the cloud at 1080p (9:16 or 16:9) without comments or likes, recorded and pushed live to your other platforms.',
          callout: 'Restream to Facebook Live, YouTube Live, TikTok LIVE, Twitch, Instagram Live, Kick or any RTMP server; stream keys stay on the server.',
          bullets: [
            'Add platforms once in Settings → Camera & Live → Live destinations.',
            'When the live ends, choose Keep (saved to Live recordings, ready to share or download) or Delete.',
            'Fast join, automatic reconnect with a Reconnecting banner, and no hanging lives: a live closes when the host ends it, closes the app or stays offline ~90 s.',
          ],
        ),
      ],
    ),
    PlatformCmsDoc(
      id: 'creator-rooms',
      docType: 'feature',
      category: 'Live & Broadcasting',
      title: 'Interactive Creator Collaboration Rooms',
      badge: 'COLLAB STAGE',
      readTime: '4 min read',
      order: 2,
      inShort: 'Drop-in spatial audio and video stages featuring speaker seats, private backstage greenrooms, hand-raise queues, and synchronized media review.',
      sections: [
        PlatformDocSection(
          heading: '1. Stage, Greenroom & Audience Architecture',
          bullets: [
            'Dedicated Speaker Stage with instant hand-raise promotion from the listener gallery.',
            'Private Backstage Greenroom channel so co-hosts and producers can coordinate off-air before going live.',
            'Synchronized rough-cut video, moodboard, and audio stem scrubbing inside the room.',
            'AI noise cancellation and voice isolation built for crystal-clear mobile microphones.',
          ],
        ),
      ],
    ),
    PlatformCmsDoc(
      id: 'looks-color-engine',
      docType: 'feature',
      category: 'Studio, AI & Color Engine',
      title: 'GPU Looks Engine, AI Color Grader & Scope Sentinel',
      badge: 'GLSL COLOR',
      isAccentBadge: true,
      readTime: '6 min read',
      order: 3,
      inShort: 'One unified GLSL shader graph powering Live, Camera, Photo, and Video—paired with conversational AI Color Grading and broadcast GPU scopes.',
      sections: [
        PlatformDocSection(
          heading: '1. Unified Cross-Surface Color Science',
          summary: 'A Look created in Photo Studio or Video Timeline renders identically in Live Broadcasts and Capture Camera with golden ΔE color accuracy.',
          bullets: [
            'Native Android OpenGL ES, iOS Metal, and Flutter FragmentProgram pipeline supporting 3D LUT stacks, tone curves, HSL qualifiers, and halation/grain.',
            'Conversational AI Color Grader: describe any mood by voice or text (online via Gemini Live or offline via on-device AI) with full parameter diffs and undo history.',
          ],
        ),
        PlatformDocSection(
          heading: '2. Broadcast Scopes & AI Scope Sentinel',
          bullets: [
            'Real-time GPU Waveform, RGB Parade, Vectorscope with calibrated skin-tone line (calibrated across diverse dark to light skin tones), Histogram, False Color, and Zebras.',
            'Scope Sentinel silently monitors clipped highlights, crushed shadows, color cast, and skin-tone drift—offering 1-tap automatic fixes.',
          ],
        ),
      ],
    ),
    PlatformCmsDoc(
      id: 'mobile-editor',
      docType: 'feature',
      category: 'Studio, AI & Color Engine',
      title: 'Pro Video Timeline, Photo Studio & AI Rotoscoping',
      badge: 'PRO STUDIO',
      readTime: '5 min read',
      order: 4,
      inShort: 'Frame-accurate multi-layer video editing, Simple/Pro photo grading, natural-language AI subject cutouts, and lossless hardware export.',
      sections: [
        PlatformDocSection(
          heading: '1. Multi-Layer Timeline & Natural-Language Rotoscoping',
          bullets: [
            'Magnetic multi-track timeline with per-clip color grades, adjustment layers, keyframed transitions, and automatic shot-matching.',
            'AI Rotoscoping & Mask Canvas: isolate people, clothing, sky, or objects with a tap or text prompt—place bold titles behind subjects without a green screen.',
            'Word-by-word animated captions, beat-transient snapping, and vocal/instrumental stem separation.',
            'Hardware-accelerated Media3 Transformer (Android) and AVFoundation + Metal (iOS) export preserving source resolution, FPS, and HDR.',
          ],
        ),
      ],
    ),
    PlatformCmsDoc(
      id: 'reels-feed',
      docType: 'feature',
      category: 'Reels, Feed & Social',
      title: 'High-Velocity Reels, 24h Stories & Triple-Stream Feed',
      badge: '60 FPS FEED',
      readTime: '4 min read',
      order: 5,
      inShort: 'Zero-buffering vertical video feed uniting Following, For You, and Biz streams with 24-hour Stories, audio-disc Remixing, and low-data caching.',
      sections: [
        PlatformDocSection(
          heading: '1. Triple-Stream Discovery & Low-Bandwidth Engineering',
          bullets: [
            'Top-bar instant switch between Following, For You, and Biz commerce streams, plus interactive 24-hour Stories.',
            'Adaptive pre-caching engineered for smooth 60 FPS playback on high-speed networks and ultra-thrifty data consumption on African & emerging mobile networks.',
            '1-Tap REMIX & spinning Audio Discs preserving permanent creator attribution.',
          ],
        ),
      ],
    ),
    PlatformCmsDoc(
      id: 'ova-ai-lab',
      docType: 'feature',
      category: 'Studio, AI & Color Engine',
      title: 'AI Lab, Ova Voice Assistant & Post Intelligence',
      badge: 'AI LAB',
      isAccentBadge: true,
      readTime: '5 min read',
      order: 6,
      inShort: 'Hands-free voice camera control, smart post titles/hashtags/cover scrubbing, offline AI fallback, and AiSecurityGateway prompt-injection defense.',
      sections: [
        PlatformDocSection(
          heading: '1. Creator-First AI With Strict Privacy Boundaries',
          bullets: [
            'Ova Assistant executes hands-free camera capture, studio commands, and workflow triggers via natural voice.',
            'Smart Post Studio analyzes video frames to suggest high-retention titles, captions, niche tags, and optimal cover frames—with debounced cloud draft autosave.',
            'Protected by AiSecurityGateway delimiter isolation; private Chats and unpublished drafts are never used to train generative models.',
          ],
        ),
      ],
    ),
    PlatformCmsDoc(
      id: 'device-thermal-advisor',
      docType: 'feature',
      category: 'Hardware, Security & Desktop',
      title: 'AI Device Advisor & Predictive Thermal Governor',
      badge: 'THERMAL SHIELD',
      readTime: '4 min read',
      order: 7,
      inShort: 'Benchmarks GPU/CPU/RAM capabilities and predicts thermal load so entry-level to flagship phones run smoothly without overheating.',
      sections: [
        PlatformDocSection(
          heading: '1. Built for Every Device Tier Across Africa & Worldwide',
          bullets: [
            'Automatic hardware profiling calibrates preview resolution, shader complexity, and encoder ceilings to your exact phone chipset.',
            'Predictive Thermal Governor monitors Android ADPF and iOS thermal states to prevent dropped frames or sudden shutdowns during long Live streams.',
            'Compute Router intelligently offloads heavy rotoscoping, upscaling, or Cloud Render jobs when local battery or thermal headroom is tight.',
          ],
        ),
      ],
    ),
    PlatformCmsDoc(
      id: 'wallet-biz-commerce',
      docType: 'feature',
      category: 'Wallet, Biz & Growth',
      title: 'Oneova Wallet, Coins & Biz Marketplace',
      badge: 'MOBILE MONEY & BIZ',
      isAccentBadge: true,
      readTime: '5 min read',
      order: 8,
      inShort: 'Double-entry local-currency Wallet, Live Coins/Gifts, M-Pesa/MoMo/card payouts, `.oneovapack` digital Look stores, and direct Biz social commerce.',
      sections: [
        PlatformDocSection(
          heading: '1. Africa-First & Global Creator Economy Infrastructure',
          bullets: [
            'Seamless support for African mobile money (M-Pesa, MTN MoMo, Airtel Money, Orange Money, Telecel/Vodafone, Wave via Flutterwave) alongside global cards, Apple Pay, Google Pay, Stripe, and required App Store / Play Billing.',
            'Biz profiles can sell physical products directly from Reels/Live chips or package custom LUTs & grades as commercial `.oneovapack` bundles.',
            'Cryptographic webhook verification and server-only double-entry accounting protect every single coin and payout.',
          ],
        ),
      ],
    ),
    PlatformCmsDoc(
      id: 'universal-sharing',
      docType: 'feature',
      category: 'Wallet, Biz & Growth',
      title: 'Universal 1-Tap Cross-Platform Sharing & Analytics',
      badge: 'OMNICHANNEL',
      readTime: '4 min read',
      order: 9,
      inShort: 'Publish simultaneously to TikTok, YouTube Shorts, Instagram Reels, Facebook, and X with smart aspect-ratio reframing and unified analytics.',
      sections: [
        PlatformDocSection(
          heading: '1. Encrypted OAuth Publishing & Command Center',
          bullets: [
            '1-Tap Simultaneous Export to TikTok, YouTube Shorts, Instagram, and Facebook using revocable OAuth tokens.',
            'Smart focal-point reframing across 9:16, 1:1, and 16:9 aspect ratios with `#ad` commercial tag sync.',
            'Unified Analytics Command Center tracking cross-platform view velocity and engagement.',
          ],
        ),
      ],
    ),
    PlatformCmsDoc(
      id: 'security-desktop-ecosystem',
      docType: 'feature',
      category: 'Hardware, Security & Desktop',
      title: 'Account Health Diagnostics, Biometric Lock & Desktop Agent',
      badge: 'ZERO-TRUST SECURITY',
      readTime: '4 min read',
      order: 10,
      inShort: 'Autonomous Account Health scoring with 1-tap AI Auto-Fix, Passkeys/2FA, SIM-recycle protection, Private Chat & Calls, and paired Desktop Studio Agent.',
      sections: [
        PlatformDocSection(
          heading: '1. End-to-End Account & Studio Protection',
          bullets: [
            'Autonomous Account Health Diagnostics continuously audits 2FA, App PIN, biometric enclave lock, and session hygiene with 1-tap AI Auto-Fix.',
            'Encrypted WebRTC voice/video calls, Unified Inbox, and instant remote device sign-out.',
            'Secure QR/PIN-paired macOS & Windows Desktop Agent for multi-cam production and remote studio control.',
          ],
        ),
      ],
    ),

    // ════════════════════════════════════════════════════════════════════════
    // TRACK 2: RULES, POLICIES & AFRICAN/GLOBAL REGULATIONS (8 FRAMEWORKS)
    // ════════════════════════════════════════════════════════════════════════
    PlatformCmsDoc(
      id: 'policy-community-guidelines',
      docType: 'policy',
      category: 'Community & Safety',
      policyTab: 'guidelines',
      title: 'Community Guidelines & Anti-Scam Rules',
      badge: 'ANTI-FRAUD & SAFETY',
      isAccentBadge: true,
      readTime: '6 min read',
      order: 11,
      inShort: 'Be real, be respectful, be safe. Zero tolerance for mobile-money scams, hate speech, trafficking, non-consensual imagery, or child exploitation—with transparent strikes and human appeals.',
      sections: [
        PlatformDocSection(
          heading: '1. Financial Integrity & Mobile-Money Scam Bans',
          callout: 'Official Safety Rule: Oneova staff will NEVER ask for your password, 2FA OTP, or mobile-money PIN.',
          bullets: [
            'Strictly banned: Fake M-Pesa, MTN MoMo, Airtel Money, Orange Money, or Wave reversal messages, doctored payment receipts, SIM-swap phishing, and "419" advance-fee fraud.',
            'Strictly banned: Ponzi/"double your money" schemes, fake overseas visas/jobs/scholarships, exam-paper leak rings (KCSE, WAEC, NECO, Matric, UNEB, NECTA), and romance/sextortion scams.',
            'No impersonating creators, businesses, banks, government agencies, or buying/selling fake bot engagement.',
          ],
        ),
        PlatformDocSection(
          heading: '2. Human Dignity, Public Safety & Cultural Respect',
          bullets: [
            'Zero hate speech or ethnic, tribal, clan, religious, national, racial, gender, or disability incitement.',
            'Zero bullying, doxxing (leaking phone numbers, IDs, or addresses), non-consensual intimate images (NCII), terrorism, human trafficking, or illegal weapons/narcotics/wildlife trade.',
            'Traditional African and global cultural attire, health education, and art are respected; pornography and sexual solicitation are prohibited.',
            'Realistic AI media must keep Oneova\'s AI-Generated badge; election voting-procedure falsehoods are banned.',
          ],
        ),
        PlatformDocSection(
          heading: '3. Graduated 3-Strike Enforcement, 2-Tap Reporting & Human Appeals',
          bullets: [
            'Enforcement Ladder: Educational Warning (0 strikes) → Strike 1 (7-day feature limit) → Strike 2 (30-day feature & monetization limit) → Strike 3 (account suspension). Strikes expire after 90 clean days.',
            'Instant Permanent Ban: CSAM/CSAE, terrorism, human trafficking, NCII/sextortion, and severe financial fraud.',
            'Tap ⋯ → Report anonymously in 2 taps. Every moderation notice states the rule and includes a free Appeal reviewed by an independent human specialist.',
          ],
        ),
      ],
    ),
    PlatformCmsDoc(
      id: 'policy-terms-of-service',
      docType: 'policy',
      category: 'Legal & Privacy',
      policyTab: 'terms',
      title: 'Terms of Service & Creator Ownership',
      badge: '100% CREATOR IP',
      readTime: '7 min read',
      order: 12,
      inShort: 'You retain 100% ownership of your original creations, protected by SIM-recycle safeguards, transparent Wallet/Biz rules, 14–30 day change notice, and preserved local consumer rights.',
      sections: [
        PlatformDocSection(
          heading: '1. Age Eligibility (13+ / 18+) & SIM-Recycle Safeguards',
          bullets: [
            'Minimum age is 13 (or higher digital consent age under your national law). Hosting Live, buying/withdrawing Wallet/Coins, and selling on Biz require age 18+.',
            'SIM-Recycle Protection: Because mobile carriers reassign inactive SIMs after 90–180 days, bind a recovery email/passkey and App PIN so reassigned numbers cannot access your account or chats.',
          ],
        ),
        PlatformDocSection(
          heading: '2. 100% Creator Intellectual Property Ownership',
          bullets: [
            'You keep 100% ownership of your videos, music, photos, voice recordings, and custom Studio Looks.',
            'You grant Oneova only a non-exclusive, revocable operational license to host, transcode (including low-data bitrates), and display posts per your audience/Remix settings—ending upon deletion.',
            'Private Chats and unpublished Studio drafts are never distributed publicly or used to train public AI models.',
          ],
        ),
        PlatformDocSection(
          heading: '3. Notice of Updates, Liability & Local Consumer Rights',
          bullets: [
            'At least 14 days advance notice before material Terms updates (30 days for creator revenue-share or Wallet fee changes).',
            'Nothing in these Terms waives mandatory consumer or data rights under the laws of Kenya, Nigeria, South Africa, Tanzania, Uganda, Rwanda, Ghana, Egypt, the EU, UK, or your home jurisdiction.',
            '30-day zero-cost friendly dispute resolution via disputes@oneova.app.',
          ],
        ),
      ],
    ),
    PlatformCmsDoc(
      id: 'policy-privacy',
      docType: 'policy',
      category: 'Legal & Privacy',
      policyTab: 'privacy',
      title: 'Privacy Policy & Data Protection Charter',
      badge: 'ZERO DATA SALES',
      isAccentBadge: true,
      readTime: '7 min read',
      order: 13,
      inShort: 'We never sell your personal data, never store mobile-money PINs, isolate AI prompts, encrypt cross-border transfers, and give you 2-tap Export & Delete controls.',
      sections: [
        PlatformDocSection(
          heading: '1. Data Minimization & Strict Exclusions',
          bullets: [
            'Collected strictly to operate Oneova: account profile, content you share, message routing, licensed payment transaction IDs, device/thermal capability tier, and opt-in permissions.',
            'NEVER collected or stored: Mobile-money PINs (M-Pesa/MoMo/Airtel/Orange PINs), raw card CVVs, covert background mic/camera recordings, or unconsented phonebook uploads.',
            'AR camera lenses process facial landmarks in volatile memory; fingerprint/face app unlock stays strictly inside Android Keystore / Apple Secure Enclave.',
          ],
        ),
        PlatformDocSection(
          heading: '2. Retention, 72-Hour Breach SLA & Global/African Rights',
          bullets: [
            'Deleted posts/accounts disappear from public view immediately, purge from active servers within 24h–30 days, and rotate out of encrypted backups within 90 days (statutory tax/AML ledgers kept 5–7 years).',
            '72-hour breach notification commitment to competent Data Protection Authorities and affected users.',
            'Exercise Access, Export, Correction, Consent Withdrawal, and Erasure in Settings → Privacy & Security or via dpo@oneova.app (response within 21 days).',
          ],
        ),
      ],
    ),
    PlatformCmsDoc(
      id: 'policy-child-safety',
      docType: 'policy',
      category: 'Community & Safety',
      policyTab: 'safety',
      title: 'Child & Teen Safety Policy (CSAE Zero Tolerance)',
      badge: 'ZERO TOLERANCE CSAE',
      isAccentBadge: true,
      readTime: '5 min read',
      order: 14,
      inShort: 'Instant permanent ban and NCMEC/INTERPOL reporting for any child sexual exploitation, strict under-13 prohibition, automatic teen privacy defaults (13–17), and free 116 helplines.',
      sections: [
        PlatformDocSection(
          heading: '1. Zero Tolerance for CSAM, Grooming & Youth Sextortion',
          bullets: [
            'Any real, edited, or AI-generated sexual content involving minors (<18), grooming, solicitation, or trafficking triggers immediate quarantine, permanent account/device ban, and statutory reporting to NCMEC, INTERPOL, and national authorities.',
            'Teen victims of sextortion are protected and supported—never punished. 24/7 urgent contact: childsafety@oneova.app.',
          ],
        ),
        PlatformDocSection(
          heading: '2. Built-In Teen Safe Defaults & Pan-African 116 Helplines',
          bullets: [
            'Ages 13–15: Private profile by default, DMs restricted to mutual followers, video downloads OFF, strict mature filter locked ON, quiet hours 21:00–06:00.',
            'All under-18s: Blocked from hosting Live streams, buying Coins/Gifts, selling on Biz, and behavioral ad profiling.',
            'Free Confidential Helplines: Call 116 toll-free across Kenya, South Africa, Tanzania, Uganda, Rwanda, Ghana, Zambia, Malawi & Zimbabwe · Nigeria Cece Yara 0800 800 8001 · Egypt 16000 · UK 0800 1111 · EU 116 111 · US/CA 988.',
          ],
        ),
      ],
    ),
    PlatformCmsDoc(
      id: 'policy-biz-monetization',
      docType: 'policy',
      category: 'Commerce & Law Enforcement',
      policyTab: 'biz',
      title: 'Biz Marketplace & Creator Monetization Rules',
      badge: 'MOBILE MONEY & KYC',
      readTime: '5 min read',
      order: 15,
      inShort: 'Transparent local-currency Coins, Live Gifts, `.oneovapack` licensing, licensed PSP mobile-money/bank payouts with 18+ KYC/AML, and honest Biz merchant obligations.',
      sections: [
        PlatformDocSection(
          heading: '1. Creator Payouts, Coins & Anti-Wash-Trading Rules',
          bullets: [
            'Oneova Coins are closed-loop virtual tokens priced transparently in local currency inclusive of applicable taxes.',
            '18+ creators withdraw verified earnings to M-Pesa, MTN MoMo, Airtel Money, Orange Money, Wave, or bank accounts via central-bank-licensed PSPs following KYC & AML/CTF checks.',
            'Wash-gifting, stolen credentials, or chargeback cycling freezes tainted credits while legitimate creator balances remain protected.',
          ],
        ),
        PlatformDocSection(
          heading: '2. Biz Merchant Standards & Prohibited Goods',
          bullets: [
            'Biz Sellers must show authentic product media, full local-currency prices, clear delivery fees, and honor statutory consumer refunds.',
            'Banned items: Counterfeits, firearms/explosives, illegal drugs/unlicensed medicines, mercury/hydroquinone bleaching hazards, poached wildlife, adult services, Ponzi packages, and leaked personal data.',
          ],
        ),
      ],
    ),
    PlatformCmsDoc(
      id: 'policy-data-deletion',
      docType: 'policy',
      category: 'Legal & Privacy',
      policyTab: 'deletion',
      title: 'Self-Service Data Deletion, Export & OAuth Revocation',
      badge: '2-TAP DELETION',
      readTime: '3 min read',
      order: 16,
      inShort: 'Delete your account in 2 taps in-app, export a portable archive of your data, revoke TikTok/Meta/YouTube OAuth tokens instantly, or request erasure via email.',
      sections: [
        PlatformDocSection(
          heading: '1. Four Immediate Ways to Control or Erase Your Data',
          bullets: [
            'In-App Instant Deletion: Me → Settings → Privacy & Security → Delete Account & Purge Data (verified via PIN/biometrics/2FA).',
            'Data Portability Archive: Me → Settings → Privacy & Security → Export My Data.',
            'Revoke Social OAuth Tokens: Me → Settings → Social Accounts → Disconnect (TikTok, YouTube, Instagram, Facebook tokens deleted immediately).',
            'Low-Data Email Request: Email privacy@oneova.app with subject "Account Deletion Request — @username" if you no longer have the app.',
          ],
        ),
      ],
    ),
    PlatformCmsDoc(
      id: 'policy-law-enforcement',
      docType: 'regulation',
      category: 'Commerce & Law Enforcement',
      policyTab: 'law_enforcement',
      title: 'Law Enforcement & Government Request Guidelines',
      badge: 'DUE PROCESS',
      readTime: '5 min read',
      order: 17,
      inShort: 'Strict judicial warrant/court-order standards, rejection of bulk fishing demands, human-rights review, 90-day preservation, 24/7 emergency life-safety intake, and user notice.',
      sections: [
        PlatformDocSection(
          heading: '1. Valid Legal Process, Human Rights & User Notice',
          bullets: [
            'All official requests must come from a verified government/judicial domain to lawenforcement@oneova.app citing statutory authority and exact @username / URL.',
            'Basic subscriber records require a valid subpoena/court order; private Chat messages or unpublished drafts require a Judicial Search Warrant.',
            'Overbroad bulk requests are rejected; peaceful civic speech and journalism undergo Senior Counsel human-rights review under the African Charter & ICCPR.',
            'Users are notified prior to disclosure unless barred by a valid court gag order or imminent risk to child/human life.',
          ],
        ),
      ],
    ),
    PlatformCmsDoc(
      id: 'regulation-african-global-compliance',
      docType: 'regulation',
      category: 'African & Global Regulations',
      policyTab: 'africa',
      title: 'African & Global Regulatory Compliance Framework',
      badge: 'AU · ODPC · NDPA · POPIA · GDPR',
      isAccentBadge: true,
      readTime: '6 min read',
      order: 18,
      inShort: 'Comprehensive statutory compliance across East, West, Southern, Central & North Africa, AU Malabo & AfCFTA Digital Trade, EU GDPR/DSA/AI Act, UK OSA, US COPPA/DMCA & App Stores.',
      sections: [
        PlatformDocSection(
          heading: '1. African National Data, Consumer & Fintech Laws',
          bullets: [
            'East Africa: Kenya Data Protection Act 2019 (ODPC), Computer Misuse & Cybercrimes Act, Consumer Protection Act & CBK NPS rules; Tanzania PDPA 2022 (PDPC) & EPOCA; Uganda DPPA 2019 (PDPO); Rwanda Law No. 058/2021 (NCSA); Ethiopia Proclamation 1321/2024.',
            'West Africa: Nigeria Data Protection Act 2023 (NDPC), FCCPA, Cybercrimes Act, CBN PSSP & ARCON rules; Ghana Act 843 (DPC) & Cybersecurity Act 2020; Côte d\'Ivoire ARTCI, Senegal CDP & BCEAO e-money rules.',
            'Southern & North Africa + Continental: South Africa POPIA (Information Regulator), ECTA, CPA & FICA; Egypt PDPL 151/2020; Morocco Law 09-08 (CNDP); AU Malabo Convention & AfCFTA Digital Trade Protocol.',
          ],
        ),
        PlatformDocSection(
          heading: '2. International Laws, App Store Mandates & Enterprise Data Shield',
          bullets: [
            'EU GDPR, Digital Services Act (DSA Statements of Reasons + human appeals + minor ad-profiling ban) & EU AI Act Art. 50 synthetic media labeling.',
            'UK Online Safety Act & Children\'s Code; US COPPA, 18 U.S.C. § 2258A (NCMEC), DMCA § 512 & CCPA/CPRA.',
            'Apple App Store (§ 1.2 UGC, § 3.1.1 IAP, § 5.1.1v Account Deletion) & Google Play UGC + Child Safety Standards.',
            'Internal Company Data Shield: 5-tier asset security, Cloud Secret Manager isolation, Passkey/Hardware MFA, zero standing staff DM access (instant termination for snooping), and 15-minute offboarding revocation.',
          ],
        ),
      ],
    ),
  ];
}

/// Real-time service reading and updating `platform_cms_docs` in Firestore.
class PlatformDocsCmsService {
  final FirebaseFirestore? _firestoreOverride;
  final FirebaseAuth? _authOverride;

  PlatformDocsCmsService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestoreOverride = firestore,
        _authOverride = auth;

  FirebaseFirestore get _firestore => _firestoreOverride ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('platform_cms_docs');

  /// Streams merged catalog (defaults overridden by live Firestore docs + any new custom docs).
  Stream<List<PlatformCmsDoc>> watchMergedDocs({required bool includeDrafts}) {
    final query = includeDrafts ? _col : _col.where('isPublished', isEqualTo: true);

    return query.snapshots().map((snap) {
      final liveById = <String, PlatformCmsDoc>{};
      for (final doc in snap.docs) {
        final parsed = PlatformCmsDoc.fromFirestore(doc);
        liveById[parsed.id] = parsed;
      }
      return _mergeWithDefaults(liveById, includeDrafts: includeDrafts);
    }).handleError((_) {
      // Graceful offline/permission fallback so UI never breaks
      return OneovaPlatformDocsCatalog.defaults
          .where((d) => includeDrafts || d.isPublished)
          .toList();
    });
  }

  static List<PlatformCmsDoc> _mergeWithDefaults(
    Map<String, PlatformCmsDoc> liveById, {
    required bool includeDrafts,
  }) {
    final merged = <PlatformCmsDoc>[];
    final seen = <String>{};

    for (final def in OneovaPlatformDocsCatalog.defaults) {
      seen.add(def.id);
      final live = liveById[def.id];
      final chosen = live ?? def;
      if (includeDrafts || chosen.isPublished) {
        merged.add(chosen);
      }
    }

    for (final entry in liveById.entries) {
      if (!seen.contains(entry.key)) {
        if (includeDrafts || entry.value.isPublished) {
          merged.add(entry.value);
        }
      }
    }

    merged.sort((a, b) {
      final cmp = a.order.compareTo(b.order);
      return cmp != 0 ? cmp : a.title.compareTo(b.title);
    });
    return merged;
  }

  /// Checks whether the currently signed-in user holds admin/owner/founder privileges.
  Stream<bool> watchIsCurrentUserAdmin() {
    return _auth.authStateChanges().asyncExpand((user) async* {
      if (user == null || user.isAnonymous) {
        yield false;
        return;
      }
      bool tokenAdmin = false;
      try {
        final token = await user.getIdTokenResult();
        tokenAdmin = token.claims?['admin'] == true;
      } catch (_) {}
      if (tokenAdmin) {
        yield true;
        return;
      }
      yield* _firestore
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .map((snap) {
            final role = (snap.data()?['role'] as String? ?? '').toLowerCase().trim();
            return role == 'admin' || role == 'owner' || role == 'founder';
          })
          .handleError((_) => false);
    });
  }

  /// Saves/publishes a document in real time and records an immutable audit revision.
  Future<void> saveDoc(PlatformCmsDoc doc, {String changeNote = ''}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Sign in with an Admin account to publish changes.');
    }

    final actorName = (user.displayName?.trim().isNotEmpty == true)
        ? user.displayName!.trim()
        : (user.email ?? 'Oneova Admin');

    final docRef = _col.doc(doc.id.trim());
    final revRef = docRef.collection('revisions').doc();
    final payload = doc.toFirestoreMap(
      actorUid: user.uid,
      actorName: actorName,
      note: changeNote,
    );

    final batch = _firestore.batch();
    batch.set(docRef, payload);
    batch.set(revRef, <String, dynamic>{
      'version': doc.version.trim(),
      'actorUid': user.uid,
      'actorName': actorName,
      'changeNote': changeNote.trim().isEmpty ? 'Live admin update' : changeNote.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'snapshot': <String, dynamic>{
        'id': doc.id.trim(),
        'docType': doc.docType.trim(),
        'category': doc.category.trim(),
        'policyTab': doc.policyTab.trim(),
        'title': doc.title.trim(),
        'badge': doc.badge.trim(),
        'isAccentBadge': doc.isAccentBadge,
        'inShort': doc.inShort.trim(),
        'readTime': doc.readTime.trim(),
        'version': doc.version.trim(),
        'effectiveDate': doc.effectiveDate.trim(),
        'order': doc.order,
        'isPublished': doc.isPublished,
        'sections': doc.sections.map((s) => s.toMap()).toList(),
        'htmlOverride': doc.htmlOverride.trim(),
      },
    });
    await batch.commit();
  }

  /// Seeds any default catalog documents not yet in Firestore so both mobile and
  /// web clients have live cloud documents ready for instant editing.
  Future<int> seedMissingDefaultsToCloud() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Sign in with an Admin account to sync catalog.');
    }
    final existing = await _col.get();
    final existingIds = existing.docs.map((d) => d.id).toSet();

    int count = 0;
    for (final def in OneovaPlatformDocsCatalog.defaults) {
      if (!existingIds.contains(def.id)) {
        await saveDoc(def, changeNote: 'Initial baseline sync to live cloud');
        count++;
      }
    }
    return count;
  }

  /// Streams revision history for a specific document (Admin only).
  Stream<List<PlatformDocRevision>> watchRevisions(String docId) {
    return _col
        .doc(docId)
        .collection('revisions')
        .orderBy('createdAt', descending: true)
        .limit(25)
        .snapshots()
        .map((snap) => snap.docs.map(PlatformDocRevision.fromFirestore).toList());
  }

  /// Restores a previous revision snapshot as a new live update.
  Future<void> rollbackToRevision(String docId, PlatformDocRevision rev) async {
    final s = rev.snapshot;
    if (s.isEmpty) return;
    final rawSections = s['sections'];
    final restored = PlatformCmsDoc(
      id: docId,
      docType: (s['docType'] as String? ?? 'policy'),
      category: (s['category'] as String? ?? 'Community & Safety'),
      policyTab: (s['policyTab'] as String? ?? ''),
      title: (s['title'] as String? ?? docId),
      badge: (s['badge'] as String? ?? 'OFFICIAL'),
      isAccentBadge: s['isAccentBadge'] as bool? ?? false,
      inShort: (s['inShort'] as String? ?? ''),
      readTime: (s['readTime'] as String? ?? '4 min read'),
      version: (s['version'] as String? ?? rev.version),
      effectiveDate: (s['effectiveDate'] as String? ?? 'October 25, 2026'),
      order: (s['order'] as num?)?.toInt() ?? 10,
      isPublished: s['isPublished'] as bool? ?? true,
      sections: rawSections is List
          ? rawSections
              .whereType<Map>()
              .map((m) => PlatformDocSection.fromMap(Map<String, dynamic>.from(m)))
              .toList()
          : const <PlatformDocSection>[],
      htmlOverride: (s['htmlOverride'] as String? ?? ''),
    );
    await saveDoc(restored, changeNote: 'Rolled back to ${rev.version}');
  }

  /// Deletes a custom cloud document (if a built-in ID is deleted, it reverts to baseline default).
  Future<void> deleteCloudDoc(String docId) async {
    await _col.doc(docId).delete();
  }
}

final platformDocsCmsServiceProvider = Provider<PlatformDocsCmsService>((ref) {
  return PlatformDocsCmsService();
});

final isPlatformDocsAdminProvider = StreamProvider<bool>((ref) {
  return ref.watch(platformDocsCmsServiceProvider).watchIsCurrentUserAdmin();
});

final publishedPlatformDocsProvider = StreamProvider<List<PlatformCmsDoc>>((ref) {
  return ref.watch(platformDocsCmsServiceProvider).watchMergedDocs(includeDrafts: false);
});

final adminAllPlatformDocsProvider = StreamProvider<List<PlatformCmsDoc>>((ref) {
  return ref.watch(platformDocsCmsServiceProvider).watchMergedDocs(includeDrafts: true);
});
