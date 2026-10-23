import React from 'react';

export default function Navbar({
  theme = 'dark',
  onToggleTheme,
  onOpenDownload,
  onSearchFocus,
  onSelectDoc
}) {
  const [mobileMenuOpen, setMobileMenuOpen] = React.useState(false);

  return (
    <>
      {/* Top Futuristic Announcement Banner */}
      <div className="top-vision-banner">
        <div className="vision-banner-content">
          <span className="vision-badge">ONEOVA</span>
          <span className="vision-text">
            Social media re-imagined from first principles. <strong>Is the reason you matter.</strong>
          </span>
          <a href="#about" className="vision-link">
            <span>Our Story</span>
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><polyline points="9 18 15 12 9 6"/></svg>
          </a>
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

          {/* Desktop Navigation with Icons and Concise Suitable Names */}
          <nav className="nav-menu" aria-label="Main Navigation">
            <a href="#showcase" className="nav-link">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/></svg>
              <span>Movement</span>
            </a>

            <a href="#about" className="nav-link nav-highlight-pink">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>
              <span>Manifesto</span>
              <span className="nav-mini-dot-pink"></span>
            </a>

            <a href="#docs" className="nav-link" onClick={() => onSelectDoc('live-studio')}>
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2" ry="2"/></svg>
              <span>Studio</span>
            </a>

            <a href="#docs" className="nav-link" onClick={() => onSelectDoc('creator-rooms')}>
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" y1="19" x2="12" y2="23"/><line x1="8" y1="23" x2="16" y2="23"/></svg>
              <span>Rooms</span>
            </a>

            <a href="#docs" className="nav-link" onClick={() => onSelectDoc('mobile-editor')}>
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><circle cx="6" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><line x1="20" y1="4" x2="8.12" y2="15.88"/><line x1="14.47" y1="14.48" x2="20" y2="20"/><line x1="8.12" y1="8.12" x2="12" y2="12"/></svg>
              <span>AI Lab</span>
            </a>

            <a href="#docs" className="nav-link" onClick={() => onSelectDoc('universal-sharing')}>
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><line x1="8.59" y1="13.51" x2="15.42" y2="17.49"/><line x1="15.41" y1="6.51" x2="8.59" y2="10.49"/></svg>
              <span>Share</span>
            </a>
          </nav>

          <div className="header-actions">
            {/* Dark / Light Mode Switcher */}
            <button
              className="theme-toggle-btn"
              onClick={onToggleTheme}
              aria-label={`Switch to ${theme === 'dark' ? 'Light' : 'Dark'} mode`}
              title={`Switch to ${theme === 'dark' ? 'Light' : 'Dark'} mode`}
            >
              {theme === 'dark' ? (
                <>
                  <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2">
                    <circle cx="12" cy="12" r="5"></circle>
                    <line x1="12" y1="1" x2="12" y2="3"></line>
                    <line x1="12" y1="21" x2="12" y2="23"></line>
                    <line x1="4.22" y1="4.22" x2="5.64" y2="5.64"></line>
                    <line x1="18.36" y1="18.36" x2="19.78" y2="19.78"></line>
                    <line x1="1" y1="12" x2="3" y2="12"></line>
                    <line x1="21" y1="12" x2="23" y2="12"></line>
                    <line x1="4.22" y1="19.78" x2="5.64" y2="18.36"></line>
                    <line x1="18.36" y1="5.64" x2="19.78" y2="4.22"></line>
                  </svg>
                  <span className="theme-toggle-label">Light</span>
                </>
              ) : (
                <>
                  <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2">
                    <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"></path>
                  </svg>
                  <span className="theme-toggle-label">Dark</span>
                </>
              )}
            </button>

            {/* Quick Search Shortcut */}
            <button className="search-trigger-btn" onClick={onSearchFocus} aria-label="Search Documentation">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><circle cx="11" cy="11" r="8"></circle><path d="m21 21-4.35-4.35"></path></svg>
              <span className="search-btn-label">Search</span>
              <kbd className="search-kbd">⌘K</kbd>
            </button>

            {/* Main CTA */}
            <button className="btn-primary header-cta-btn" onClick={onOpenDownload}>
              <span className="cta-full-label">Join Movement</span>
              <span className="cta-short-label">Join</span>
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><line x1="5" y1="12" x2="19" y2="12"></line><polyline points="12 5 19 12 12 19"></polyline></svg>
            </button>

            {/* Mobile Hamburger Toggle */}
            <button className="mobile-menu-toggle" onClick={() => setMobileMenuOpen(!mobileMenuOpen)} aria-label="Toggle Navigation Menu">
              {mobileMenuOpen ? (
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><line x1="18" y1="6" x2="6" y2="18"></line><line x1="6" y1="6" x2="18" y2="18"></line></svg>
              ) : (
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><line x1="3" y1="12" x2="21" y2="12"></line><line x1="3" y1="6" x2="21" y2="6"></line><line x1="3" y1="18" x2="21" y2="18"></line></svg>
              )}
            </button>
          </div>
        </div>

        {/* Clean, Modular Mobile Drawer Menu */}
        {mobileMenuOpen && (
          <div className="mobile-nav-drawer">
            <div className="mobile-drawer-header">
              <div className="mobile-drawer-brand">
                <span className="mobile-drawer-logo">ONEOVA</span>
                <span className="mobile-drawer-slogan">Is the reason you matter.</span>
              </div>
              <button className="mobile-theme-pill" onClick={onToggleTheme}>
                {theme === 'dark' ? '☀️ Light' : '🌙 Dark'}
              </button>
            </div>

            <div className="mobile-drawer-links">
              <a href="#showcase" className="mobile-nav-card" onClick={() => setMobileMenuOpen(false)}>
                <span className="mobile-card-icon blue">
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/></svg>
                </span>
                <div className="mobile-card-text">
                  <span className="mobile-card-title">Movement</span>
                  <span className="mobile-card-sub">Next-gen short-form feed & reels</span>
                </div>
                <span className="mobile-card-arrow">→</span>
              </a>

              <a href="#about" className="mobile-nav-card highlight-pink" onClick={() => setMobileMenuOpen(false)}>
                <span className="mobile-card-icon pink">
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>
                </span>
                <div className="mobile-card-text">
                  <span className="mobile-card-title">Manifesto</span>
                  <span className="mobile-card-sub">The reason you matter</span>
                </div>
                <span className="mobile-card-arrow">→</span>
              </a>

              <a href="#docs" className="mobile-nav-card" onClick={() => { onSelectDoc('live-studio'); setMobileMenuOpen(false); }}>
                <span className="mobile-card-icon blue">
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><polygon points="23 7 16 12 23 17 23 7"/><rect x="1" y="5" width="15" height="14" rx="2" ry="2"/></svg>
                </span>
                <div className="mobile-card-text">
                  <span className="mobile-card-title">Live Studio</span>
                  <span className="mobile-card-sub">4K ultra-low latency streams</span>
                </div>
                <span className="mobile-card-arrow">→</span>
              </a>

              <a href="#docs" className="mobile-nav-card" onClick={() => { onSelectDoc('creator-rooms'); setMobileMenuOpen(false); }}>
                <span className="mobile-card-icon blue">
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" y1="19" x2="12" y2="23"/><line x1="8" y1="23" x2="16" y2="23"/></svg>
                </span>
                <div className="mobile-card-text">
                  <span className="mobile-card-title">Creator Rooms</span>
                  <span className="mobile-card-sub">Spatial drop-in audio & video</span>
                </div>
                <span className="mobile-card-arrow">→</span>
              </a>

              <a href="#docs" className="mobile-nav-card highlight-pink" onClick={() => { onSelectDoc('mobile-editor'); setMobileMenuOpen(false); }}>
                <span className="mobile-card-icon pink">
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><circle cx="6" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><line x1="20" y1="4" x2="8.12" y2="15.88"/><line x1="14.47" y1="14.48" x2="20" y2="20"/><line x1="8.12" y1="8.12" x2="12" y2="12"/></svg>
                </span>
                <div className="mobile-card-text">
                  <span className="mobile-card-title">AI Lab</span>
                  <span className="mobile-card-sub">Rotoscoping & auto captions</span>
                </div>
                <span className="mobile-card-arrow">→</span>
              </a>

              <a href="#docs" className="mobile-nav-card" onClick={() => { onSelectDoc('universal-sharing'); setMobileMenuOpen(false); }}>
                <span className="mobile-card-icon blue">
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><line x1="8.59" y1="13.51" x2="15.42" y2="17.49"/><line x1="15.41" y1="6.51" x2="8.59" y2="10.49"/></svg>
                </span>
                <div className="mobile-card-text">
                  <span className="mobile-card-title">Universal Share</span>
                  <span className="mobile-card-sub">1-Tap simultaneous sync</span>
                </div>
                <span className="mobile-card-arrow">→</span>
              </a>
            </div>

            <button className="btn-primary mobile-drawer-btn" onClick={() => { onOpenDownload(); setMobileMenuOpen(false); }}>
              <span>Join The Movement Free</span>
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><line x1="5" y1="12" x2="19" y2="12"></line><polyline points="12 5 19 12 12 19"></polyline></svg>
            </button>
          </div>
        )}
      </header>
    </>
  );
}
