import React from 'react';

const FEATURE_CARDS = [
  {
    id: 'wallet-biz-commerce',
    pink: true,
    title: 'Oneova Wallet, Mobile Money & Payouts',
    desc: 'Separate Personal and Business balances on an immutable double-entry ledger. Accept and withdraw via M-Pesa STK, MTN MoMo, Airtel Money, Orange Money, Telecel, Wave, and bank rails in local currencies.',
    tags: ['M-Pesa & MoMo', 'Business Balance', 'Scan-to-Pay QR'],
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4">
        <rect width="20" height="14" x="2" y="5" rx="2" />
        <line x1="2" x2="22" y1="10" y2="10" />
      </svg>
    ),
  },
  {
    id: 'biz-3d-shops',
    pink: true,
    title: 'Oneova 3D Shops & Biz Showrooms',
    desc: 'Open a verified store in minutes with zero payout setup blocker. Display interactive 3D items right on your Live stage and sell 24/7 with live FX currency conversion and order escrow.',
    tags: ['Interactive 3D Stage', 'Live Goods Pins', 'Order Escrow'],
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4">
        <path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z" />
        <line x1="3" y1="6" x2="21" y2="6" />
        <path d="M16 10a4 4 0 0 1-8 0" />
      </svg>
    ),
  },
  {
    id: 'global-id',
    pink: false,
    title: 'Oneova Global ID (Personal & Business)',
    desc: 'One portable creator and merchant credential built for cross-border trust across Africa and worldwide—combining ID/selfie KYC, business ownership verification, biometric approvals, and linked handles.',
    tags: ['Personal KYC', 'Business KYB', 'Biometric Keystore'],
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4">
        <rect x="3" y="4" width="18" height="16" rx="2" />
        <circle cx="9" cy="10" r="2.5" />
        <path d="M6.5 16c.5-1.8 4.5-1.8 5 0" />
        <line x1="14" y1="9" x2="18" y2="9" />
        <line x1="14" y1="13" x2="18" y2="13" />
      </svg>
    ),
  },
  {
    id: 'live-studio',
    pink: true,
    title: 'Live Commerce Stage, Co-Hosts & Gifts',
    desc: 'Launch Solo or Multi-Guest broadcasts in seconds with Presenter’s Goods 3D cards, audience polls, countdowns, raffles, and instant fan Gifts that convert into creator earnings.',
    tags: ['Multi-Guest Stage', 'Presenter Goods', 'Creator Gifts'],
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4">
        <circle cx="12" cy="12" r="10" />
        <polygon points="10 8 16 12 10 16 10 8" />
      </svg>
    ),
  },
  {
    id: 'reels-feed',
    pink: false,
    title: 'African Creator Feed, Stories & Remix',
    desc: 'Discovery across Following, For You, and Biz streams tuned for low-bandwidth mobile bundles—paired with 24-hour Stories, shoppable tags, and permanent original-sound Remix attribution.',
    tags: ['Following · For You · Biz', 'Low-Data Ready', 'Audio Attribution'],
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
    title: 'Ova Personal AI, Live Help & Desktop Agent',
    desc: 'Hands-free voice assistance, power-button Highlight & instant screen translation on mobile, plus live Support AI connected to real-time human admins and Mac & Windows desktop automation.',
    tags: ['Live Support AI', 'In-Place Translate', 'Mac & Windows'],
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4">
        <path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3Z" />
        <path d="M19 10v2a7 7 0 0 1-14 0v-2" />
        <line x1="12" x2="12" y1="19" y2="22" />
      </svg>
    ),
  },
  {
    id: 'translated-chat',
    pink: false,
    title: 'Encrypted Chat & Real-Time Voice Calls',
    desc: 'Private 1:1 and group conversations protected by end-to-end encryption, disappearing messages, and real-time voice translation so creators and buyers collaborate across any language.',
    tags: ['Encrypted Calls', 'Voice Translation', 'Disappearing Chats'],
    icon: (
      <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4">
        <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
      </svg>
    ),
  },
  {
    id: 'security-desktop-ecosystem',
    pink: false,
    title: 'Account Safety, SIM Shield & Device Health',
    desc: 'Protects African phone accounts against SIM-swap and phone-number recycling, pairs biometric hardware locks to Wallet actions, and adapts quality for affordable smartphones.',
    tags: ['SIM-Recycle Shield', 'Biometric Guard', 'Everyday Phones'],
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
    title: 'African & Global Trust & Compliance',
    desc: '100% creator copyright ownership, zero personal data sales, anti-mobile-money-scam protection, Teen Safety (116 helplines), and compliance across ODPC, NDPA, POPIA & GDPR.',
    tags: ['ODPC · NDPA · POPIA', 'Anti-Scam Shield', '100% Creator IP'],
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
        <span className="section-tag pink">THE ONEOVA CREATOR ECONOMY</span>
        <h2 className="section-title">
          Everything African Creators &amp; Merchants Need to Monetize &amp; Scale
        </h2>
        <p className="section-desc">
          Explore the real features Oneova brings together in one platform—from 3D Shops, Wallet
          &amp; Mobile Money payouts, and Oneova Global ID to Live Commerce and real-time Support
          AI. Click any card to open its full guide.
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
                <span>Read Guide →</span>
              </div>
            )}
          </div>
        ))}
      </div>
    </section>
  );
}
