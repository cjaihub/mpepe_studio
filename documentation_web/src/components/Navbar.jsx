import React from 'react';

export default function Navbar({
  theme = 'dark',
  onToggleTheme,
  onOpenDownload,
  onSearchFocus,
  onSelectDoc,
  onOpenPolicy,
  onOpenOvaAssistant,
}) {
  const [mobileMenuOpen, setMobileMenuOpen] = React.useState(false);

  return (
    <>
      <div className="top-vision-banner">
        <div className="vision-banner-content">
          <div className="vision-banner-brand-chip">
            <span className="vision-badge">ONEOVA PORTAL</span>
            <span className="live-status-dot-pulse" aria-hidden="true" />
            <span className="vision-status-text">Help Center · Live Docs</span>
          </div>
          <span className="vision-text">
            Everything you need for 4K Live, Studio Editing, Ova AI &amp; Mobile Money—
            <strong>all in plain language.</strong>
          </span>
          <div className="vision-banner-right-actions">
            <a href="#help" className="vision-link">
              <span>Help Center</span>
              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                <polyline points="9 18 15 12 9 6" />
              </svg>
            </a>
          </div>
        </div>
      </div>

      <header className="site-header" id="site-header">
        <div className="header-container">
          <a href="#help" className="brand-identity">
            <img src="/assets/images/oneova_logo.jpg" alt="Oneova Logo" className="brand-logo-img" />
            <div className="brand-text-wrap">
              <span className="brand-title">ONEOVA</span>
              <span className="brand-badge">Help Center &amp; Guide</span>
            </div>
          </a>

          <nav className="nav-menu" aria-label="Main Navigation">
            <a href="#help" className="nav-link">
              <span>Help Center</span>
            </a>

            <a
              href="#docs"
              className="nav-link"
              onClick={() => onSelectDoc?.('live-studio')}
            >
              <span>User Guide</span>
            </a>

            <a href="#features" className="nav-link">
              <span>Features</span>
            </a>

            <a href="#desktop" className="nav-link">
              <span>Mac &amp; Windows</span>
            </a>

            <button
              type="button"
              className="nav-link nav-highlight-pink"
              onClick={() => onOpenPolicy?.('guidelines')}
            >
              <span>Safety &amp; Legal</span>
              <span className="nav-mini-dot-pink" />
            </button>
          </nav>

          <div className="header-actions">
            <button
              type="button"
              className="search-trigger-btn"
              onClick={onSearchFocus}
              aria-label="Search User Guide"
            >
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                <circle cx="11" cy="11" r="8" />
                <path d="m21 21-4.35-4.35" />
              </svg>
              <span className="search-btn-label">Search</span>
              <kbd className="search-kbd">⌘K</kbd>
            </button>

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

            {onOpenOvaAssistant && (
              <button
                type="button"
                className="header-ova-ai-btn"
                onClick={onOpenOvaAssistant}
                aria-label="Open Oneova Support"
              >
                <span className="ova-sparkle-icon">✦</span>
                <span className="ova-btn-text">Support</span>
              </button>
            )}

            <button type="button" className="btn-primary header-cta-btn" onClick={onOpenDownload}>
              <span className="cta-full-label">Get App</span>
              <span className="cta-short-label">App</span>
            </button>

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

        {mobileMenuOpen && (
          <div className="mobile-nav-drawer">
            <div className="mobile-drawer-header">
              <div className="mobile-drawer-brand">
                <span className="mobile-drawer-logo">ONEOVA</span>
                <span className="mobile-drawer-slogan">Help Center &amp; Creator Portal</span>
              </div>
              <button type="button" className="mobile-theme-pill" onClick={onToggleTheme}>
                {theme === 'dark' ? '☀️ Light' : '🌙 Dark'}
              </button>
            </div>

            <div className="mobile-drawer-links">
              <a
                href="#help"
                className="mobile-nav-card highlight-pink"
                onClick={() => setMobileMenuOpen(false)}
              >
                <span className="mobile-card-icon pink">?</span>
                <div className="mobile-card-text">
                  <span className="mobile-card-title">Help Center &amp; FAQs</span>
                  <span className="mobile-card-sub">Search answers or submit a support ticket</span>
                </div>
                <span className="mobile-card-arrow">→</span>
              </a>

              <a
                href="#docs"
                className="mobile-nav-card"
                onClick={() => {
                  onSelectDoc?.('live-studio');
                  setMobileMenuOpen(false);
                }}
              >
                <span className="mobile-card-icon blue">📖</span>
                <div className="mobile-card-text">
                  <span className="mobile-card-title">Advanced User Guide</span>
                  <span className="mobile-card-sub">Step-by-step guides &amp; Table of Contents</span>
                </div>
                <span className="mobile-card-arrow">→</span>
              </a>

              <a
                href="#desktop"
                className="mobile-nav-card"
                onClick={() => setMobileMenuOpen(false)}
              >
                <span className="mobile-card-icon blue">💻</span>
                <div className="mobile-card-text">
                  <span className="mobile-card-title">Mac &amp; Windows Desktop Agent</span>
                  <span className="mobile-card-sub">Studio automation, hotkeys &amp; installers</span>
                </div>
                <span className="mobile-card-arrow">→</span>
              </a>

              <button
                type="button"
                className="mobile-nav-card highlight-pink"
                style={{ width: '100%', textAlign: 'left', cursor: 'pointer' }}
                onClick={() => {
                  setMobileMenuOpen(false);
                  onOpenPolicy?.('guidelines');
                }}
              >
                <span className="mobile-card-icon pink">🛡️</span>
                <div className="mobile-card-text">
                  <span className="mobile-card-title">Safety, Privacy &amp; Legal</span>
                  <span className="mobile-card-sub">Zero data sales, 116 Teen Safety &amp; Terms</span>
                </div>
                <span className="mobile-card-arrow">→</span>
              </button>

              {onOpenOvaAssistant && (
                <button
                  type="button"
                  className="mobile-nav-card"
                  style={{ width: '100%', textAlign: 'left', cursor: 'pointer' }}
                  onClick={() => {
                    setMobileMenuOpen(false);
                    onOpenOvaAssistant();
                  }}
                >
                  <span className="mobile-card-icon blue">✦</span>
                  <div className="mobile-card-text">
                    <span className="mobile-card-title">Oneova Support Assistant</span>
                    <span className="mobile-card-sub">Instant guided troubleshooting</span>
                  </div>
                  <span className="mobile-card-arrow">→</span>
                </button>
              )}
            </div>

            <button
              type="button"
              className="btn-primary mobile-drawer-btn"
              onClick={() => {
                onOpenDownload?.();
                setMobileMenuOpen(false);
              }}
            >
              <span>Download Oneova</span>
            </button>
          </div>
        )}
      </header>
    </>
  );
}
