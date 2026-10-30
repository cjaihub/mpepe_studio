import React, { useState, useRef, useEffect, useMemo } from 'react';
import { getOfficialPdfHref, getStandaloneLegalHref } from '../data/platformCatalog';

/**
 * Ova Assistant Web Intelligence Widget.
 * Possesses all 18 Oneova Platform Feature Documents, Rules & Global Regulations as its skills.
 * Provides instant, user-friendly, non-technical answers with direct deep-links and official citations.
 */
export default function OvaAssistantWidget({
  isOpen,
  onClose,
  onOpen,
  docs = [],
  onSelectDoc,
  currentDocId,
}) {
  const [messages, setMessages] = useState(() => [
    {
      id: 'welcome',
      sender: 'ova',
      text: "Habari! I'm Ova Assistant. I have all 18 Oneova feature specifications, community rules, creator monetization terms, teen safety guidelines, and African & international data laws as my native skills. How can I help you today?",
      skill: 'Oneova Knowledge Engine',
      docLink: null,
      quickQuestions: [
        '💰 How do M-Pesa creator payouts work?',
        '⚖️ Do I own 100% of my uploaded reels?',
        '🎥 How does 4K Live broadcast work?',
        '🛡️ What are the child & teen safety rules?',
        '🗑️ How do I permanently delete my account?',
        '🔒 Does Oneova ever sell my personal data?',
      ],
      timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
    },
  ]);
  const [inputText, setInputText] = useState('');
  const [isThinking, setIsThinking] = useState(false);
  const [isMinimized, setIsMinimized] = useState(false);
  const messagesEndRef = useRef(null);
  const inputRef = useRef(null);

  // Auto-scroll chat to bottom
  useEffect(() => {
    if (isOpen && !isMinimized && messagesEndRef.current) {
      messagesEndRef.current.scrollIntoView({ behavior: 'smooth' });
    }
  }, [messages, isOpen, isMinimized, isThinking]);

  // Focus input when opened
  useEffect(() => {
    if (isOpen && !isMinimized && inputRef.current) {
      setTimeout(() => inputRef.current?.focus(), 150);
    }
  }, [isOpen, isMinimized]);

  // Index knowledge skills from docs
  const knowledgeBase = useMemo(() => {
    return docs.map((doc) => {
      const allText = [
        doc.title,
        doc.category,
        doc.inShort,
        ...(doc.sections || []).flatMap((s) => [s.heading, s.summary, s.callout, ...(s.bullets || [])]),
      ]
        .join(' ')
        .toLowerCase();

      return {
        id: doc.id,
        doc,
        title: doc.title,
        category: doc.category,
        inShort: doc.inShort,
        docType: doc.docType,
        policyTab: doc.policyTab,
        allText,
      };
    });
  }, [docs]);

  // Reasoning Engine: Maps user query to knowledge skill and crafts a plain-language answer
  const answerQuery = (userQuery) => {
    const q = userQuery.toLowerCase().trim();

    // Specific Intent Recognizers for best user experience
    let matchedDoc = null;
    let skillName = 'Oneova Core Skill';
    let plainExplanation = '';
    let keyPoints = [];

    if (q.includes('m-pesa') || q.includes('mpesa') || q.includes('payout') || q.includes('withdraw') || q.includes('coin') || q.includes('gift') || q.includes('earn') || q.includes('wallet') || q.includes('monetiz')) {
      matchedDoc = knowledgeBase.find((k) => k.id === 'wallet-biz-commerce' || k.id === 'policy-biz-monetization')?.doc;
      skillName = 'Wallet & Mobile Money Payouts';
      plainExplanation =
        'Oneova is built Africa-first with native support for M-Pesa, MTN Mobile Money, Airtel Money, Orange Money, Wave, card rails, and bank transfers. You earn Creator Balance in your local currency through Coins, Live stream Gifts, and custom Look Packs without hidden deductions.';
      keyPoints = [
        'Zero hidden currency exchange markups: prices and payouts are displayed in your local currency (KES, NGN, ZAR, GHS, UGX, TZS, USD, etc.).',
        'Direct payout to verified mobile money or bank accounts after standard KYC/identity check.',
        'Coins are closed-loop virtual tokens for Live Gifts and cannot be gambled or traded off-platform.',
        'Fraud protection: chargeback shields and SIM-recycle safeguards protect creator earnings.',
      ];
    } else if (q.includes('own') || q.includes('copyright') || q.includes('ip') || q.includes('license') || q.includes('intellectual property') || q.includes('terms') || q.includes('steal')) {
      matchedDoc = knowledgeBase.find((k) => k.id === 'policy-terms-of-service')?.doc;
      skillName = '100% Creator IP Ownership';
      plainExplanation =
        'You own 100% of everything you create and upload to Oneova. You grant Oneova only a non-exclusive license strictly needed to stream, transcode, and display your content to your viewers. We never claim ownership of your video, audio, or brand.';
      keyPoints = [
        'Complete creator retention: you can delete or license your content anywhere else at any time.',
        'Studio & AI Outputs: you own creative outputs generated using Oneova Studio and AI Color Grader.',
        'SIM-recycle protection: if your phone number is reassigned by a telecom carrier, your account is protected with multi-factor recovery.',
        'Fair takedown process: rightsholders can file notices, and creators get fair counter-notice rights.',
      ];
    } else if (q.includes('privacy') || q.includes('sell data') || q.includes('personal data') || q.includes('pin') || q.includes('password') || q.includes('spy') || q.includes('track')) {
      matchedDoc = knowledgeBase.find((k) => k.id === 'policy-privacy')?.doc;
      skillName = 'Zero Personal-Data Sales & Privacy Shield';
      plainExplanation =
        'Oneova has an absolute zero-data-selling policy. We never sell your personal data, phone numbers, contacts, private chats, or browsing habits to advertisers or data brokers.';
      keyPoints = [
        'Zero mobile money PIN storage: Oneova never sees, requests, or stores your mobile-money or banking PIN.',
        'AI Privacy Firewall: your private Chat messages and unposted studio drafts are NEVER used to train public generative AI models.',
        'On-device first: beauty and color filters run locally on your phone GPU whenever possible.',
        'Strict statutory compliance with Kenya ODPC, Nigeria NDPA, South Africa POPIA, and EU GDPR.',
      ];
    } else if (q.includes('child') || q.includes('teen') || q.includes('kid') || q.includes('minor') || q.includes('safety') || q.includes('116') || q.includes('grooming') || q.includes('age')) {
      matchedDoc = knowledgeBase.find((k) => k.id === 'policy-child-safety')?.doc;
      skillName = 'Pan-African Child & Teen Safety';
      plainExplanation =
        'Oneova operates with zero tolerance for child sexual abuse material (CSAM/CSAE), grooming, or exploitation. Accounts belonging to teens aged 13–17 have protective privacy defaults automatically enabled.',
      keyPoints = [
        'Private by default for teens: direct messages from strangers are restricted, and location sharing is off.',
        'Free 116 Emergency Helpline Directory: direct in-app emergency links to 116 helplines across Kenya, Nigeria, South Africa, Ghana, Uganda, and continental Africa.',
        'Immediate reporting: any user can flag underage endangerment in 2 taps for 24/7 priority review.',
        'Mandatory statutory reporting to law enforcement and international child protection databases (NCMEC).',
      ];
    } else if (q.includes('delete') || q.includes('erase') || q.includes('remove account') || q.includes('export') || q.includes('download data')) {
      matchedDoc = knowledgeBase.find((k) => k.id === 'policy-data-deletion')?.doc;
      skillName = '2-Tap Self-Service Data Deletion';
      plainExplanation =
        'You have the legal right to delete your Oneova account and all associated personal data at any time directly from the app or via the web deletion portal, without having to email support.';
      keyPoints = [
        'In-app self-service: Go to Me → Settings → Privacy & Security → Delete Account.',
        'Immediate deactivation with a 30-day grace period to prevent accidental loss or malicious account takeover.',
        'Permanent erasure of videos, comments, likes, profile data, and biometric templates after the grace period.',
        'Full data export: download a clean copy of your profile and uploaded content in ZIP/JSON format anytime.',
      ];
    } else if (q.includes('4k') || q.includes('live') || q.includes('pk') || q.includes('broadcast') || q.includes('stream') || q.includes('webrtc')) {
      matchedDoc = knowledgeBase.find((k) => k.id === 'live-studio')?.doc;
      skillName = '4K Broadcast Studio & WebRTC Engine';
      plainExplanation =
        'Oneova Live Studio allows broadcasting up to 4K resolution using real-time WebRTC and GPU Looks that are baked into the video track so all viewers experience cinema-grade color and Boost Beauty.';
      keyPoints = [
        'Adaptive Simulcast: streams in high-res 4K/1080p on fast Wi-Fi/5G and scales down smoothly for viewers on low-data 3G mobile bundles.',
        'Interactive PK Duels: split-screen battles with animated gift combos and live audience voting.',
        'Stream Health HUD: live indicators for bitrate, device temperature, and network stability.',
        'Multi-scene switching: switch between camera views and overlays with zero-cut latency.',
      ];
    } else if (q.includes('color') || q.includes('lut') || q.includes('look') || q.includes('grader') || q.includes('grading') || q.includes('filter') || q.includes('glsl') || q.includes('preset')) {
      matchedDoc = knowledgeBase.find((k) => k.id === 'looks-color-engine')?.doc;
      skillName = 'GPU Looks Engine & AI Color Grader';
      plainExplanation =
        'The GPU Looks Engine delivers Hollywood-grade GLSL shaders, 3D LUTs, curves, and natural-language AI color grading. Simply tell Ova "warm golden hour with punchy skin tones" to grade your shot automatically.';
      keyPoints = [
        'Conversational AI Color Grader: describe the look you want, and AI adjusts exposure, contrast, and color curves.',
        'Scope Sentinel: real-time GPU waveform, vectorscope, and RGB parade that alerts you to skin-tone clipping or crushed shadows.',
        'Zero quality loss: grade 10-bit HDR video right on your mobile phone without needing a desktop workstation.',
        'Export as .oneovapack to sell or share your signature look with other creators.',
      ];
    } else if (q.includes('law') || q.includes('regulation') || q.includes('popia') || q.includes('odpc') || q.includes('ndpa') || q.includes('gdpr') || q.includes('compliance') || q.includes('kenya') || q.includes('nigeria') || q.includes('south africa')) {
      matchedDoc = knowledgeBase.find((k) => k.id === 'regulation-african-global-compliance')?.doc;
      skillName = 'African & Global Regulatory Compliance';
      plainExplanation =
        'Oneova is formally aligned with national data protection, consumer rights, and fintech laws across Africa (Kenya ODPC, Nigeria NDPA, South Africa POPIA, Ghana DPC, Rwanda NCSA) as well as continental AU Malabo and international standards (EU GDPR, DSA, US COPPA).';
      keyPoints = [
        'Local legal jurisdiction: users retain full rights under their home country laws and consumer protection tribunals.',
        'Data sovereignty & cross-border safeguards: transfer of data complies with adequacy and consent frameworks.',
        'Independent DPO office: official data protection officers reachable directly at dpo@oneova.app.',
        'DSA transparent moderation: every enforcement action includes a clear reason and an independent human appeal.',
      ];
    } else {
      // General semantic matching across all docs
      let bestScore = 0;
      let bestCandidate = knowledgeBase[0]?.doc;

      const queryTokens = q.split(/\s+/).filter((w) => w.length > 2);
      knowledgeBase.forEach((entry) => {
        let score = 0;
        queryTokens.forEach((token) => {
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
      skillName = matchedDoc.category || 'Platform Knowledge';
      plainExplanation = matchedDoc.inShort || `Here is the authoritative information on ${matchedDoc.title}:`;
      keyPoints = (matchedDoc.sections || []).flatMap((s) => (s.bullets || []).slice(0, 3)).slice(0, 4);
      if (keyPoints.length === 0) {
        keyPoints = ['Full details are synchronized live across the Oneova mobile app and official web portals.'];
      }
    }

    return {
      matchedDoc,
      skillName,
      plainExplanation,
      keyPoints,
    };
  };

  const handleSend = (textToSend = null) => {
    const query = (textToSend || inputText).trim();
    if (!query) return;

    const userMsg = {
      id: `user-${Date.now()}`,
      sender: 'user',
      text: query,
      timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
    };

    setMessages((prev) => [...prev, userMsg]);
    setInputText('');
    setIsThinking(true);

    // Simulate snappy AI reasoning
    setTimeout(() => {
      const result = answerQuery(query);
      const botMsg = {
        id: `ova-${Date.now()}`,
        sender: 'ova',
        text: result.plainExplanation,
        skill: result.skillName,
        bullets: result.keyPoints,
        docLink: result.matchedDoc,
        timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
      };
      setMessages((prev) => [...prev, botMsg]);
      setIsThinking(false);
    }, 400);
  };

  const handleDocJump = (docId) => {
    if (onSelectDoc) {
      onSelectDoc(docId);
      const docsSection = document.getElementById('docs');
      if (docsSection) {
        docsSection.scrollIntoView({ behavior: 'smooth' });
      }
    }
  };

  if (!isOpen) {
    return (
      <button
        type="button"
        className="ova-floating-launcher"
        onClick={onOpen}
        aria-label="Open Ova Assistant"
        title="Ask Ova Assistant about features, rules & policies"
      >
        <span className="ova-launcher-halo" aria-hidden="true" />
        <span className="ova-launcher-icon">✨</span>
        <span className="ova-launcher-text">Ask Ova AI</span>
        <span className="ova-launcher-badge">18 Skills</span>
      </button>
    );
  }

  return (
    <aside
      className={`ova-chat-drawer ${isMinimized ? 'minimized' : ''}`}
      aria-label="Ova AI Assistant"
      role="complementary"
    >
      {/* Header */}
      <div className="ova-header">
        <div className="ova-header-left">
          <div className="ova-orb-badge">
            <span className="ova-orb-inner">✨</span>
          </div>
          <div>
            <div className="ova-name-row">
              <span className="ova-name">Ova Assistant</span>
              <span className="ova-status-pill">● 18 Skills Active</span>
            </div>
            <span className="ova-sub">Oneova Platform & Legal Intelligence</span>
          </div>
        </div>
        <div className="ova-header-actions">
          <button
            type="button"
            className="ova-tool-btn"
            onClick={() => setIsMinimized(!isMinimized)}
            title={isMinimized ? 'Expand Assistant' : 'Minimize'}
          >
            {isMinimized ? '▢' : '—'}
          </button>
          <button
            type="button"
            className="ova-tool-btn"
            onClick={onClose}
            title="Close Assistant"
          >
            ✕
          </button>
        </div>
      </div>

      {!isMinimized && (
        <>
          {/* Skills Ribbon */}
          <div className="ova-skills-ribbon">
            <span className="skills-ribbon-tag">VERIFIED KNOWLEDGE SKILLS:</span>
            <div className="skills-chips-row">
              <span className="skill-chip">🎥 4K Live Broadcast</span>
              <span className="skill-chip">🎨 GPU Looks</span>
              <span className="skill-chip">💳 M-Pesa / MoMo</span>
              <span className="skill-chip">🛡️ Teen Safety 116</span>
              <span className="skill-chip">⚖️ 100% Creator IP</span>
              <span className="skill-chip">🔒 Zero Data Sales</span>
              <span className="skill-chip">🌍 ODPC / NDPA / POPIA</span>
            </div>
          </div>

          {/* Messages Body */}
          <div className="ova-messages-body">
            {messages.map((m) => (
              <div key={m.id} className={`ova-bubble-row ${m.sender}`}>
                {m.sender === 'ova' && (
                  <div className="ova-avatar-small" aria-hidden="true">
                    ✨
                  </div>
                )}
                <div className={`ova-message-card ${m.sender}`}>
                  {m.skill && <div className="ova-skill-label">✦ {m.skill}</div>}
                  <p className="ova-message-text">{m.text}</p>

                  {/* Bullet Highlights */}
                  {Array.isArray(m.bullets) && m.bullets.length > 0 && (
                    <ul className="ova-bullets-list">
                      {m.bullets.map((b, idx) => (
                        <li key={idx}>{b}</li>
                      ))}
                    </ul>
                  )}

                  {/* Deep-link Action Button */}
                  {m.docLink && (
                    <div className="ova-citation-box">
                      <div className="ova-citation-info">
                        <strong>Official Document:</strong> {m.docLink.title}
                      </div>
                      <div className="ova-citation-actions">
                        <button
                          type="button"
                          className="ova-jump-btn"
                          onClick={() => handleDocJump(m.docLink.id)}
                        >
                          <span>Open in Docs Portal</span>
                          <span>→</span>
                        </button>
                        {getOfficialPdfHref(m.docLink) && (
                          <a
                            href={getOfficialPdfHref(m.docLink)}
                            download
                            target="_blank"
                            rel="noreferrer"
                            className="ova-pdf-btn"
                          >
                            ⬇ PDF
                          </a>
                        )}
                      </div>
                    </div>
                  )}

                  {/* Quick question prompts on welcome message */}
                  {Array.isArray(m.quickQuestions) && (
                    <div className="ova-quick-questions-grid">
                      <span className="quick-q-heading">POPULAR QUESTIONS:</span>
                      {m.quickQuestions.map((qText, qIdx) => (
                        <button
                          key={qIdx}
                          type="button"
                          className="ova-quick-q-btn"
                          onClick={() => handleSend(qText)}
                        >
                          {qText}
                        </button>
                      ))}
                    </div>
                  )}

                  <span className="ova-msg-time">{m.timestamp}</span>
                </div>
              </div>
            ))}

            {isThinking && (
              <div className="ova-bubble-row ova thinking">
                <div className="ova-avatar-small">✨</div>
                <div className="ova-message-card ova thinking">
                  <span className="ova-thinking-dots">
                    <span>•</span>
                    <span>•</span>
                    <span>•</span>
                  </span>
                  <span className="ova-thinking-text">Searching 18 Oneova knowledge skills...</span>
                </div>
              </div>
            )}
            <div ref={messagesEndRef} />
          </div>

          {/* Footer Input */}
          <div className="ova-input-bar">
            <input
              ref={inputRef}
              type="text"
              className="ova-input-field"
              placeholder="Ask about M-Pesa payouts, copyright, 4K Live, privacy..."
              value={inputText}
              onChange={(e) => setInputText(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  e.preventDefault();
                  handleSend();
                }
              }}
            />
            <button
              type="button"
              className="ova-send-btn"
              disabled={!inputText.trim() || isThinking}
              onClick={() => handleSend()}
              aria-label="Send message to Ova"
            >
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                <line x1="22" y1="2" x2="11" y2="13" />
                <polygon points="22 2 15 22 11 13 2 9 22 2" />
              </svg>
            </button>
          </div>
        </>
      )}
    </aside>
  );
}
