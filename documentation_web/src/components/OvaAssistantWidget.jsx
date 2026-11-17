import React, { useState, useRef, useEffect, useMemo } from 'react';
import { getOfficialPdfHref, getStandaloneLegalHref } from '../data/platformCatalog';

const ISSUE_TILES = [
  {
    id: 'account',
    label: 'Account',
    tint: 'pink',
    query: 'sign in account passkey oneova id deletion',
    icon: (
      <svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor">
        <path d="M12 12a4.5 4.5 0 1 0-4.5-4.5A4.5 4.5 0 0 0 12 12Zm0 2c-4.4 0-8 2.2-8 5v1h16v-1c0-2.8-3.6-5-8-5Z" />
      </svg>
    ),
  },
  {
    id: 'live',
    label: 'LIVE',
    tint: 'pink',
    query: '4k live broadcast studio pk shop',
    icon: (
      <svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor">
        <path d="M17 10.5V7a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-3.5l4 4v-11l-4 4Z" />
      </svg>
    ),
  },
  {
    id: 'interaction',
    label: 'Interaction',
    tint: 'blue',
    query: 'chat calls encryption translate notifications',
    icon: (
      <svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor">
        <path d="M4 4h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H8l-5 4V6a2 2 0 0 1 2-2Z" />
      </svg>
    ),
  },
  {
    id: 'desktop',
    label: 'Desktop',
    tint: 'blue',
    query: 'desktop agent mac windows permissions hotkey creative skills',
    icon: (
      <svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor">
        <path d="M3 4h18a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1Zm6 15h6v2H9v-2Z" />
      </svg>
    ),
  },
  {
    id: 'post',
    label: 'Studio / Post',
    tint: 'blue',
    query: 'color grade lut editor post rotoscope',
    icon: (
      <svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor">
        <path d="M12 5v14M5 12h14" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round" />
      </svg>
    ),
  },
  {
    id: 'monetization',
    label: 'Monetization',
    tint: 'amber',
    query: 'm-pesa momo payouts coins biz monetization',
    icon: (
      <svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor">
        <circle cx="12" cy="12" r="9" />
      </svg>
    ),
  },
  {
    id: 'feed',
    label: 'Feed & Reels',
    tint: 'blue',
    query: 'reels feed translate captions stories',
    icon: (
      <svg width="15" height="15" viewBox="0 0 24 24" fill="currentColor">
        <path d="M8 5v14l11-7-11-7Z" />
      </svg>
    ),
  },
  {
    id: 'other',
    label: 'Other',
    tint: 'slate',
    query: 'privacy zero data sales safety law ticket',
    icon: (
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4">
        <line x1="4" y1="7" x2="20" y2="7" />
        <line x1="4" y1="12" x2="20" y2="12" />
        <line x1="4" y1="17" x2="14" y2="17" />
      </svg>
    ),
  },
];

/**
 * Modern Oneova Support & Ova Help Drawer.
 * Modeled on clean issue-first Help Center triage with real guide linking
 * and one-click Support Ticket escalation.
 */
