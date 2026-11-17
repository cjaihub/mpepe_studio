import React, { useEffect, useRef, useState } from 'react';
import {
  pollSupportSessionMessages,
  runSupportAgentTurn,
  sendSupportSessionMessage,
  signInOneovaSupportUser,
  signOutOneovaSupportUser,
  subscribeOneovaAuth,
  subscribeSignedInTicketMessages,
} from '../services/publicDocsClient';

const ISSUE_TYPES = [
  {
    id: 'wallet',
    label: 'Wallet & Payouts',
    icon: '💳',
    tint: 'amber',
    prompt: 'Check my Oneova Wallet balance, mobile-money setup, or pending payouts',
  },
  {
    id: 'shops',
    label: '3D Shops',
    icon: '🛍️',
    tint: 'pink',
    prompt: 'Inspect my Oneova 3D Shop storefront and active products or fix missing featured items',
  },
  {
    id: 'identity',
    label: 'Global ID & KYC',
    icon: '🪪',
    tint: 'blue',
    prompt: 'Check my Oneova Global ID verification status or KYC review progress',
  },
  {
    id: 'live',
    label: 'Live & Gifts',
    icon: '🎥',
    tint: 'pink',
    prompt: 'Help with Live Stage, Presenter Goods pinning, or fan gift earnings',
  },
  {
    id: 'account',
    label: 'Account & Safety',
    icon: '🛡️',
    tint: 'blue',
    prompt: 'Diagnose my account status, SIM-recycle protection, or security holds',
  },
  {
    id: 'desktop',
    label: 'Desktop Agent',
    icon: '🖥️',
    tint: 'slate',
    prompt: 'Help setting up Oneova Desktop on Mac or Windows, startup, and permissions',
  },
  {
    id: 'reels',
    label: 'Feed & Chat',
    icon: '💬',
    tint: 'blue',
    prompt: 'Questions about Reels Remix attribution, encrypted chat, or live call translation',
  },
  {
    id: 'human',
    label: 'Human Admin',
    icon: '👤',
    tint: 'pink',
    directHuman: true,
    prompt: 'Connect me directly to a live human Oneova admin to review my issue in real time.',
  },
];

