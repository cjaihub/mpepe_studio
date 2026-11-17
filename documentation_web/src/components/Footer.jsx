import React from 'react';

export default function Footer({
  onSelectDoc,
  onOpenDownload,
  onOpenPolicy,
  onOpenOvaAssistant,
  isLiveConnected = false,
}) {
  const handlePolicyClick = (tab, fallbackUrl) => {
    if (onOpenPolicy) {
      onOpenPolicy(tab);
    } else {
      window.open(fallbackUrl, '_blank');
    }
  };

  return (
    <footer className="site-footer">
      <div className="footer-container">
        <div className="footer-cta-card">
          <div className="footer-cta-content">
            <div className="footer-cta-badge">
              <span className="cta-dot-pulse" />
              <span>AFRICA-FIRST CREATOR ECONOMY</span>
            </div>
            <h2 className="footer-cta-title">
              Ready to Launch Your 3D Shop, Wallet &amp; Global ID?
            </h2>
            <p className="footer-cta-desc">
              Monetize your creativity with M-Pesa &amp; MoMo payouts, interactive 3D showrooms,
              Live Commerce gifts, verified identity credentials, and live human support.
            </p>
          </div>
          <div className="footer-cta-actions">
            <button type="button" className="btn-primary footer-btn-main" onClick={onOpenDownload}>
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
                <polyline points="7 10 12 15 17 10" />
                <line x1="12" y1="15" x2="12" y2="3" />
              </svg>
              <span>Get Oneova Free</span>
            </button>
            <button
              type="button"
              className="btn-secondary footer-btn-alt"
              onClick={() => onSelectDoc('policy-community-guidelines')}
            >
              <span>Read Rules &amp; Legal Charter</span>
              <span className="btn-arrow">→</span>
            </button>
          </div>
        </div>

        <div className="footer-top">
          <div className="footer-brand-col">
            <div className="footer-brand-identity">
              <div className="footer-logo-ring">
                <img src="/assets/images/oneova_logo.jpg" alt="Oneova Logo" className="footer-logo-img" />
              </div>
              <div className="footer-brand-meta">
                <span className="footer-brand-name">ONEOVA</span>
                <span className="footer-brand-sub">Is the reason you matter.</span>
              </div>
            </div>
            <p className="footer-brand-bio">
              Oneova Technologies Inc. powers Africa&apos;s creator economy with Oneova 3D Shops,
              Oneova Wallet &amp; Mobile Money payouts, Oneova Global ID, Live Commerce, and
              transparent continental &amp; global compliance.
            </p>

            <div className="footer-status-pill">
              <span className="status-live-dot" />
              <span>
                {isLiveConnected
                  ? 'Live Synced with Oneova App · Support AI Active'
                  : 'All Systems Operational · Help Center Online'}
              </span>
            </div>

            <div className="footer-social-row">
              <a href="#help" className="footer-social-btn" aria-label="Oneova Help Center">
                ?
              </a>
              <a href="#desktop" className="footer-social-btn" aria-label="Oneova Desktop">
                ⌘
              </a>
              <a href="/legal.html" className="footer-social-btn" aria-label="Oneova Legal Hub">
                ⚖
              </a>
              {onOpenOvaAssistant && (
                <button
                  type="button"
                  className="footer-social-btn"
                  onClick={onOpenOvaAssistant}
                  aria-label="Open Live Oneova Support"
                >
                  ✦
                </button>
              )}
            </div>
          </div>

          <div className="footer-nav-col">
            <div className="footer-col-header">
              <span className="col-header-dot blue" />
              <span>Creator Economy</span>
            </div>
            <ul className="footer-nav-list">
              <li>
                <button type="button" className="footer-nav-item" onClick={() => onSelectDoc('biz-3d-shops')}>
                  <span className="item-icon">🛍️</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Oneova 3D Shops</span>
                    <span className="item-badge pink">COMMERCE</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
              <li>
                <button type="button" className="footer-nav-item" onClick={() => onSelectDoc('wallet-biz-commerce')}>
                  <span className="item-icon">💳</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Wallet &amp; Mobile Money</span>
                    <span className="item-badge pink">M-PESA · MOMO</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
              <li>
                <button type="button" className="footer-nav-item" onClick={() => onSelectDoc('global-id')}>
                  <span className="item-icon">🪪</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Oneova Global ID</span>
                    <span className="item-badge blue">VERIFIED ID</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
              <li>
                <button type="button" className="footer-nav-item" onClick={() => onSelectDoc('live-studio')}>
                  <span className="item-icon">📹</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Live Stage &amp; Fan Gifts</span>
                    <span className="item-badge blue">LIVE GIFTS</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
            </ul>
          </div>

          <div className="footer-nav-col">
            <div className="footer-col-header">
              <span className="col-header-dot pink" />
              <span>Safety, AI &amp; Support</span>
            </div>
            <ul className="footer-nav-list">
              <li>
                <button type="button" className="footer-nav-item" onClick={() => onSelectDoc('ova-ai-lab')}>
                  <span className="item-icon">✦</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Ova AI &amp; Desktop Agent</span>
                    <span className="item-badge pink">LIVE AI</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
              <li>
                <button type="button" className="footer-nav-item" onClick={() => handlePolicyClick('guidelines', '/guidelines.html')}>
                  <span className="item-icon">🛡️</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Community &amp; Anti-Scam Rules</span>
                    <span className="item-badge blue">3-STRIKE</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
              <li>
                <button type="button" className="footer-nav-item" onClick={() => handlePolicyClick('safety', '/child-safety.html')}>
                  <span className="item-icon">🧒</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Child &amp; Teen Safety (116)</span>
                    <span className="item-badge pink">ZERO CSAE</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
              <li>
                <button type="button" className="footer-nav-item" onClick={() => handlePolicyClick('biz', '/biz-policy.html')}>
                  <span className="item-icon">📦</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Biz &amp; Monetization Policy</span>
                    <span className="item-badge blue">ESCROW · KYC</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
            </ul>
          </div>

          <div className="footer-nav-col">
            <div className="footer-col-header">
              <span className="col-header-dot pink" />
              <span>Legal &amp; Global Laws</span>
            </div>
            <ul className="footer-nav-list">
              <li>
                <button type="button" className="footer-nav-item" onClick={() => handlePolicyClick('privacy', '/privacy.html')}>
                  <span className="item-icon">🔒</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Privacy Policy &amp; DPO</span>
                    <span className="item-badge blue">NO SALES</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
              <li>
                <button type="button" className="footer-nav-item" onClick={() => handlePolicyClick('terms', '/terms.html')}>
                  <span className="item-icon">📜</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Terms &amp; Creator Ownership</span>
                    <span className="item-badge pink">100% IP</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
              <li>
                <button type="button" className="footer-nav-item" onClick={() => handlePolicyClick('africa', '/legal.html')}>
                  <span className="item-icon">🌍</span>
                  <div className="item-text-wrap">
                    <span className="item-title">African &amp; Global Laws</span>
                    <span className="item-badge pink">ODPC · NDPA · POPIA</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
              <li>
                <button type="button" className="footer-nav-item" onClick={() => handlePolicyClick('law_enforcement', '/law-enforcement.html')}>
                  <span className="item-icon">🏛️</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Law Enforcement Portal</span>
                    <span className="item-badge blue">DUE PROCESS</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
            </ul>
          </div>
        </div>

        <div className="footer-bottom-bar">
          <div className="footer-bottom-left">
            <span className="copyright-text">© 2026 Oneova Technologies Inc. All rights reserved.</span>
            <div className="trust-cert-row">
              <span className="cert-pill">🌍 ODPC · NDPA · POPIA · GDPR · AfCFTA</span>
              <span className="cert-pill">🔒 Zero Personal Data Sales</span>
              <span className="cert-pill">⚡ Live Oneova App Sync</span>
            </div>
          </div>

          <div className="footer-bottom-links">
            <a href="/legal.html" target="_blank" rel="noreferrer" className="footer-sub-link" style={{ color: 'var(--brand-pink)' }}>
              Legal Hub ↗
            </a>
            <span className="footer-link-divider">•</span>
            <button type="button" className="footer-sub-link" onClick={() => handlePolicyClick('privacy', '/privacy.html')}>
              Privacy
            </button>
            <span className="footer-link-divider">•</span>
            <button type="button" className="footer-sub-link" onClick={() => handlePolicyClick('terms', '/terms.html')}>
              Terms
            </button>
            <span className="footer-link-divider">•</span>
            <button type="button" className="footer-sub-link" onClick={() => handlePolicyClick('safety', '/child-safety.html')}>
              Teen Safety
            </button>
            <span className="footer-link-divider">•</span>
            <button type="button" className="footer-sub-link" onClick={() => handlePolicyClick('deletion', '/deletion.html')}>
              Delete Data
            </button>
          </div>
        </div>
      </div>
    </footer>
  );
}
