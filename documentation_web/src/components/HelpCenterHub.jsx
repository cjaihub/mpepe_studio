import React, { useMemo, useState } from 'react';
import {
  lookupSupportTicketPublic,
  submitSupportTicketPublic,
} from '../services/publicDocsClient';

const FAQ_ITEMS = [
  {
    q: 'How do M-Pesa, MTN MoMo, Airtel Money & Creator Payouts work?',
    docId: 'wallet-biz-commerce',
    answer:
      'Earnings from Live Gifts and Oneova 3D Shops settle in your local currency Wallet. Verify your 18+ Oneova Global ID and withdraw directly via M-Pesa STK, MTN MoMo, Airtel Money, Orange, Wave, or bank transfer (1.5% MoMo / 1% bank fee).',
  },
  {
    q: 'How do I open a Oneova 3D Shop & pin products to a Live broadcast?',
    docId: 'biz-3d-shops',
    answer:
      'Open Biz / Studio → 3D Shop Setup, add your store name, location, and first product (with optional 3D model or photos). There is zero payout blocker to start selling, and you can pin Presenter’s Goods live on stage.',
  },
  {
    q: 'What is Oneova Global ID and how do I verify Personal & Business identity?',
    docId: 'global-id',
    answer:
      'Oneova Global ID gives African and global creators one verified digital identity and Business KYB credential. Complete ID + face liveness once to unlock higher payout limits, shop badges, and link up to 3 handles.',
  },
  {
    q: 'How do Live Support AI & real-time human help resolve account problems?',
    docId: 'ova-ai-lab',
    answer:
      'Open Oneova Support anytime in the bottom-right corner. Sign in with Oneova to let our live AI check and repair Wallet, Global ID, or 3D Shop issues directly—or request a live human admin in real time.',
  },
  {
    q: 'How to protect your Oneova account against SIM recycling & scams',
    docId: 'security-desktop-ecosystem',
    answer:
      'Link a recovery email or Passkey and enable App PIN + biometrics. Because carriers reassign inactive phone numbers, adding a second factor ensures nobody else can access your Wallet or Global ID.',
  },
  {
    q: 'Who owns my Reels, original sounds, and 3D Shop assets?',
    docId: 'policy-terms-of-service',
    answer:
      'You keep 100% ownership and copyright over everything you create on Oneova. Original sounds preserve creator attribution automatically whenever others remix them.',
  },
  {
    q: 'How does Power-Button Ova work over any phone screen + Desktop?',
    docId: 'ova-ai-lab',
    answer:
      'Set Oneova as your Default Assistant on mobile to highlight any text or translate foreign screens in place without switching apps, or install Mac & Windows Oneova Desktop for startup hands-free help.',
  },
  {
    q: 'Deleting your account or exporting your data in 2 taps',
    docId: 'policy-data-deletion',
    answer:
      'Open Me → Settings → Privacy & Security → Delete Account (or visit /deletion.html) to export a full archive or schedule permanent erasure with a 30-day safety window.',
  },
];