export default function OvaAssistantWidget({
  isOpen,
  onOpen,
  onClose,
  docs = [],
  onSelectDoc,
  onOpenTickets,
  currentDocId,
}) {
  const [messages, setMessages] = useState([]);
  const [inputText, setInputText] = useState('');
  const [isThinking, setIsThinking] = useState(false);
  const [isMinimized, setIsMinimized] = useState(false);
  const [activeCategory, setActiveCategory] = useState('other');
  const [supportUser, setSupportUser] = useState(null);
  const [authBusy, setAuthBusy] = useState(false);

  // Live escalated ticket session (links user <-> AI <-> real-time /admin human operator)
  const [liveSession, setLiveSession] = useState(() => {
    try {
      const saved = sessionStorage.getItem('oneova_live_support_session');
      return saved ? JSON.parse(saved) : null;
    } catch {
      return null;
    }
  });
  const [serverThreadMsgs, setServerThreadMsgs] = useState([]);
  const scrollEndRef = useRef(null);

  useEffect(() => {
    scrollEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, serverThreadMsgs, isThinking, isOpen]);

  // Lazy auth listener once drawer has been opened at least once
  useEffect(() => {
    if (!isOpen) return undefined;
    let active = true;
    let unsub = () => {};
    subscribeOneovaAuth((user) => {
      if (active) setSupportUser(user);
    })
      .then((fn) => {
        if (active && typeof fn === 'function') unsub = fn;
        else if (typeof fn === 'function') fn();
      })
      .catch(() => {});
    return () => {
      active = false;
      unsub();
    };
  }, [isOpen]);

  useEffect(() => {
    try {
      if (liveSession?.ticketId) {
        sessionStorage.setItem('oneova_live_support_session', JSON.stringify(liveSession));
      } else {
        sessionStorage.removeItem('oneova_live_support_session');
      }
    } catch {}
  }, [liveSession]);

  // Real-time Firestore listener when signed in; PIN-verified live polling when guest
  useEffect(() => {
    if (!isOpen || !liveSession?.ticketId) return undefined;

    let unsubSnapshot = () => {};
    if (supportUser?.uid) {
      unsubSnapshot = subscribeSignedInTicketMessages(liveSession.ticketId, (msgs) => {
        setServerThreadMsgs(msgs);
      });
    }

    let stopped = false;
    const pollNow = async () => {
      try {
        const res = await pollSupportSessionMessages({
          ticketId: liveSession.ticketId,
          trackingCode: liveSession.trackingCode,
          accessPin: liveSession.accessPin,
        });
        if (stopped || !res) return;
        setLiveSession((prev) =>
          prev
            ? {
                ...prev,
                status: res.status || prev.status,
                handledByName: res.handledByName || prev.handledByName || '',
              }
            : prev
        );
        if (Array.isArray(res.messages)) {
          setServerThreadMsgs(res.messages);
        }
      } catch {
        // Silent retry on transient network glitch
      }
    };

    pollNow();
    const timer = setInterval(pollNow, supportUser?.uid ? 12000 : 4000);

    return () => {
      stopped = true;
      clearInterval(timer);
      unsubSnapshot();
    };
  }, [isOpen, liveSession?.ticketId, supportUser?.uid]);

  const handleSignIn = async () => {
    setAuthBusy(true);
    try {
      await signInOneovaSupportUser();
    } catch (err) {
      setMessages((prev) => [
        ...prev,
        {
          id: `auth-err-${Date.now()}`,
          sender: 'ova',
          skill: 'Sign-In Notice',
          text: err?.message || 'Sign-in window closed. You can still ask questions or escalate to a human admin.',
        },
      ]);
    } finally {
      setAuthBusy(false);
    }
  };

  const handleSend = async (rawText, opts = {}) => {
    const clean = String(rawText || '').trim();
    if (!clean || isThinking) return;

    const category = opts.category || activeCategory;
    if (opts.category) setActiveCategory(opts.category);
    setInputText('');

    // If user is already inside an escalated live human thread & not explicitly invoking AI
    if (liveSession?.ticketId && !opts.forceAi) {
      setIsThinking(true);
      try {
        await sendSupportSessionMessage({
          ticketId: liveSession.ticketId,
          trackingCode: liveSession.trackingCode,
          accessPin: liveSession.accessPin,
          text: clean,
        });
        const refreshed = await pollSupportSessionMessages({
          ticketId: liveSession.ticketId,
          trackingCode: liveSession.trackingCode,
          accessPin: liveSession.accessPin,
        });
        if (Array.isArray(refreshed?.messages)) {
          setServerThreadMsgs(refreshed.messages);
        }
      } catch (err) {
        setMessages((prev) => [
          ...prev,
          {
            id: `msg-err-${Date.now()}`,
            sender: 'ova',
            skill: 'Connection Retry',
            text: err?.message || 'Could not deliver message to live queue. Please retry.',
          },
        ]);
      } finally {
        setIsThinking(false);
      }
      return;
    }

    const userMsg = {
      id: `user-${Date.now()}`,
      sender: 'user',
      text: clean,
    };
    const nextHistory = [...messages, userMsg];
    setMessages(nextHistory);
    setIsThinking(true);

    try {
      const res = await runSupportAgentTurn({
        message: clean,
        category,
        requestHuman: Boolean(opts.directHuman),
        history: nextHistory.slice(-8).map((m) => ({
          sender: m.sender,
          text: m.text,
        })),
        ticketId: liveSession?.ticketId || '',
        trackingCode: liveSession?.trackingCode || '',
        accessPin: liveSession?.accessPin || '',
        pageContext: currentDocId || '',
      });

      const docLinks = (Array.isArray(res?.suggestedDocIds) ? res.suggestedDocIds : [])
        .map((id) => docs.find((d) => d.id === id))
        .filter(Boolean);

      setMessages((prev) => [
        ...prev,
        {
          id: `ova-${Date.now()}`,
          sender: 'ova',
          skill: res?.skillUsed || 'Oneova Live AI',
          checks: Array.isArray(res?.liveChecksRun) ? res.liveChecksRun : [],
          text: res?.reply || 'Checked live status cleanly.',
          docLinks,
        },
      ]);

      if (res?.escalation?.ticketId) {
        setLiveSession({
          ticketId: res.escalation.ticketId,
          trackingCode: res.escalation.trackingCode,
          accessPin: res.escalation.accessPin,
          status: res.escalation.status || 'escalated_human',
          handledByName: '',
        });
      }
    } catch (err) {
      setMessages((prev) => [
        ...prev,
        {
          id: `err-${Date.now()}`,
          sender: 'ova',
          skill: 'Support Escalation',
          text:
            err?.message ||
            'Unable to reach the live AI specialist right now. Tap "Talk to Human" below to open a real-time support session.',
        },
      ]);
    } finally {
      setIsThinking(false);
    }
  };

  const resetThread = () => {
    setMessages([]);
    setServerThreadMsgs([]);
    setLiveSession(null);
    setActiveCategory('other');
  };

  const isInTriageHome = messages.length === 0 && !liveSession?.ticketId;

  return (
    <>
      {!isOpen && (
        <button
          type="button"
          className="ova-floating-launcher"
          onClick={() => {
            setIsMinimized(false);
            onOpen();
          }}
          aria-label="Open Oneova Live Support"
        >
          <span className="ova-launcher-glow" />
          <span className="ova-launcher-icon">✦</span>
          <span className="ova-launcher-text">
            {liveSession?.ticketId ? 'Live Support Active' : 'Oneova Support'}
          </span>
          <span className="ova-launcher-badge">LIVE AI</span>
        </button>
      )}

      {isOpen && (
        <div
          className={`ova-chat-drawer modern-support ${isMinimized ? 'minimized' : ''}`}
          role="dialog"
          aria-label="Oneova Live Support Agent"
        >
          <div className="ova-support-header">
            <div className="ova-support-title-row">
              <span className="ova-support-mark">O</span>
              <span>Oneova Support</span>
              <span
                className="ova-online-dot"
                title={liveSession?.ticketId ? 'Connected to Live Queue' : 'Live AI Specialist Ready'}
              />
            </div>

            <div className="ova-header-controls">
              {(messages.length > 0 || liveSession?.ticketId) && (
                <button
                  type="button"
                  className="ova-ctrl-btn"
                  onClick={resetThread}
                  title="New support topic"
                  aria-label="Start new topic"
                >
                  ↺
                </button>
              )}
              <button
                type="button"
                className="ova-ctrl-btn"
                onClick={() => setIsMinimized(!isMinimized)}
                aria-label={isMinimized ? 'Expand' : 'Minimize'}
              >
                {isMinimized ? '□' : '—'}
              </button>
              <button
                type="button"
                className="ova-ctrl-btn"
                onClick={onClose}
                aria-label="Close Oneova Support"
              >
                ✕
              </button>
            </div>
          </div>

          {!isMinimized && (
            <>
              {/* Account Binding Strip for Real Live Diagnostics */}
              <div className="ova-auth-bar">
                {supportUser ? (
                  <>
                    <span className="ova-auth-status live">
                      ✓ Live Linked: {supportUser.displayName}
                    </span>
                    <button
                      type="button"
                      className="ova-auth-mini-btn"
                      onClick={signOutOneovaSupportUser}
                    >
                      Sign out
                    </button>
                  </>
                ) : (
                  <>
                    <span className="ova-auth-status">
                      Sign in for live Wallet, ID &amp; 3D Shop auto-fixes
                    </span>
                    <button
                      type="button"
                      className="ova-auth-mini-btn primary"
                      disabled={authBusy}
                      onClick={handleSignIn}
                    >
                      {authBusy ? 'Signing in…' : 'Sign in'}
                    </button>
                  </>
                )}
              </div>

              {/* Active Escalated Live Human Banner */}
              {liveSession?.ticketId && (
                <div className="ova-live-escalated-bar">
                  <div className="ova-escalated-top">
                    <span className="live-dot-mini" />
                    <strong>
                      {liveSession.handledByName
                        ? `${liveSession.handledByName} (Human Admin)`
                        : 'Live Human Queue Connected'}
                    </strong>
                    <span className="ova-esc-code">{liveSession.trackingCode}</span>
                  </div>
                  <div className="ova-escalated-sub">
                    Status: <b>{String(liveSession.status || 'escalated').replace('_', ' ')}</b>
                    {liveSession.accessPin ? ` · PIN: ${liveSession.accessPin}` : ''}
                  </div>
                </div>
              )}

              <div className="ova-messages-area">
                {isInTriageHome ? (
                  <div className="ova-triage-view">
                    <p className="ova-triage-sub">Live AI Agent · Real-Time Admin Handoff</p>
                    <h3 className="ova-triage-title">
                      How can we help you today?
                      <br />
                      Select a topic or describe your issue.
                    </h3>

                    <div className="ova-issue-grid">
                      {ISSUE_TYPES.map((tile) => (
                        <button
                          key={tile.id}
                          type="button"
                          className="ova-issue-tile"
                          onClick={() =>
                            handleSend(tile.prompt, {
                              category: tile.id === 'human' ? 'other' : tile.id,
                              directHuman: Boolean(tile.directHuman),
                            })
                          }
                        >
                          <span className={`ova-tile-icon tint-${tile.tint}`}>{tile.icon}</span>
                          <span className="ova-tile-label">{tile.label}</span>
                        </button>
                      ))}
                    </div>

                    <p className="ova-ai-disclaimer">
                      AI inspects only your signed-in account data.{' '}
                      {onOpenTickets && (
                        <button type="button" onClick={onOpenTickets}>
                          Track Ticket PIN
                        </button>
                      )}
                    </p>
                  </div>
                ) : (
                  <div className="ova-thread-list">
                    {/* Pre-escalation local messages */}
                    {!liveSession?.ticketId &&
                      messages.map((msg) => (
                        <div key={msg.id} className={`ova-msg-row ${msg.sender}`}>
                          {msg.sender === 'user' ? (
                            <div className="ova-user-bubble">{msg.text}</div>
                          ) : (
                            <div className="ova-bot-bubble">
                              {msg.skill && <span className="ova-skill-chip">✦ {msg.skill}</span>}
                              {msg.checks?.length > 0 && (
                                <div className="ova-checks-row">
                                  {msg.checks.map((ck) => (
                                    <span key={ck} className="ova-check-pill">
                                      ✓ {ck}
                                    </span>
                                  ))}
                                </div>
                              )}
                              <p>{msg.text}</p>
                              <div className="ova-bot-links">
                                {msg.docLinks?.map((d) => (
                                  <button
                                    key={d.id}
                                    type="button"
                                    className="ova-doc-jump-btn"
                                    onClick={() => onSelectDoc?.(d.id)}
                                  >
                                    {d.title} →
                                  </button>
                                ))}
                                <button
                                  type="button"
                                  className="ova-ticket-esc-btn"
                                  onClick={() =>
                                    handleSend(
                                      `Please connect a human admin for this: ${msg.text.slice(0, 120)}`,
                                      { directHuman: true }
                                    )
                                  }
                                >
                                  Talk to Human Admin
                                </button>
                              </div>
                            </div>
                          )}
                        </div>
                      ))}

                    {/* Live synced Firestore messages thread once escalated */}
                    {liveSession?.ticketId &&
                      serverThreadMsgs.map((m) => {
                        const isUser = m.senderRole === 'user';
                        return (
                          <div
                            key={m.id}
                            className={`ova-msg-row ${isUser ? 'user' : 'ova'}`}
                          >
                            {isUser ? (
                              <div className="ova-user-bubble">{m.text}</div>
                            ) : (
                              <div
                                className={`ova-bot-bubble ${
                                  m.senderRole === 'admin' ? 'human-admin' : ''
                                }`}
                              >
                                <span className="ova-skill-chip">
                                  {m.senderRole === 'admin'
                                    ? `👤 ${m.senderName || 'Oneova Human Admin'}`
                                    : '✦ Oneova AI Summary'}
                                </span>
                                <p>{m.text}</p>
                              </div>
                            )}
                          </div>
                        );
                      })}

                    {isThinking && (
                      <div className="ova-msg-row ova">
                        <div className="ova-bot-bubble thinking">
                          <div className="typing-dots">
                            <span />
                            <span />
                            <span />
                          </div>
                        </div>
                      </div>
                    )}
                    <div ref={scrollEndRef} />
                  </div>
                )}
              </div>

              <form
                className="ova-support-composer"
                onSubmit={(e) => {
                  e.preventDefault();
                  handleSend(inputText);
                }}
              >
                <input
                  type="text"
                  className="ova-support-input"
                  placeholder={
                    liveSession?.ticketId
                      ? 'Reply live to Oneova Admin...'
                      : 'Ask AI to check wallet, 3D shop, or ID...'
                  }
                  value={inputText}
                  onChange={(e) => setInputText(e.target.value)}
                  disabled={isThinking}
                />
                {!liveSession?.ticketId && (
                  <button
                    type="button"
                    className="ova-plus-ticket-btn"
                    onClick={() =>
                      handleSend(
                        inputText.trim() || 'I need a human Oneova admin to assist me live.',
                        { directHuman: true }
                      )
                    }
                    title="Escalate immediately to live Human Admin"
                    aria-label="Talk to Human Admin"
                  >
                    👤
                  </button>
                )}
                <button
                  type="submit"
                  className="ova-send-btn"
                  disabled={!inputText.trim() || isThinking}
                  aria-label="Send message"
                >
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                    <line x1="22" y1="2" x2="11" y2="13" />
                    <polygon points="22 2 15 22 11 13 2 9 22 2" />
                  </svg>
                </button>
              </form>

              <div className="ova-drawer-mini-footer">
                <button
                  type="button"
                  onClick={() => {
                    resetThread();
                    onOpenTickets?.();
                  }}
                >
                  Need a separate offline form? Submit or track Support Ticket →
                </button>
              </div>
            </>
          )}
        </div>
      )}
    </>
  );
}
