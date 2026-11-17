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
        {/* Pre-Footer Floating CTA Card */}
        <div className="footer-cta-card">
          <div className="footer-cta-content">
            <div className="footer-cta-badge">
              <span className="cta-dot-pulse" />
              <span>AFRICA-FIRST · GLOBAL CREATOR STUDIO</span>
            </div>
            <h2 className="footer-cta-title">Ready to Broadcast, Grade & Monetize in 4K?</h2>
            <p className="footer-cta-desc">
              Experience real-time WebRTC GPU Looks, interactive Creator Rooms, natural-language AI
              rotoscoping, M-Pesa/MoMo & global payouts, and ironclad creator IP protection.
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
              <span>Read Rules & Legal Charter</span>
              <span className="btn-arrow">→</span>
            </button>
          </div>
        </div>

        {/* Main Footer Links Grid */}
        <div className="footer-top">
          {/* Col 1: Brand Info */}
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
              Oneova Technologies Inc. unifies 4K interactive live broadcasting, GLSL color science,
              frame-accurate mobile editing, local-currency creator payouts, and transparent African
              & global data governance.
            </p>

            {/* Live Operational Status */}
            <div className="footer-status-pill">
              <span className="status-live-dot" />
              <span>
                {isLiveConnected
                  ? 'Live Synced with Oneova App · Help Center Online'
                  : 'All Systems Operational · Offline-Ready Guides Active'}
              </span>
            </div>

            {/* Social Icons */}
            <div className="footer-social-row">
              <a href="https://tiktok.com" target="_blank" rel="noreferrer" className="footer-social-btn" aria-label="Oneova on TikTok">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M19.59 6.69a4.83 4.83 0 0 1-3.77-4.25V2h-3.45v13.67a2.89 2.89 0 0 1-2.88 2.89 2.89 2.89 0 0 1-2.89-2.89 2.89 2.89 0 0 1 2.89-2.89c.32 0 .62.06.9.16V9.4a6.34 6.34 0 0 0-.9-.06 6.35 6.35 0 0 0-6.35 6.35 6.35 6.35 0 0 0 6.35 6.35 6.35 6.35 0 0 0 6.35-6.35V8.51c1.3.93 2.87 1.48 4.58 1.49V6.69z" />
                </svg>
              </a>
              <a href="https://instagram.com" target="_blank" rel="noreferrer" className="footer-social-btn" aria-label="Oneova on Instagram">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <rect width="20" height="20" x="2" y="2" rx="5" ry="5" />
                  <path d="M16 11.37A4 4 0 1 1 12.63 8 4 4 0 0 1 16 11.37z" />
                  <line x1="17.5" x2="17.51" y1="6.5" y2="6.5" />
                </svg>
              </a>
              <a href="https://youtube.com" target="_blank" rel="noreferrer" className="footer-social-btn" aria-label="Oneova on YouTube">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z" />
                </svg>
              </a>
              <a href="https://x.com" target="_blank" rel="noreferrer" className="footer-social-btn" aria-label="Oneova on X">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
                </svg>
              </a>
            </div>
          </div>

          {/* Col 2: Studio, AI & Hardware */}
          <div className="footer-nav-col">
            <div className="footer-col-header">
              <span className="col-header-dot blue" />
              <span>Studio, AI & Hardware</span>
            </div>
            <ul className="footer-nav-list">
              <li>
                <button type="button" className="footer-nav-item" onClick={() => onSelectDoc('live-studio')}>
                  <span className="item-icon">📹</span>
                  <div className="item-text-wrap">
                    <span className="item-title">4K Live Studio & PK</span>
                    <span className="item-badge pink">4K LIVE</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
              <li>
                <button type="button" className="footer-nav-item" onClick={() => onSelectDoc('looks-color-engine')}>
                  <span className="item-icon">🎨</span>
                  <div className="item-text-wrap">
                    <span className="item-title">GLSL Looks & Scope Sentinel</span>
                    <span className="item-badge pink">AI COLOR</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
              <li>
                <button type="button" className="footer-nav-item" onClick={() => onSelectDoc('mobile-editor')}>
                  <span className="item-icon">✂️</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Pro Editor & AI Rotoscoping</span>
                    <span className="item-badge blue">SAM 2</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
              <li>
                <button type="button" className="footer-nav-item" onClick={() => onSelectDoc('device-thermal-advisor')}>
                  <span className="item-icon">🧊</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Device Advisor & Thermal Shield</span>
                    <span className="item-badge blue">ADPF</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
            </ul>
          </div>

          {/* Col 3: Commerce, Safety & Youth */}
          <div className="footer-nav-col">
            <div className="footer-col-header">
              <span className="col-header-dot pink" />
              <span>Wallet, Biz & Safety</span>
            </div>
            <ul className="footer-nav-list">
              <li>
                <button type="button" className="footer-nav-item" onClick={() => onSelectDoc('wallet-biz-commerce')}>
                  <span className="item-icon">💳</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Wallet, M-Pesa/MoMo & Biz</span>
                    <span className="item-badge pink">FINTECH</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
              <li>
                <button type="button" className="footer-nav-item" onClick={() => handlePolicyClick('guidelines', '/guidelines.html')}>
                  <span className="item-icon">🛡️</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Community & Anti-Scam Rules</span>
                    <span className="item-badge blue">3-STRIKE</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
              <li>
                <button type="button" className="footer-nav-item" onClick={() => handlePolicyClick('safety', '/child-safety.html')}>
                  <span className="item-icon">🧒</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Child & Teen Safety (116)</span>
                    <span className="item-badge pink">ZERO CSAE</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
              <li>
                <button type="button" className="footer-nav-item" onClick={() => handlePolicyClick('biz', '/biz-policy.html')}>
                  <span className="item-icon">🛍️</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Biz & Monetization Policy</span>
                    <span className="item-badge blue">KYC / AML</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
            </ul>
          </div>

          {/* Col 4: Legal & Regulations */}
          <div className="footer-nav-col">
            <div className="footer-col-header">
              <span className="col-header-dot pink" />
              <span>Legal & Global Regulations</span>
            </div>
            <ul className="footer-nav-list">
              <li>
                <button type="button" className="footer-nav-item" onClick={() => handlePolicyClick('privacy', '/privacy.html')}>
                  <span className="item-icon">🔒</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Privacy Policy & DPO</span>
                    <span className="item-badge blue">NO SALES</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
              <li>
                <button type="button" className="footer-nav-item" onClick={() => handlePolicyClick('terms', '/terms.html')}>
                  <span className="item-icon">📜</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Terms of Service</span>
                    <span className="item-badge pink">100% IP</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
              <li>
                <button type="button" className="footer-nav-item" onClick={() => handlePolicyClick('africa', '/legal.html')}>
                  <span className="item-icon">🌍</span>
                  <div className="item-text-wrap">
                    <span className="item-title">African & Global Laws</span>
                    <span className="item-badge pink">ODPC · NDPA · POPIA</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
              <li>
                <button type="button" className="footer-nav-item" onClick={() => handlePolicyClick('law_enforcement', '/law-enforcement.html')}>
                  <span className="item-icon">🏛️</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Law Enforcement &amp; Deletion</span>
                    <span className="item-badge">DUE PROCESS</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
              {onOpenOvaAssistant && (
                <li>
                  <button type="button" className="footer-nav-item highlight-pink" onClick={onOpenOvaAssistant}>
                    <span className="item-icon">✨</span>
                    <div className="item-text-wrap">
                      <span className="item-title">Ask Ova AI Assistant</span>
                      <span className="item-badge pink">18 SKILLS</span>
                    </div>
                    <span className="item-arrow">→</span>
                  </button>
                </li>
              )}
            </ul>
          </div>
        </div>

        {/* Footer Bottom Bar */}
        <div className="footer-bottom-bar">
          <div className="footer-bottom-left">
            <span className="copyright-text">© 2026 Oneova Technologies Inc. All rights reserved.</span>
            <div className="trust-cert-row">
              <span className="cert-pill">🌍 ODPC · NDPA · POPIA · GDPR · DSA</span>
              <span className="cert-pill">🔒 Zero Personal Data Sales</span>
              <span className="cert-pill">⚡ Real-Time App ↔ Web Sync</span>
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