const CORE_CATEGORIES = [
  {
    id: 'wallet',
    title: 'Oneova Wallet & Pay',
    desc: 'Personal & Business balances, M-Pesa, MoMo, Airtel payouts, Scan-to-Pay QR & fees.',
    docId: 'wallet-biz-commerce',
    accent: 'blue',
    icon: (
      <svg width="42" height="42" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <circle cx="12" cy="12" r="9" />
        <path d="M12 7v10M9.5 9.5a2.5 2.5 0 0 1 5 0c0 1.5-5 1.5-5 3a2.5 2.5 0 0 0 5 0" />
      </svg>
    ),
  },
  {
    id: 'shops',
    title: 'Oneova 3D Shops & Biz',
    desc: 'Launch 3D product rooms, sell live with Presenter’s Goods, manage escrow orders.',
    docId: 'biz-3d-shops',
    accent: 'pink',
    icon: (
      <svg width="42" height="42" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z" />
        <line x1="3" y1="6" x2="21" y2="6" />
        <path d="M16 10a4 4 0 0 1-8 0" />
      </svg>
    ),
  },
  {
    id: 'global-id',
    title: 'Oneova Global ID & KYC',
    desc: 'Personal verification, Business KYB, shareable ID card & linked handles.',
    docId: 'global-id',
    accent: 'blue',
    icon: (
      <svg width="42" height="42" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <rect x="3" y="4" width="18" height="16" rx="2" />
        <circle cx="9" cy="10" r="2.5" />
        <path d="M6.5 16c.5-1.8 4.5-1.8 5 0" />
      </svg>
    ),
  },
  {
    id: 'live',
    title: 'Live Stage & Fan Gifts',
    desc: 'Host Solo or Co-Host stages, run polls & raffles, and earn from fan Coins & Gifts.',
    docId: 'live-studio',
    accent: 'pink',
    icon: (
      <svg width="42" height="42" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <polygon points="23 7 16 12 23 17 23 7" />
        <rect x="1" y="5" width="15" height="14" rx="2" />
      </svg>
    ),
  },
  {
    id: 'ova-desktop',
    title: 'Ova AI & Live Support',
    desc: 'Power-button screen translate, Desktop startup agent & live human support escalation.',
    docId: 'ova-ai-lab',
    accent: 'blue',
    icon: (
      <svg width="42" height="42" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <rect x="2" y="3" width="20" height="14" rx="2" />
        <line x1="8" y1="21" x2="16" y2="21" />
        <line x1="12" y1="17" x2="12" y2="21" />
      </svg>
    ),
  },
  {
    id: 'privacy',
    title: 'Safety, IP & African Laws',
    desc: 'Zero data sales, anti-scam shields, 116 Teen Safety, ODPC, NDPA, POPIA & GDPR.',
    docId: 'policy-privacy',
    accent: 'pink',
    icon: (
      <svg width="42" height="42" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
      </svg>
    ),
  },
];

const EXTRA_CATEGORIES = [
  {
    id: 'reels',
    title: 'Creator Feed, Stories & Remix Attribution',
    desc: 'Following · For You · Biz discovery tuned for affordable mobile data bundles.',
    docId: 'reels-feed',
    accent: 'pink',
  },
  {
    id: 'chat',
    title: 'Encrypted Chat & Translated Calls',
    desc: 'End-to-end encrypted messaging with live cross-language voice translation.',
    docId: 'translated-chat',
    accent: 'blue',
  },
  {
    id: 'security',
    title: 'SIM-Recycle Guard & Account Health',
    desc: 'Protect your phone account, biometric locks & device stability.',
    docId: 'security-desktop-ecosystem',
    accent: 'blue',
  },
];

