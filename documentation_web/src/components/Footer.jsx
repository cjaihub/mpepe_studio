import React from 'react';

export default function Footer({ onSelectDoc, onOpenDownload, onOpenPolicy }) {
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
              <span className="cta-dot-pulse"></span>
              <span>CREATOR REVOLUTION · MOBILE FIRST</span>
            </div>
            <h2 className="footer-cta-title">
              Ready to Broadcast & Edit in 4K?
            </h2>
            <p className="footer-cta-desc">
              Transform your mobile workflow with ultra-low latency live streams, drop-in creator rooms, AI rotoscoping, and 1-tap multi-platform publishing.
            </p>
          </div>
          <div className="footer-cta-actions">
            <button className="btn-primary footer-btn-main" onClick={onOpenDownload}>
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path><polyline points="7 10 12 15 17 10"></polyline><line x1="12" y1="15" x2="12" y2="3"></line></svg>
              <span>Get Oneova Free</span>
            </button>
            <button className="btn-secondary footer-btn-alt" onClick={() => onSelectDoc('live-studio')}>
              <span>Explore Live Studio</span>
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
              The next-generation mobile creator ecosystem. Unifying 4K interactive live broadcasting, drop-in collaboration rooms, frame-accurate mobile editing, and universal social distribution.
            </p>

            {/* Live Operational Status */}
            <div className="footer-status-pill">
              <span className="status-live-dot"></span>
              <span>All Systems Operational · 4K Studio Online</span>
            </div>

            {/* Social Icons */}
            <div className="footer-social-row">
              <a href="https://tiktok.com" target="_blank" rel="noreferrer" className="footer-social-btn" aria-label="Oneova on TikTok">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M19.59 6.69a4.83 4.83 0 0 1-3.77-4.25V2h-3.45v13.67a2.89 2.89 0 0 1-2.88 2.89 2.89 2.89 0 0 1-2.89-2.89 2.89 2.89 0 0 1 2.89-2.89c.32 0 .62.06.9.16V9.4a6.34 6.34 0 0 0-.9-.06 6.35 6.35 0 0 0-6.35 6.35 6.35 6.35 0 0 0 6.35 6.35 6.35 6.35 0 0 0 6.35-6.35V8.51c1.3.93 2.87 1.48 4.58 1.49V6.69z"/></svg>
              </a>
              <a href="https://instagram.com" target="_blank" rel="noreferrer" className="footer-social-btn" aria-label="Oneova on Instagram">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><rect width="20" height="20" x="2" y="2" rx="5" ry="5"></rect><path d="M16 11.37A4 4 0 1 1 12.63 8 4 4 0 0 1 16 11.37z"></path><line x1="17.5" x2="17.51" y1="6.5" y2="6.5"></line></svg>
              </a>
              <a href="https://youtube.com" target="_blank" rel="noreferrer" className="footer-social-btn" aria-label="Oneova on YouTube">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z"/></svg>
              </a>
              <a href="https://x.com" target="_blank" rel="noreferrer" className="footer-social-btn" aria-label="Oneova on X">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"/></svg>
              </a>
            </div>
          </div>

          {/* Col 2: Studio & Creation */}
          <div className="footer-nav-col">
            <div className="footer-col-header">
              <span className="col-header-dot blue"></span>
              <span>Studio & Creation</span>
            </div>
            <ul className="footer-nav-list">
              <li>
                <button className="footer-nav-item" onClick={() => onSelectDoc('live-studio')}>
                  <span className="item-icon">📹</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Live Broadcast Studio</span>
                    <span className="item-badge pink">4K LIVE</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
              <li>
                <button className="footer-nav-item" onClick={() => onSelectDoc('creator-rooms')}>
                  <span className="item-icon">🎙️</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Interactive Creator Rooms</span>
                    <span className="item-badge blue">STAGE</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
              <li>
                <button className="footer-nav-item" onClick={() => onSelectDoc('mobile-editor')}>
                  <span className="item-icon">✂️</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Pro Mobile Editor</span>
                    <span className="item-badge pink">AI MASK</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
              <li>
                <button className="footer-nav-item" onClick={() => onSelectDoc('reels-feed')}>
                  <span className="item-icon">⚡</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Short-Form Reels Feed</span>
                    <span className="item-badge blue">60 FPS</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
            </ul>
          </div>

          {/* Col 3: Distribution & Safety */}
          <div className="footer-nav-col">
            <div className="footer-col-header">
              <span className="col-header-dot pink"></span>
              <span>Distribution & Safety</span>
            </div>
            <ul className="footer-nav-list">
              <li>
                <button className="footer-nav-item" onClick={() => onSelectDoc('universal-sharing')}>
                  <span className="item-icon">🌐</span>
                  <div className="item-text-wrap">
                    <span className="item-title">1-Tap Universal Sharing</span>
                    <span className="item-badge pink">HOT</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
              <li>
                <button className="footer-nav-item" onClick={() => handlePolicyClick('guidelines', '/privacy.html')}>
                  <span className="item-icon">🛡️</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Community Guidelines & Rules</span>
                    <span className="item-badge blue">TIKTOK STD</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
              <li>
                <button className="footer-nav-item" onClick={onOpenDownload}>
                  <span className="item-icon">🍏</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Oneova for Apple iOS</span>
                    <span className="item-badge">APP STORE</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
              <li>
                <button className="footer-nav-item" onClick={onOpenDownload}>
                  <span className="item-icon">🤖</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Oneova for Android</span>
                    <span className="item-badge">GOOGLE PLAY</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
            </ul>
          </div>

          {/* Col 4: Legal & Trust */}
          <div className="footer-nav-col">
            <div className="footer-col-header">
              <span className="col-header-dot pink"></span>
              <span>Legal & Trust</span>
            </div>
            <ul className="footer-nav-list">
              <li>
                <button className="footer-nav-item" onClick={() => handlePolicyClick('privacy', '/privacy.html')}>
                  <span className="item-icon">🔒</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Privacy Policy</span>
                    <span className="item-badge blue">ENCRYPTED</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
              <li>
                <button className="footer-nav-item" onClick={() => handlePolicyClick('terms', '/terms.html')}>
                  <span className="item-icon">📜</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Terms of Service</span>
                    <span className="item-badge pink">CREATOR RIGHTS</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
              <li>
                <button className="footer-nav-item" onClick={() => handlePolicyClick('deletion', '/deletion.html')}>
                  <span className="item-icon">🗑️</span>
                  <div className="item-text-wrap">
                    <span className="item-title">Data Deletion Protocol</span>
                    <span className="item-badge">SELF-SERVE</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
              <li>
                <button className="footer-nav-item" onClick={() => handlePolicyClick('guidelines', '/privacy.html')}>
                  <span className="item-icon">⚖️</span>
                  <div className="item-text-wrap">
                    <span className="item-title">FTC Commercial Disclosures</span>
                    <span className="item-badge blue">COMPLIANT</span>
                  </div>
                  <span className="item-arrow">→</span>
                </button>
              </li>
            </ul>
          </div>
        </div>

        {/* Footer Bottom Bar with Trust Badges */}
        <div className="footer-bottom-bar">
          <div className="footer-bottom-left">
            <span className="copyright-text">© 2026 Oneova Technologies Inc. All rights reserved.</span>
            <div className="trust-cert-row">
              <span className="cert-pill">🛡️ TikTok Standards Aligned</span>
              <span className="cert-pill">🔒 End-to-End Media Privacy</span>
              <span className="cert-pill">⚖️ FTC Compliant</span>
            </div>
          </div>

          <div className="footer-bottom-links">
            <a href="#about" className="footer-sub-link" style={{ color: 'var(--brand-pink)' }}>About Us</a>
            <span className="footer-link-divider">•</span>
            <button className="footer-sub-link" onClick={() => handlePolicyClick('privacy', '/privacy.html')}>Privacy</button>
            <span className="footer-link-divider">•</span>
            <button className="footer-sub-link" onClick={() => handlePolicyClick('terms', '/terms.html')}>Terms</button>
            <span className="footer-link-divider">•</span>
            <button className="footer-sub-link" onClick={() => handlePolicyClick('guidelines', '/privacy.html')}>Guidelines</button>
            <span className="footer-link-divider">•</span>
            <button className="footer-sub-link" onClick={() => handlePolicyClick('deletion', '/deletion.html')}>Data Deletion</button>
          </div>
        </div>
      </div>
    </footer>
  );
}
