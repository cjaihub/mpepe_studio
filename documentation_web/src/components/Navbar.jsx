import React from 'react';

export default function Navbar({
  theme = 'dark',
  onToggleTheme,
  onOpenDownload,
  onSearchFocus,
  onSelectDoc,
  onOpenPolicy,
  onOpenAdminCms,
  onOpenOvaAssistant,
  isAdmin = false,
}) {
  const [mobileMenuOpen, setMobileMenuOpen] = React.useState(false);

  return (
    <>
      {/* Top Futuristic Announcement & Status Banner */}
      <div className="top-vision-banner">
        <div className="vision-banner-content">
          <div className="vision-banner-brand-chip">
            <span className="vision-badge">ONEOVA</span>
            <span className="live-status-dot-pulse" aria-hidden="true"></span>
            <span className="vision-status-text">Live Sync Operational</span>
          </div>
          <span className="vision-text">
            Social media re-imagined from first principles. <strong>Is the reason you matter.</strong>
          </span>
          <div className="vision-banner-right-actions">
            <a href="#docs" className="vision-link" onClick={() => onSelectDoc('policy-community-guidelines')}>
              <span>Rules &amp; Global Regulations</span>
              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                <polyline points="9 18 15 12 9 6" />
              </svg>
            </a>
            {onOpenOvaAssistant && (
              <button
                type="button"
                className="vision-ask-ova-quick"
                onClick={onOpenOvaAssistant}
                title="Ask Ova AI Assistant"
              >
                <span>✨ Ask Ova</span>
              </button>
            )}
          </div>
        </div>
      </div>

      <header className="site-header" id="site-header">
        <div className="header-container">
          <a href="#showcase" className="brand-identity">
            <img src="/assets/images/oneova_logo.jpg" alt="Oneova Logo" className="brand-logo-img" />
            <div className="brand-text-wrap">
              <span className="brand-title">ONEOVA</span>
              <span className="brand-badge">Is the reason you matter.</span>
            </div>
          </a>

          {/* Desktop Navigation with Clear Non-Technical Labels */}
          <nav className="nav-menu" aria-label="Main Navigation">
            <a href="#features" className="nav-link">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2">
                <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2" />
              </svg>
              <span>Features</span>
            </a>

            <a href="#docs" className="nav-link" onClick={() => onSelectDoc('live-studio')}>
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2">
                <polygon points="23 7 16 12 23 17 23 7" />
                <rect x="1" y="5" width="15" height="14" rx="2" ry="2" />
              </svg>
              <span>Live &amp; Studio</span>
            </a>

            <a href="#docs" className="nav-link" onClick={() => onSelectDoc('wallet-biz-commerce')}>
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2">
                <rect width="20" height="14" x="2" y="5" rx="2" />
                <line x1="2" x2="22" y1="10" y2="10" />
              </svg>
              <span>Earnings &amp; M-Pesa</span>
            </a>

            <a
              href="#docs"
              className="nav-link nav-highlight-pink"
              onClick={() => onSelectDoc('policy-community-guidelines')}
            >
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2">
                <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
              </svg>
              <span>Community Rules</span>
              <span className="nav-mini-dot-pink" />
            </a>

            <button
              type="button"
              className="nav-link"
              onClick={() => onOpenPolicy && onOpenPolicy('africa')}
            >
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2">
                <circle cx="12" cy="12" r="10" />
                <line x1="2" y1="12" x2="22" y2="12" />
                <path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z" />
              </svg>
              <span>Global Laws</span>
            </button>
          </nav>

          <div className="header-actions">
            {/* Ask Ova Assistant Button */}
            {onOpenOvaAssistant && (
              <button
                type="button"
                className="header-ova-ai-btn"
                onClick={onOpenOvaAssistant}
                aria-label="Open Ova Assistant"
                title="Ask Ova AI about rules, features &amp; earnings"
              >
                <span className="ova-sparkle-icon">✨</span>
                <span className="ova-btn-text">Ask Ova</span>
                <span className="ova-btn-badge">AI</span>
              </button>
            )}

            {/* Dark / Light Mode Switcher */}
            <button
              type="button"
              className="theme-toggle-btn"
              onClick={onToggleTheme}
              aria-label={`Switch to ${theme === 'dark' ? 'Light' : 'Dark'} mode`}
              title={`Switch to ${theme === 'dark' ? 'Light' : 'Dark'} mode`}
            >
              {theme === 'dark' ? (
                <>
                  <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2">
                    <circle cx="12" cy="12" r="5" />
                    <line x1="12" y1="1" x2="12" y2="3" />
                    <line x1="12" y1="21" x2="12" y2="23" />
                    <line x1="4.22" y1="4.22" x2="5.64" y2="5.64" />
                    <line x1="18.36" y1="18.36" x2="19.78" y2="19.78" />
                    <line x1="1" y1="12" x2="3" y2="12" />
                    <line x1="21" y1="12" x2="23" y2="12" />
                    <line x1="4.22" y1="19.78" x2="5.64" y2="18.36" />
                    <line x1="18.36" y1="5.64" x2="19.78" y2="4.22" />
                  </svg>
                  <span className="theme-toggle-label">Light</span>
                </>
              ) : (
                <>
                  <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2">
                    <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z" />
                  </svg>
                  <span className="theme-toggle-label">Dark</span>
                </>
              )}
            </button>

            {/* Quick Search Shortcut */}
            <button
              type="button"
              className="search-trigger-btn"
              onClick={onSearchFocus}
              aria-label="Search Documentation"
            >
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                <circle cx="11" cy="11" r="8" />
                <path d="m21 21-4.35-4.35" />
              </svg>
              <span className="search-btn-label">Search</span>
              <kbd className="search-kbd">⌘K</kbd>
            </button>

            {/* Live Admin CMS Trigger — signed-in admins only; others use /admin or ⌘⇧E */}
            {onOpenAdminCms && isAdmin && (
              <button
                type="button"
                className="cms-nav-pill-btn"
                onClick={() => onOpenAdminCms()}
                title="Open Real-Time App + Web Admin CMS (⌘⇧E)"
              >
                <span>✎ {isAdmin ? 'Live CMS' : 'CMS'}</span>
              </button>
            )}

            {/* Main CTA */}
            <button type="button" className="btn-primary header-cta-btn" onClick={onOpenDownload}>
              <span className="cta-full-label">Get App</span>
              <span className="cta-short-label">Join</span>
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                <line x1="5" y1="12" x2="19" y2="12" />
                <polyline points="12 5 19 12 12 19" />
              </svg>
            </button>

            {/* Mobile Hamburger Toggle */}
            <button
              type="button"
              className="mobile-menu-toggle"
              onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
              aria-label="Toggle Navigation Menu"
            >
              {mobileMenuOpen ? (
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                  <line x1="18" y1="6" x2="6" y2="18" />
                  <line x1="6" y1="6" x2="18" y2="18" />
                </svg>
              ) : (
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2">
                  <line x1="3" y1="12" x2="21" y2="12" />
                  <line x1="3" y1="6" x2="21" y2="6" />
                  <line x1="3" y1="18" x2="21" y2="18" />
                </svg>
              )}
            </button>
          </div>
        </div>

        {/* Mobile Drawer */}
        {mobileMenuOpen && (
          <div className="mobile-nav-drawer">
            <div className="mobile-drawer-header">
              <div className="mobile-drawer-brand">
                <span className="mobile-drawer-logo">ONEOVA</span>
                <span className="mobile-drawer-slogan">Is the reason you matter.</span>
              </div>
              <button type="button" className="mobile-theme-pill" onClick={onToggleTheme}>
                {theme === 'dark' ? '☀️ Light' : '🌙 Dark'}
              </button>
            </div>

            <div className="mobile-drawer-links">
              {onOpenOvaAssistant && (
                <button
                  type="button"
                  className="mobile-nav-card highlight-pink"
                  style={{ width: '100%', textAlign: 'left', cursor: 'pointer' }}
                  onClick={() => {
                    setMobileMenuOpen(false);
                    onOpenOvaAssistant();
                  }}
                >
                  <span className="mobile-card-icon pink">✨</span>
                  <div className="mobile-card-text">
                    <span className="mobile-card-title">Ask Ova AI Assistant</span>
                    <span className="mobile-card-sub">Instant plain-language answers to all 18 topics</span>
                  </div>
                  <span className="mobile-card-arrow">→</span>
                </button>
              )}

              <a
                href="#features"
                className="mobile-nav-card"
                onClick={() => setMobileMenuOpen(false)}
              >
                <span className="mobile-card-icon blue">⚡</span>
                <div className="mobile-card-text">
                  <span className="mobile-card-title">Platform Features</span>
                  <span className="mobile-card-sub">Live Studio, GLSL Looks, AI Lab &amp; Wallet</span>
                </div>
                <span className="mobile-card-arrow">→</span>
              </a>

              <a
                href="#docs"
                className="mobile-nav-card highlight-pink"
                onClick={() => {
                  onSelectDoc('policy-community-guidelines');
                  setMobileMenuOpen(false);
                }}
              >
                <span className="mobile-card-icon pink">🛡️</span>
                <div className="mobile-card-text">
                  <span className="mobile-card-title">Community Rules &amp; Safety</span>
                  <span className="mobile-card-sub">Anti-scam shields, 116 Teen Safety &amp; Law</span>
                </div>
                <span className="mobile-card-arrow">→</span>
              </a>

              <a
                href="#docs"
                className="mobile-nav-card"
                onClick={() => {
                  onSelectDoc('wallet-biz-commerce');
                  setMobileMenuOpen(false);
                }}
              >
                <span className="mobile-card-icon blue">💳</span>
                <div className="mobile-card-text">
                  <span className="mobile-card-title">Earnings, M-Pesa &amp; Biz</span>
                  <span className="mobile-card-sub">M-Pesa, MTN MoMo &amp; .oneovapack</span>
                </div>
                <span className="mobile-card-arrow">→</span>
              </a>

              {onOpenAdminCms && isAdmin && (
                <button
                  type="button"
                  className="mobile-nav-card highlight-pink"
                  style={{ width: '100%', textAlign: 'left', cursor: 'pointer' }}
                  onClick={() => {
                    setMobileMenuOpen(false);
                    onOpenAdminCms();
                  }}
                >
                  <span className="mobile-card-icon pink">✎</span>
                  <div className="mobile-card-text">
                    <span className="mobile-card-title">Admin Live CMS</span>
                    <span className="mobile-card-sub">Real-time App + Website sync editor</span>
                  </div>
                  <span className="mobile-card-arrow">→</span>
                </button>
              )}
            </div>

            <button
              type="button"
              className="btn-primary mobile-drawer-btn"
              onClick={() => {
                onOpenDownload();
                setMobileMenuOpen(false);
              }}
            >
              <span>Join Oneova Free</span>
            </button>
          </div>
        )}
      </header>
    </>
  );
}
