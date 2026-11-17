import React, { useState, useRef } from 'react';

export default function AboutUs({ onOpenDownload, onSelectDoc }) {
  const [isPlaying, setIsPlaying] = useState(true);
  const [isMuted, setIsMuted] = useState(true);
  const videoRef = useRef(null);

  const togglePlay = () => {
    if (!videoRef.current) return;
    if (videoRef.current.paused) {
      videoRef.current.play();
      setIsPlaying(true);
    } else {
      videoRef.current.pause();
      setIsPlaying(false);
    }
  };

  const toggleMute = () => {
    if (!videoRef.current) return;
    videoRef.current.muted = !isMuted;
    setIsMuted(!isMuted);
  };

  const handleFullscreen = () => {
    if (videoRef.current && videoRef.current.requestFullscreen) {
      videoRef.current.requestFullscreen();
    }
  };

  return (
    <section className="about-us-section" id="about">
      <div className="about-pink-glow-ray" aria-hidden="true" />
      <div className="about-blue-glow-ray" aria-hidden="true" />

      <div className="about-container">
        <div className="about-header-block">
          <div className="about-tag-pill">
            <span className="about-pulse-dot" />
            <span>BUILT FOR AFRICA&apos;S CREATIVE ECONOMY</span>
          </div>

          <h2 className="about-hero-title">
            Turning Creativity Into{' '}
            <span className="hero-title-gradient">Fair, Borderless Income</span>
          </h2>

          <p className="about-hero-desc">
            African creators and local businesses create culture seen around the world—yet legacy
            platforms leave them without direct local payouts, verified cross-border identity, or
            integrated storefronts. Oneova solves this from the ground up with Oneova 3D Shops,
            Oneova Wallet with instant mobile-money rails, and Oneova Global ID.
          </p>
        </div>

        {/* Video Theater */}
        <div className="about-video-theater-wrap">
          <div className="theater-ambient-backlight" aria-hidden="true" />

          <div className="theater-card-chassis">
            <div className="theater-top-bar">
              <div className="theater-status-group">
                <span className="live-dot-pink" />
                <span className="theater-feed-label">ONEOVA ECOSYSTEM OVERVIEW</span>
                <span className="theater-badge-hd">LIVE ECONOMY</span>
              </div>
              <div className="theater-controls-group">
                <button
                  type="button"
                  className="theater-btn-mini"
                  onClick={toggleMute}
                  title={isMuted ? 'Unmute Audio' : 'Mute Audio'}
                >
                  <span>{isMuted ? 'Unmute Sound' : 'Sound On 🔊'}</span>
                </button>
                <button
                  type="button"
                  className="theater-btn-mini"
                  onClick={handleFullscreen}
                  title="Expand to Fullscreen"
                >
                  <span>Fullscreen</span>
                </button>
              </div>
            </div>

            <div className="theater-screen-surface" onClick={togglePlay}>
              <video
                ref={videoRef}
                className="theater-video-element"
                src="/assets/oneova_promo.mp4"
                poster="/assets/images/oneova_reel_bg.jpg"
                autoPlay
                loop
                muted={isMuted}
                playsInline
              />
              <div className="theater-vignette-overlay" />

              {!isPlaying && (
                <div className="theater-center-play-badge">
                  <svg width="32" height="32" viewBox="0 0 24 24" fill="#FFFFFF">
                    <polygon points="5 3 19 12 5 21 5 3" />
                  </svg>
                  <span>Click to Resume</span>
                </div>
              )}

              <div className="theater-feature-pill-left">
                <span className="pill-dot-pink" />
                <span>M-Pesa · MTN MoMo · Airtel · Orange · Wave</span>
              </div>

              <div className="theater-feature-pill-right">
                <span className="pill-dot-blue" />
                <span>3D Shops · Global ID · Live Support AI</span>
              </div>
            </div>

            <div className="theater-bottom-status-bar">
              <div className="theater-bottom-meta">
                <span className="theater-meta-title">Oneova — Is The Reason You Matter</span>
                <span className="theater-meta-sub">
                  Direct monetization, verified trust, and seamless commerce for creators everywhere.
                </span>
              </div>
              <div className="theater-action-links">
                <button type="button" className="theater-cta-btn" onClick={onOpenDownload}>
                  <span>Get Oneova Free</span>
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                    <path d="M5 12h14" />
                    <path d="m12 5 7 7-7 7" />
                  </svg>
                </button>
              </div>
            </div>
          </div>
        </div>

        {/* Real Platform Highlights */}
        <div className="about-stats-grid">
          <div className="about-stat-card">
            <span className="stat-number pink">6+ Rails</span>
            <span className="stat-label">Local Mobile Money &amp; Banks</span>
            <p className="stat-desc">
              Withdraw creator gifts and shop sales directly via M-Pesa, MTN MoMo, Airtel Money,
              Orange Money, Wave, and bank accounts.
            </p>
          </div>

          <div className="about-stat-card">
            <span className="stat-number blue">1.5% / 1%</span>
            <span className="stat-label">Transparent Cashout Fees</span>
            <p className="stat-desc">
              Published integer fee rules: 1.5% mobile-money payouts, 1% bank payouts, and 10%
              commission on completed Biz shop orders.
            </p>
          </div>

          <div className="about-stat-card">
            <span className="stat-number pink">3D Shops</span>
            <span className="stat-label">Instant Live Commerce Stage</span>
            <p className="stat-desc">
              Showcase interactive 3D products during Live streams or 24/7 storefronts with server
              order escrow and local currency pricing.
            </p>
          </div>

          <div className="about-stat-card">
            <span className="stat-number blue">Global ID</span>
            <span className="stat-label">Verified Personal &amp; Biz Trust</span>
            <p className="stat-desc">
              One hardware-backed credential unlocking higher payout trust, verified shop badges,
              and up to 3 linked creator handles.
            </p>
          </div>
        </div>

        {/* 4 Core Pillars */}
        <div className="about-pillars-block">
          <div className="pillars-header">
            <span className="pillars-eyebrow">CORE MONETIZATION PILLARS</span>
            <h3 className="pillars-title">Designed From the Ground Up for African Creators</h3>
            <p className="pillars-desc">
              Every system inside Oneova helps creators keep ownership, build trust, and turn
              engagement into reliable income.
            </p>
          </div>

          <div className="pillars-grid">
            <div className="pillar-card highlight-pink">
              <div className="pillar-num-badge">01</div>
              <div className="pillar-icon-box">🛍️</div>
              <h4 className="pillar-card-title">Oneova 3D Shops &amp; Live Selling</h4>
              <p className="pillar-card-desc">
                Open your storefront in minutes—even before linking a payout rail. Present 3D items
                live on stage (`Presenter’s Goods`) and keep selling automatically when offline.
              </p>
              <div className="pillar-tag-list">
                <span className="p-tag">3D Product Stage</span>
                <span className="p-tag">Order Escrow</span>
                <span className="p-tag">Zero Blocker Setup</span>
              </div>
            </div>

            <div className="pillar-card">
              <div className="pillar-num-badge">02</div>
              <div className="pillar-icon-box">💳</div>
              <h4 className="pillar-card-title">Oneova Wallet &amp; Oneova Pay</h4>
              <p className="pillar-card-desc">
                Separate Personal and Business balances secured on a double-entry ledger with
                Scan-to-Pay QR codes, biometric approval, and instant local-currency withdrawals.
              </p>
              <div className="pillar-tag-list">
                <span className="p-tag">M-Pesa &amp; MoMo</span>
                <span className="p-tag">Scan to Pay</span>
                <span className="p-tag">Double-Entry Ledger</span>
              </div>
            </div>

            <div className="pillar-card highlight-pink">
              <div className="pillar-num-badge">03</div>
              <div className="pillar-icon-box">🪪</div>
              <h4 className="pillar-card-title">Oneova Global ID Verification</h4>
              <p className="pillar-card-desc">
                Carry a verifiable digital creator and business credential stored safely on your
                device, guarded against SIM recycling and unauthorized account takeovers.
              </p>
              <div className="pillar-tag-list">
                <span className="p-tag">Personal KYC</span>
                <span className="p-tag">Business KYB</span>
                <span className="p-tag">SIM-Recycle Guard</span>
              </div>
            </div>

            <div className="pillar-card">
              <div className="pillar-num-badge">04</div>
              <div className="pillar-icon-box">✦</div>
              <h4 className="pillar-card-title">Ova AI &amp; Live Human Support</h4>
              <p className="pillar-card-desc">
                Real-time AI troubleshooting over encrypted voice or help desk—backed by instant
                human admin escalation so you never get stuck without answers.
              </p>
              <div className="pillar-tag-list">
                <span className="p-tag">Live Data Fixes</span>
                <span className="p-tag">In-Place Translate</span>
                <span className="p-tag">Human Handoff</span>
              </div>
            </div>
          </div>
        </div>

        {/* Creator Bill of Rights */}
        <div className="about-trust-manifesto-card">
          <div className="trust-manifesto-left">
            <span className="manifesto-tag">CREATOR SOVEREIGNTY</span>
            <h3 className="manifesto-title">The Oneova Creator Ownership Charter</h3>
            <p className="manifesto-text">
              Your audience, your products, your sounds, and your earnings belong to you—protected
              by transparent rules written in plain language and enforced equally for everyone.
            </p>
            <ul className="manifesto-points">
              <li>
                <span className="m-icon">🛡️</span>
                <span>
                  <strong>Audio &amp; Remix Attribution:</strong> Original sounds and Remixes keep
                  your credit and attribution link intact across every share.
                </span>
              </li>
              <li>
                <span className="m-icon">🔒</span>
                <span>
                  <strong>Zero Personal Data Sales:</strong> We never sell user data, phone
                  contacts, or private conversations.
                </span>
              </li>
              <li>
                <span className="m-icon">⚖️</span>
                <span>
                  <strong>African &amp; Global Compliance:</strong> Engineered for ODPC (Kenya),
                  NDPA (Nigeria), POPIA (South Africa), AfCFTA Digital Trade, GDPR, and transparent
                  commercial disclosures.
                </span>
              </li>
            </ul>
          </div>

          <div className="trust-manifesto-right">
            <div className="guarantee-box">
              <span className="guarantee-icon">🌍</span>
              <span className="guarantee-title">Start Monetizing Today</span>
              <span className="guarantee-desc">
                Open your Oneova 3D Shop, verify your Global ID, and connect mobile-money payouts.
              </span>
              <button type="button" className="btn-primary guarantee-btn" onClick={onOpenDownload}>
                Install Oneova App
              </button>
            </div>
          </div>
        </div>

        {/* Bottom CTA */}
        <div className="about-bottom-cta">
          <div className="about-bottom-cta-inner">
            <h3>Built for Creators Across Africa &amp; Everywhere</h3>
            <p>Explore our documentation or install Oneova on mobile, Mac, or Windows.</p>
            <div className="cta-btn-wrap">
              <button type="button" className="btn-primary" onClick={onOpenDownload}>
                <span>Get Oneova App</span>
              </button>
              <button
                type="button"
                className="btn-secondary"
                onClick={() => onSelectDoc('wallet-biz-commerce')}
              >
                <span>Read Wallet &amp; Shops Guide</span>
                <span className="btn-arrow">→</span>
              </button>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
