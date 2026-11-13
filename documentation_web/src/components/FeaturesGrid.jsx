import React from 'react';

const FEATURE_CARDS = [
  {
    id: 'live-studio',
    pink: true,
    title: '4K Live Broadcast Studio & PK Stage',
    desc: 'Broadcast up to 4K with real-time WebRTC GPU Looks, Boost Beauty, split-screen Co-Host PK Battles, Stream Health HUD, and live Biz product pins.',
    tags: ['4K Simulcast', 'PK Co-Host Duels', 'Stream Health HUD'],
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4">
        <circle cx="12" cy="12" r="10" />
        <polygon points="10 8 16 12 10 16 10 8" />
      </svg>
    ),
  },
  {
    id: 'creator-rooms',
    pink: false,
    title: 'Interactive Creator Collaboration Rooms',
    desc: 'Drop-in spatial audio & video stages featuring dedicated speaker seats, private backstage greenrooms, hand-raise queues, and synchronized media review.',
    tags: ['Speaker Stage', 'Backstage Greenroom', 'AI Voice Isolation'],
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4">
        <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
        <circle cx="9" cy="7" r="4" />
        <path d="M23 21v-2a4 4 0 0 0-3-3.87" />
        <path d="M16 3.13a4 4 0 0 1 0 7.75" />
      </svg>
    ),
  },
  {
    id: 'looks-color-engine',
    pink: true,
    title: 'GLSL Looks Engine & AI Scope Sentinel',
    desc: 'Unified shader graph across Live, Camera, Photo, and Video—paired with conversational AI Color Grading, Vectorscope skin-tone calibration, and 1-tap Sentinel fixes.',
    tags: ['GLSL + Metal/GLES', 'AI Color Grader', 'GPU Scopes'],
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4">
        <circle cx="13.5" cy="6.5" r=".5" fill="currentColor" />
        <circle cx="17.5" cy="10.5" r=".5" fill="currentColor" />
        <circle cx="8.5" cy="7.5" r=".5" fill="currentColor" />
        <circle cx="6.5" cy="12.5" r=".5" fill="currentColor" />
        <path d="M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10c.926 0 1.648-.746 1.648-1.688 0-.437-.18-.835-.437-1.125-.29-.289-.438-.652-.438-1.125a1.64 1.64 0 0 1 1.668-1.668h1.996c3.051 0 5.555-2.503 5.555-5.554C21.965 6.012 17.461 2 12 2z" />
      </svg>
    ),
  },
  {
    id: 'mobile-editor',
    pink: false,
    title: 'Pro Video Timeline, Photo Studio & AI Rotoscoping',
    desc: 'Magnetic multi-track video editing, natural-language SAM 2 subject cutouts, text-behind-subject masking, karaoke captions, and lossless hardware export.',
    tags: ['AI Rotoscoping', 'Multi-Track Timeline', 'HDR Hardware Export'],
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4">
        <path d="M12 20h9" />
        <path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z" />
      </svg>
    ),
  },
  {
    id: 'reels-feed',
    pink: false,
    title: '60 FPS Reels, 24h Stories & Triple-Stream Feed',
    desc: 'Zero-buffering vertical feed uniting Following, For You, and Biz streams with 24-hour Stories, spinning sound discs, 1-tap Remix, and low-data pre-caching.',
    tags: ['Following · For You · Biz', 'Low-Data Caching', '24h Stories'],
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4">
        <rect width="18" height="18" x="3" y="3" rx="2" />
        <path d="m9 8 7 4-7 4Z" />
      </svg>
    ),
  },
  {
    id: 'ova-ai-lab',
    pink: true,
    title: 'Ova Voice Assistant, AI Lab & Smart Post Studio',
    desc: 'Hands-free voice camera capture, AI video frame analysis for high-retention titles/hashtags/covers, offline AI fallback, and AiSecurityGateway isolation.',
    tags: ['Ova Voice Control', 'Smart Post Drafts', 'Offline AI Ready'],
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4">
        <path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z" />
        <path d="M19 10v2a7 7 0 0 1-14 0v-2" />
        <line x1="12" x2="12" y1="19" y2="22" />
      </svg>
    ),
  },
  {
    id: 'wallet-biz-commerce',
    pink: true,
    title: 'Oneova Wallet, Mobile Money & Biz Marketplace',
    desc: 'Double-entry local-currency Wallet supporting M-Pesa, MTN MoMo, Airtel, Orange, Wave & IAP—plus Biz product Reels and `.oneovapack` Look stores.',
    tags: ['M-Pesa & MoMo', 'Biz Social Commerce', '.oneovapack Store'],
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4">
        <rect width="20" height="14" x="2" y="5" rx="2" />
        <line x1="2" x2="22" y1="10" y2="10" />
      </svg>
    ),
  },
  {
    id: 'device-thermal-advisor',
    pink: false,
    title: 'AI Device Advisor & Predictive Thermal Shield',
    desc: 'Profiles every phone chipset and monitors Android ADPF / iOS thermal states in real time so entry-level to flagship devices stream smoothly without overheating.',
    tags: ['Hardware Profiling', 'Thermal Governor', 'Cloud GPU Offload'],
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4">
        <rect width="16" height="16" x="4" y="4" rx="2" />
        <rect width="6" height="6" x="9" y="9" rx="1" />
        <path d="M15 2v2M15 20v2M2 15h2M2 9h2M20 15h2M20 9h2M9 2v2M9 20v2" />
      </svg>
    ),
  },
  {
    id: 'regulation-african-global-compliance',
    pink: true,
    title: 'African & Global Trust, Safety & Legal Shield',
    desc: '100% Creator IP ownership, zero data sales, anti-MoMo-scam shields, Teen Safe Defaults (116 helplines), and full ODPC, NDPA, POPIA, GDPR & DSA compliance.',
    tags: ['ODPC · NDPA · POPIA', 'GDPR & EU DSA', '100% Creator IP'],
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4">
        <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
      </svg>
    ),
  },
];

export default function FeaturesGrid({ onSelectDoc }) {
  return (
    <section className="showcase-section" id="features">
      <div className="section-header-center">
        <span className="section-tag pink">COMPLETE PLATFORM ECOSYSTEM</span>
        <h2 className="section-title">
          Advanced Mobile Creation, Africa-First Commerce & Global Legal Trust
        </h2>
        <p className="section-desc">
          Explore Oneova’s complete technical and regulatory architecture—from 4K WebRTC GPU Looks
          and conversational AI Color Grading to M-Pesa/MoMo creator payouts and statutory data
          protection. Click any card to jump straight to its live-synced specification.
        </p>
      </div>

      <div className="features-grid">
        {FEATURE_CARDS.map((card) => (
          <div
            key={card.id}
            className={`feature-card ${card.pink ? 'highlight-pink' : ''}`}
            style={{ cursor: onSelectDoc ? 'pointer' : 'default' }}
            onClick={() => onSelectDoc && onSelectDoc(card.id)}
          >
            <div className={`feature-icon-box ${card.pink ? 'pink' : ''}`}>{card.icon}</div>
            <h3 className="feature-title">{card.title}</h3>
            <p className="feature-description">{card.desc}</p>
            <div className="feature-tags-wrap">
              {card.tags.map((t) => (
                <span className="f-badge" key={t}>
                  {t}
                </span>
              ))}
            </div>
            {onSelectDoc && (
              <div className="feature-card-spec-link">
                <span>Read Live Documentation →</span>
              </div>
            )}
          </div>
        ))}
      </div>
    </section>
  );
}