export default function OvaAssistantWidget({
  isOpen,
  onClose,
  onOpen,
  docs = [],
  onSelectDoc,
  onOpenTickets,
  currentDocId,
}) {
  const [messages, setMessages] = useState([]);
  const [inputText, setInputText] = useState('');
  const [isThinking, setIsThinking] = useState(false);
  const messagesEndRef = useRef(null);
  const inputRef = useRef(null);

  useEffect(() => {
    if (isOpen && messagesEndRef.current) {
      messagesEndRef.current.scrollIntoView({ behavior: 'smooth' });
    }
  }, [messages, isOpen, isThinking]);

  useEffect(() => {
    if (isOpen && inputRef.current) {
      setTimeout(() => inputRef.current?.focus(), 140);
    }
  }, [isOpen]);

  const knowledgeBase = useMemo(() => {
    return docs.map((doc) => {
      const allText = [
        doc.title,
        doc.category,
        doc.inShort,
        ...(doc.sections || []).flatMap((s) => [
          s.heading,
          s.summary,
          s.callout,
          ...(s.bullets || []),
        ]),
      ]
        .join(' ')
        .toLowerCase();

      return {
        id: doc.id,
        doc,
        title: doc.title,
        category: doc.category,
        inShort: doc.inShort,
        allText,
      };
    });
  }, [docs]);

  const answerQuery = (userQuery) => {
    const q = userQuery.toLowerCase().trim();
    let matchedDoc = null;
    let skillName = 'Oneova Support';
    let plainExplanation = '';
    let keyPoints = [];

    if (
      q.includes('desktop') ||
      q.includes('mac') ||
      q.includes('windows') ||
      q.includes('hotkey') ||
      q.includes('permissions') ||
      q.includes('davinci') ||
      q.includes('logic')
    ) {
      matchedDoc = knowledgeBase.find((k) => k.id === 'security-desktop-ecosystem')?.doc;
      skillName = 'Desktop Agent & Permissions';
      plainExplanation =
        'Oneova Desktop Agent runs natively on macOS and Windows with Launch on Startup, global hotkeys (⌥Space / Alt+Space), multi-monitor cursor control, and creative suite automation (DaVinci Resolve, Logic Pro, Adobe).';
      keyPoints = [
        'Tap the Shield icon in Desktop Agent to grant Storage, Screen Recording, Mouse/Keyboard, and Automation toggles.',
        'If macOS toggles look stuck after updating, click "Reset Permission Cache" inside the Shield sheet and re-enable.',
        'Use ⌥Space (Mac) or Alt+Space (Windows) over any full-screen studio app to summon the Floating HUD.',
      ];
    } else if (
      q.includes('m-pesa') ||
      q.includes('mpesa') ||
      q.includes('momo') ||
      q.includes('payout') ||
      q.includes('coin') ||
      q.includes('monetiz') ||
      q.includes('wallet')
    ) {
      matchedDoc = knowledgeBase.find((k) => k.id === 'wallet-biz-commerce')?.doc;
      skillName = 'Wallet & Mobile Money';
      plainExplanation =
        'You can open a Biz Shop with zero payout blocker and configure M-Pesa, MTN MoMo, Airtel Money, Orange, or Stripe withdrawals anytime inside Wallet → Payouts.';
      keyPoints = [
        'Creator gifts and Biz sales are held safely in local currency inside Oneova Wallet.',
        'Oneova never requests, transmits, or stores mobile-money or bank PINs.',
        'Chargeback and SIM-recycle protections shield your balance automatically.',
      ];
    } else if (
      q.includes('power') ||
      q.includes('holla') ||
      q.includes('highlight') ||
      q.includes('translate screen') ||
      q.includes('ova')
    ) {
      matchedDoc = knowledgeBase.find((k) => k.id === 'ova-ai-lab')?.doc;
      skillName = 'Ova AI & Screen Vision';
      plainExplanation =
        'Set Oneova as your Default Assistant under Settings → Ova Triggers to summon Ova with the Power button over any app—with Vertex Live voice, Circle/Highlight analysis, and instant in-place screen translation.';
      keyPoints = [
        'Zero app switching: tap Translate Screen ("A文") inside the overlay to read foreign text directly where it appears.',
        'Voice modes run end-to-end on Vertex Live Native Audio with personalized natural tone.',
        'All assistant threads and desktop commands stay synced with your account.',
      ];
    } else if (
      q.includes('live') ||
      q.includes('pk') ||
      q.includes('3d') ||
      q.includes('shop') ||
      q.includes('broadcast')
    ) {
      matchedDoc = knowledgeBase.find((k) => k.id === 'live-studio')?.doc;
      skillName = 'Live Studio & 3D Shops';
      plainExplanation =
        'Studio (+) → Live opens the 6-step Live wizard with real-time GPU Looks, Boost Beauty, multi-guest co-host panels, 3D product shelves, and RTMP restreaming.';
      keyPoints = [
        'Adaptive WebRTC simulcast scales cleanly from fast fiber down to low-bandwidth 3G bundles.',
        'Hold auctions, raffles, polls, and live shopping checkouts directly on stage.',
      ];
    } else if (
      q.includes('chat') ||
      q.includes('call') ||
      q.includes('notification') ||
      q.includes('interaction')
    ) {
      matchedDoc = knowledgeBase.find((k) => k.id === 'creator-rooms')?.doc;
      skillName = 'Chats, Voice & E2EE Calls';
      plainExplanation =
        '1:1 DMs, group rooms, and WebRTC video calls support FrameCryptor end-to-end encryption, live translated captions/audio, and quiet ring-only notification defaults.';
      keyPoints = [
        'Verify your peer safety code anytime via the Oneova Shield pill inside calls.',
        'Live voice interpreter translates between spoken languages in real time.',
      ];
    } else if (
      q.includes('privacy') ||
      q.includes('teen') ||
      q.includes('delete') ||
      q.includes('safety') ||
      q.includes('law')
    ) {
      matchedDoc = knowledgeBase.find((k) => k.id === 'policy-privacy')?.doc;
      skillName = 'Trust, Privacy & Deletion';
      plainExplanation =
        'Oneova enforces zero personal-data sales, strict 13–17 teen safety defaults with 116 helplines, and 2-tap self-service data export and account deletion.';
      keyPoints = [
        'Private chats and unposted drafts are never used to train external public AI models.',
        'Compliant with Kenya ODPC, Nigeria NDPA, South Africa POPIA, and EU GDPR/DSA.',
      ];
    } else if (q.includes('own') || q.includes('ip') || q.includes('sign') || q.includes('passkey') || q.includes('account')) {
      matchedDoc = knowledgeBase.find((k) => k.id === 'policy-terms-of-service')?.doc;
      skillName = 'Account & Creator Rights';
      plainExplanation =
        'You own 100% of every reel, look, and broadcast you create on Oneova, and your login is protected by WebAuthn passkeys and SIM-recycle verification.';
      keyPoints = [
        'Delete or export your original masters anytime with zero lock-in.',
        'If you lost phone access, open Support Tickets to verify recovery.',
      ];
    } else {
      let bestScore = 0;
      let bestCandidate = knowledgeBase[0]?.doc;
      const tokens = q.split(/\s+/).filter((w) => w.length > 2);
      knowledgeBase.forEach((entry) => {
        let score = 0;
        tokens.forEach((token) => {
          if (entry.title.toLowerCase().includes(token)) score += 5;
          if (entry.category.toLowerCase().includes(token)) score += 3;
          if (entry.inShort.toLowerCase().includes(token)) score += 4;
          if (entry.allText.includes(token)) score += 1;
        });
        if (score > bestScore) {
          bestScore = score;
          bestCandidate = entry.doc;
        }
      });
      matchedDoc = bestCandidate;
      skillName = matchedDoc?.category || 'Oneova Help Center';
      plainExplanation =
        matchedDoc?.inShort ||
        'Here is the most relevant guide from the Oneova Help Center.';
      keyPoints = (matchedDoc?.sections || [])
        .flatMap((s) => (s.bullets || []).slice(0, 2))
        .slice(0, 3);
    }

    return { matchedDoc, skillName, plainExplanation, keyPoints };
  };

  const handleSend = (textOverride = null) => {
    const query = (textOverride ?? inputText).trim();
    if (!query) return;

    const userMsg = {
      id: `user-${Date.now()}`,
      sender: 'user',
      text: query,
    };

    setMessages((prev) => [...prev, userMsg]);
    if (!textOverride) setInputText('');
    setIsThinking(true);

    setTimeout(() => {
      const result = answerQuery(query);
      setMessages((prev) => [
        ...prev,
        {
          id: `ova-${Date.now()}`,
          sender: 'ova',
          text: result.plainExplanation,
          skill: result.skillName,
          bullets: result.keyPoints,
          docLink: result.matchedDoc,
        },
      ]);
      setIsThinking(false);
    }, 260);
  };

  const handleDocJump = (docId) => {
    onSelectDoc?.(docId);
    const docsEl = document.getElementById('docs');
    if (docsEl) docsEl.scrollIntoView({ behavior: 'smooth' });
  };

  const activeDoc = docs.find((d) => d.id === currentDocId) || docs[0];
  const pdfHref = activeDoc ? getOfficialPdfHref(activeDoc) : null;
  const standaloneHref = activeDoc ? getStandaloneLegalHref(activeDoc) : null;

  if (!isOpen) {
    return (
      <button
        type="button"
        className="ova-floating-launcher"
        onClick={onOpen}
        aria-label="Open Oneova Support"
        title="Oneova Support & AI Help"
      >
        <span className="ova-launcher-glow" aria-hidden="true" />
        <span className="ova-launcher-icon">✦</span>
        <span className="ova-launcher-text">Oneova Support</span>
        <span className="ova-launcher-badge">HELP</span>
      </button>
    );
  }

  return (
    <aside className="ova-chat-drawer modern-support" aria-label="Oneova Support Drawer">
      <div className="ova-support-header">
        <div className="ova-support-title-row">
          <div className="ova-support-mark">
            <img src="/assets/images/oneova_logo.jpg" alt="Oneova" />
            <span className="ova-online-dot" />
          </div>
          <div>
            <strong>Oneova Support</strong>
            <span>Instant guide triage &amp; ticket help</span>
          </div>
        </div>
        <div className="ova-header-controls">
          {messages.length > 0 && (
            <button
              type="button"
              className="ova-ctrl-btn"
              onClick={() => setMessages([])}
              title="Back to issue selector"
              aria-label="Back to issue selector"
            >
              ↺
            </button>
          )}
          <button
            type="button"
            className="ova-ctrl-btn"
            onClick={onClose}
            aria-label="Close support drawer"
          >
            ✕
          </button>
        </div>
      </div>

      <div className="ova-messages-area">
        {messages.length === 0 ? (
          <div className="ova-triage-view">
            <p className="ova-triage-sub">We’re here to help!</p>
            <h4 className="ova-triage-title">Select an issue type.</h4>

            <div className="ova-issue-grid">
              {ISSUE_TILES.map((tile) => (
                <button
                  key={tile.id}
                  type="button"
                  className="ova-issue-tile"
                  onClick={() => handleSend(`Help with ${tile.label}: ${tile.query}`)}
                >
                  <span className={`ova-tile-icon tint-${tile.tint}`}>{tile.icon}</span>
                  <span className="ova-tile-label">{tile.label}</span>
                </button>
              ))}
            </div>

            <p className="ova-ai-disclaimer">
              Responses are assisted by Ova AI &amp; Oneova Docs.{' '}
              <a href="/privacy.html" target="_blank" rel="noreferrer">
                Learn more
              </a>
            </p>
          </div>
        ) : (
          <div className="ova-thread-list">
            {messages.map((msg) => (
              <div key={msg.id} className={`ova-msg-row ${msg.sender}`}>
                {msg.sender === 'ova' ? (
                  <div className="ova-bot-bubble">
                    <span className="ova-skill-chip">{msg.skill}</span>
                    <p>{msg.text}</p>
                    {msg.bullets?.length > 0 && (
                      <ul>
                        {msg.bullets.map((b, idx) => (
                          <li key={idx}>{b}</li>
                        ))}
                      </ul>
                    )}
                    <div className="ova-bot-links">
                      {msg.docLink && (
                        <button
                          type="button"
                          className="ova-doc-jump-btn"
                          onClick={() => handleDocJump(msg.docLink.id)}
                        >
                          Read “{msg.docLink.title}” →
                        </button>
                      )}
                      {onOpenTickets && (
                        <button
                          type="button"
                          className="ova-ticket-esc-btn"
                          onClick={() => {
                            onClose();
                            onOpenTickets();
                          }}
                        >
                          Open Support Ticket
                        </button>
                      )}
                    </div>
                  </div>
                ) : (
                  <div className="ova-user-bubble">{msg.text}</div>
                )}
              </div>
            ))}

            {isThinking && (
              <div className="ova-bot-bubble thinking">
                <div className="typing-dots">
                  <span />
                  <span />
                  <span />
                </div>
              </div>
            )}
            <div ref={messagesEndRef} />
          </div>
        )}
      </div>

      <form
        className="ova-support-composer"
        onSubmit={(e) => {
          e.preventDefault();
          handleSend();
        }}
      >
        <input
          ref={inputRef}
          type="text"
          className="ova-support-input"
          placeholder="Send a message..."
          value={inputText}
          onChange={(e) => setInputText(e.target.value)}
        />
        {onOpenTickets && (
          <button
            type="button"
            className="ova-plus-ticket-btn"
            onClick={() => {
              onClose();
              onOpenTickets();
            }}
            title="Create or track a Support Ticket"
            aria-label="Create or track a Support Ticket"
          >
            +
          </button>
        )}
        <button
          type="submit"
          className="ova-send-btn"
          disabled={!inputText.trim() || isThinking}
          aria-label="Send message"
        >
          <svg
            width="15"
            height="15"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2.5"
          >
            <line x1="22" y1="2" x2="11" y2="13" />
            <polygon points="22 2 15 22 11 13 2 9 22 2" />
          </svg>
        </button>
      </form>

      {(pdfHref || standaloneHref) && messages.length > 0 && (
        <div className="ova-drawer-mini-footer">
          {standaloneHref && (
            <a href={standaloneHref} target="_blank" rel="noreferrer">
              Legal Page ↗
            </a>
          )}
          {pdfHref && (
            <a href={pdfHref} download>
              ⬇ Official PDF
            </a>
          )}
        </div>
      )}
    </aside>
  );
}