export default function HelpCenterHub({
  docs = [],
  onSelectDoc,
  onOpenSupportDrawer,
  initialTicketOpen = false,
}) {
  const [queryText, setQueryText] = useState('');
  const [expandedFaqIdx, setExpandedFaqIdx] = useState(null);
  const [showOtherTopics, setShowOtherTopics] = useState(false);

  // Support Tickets modal
  const [isTicketsOpen, setIsTicketsOpen] = useState(initialTicketOpen);
  const [ticketTab, setTicketTab] = useState('new'); // 'new' | 'track'
  const [category, setCategory] = useState('wallet');
  const [subject, setSubject] = useState('');
  const [contactEmail, setContactEmail] = useState('');
  const [message, setMessage] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [submitResult, setSubmitResult] = useState(null);
  const [submitError, setSubmitError] = useState('');

  const [trackCode, setTrackCode] = useState('');
  const [trackPin, setTrackPin] = useState('');
  const [trackingBusy, setTrackingBusy] = useState(false);
  const [trackedTicket, setTrackedTicket] = useState(null);
  const [trackError, setTrackError] = useState('');

  const liveMatches = useMemo(() => {
    const q = queryText.trim().toLowerCase();
    if (!q) return [];
    const faqHits = FAQ_ITEMS.filter(
      (f) => f.q.toLowerCase().includes(q) || f.answer.toLowerCase().includes(q)
    ).map((f) => ({
      kind: 'FAQ',
      title: f.q,
      sub: f.answer,
      docId: f.docId,
    }));

    const docHits = docs
      .filter(
        (d) =>
          d.title.toLowerCase().includes(q) ||
          d.category.toLowerCase().includes(q) ||
          d.inShort.toLowerCase().includes(q)
      )
      .slice(0, 5)
      .map((d) => ({
        kind: d.badge || 'GUIDE',
        title: d.title,
        sub: d.inShort,
        docId: d.id,
      }));

    return [...faqHits, ...docHits].slice(0, 6);
  }, [queryText, docs]);

  const handleSubmitTicket = async (e) => {
    e.preventDefault();
    setSubmitting(true);
    setSubmitError('');
    setSubmitResult(null);
    try {
      const res = await submitSupportTicketPublic({
        category,
        subject: subject.trim(),
        message: message.trim(),
        contactEmail: contactEmail.trim(),
      });
      setSubmitResult(res);
      setSubject('');
      setMessage('');
    } catch (err) {
      setSubmitError(
        err?.message || 'Unable to submit ticket right now. Check fields and retry.'
      );
    } finally {
      setSubmitting(false);
    }
  };

  const handleLookupTicket = async (e) => {
    e.preventDefault();
    setTrackingBusy(true);
    setTrackError('');
    setTrackedTicket(null);
    try {
      const res = await lookupSupportTicketPublic({
        trackingCode: trackCode,
        accessPin: trackPin,
      });
      setTrackedTicket(res);
    } catch (err) {
      setTrackError(
        err?.message || 'Ticket not found or PIN did not match.'
      );
    } finally {
      setTrackingBusy(false);
    }
  };

  return (
    <section className="hc-section" id="help" aria-label="Oneova Help Center">
      <div className="hc-shell">
        <div className="hc-hero-row">
          <div className="hc-title-block">
            <span className="hc-eyebrow">ONEOVA HELP CENTER</span>
            <h2 className="hc-heading">How can we help?</h2>
          </div>

          <div className="hc-actions-strip">
            <div className="hc-search-wrap">
              <svg
                className="hc-search-icon"
                width="17"
                height="17"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2.3"
              >
                <circle cx="11" cy="11" r="8" />
                <path d="m21 21-4.35-4.35" />
              </svg>
              <input
                type="search"
                className="hc-search-input"
                placeholder="Search Oneova Wallet, 3D Shops, Global ID, M-Pesa, safety..."
                value={queryText}
                onChange={(e) => setQueryText(e.target.value)}
                aria-label="Search help articles"
              />
              {queryText && (
                <button
                  type="button"
                  className="hc-search-clear"
                  onClick={() => setQueryText('')}
                  aria-label="Clear search"
                >
                  ✕
                </button>
              )}

              {liveMatches.length > 0 && (
                <div className="hc-search-dropdown" role="listbox">
                  {liveMatches.map((m, idx) => (
                    <button
                      key={`${m.docId}-${idx}`}
                      type="button"
                      className="hc-dropdown-item"
                      onClick={() => {
                        setQueryText('');
                        onSelectDoc?.(m.docId);
                      }}
                    >
                      <span className="hc-dropdown-badge">{m.kind}</span>
                      <div className="hc-dropdown-copy">
                        <strong>{m.title}</strong>
                        <span>{m.sub}</span>
                      </div>
                    </button>
                  ))}
                </div>
              )}
            </div>

            <button
              type="button"
              className="hc-tickets-btn"
              onClick={() => setIsTicketsOpen(true)}
            >
              <svg
                width="16"
                height="16"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2.2"
              >
                <rect x="3" y="4" width="18" height="16" rx="2" />
                <line x1="7" y1="9" x2="17" y2="9" />
                <line x1="7" y1="13" x2="13" y2="13" />
              </svg>
              <span>Support tickets</span>
            </button>
          </div>
        </div>

        {/* Frequently Asked Questions */}
        <div className="hc-faq-block">
          <div className="hc-block-header">
            <h3>Frequently asked questions</h3>
            {onOpenSupportDrawer && (
              <button
                type="button"
                className="hc-inline-support-link"
                onClick={() => onOpenSupportDrawer()}
              >
                Chat with Oneova Support →
              </button>
            )}
          </div>
          <div className="hc-faq-grid">
            {FAQ_ITEMS.map((item, idx) => {
              const isOpen = expandedFaqIdx === idx;
              return (
                <div
                  key={item.q}
                  className={`hc-faq-item ${isOpen ? 'open' : ''}`}
                >
                  <button
                    type="button"
                    className="hc-faq-trigger"
                    onClick={() => setExpandedFaqIdx(isOpen ? null : idx)}
                    aria-expanded={isOpen}
                  >
                    <span className="hc-faq-ring" aria-hidden="true" />
                    <span className="hc-faq-q">{item.q}</span>
                  </button>
                  {isOpen && (
                    <div className="hc-faq-answer">
                      <p>{item.answer}</p>
                      <button
                        type="button"
                        className="hc-faq-read-more"
                        onClick={() => onSelectDoc?.(item.docId)}
                      >
                        Read full guide →
                      </button>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>

        {/* Category Cards Grid */}
        <div className="hc-categories-grid">
          {CORE_CATEGORIES.map((cat) => (
            <button
              key={cat.id}
              type="button"
              className={`hc-cat-card accent-${cat.accent}`}
              onClick={() => onSelectDoc?.(cat.docId)}
            >
              <div className="hc-cat-copy">
                <h4>{cat.title}</h4>
                <p>{cat.desc}</p>
              </div>
              <div className="hc-cat-watermark" aria-hidden="true">
                {cat.icon}
              </div>
            </button>
          ))}
        </div>

        <div className="hc-more-row">
          <button
            type="button"
            className="hc-see-other-btn"
            onClick={() => setShowOtherTopics((v) => !v)}
          >
            <span>{showOtherTopics ? 'Hide other topics' : 'See other topics'}</span>
            <svg
              width="14"
              height="14"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2.5"
              style={{
                transform: showOtherTopics ? 'rotate(180deg)' : 'none',
                transition: 'transform 180ms ease',
              }}
            >
              <polyline points="6 9 12 15 18 9" />
            </svg>
          </button>
        </div>

        {showOtherTopics && (
          <div className="hc-extra-grid">
            {EXTRA_CATEGORIES.map((cat) => (
              <button
                key={cat.id}
                type="button"
                className={`hc-cat-card compact accent-${cat.accent}`}
                onClick={() => onSelectDoc?.(cat.docId)}
              >
                <div className="hc-cat-copy">
                  <h4>{cat.title}</h4>
                  <p>{cat.desc}</p>
                </div>
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Secure Support Tickets Modal (Server Rate-Limited + PIN Tracking) */}
      {isTicketsOpen && (
        <div
          className="modal-overlay"
          role="dialog"
          aria-modal="true"
          aria-label="Oneova Support Tickets"
          onClick={() => setIsTicketsOpen(false)}
        >
          <div className="hc-ticket-modal" onClick={(e) => e.stopPropagation()}>
            <div className="hc-ticket-head">
              <div>
                <span className="hc-eyebrow">ENCRYPTED INTAKE</span>
                <h3>Oneova Support Tickets</h3>
              </div>
              <button
                type="button"
                className="modal-close-btn"
                onClick={() => setIsTicketsOpen(false)}
                aria-label="Close Support Tickets"
              >
                ✕
              </button>
            </div>

            <div className="hc-ticket-tabs">
              <button
                type="button"
                className={`hc-ticket-tab ${ticketTab === 'new' ? 'active' : ''}`}
                onClick={() => setTicketTab('new')}
              >
                Submit a Ticket
              </button>
              <button
                type="button"
                className={`hc-ticket-tab ${ticketTab === 'track' ? 'active' : ''}`}
                onClick={() => setTicketTab('track')}
              >
                Track Status
              </button>
            </div>

            {ticketTab === 'new' ? (
              <form className="hc-ticket-form" onSubmit={handleSubmitTicket}>
                <label className="cms-field-label">
                  Issue Category
                  <select
                    className="cms-input"
                    value={category}
                    onChange={(e) => setCategory(e.target.value)}
                  >
                    <option value="wallet">Wallet, M-Pesa/MoMo &amp; Payouts</option>
                    <option value="shops">Oneova 3D Shops &amp; Orders</option>
                    <option value="identity">Oneova Global ID &amp; KYC</option>
                    <option value="account">Account, Sign-In &amp; Security</option>
                    <option value="live">Live Stage, Goods &amp; Fan Gifts</option>
                    <option value="desktop">Mac &amp; Windows Desktop Agent</option>
                    <option value="reels">Feed, Remix &amp; Encrypted Chat</option>
                    <option value="privacy">Privacy, Safety &amp; Reporting</option>
                    <option value="other">Other Question</option>
                  </select>
                </label>

                <label className="cms-field-label">
                  Subject
                  <input
                    type="text"
                    required
                    minLength={3}
                    maxLength={140}
                    className="cms-input"
                    placeholder="Brief summary of what you need help with"
                    value={subject}
                    onChange={(e) => setSubject(e.target.value)}
                  />
                </label>

                <label className="cms-field-label">
                  Reply Email (optional)
                  <input
                    type="email"
                    maxLength={120}
                    className="cms-input"
                    placeholder="you@example.com"
                    value={contactEmail}
                    onChange={(e) => setContactEmail(e.target.value)}
                  />
                </label>

                <label className="cms-field-label">
                  Details
                  <textarea
                    required
                    minLength={10}
                    maxLength={2000}
                    rows={4}
                    className="cms-input"
                    placeholder="Describe your device (iOS, Android, macOS, Windows) and what happened..."
                    value={message}
                    onChange={(e) => setMessage(e.target.value)}
                  />
                </label>

                {submitError && <div className="hc-form-error">{submitError}</div>}

                {submitResult && (
                  <div className="hc-form-success">
                    <strong>Ticket Received — Save Your Reference PIN</strong>
                    <div className="hc-code-pair">
                      <span>
                        Ticket: <code>{submitResult.trackingCode}</code>
                      </span>
                      <span>
                        PIN: <code>{submitResult.accessPin}</code>
                      </span>
                    </div>
                  </div>
                )}

                <button type="submit" className="btn-primary" disabled={submitting}>
                  {submitting ? 'Submitting…' : 'Send Support Request'}
                </button>
              </form>
            ) : (
              <form className="hc-ticket-form" onSubmit={handleLookupTicket}>
                <label className="cms-field-label">
                  Tracking Code
                  <input
                    type="text"
                    required
                    className="cms-input"
                    placeholder="OVA-123456"
                    value={trackCode}
                    onChange={(e) => setTrackCode(e.target.value)}
                  />
                </label>
                <label className="cms-field-label">
                  6-Character Access PIN
                  <input
                    type="text"
                    required
                    className="cms-input"
                    placeholder="e.g. A7K9P2"
                    value={trackPin}
                    onChange={(e) => setTrackPin(e.target.value)}
                  />
                </label>
                {trackError && <div className="hc-form-error">{trackError}</div>}
                {trackedTicket && (
                  <div className="hc-tracked-card">
                    <div className="hc-tracked-top">
                      <strong>{trackedTicket.trackingCode}</strong>
                      <span className="hc-status-pill">{trackedTicket.status}</span>
                    </div>
                    <p className="hc-tracked-subj">{trackedTicket.subject}</p>
                    <p className="hc-tracked-reply">
                      {trackedTicket.adminReply
                        ? trackedTicket.adminReply
                        : 'Our support team is reviewing your request.'}
                    </p>
                  </div>
                )}
                <button type="submit" className="btn-primary" disabled={trackingBusy}>
                  {trackingBusy ? 'Checking…' : 'Check Ticket Status'}
                </button>
              </form>
            )}
          </div>
        </div>
      )}
    </section>
  );
}
