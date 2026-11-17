import React, { useMemo, useState } from 'react';
import {
  lookupSupportTicketPublic,
  submitSupportTicketPublic,
} from '../services/publicDocsClient';

const FAQ_ITEMS = [
  {
    q: 'How to sign in, use Passkeys or recover your Oneova ID',
    docId: 'security-desktop-ecosystem',
    answer:
      'Sign in using your phone number, email, Google account, or hardware Passkey. Every phone account includes SIM-recycle protection and encrypted cloud backups.',
  },
  {
    q: 'How to set Power-Button Ova, Highlight & Zero-Switch Translate',
    docId: 'ova-ai-lab',
    answer:
      'Go to Me → Settings → Ova Triggers and set Oneova as Default Assistant. Long-press your power button over any app to circle/highlight text or translate the whole screen in place.',
  },
  {
    q: 'Mac & Windows Desktop Agent: startup, permissions & creative skills',
    docId: 'security-desktop-ecosystem',
    answer:
      'Download Oneova Desktop from #desktop, enable Launch on Startup, and tap the Shield icon to allow Storage, Multiple Screens, Mouse, Keyboard, and Studio App Automation (DaVinci Resolve, Logic Pro, Adobe).',
  },
  {
    q: 'How 4K Live Studio, PK duels & 3D Shops work',
    docId: 'live-studio',
    answer:
      'Tap Studio (+) → Live to launch our unified 6-step Live Studio wizard with real-time GPU Looks, Co-Host stages, live polls, multi-platform RTMP restream, and interactive 3D shopping pins.',
  },
  {
    q: 'M-Pesa, MTN MoMo, Airtel Money & Creator Balance payouts',
    docId: 'wallet-biz-commerce',
    answer:
      'Creator gift shares and Biz sales settle in local currency in your Oneova Wallet. Withdraw directly to M-Pesa, MTN MoMo, Airtel Money, Orange, or bank rails after quick KYC verification.',
  },
  {
    q: 'Who owns my Reels, Sounds & .oneovapack Looks?',
    docId: 'policy-terms-of-service',
    answer:
      'You retain 100% copyright and ownership of every reel, voiceover, 3D scan, and `.oneovapack` grade you publish. Oneova takes only a limited license to host and stream it at your command.',
  },
  {
    q: 'Chats, Disappearing Messages & Encrypted WebRTC Calls',
    docId: 'creator-rooms',
    answer:
      '1:1 chats, voice notes, and WebRTC video calls support FrameCryptor end-to-end encryption, live two-way Vertex speech translation, and safety-number verification.',
  },
  {
    q: 'Deleting your account or exporting your data in 2 taps',
    docId: 'policy-data-deletion',
    answer:
      'Open Me → Settings → Privacy & Security → Delete Account (or visit /deletion.html) to export a full ZIP archive or schedule permanent erasure with a 30-day safety window.',
  },
];

const CORE_CATEGORIES = [
  {
    id: 'account',
    title: 'Account & Oneova ID',
    desc: 'Manage sign-in, passkeys, SIM-recycle shields, notifications & data export.',
    docId: 'security-desktop-ecosystem',
    accent: 'blue',
    icon: (
      <svg width="42" height="42" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
        <circle cx="12" cy="7" r="4" />
      </svg>
    ),
  },
  {
    id: 'using',
    title: 'Reels, Feed & Creation',
    desc: 'Master the Triple-Stream Feed, Stories, 1-tap Remix & multi-platform Share.',
    docId: 'reels-feed',
    accent: 'pink',
    icon: (
      <svg width="42" height="42" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <rect x="3" y="3" width="18" height="18" rx="3" />
        <polygon points="10 8 16 12 10 16 10 8" />
      </svg>
    ),
  },
  {
    id: 'ova-desktop',
    title: 'Ova AI & Desktop Agent',
    desc: 'Power-button Holla overlay, live screen translate, Mac & Windows studio control.',
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
    id: 'live',
    title: 'Oneova LIVE & 3D Shops',
    desc: 'Go live in 4K, run PK battles, Co-Host stages & pin 3D shoppable items.',
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
    id: 'monetization',
    title: 'Monetization & Wallet',
    desc: 'Understand Coins, Gifts, M-Pesa/MoMo payouts, Biz shops & .oneovapack.',
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
    id: 'privacy',
    title: 'Privacy, Safety & Laws',
    desc: 'Zero data sales, 116 Teen Safety, anti-scam protection, ODPC, NDPA & POPIA.',
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
    id: 'looks',
    title: 'Studio Editor, Looks & Color Grading',
    desc: 'SAM 2 cutouts, GPU waveform scopes, Scope Sentinel fixes & hardware export.',
    docId: 'looks-color-engine',
    accent: 'pink',
  },
  {
    id: 'sharing',
    title: 'Universal 4-Platform Publishing & Rooms',
    desc: 'One-tap sync to TikTok, Reels, Shorts & E2EE voice-translated Rooms.',
    docId: 'universal-sharing',
    accent: 'blue',
  },
  {
    id: 'thermal',
    title: 'Device Performance & Thermal Shield',
    desc: 'Smart resolution scaling for mid-range & flagship Android and iOS devices.',
    docId: 'device-thermal-advisor',
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
  const [category, setCategory] = useState('account');
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
                placeholder="Search help articles, M-Pesa, Desktop Agent, privacy..."
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
                    <option value="account">Account, Login &amp; Oneova ID</option>
                    <option value="live">4K Live Studio &amp; 3D Shops</option>
                    <option value="interaction">Chats, Calls &amp; Notifications</option>
                    <option value="desktop">Mac &amp; Windows Desktop Agent</option>
                    <option value="post">Reels, Studio Editor &amp; Looks</option>
                    <option value="monetization">Wallet, M-Pesa/MoMo &amp; Payouts</option>
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
