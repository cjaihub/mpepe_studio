import React from 'react';
import PhoneMockup from './PhoneMockup';

export default function Hero({
  theme = 'dark',
  showcase,
  onOpenDownload,
  onOpenHelp,
  onOpenOvaAssistant,
  onSelectDoc,
}) {
  return (
    <section className="hero-section" id="showcase">
      <div className="hero-grid">
        <div className="hero-content">
          <div className="status-pill">
            <span className="status-dot-pulse" />
            <span>AFRICA&apos;S CREATOR ECONOMY · MONETIZE · SELL · VERIFY</span>
          </div>

          <h1 className="hero-title">
            Powering Africa&apos;s Creator Economy.{' '}
            <span className="hero-title-gradient">Monetize Every Moment.</span>
          </h1>

          <p className="hero-subtitle">
            Built so African creators, merchants, and communities earn real income directly from
            what they share. Launch verified <strong>Oneova 3D Shops</strong>, accept local
            currencies and mobile money in <strong>Oneova Wallet</strong>, carry one trusted{' '}
            <strong>Oneova Global ID</strong>, and get live help whenever you need it.
          </p>

          <div className="hero-cta-group">
            <a
              href="#help"
              className="app-store-btn"
              onClick={(e) => {
                if (onOpenHelp) {
                  e.preventDefault();
                  onOpenHelp();
                }
              }}
              style={{ textDecoration: 'none' }}
            >
              <span className="store-icon">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.3">
                  <circle cx="12" cy="12" r="10" />
                  <path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3" />
                  <line x1="12" y1="17" x2="12.01" y2="17" />
                </svg>
              </span>
              <div className="store-text-wrap">
                <span className="store-label">Guided Portal</span>
                <span className="store-name">Help Center</span>
              </div>
            </a>

            <button
              type="button"
              className="app-store-btn android"
              onClick={onOpenDownload}
              aria-label="Download Oneova App"
            >
              <span className="store-icon">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.3">
                  <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
                  <polyline points="7 10 12 15 17 10" />
                  <line x1="12" y1="15" x2="12" y2="3" />
                </svg>
              </span>
              <div className="store-text-wrap">
                <span className="store-label">Mobile &amp; Desktop</span>
                <span className="store-name">Get Oneova</span>
              </div>
            </button>

            {onOpenOvaAssistant && (
              <button
                type="button"
                className="qr-trigger-btn"
                onClick={onOpenOvaAssistant}
              >
                <span style={{ color: 'var(--brand-pink)' }}>✦</span>
                <span>Ask Live Support AI</span>
              </button>
            )}
          </div>

          <div className="hero-trust-bar hero-trust-4">
            <div className="trust-item">
              <span className="trust-stat"><span className="pink">01</span> SHOPS</span>
              <span className="trust-desc">3D Showrooms &amp; Live Goods</span>
            </div>
            <div className="trust-item">
              <span className="trust-stat"><span className="blue">02</span> WALLET</span>
              <span className="trust-desc">M-Pesa, MoMo &amp; Local Cashouts</span>
            </div>
            <div className="trust-item">
              <span className="trust-stat"><span className="pink">03</span> GLOBAL ID</span>
              <span className="trust-desc">Verified Personal &amp; Business ID</span>
            </div>
            <div className="trust-item">
              <span className="trust-stat"><span className="blue">04</span> OVA AI</span>
              <span className="trust-desc">Live Diagnostics &amp; Desktop Agent</span>
            </div>
          </div>
        </div>

        <PhoneMockup
          theme={theme}
          showcase={showcase}
          onOpenOvaAssistant={onOpenOvaAssistant}
          onSelectDoc={onSelectDoc}
        />
      </div>
    </section>
  );
}
