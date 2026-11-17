import React from 'react';
import PhoneMockup from './PhoneMockup';

export default function Hero({ onOpenDownload, onOpenHelp }) {
  return (
    <section className="hero-section" id="showcase">
      <div className="hero-grid">
        <div className="hero-content">
          <div className="status-pill">
            <span className="status-dot-pulse" />
            <span>ONEOVA ECOSYSTEM · CREATOR STUDIO, AI &amp; HELP CENTER</span>
          </div>

          <h1 className="hero-title">
            Create, Stream, Grade &amp; Stay Supported.{' '}
            <span className="hero-title-gradient">All In One Studio.</span>
          </h1>

          <p className="hero-subtitle">
            Go live in 4K with real-time GPU Looks, edit Reels with AI cutouts, summon Ova
            hands-free from your phone or Mac &amp; Windows Desktop Agent, and cash out via
            M-Pesa and local payouts—backed by a guided Help Center and plain-language rules.
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
              aria-label="Download Oneova Mobile App"
            >
              <span className="store-icon">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.3">
                  <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
                  <polyline points="7 10 12 15 17 10" />
                  <line x1="12" y1="15" x2="12" y2="3" />
                </svg>
              </span>
              <div className="store-text-wrap">
                <span className="store-label">iOS &amp; Android</span>
                <span className="store-name">Get Mobile App</span>
              </div>
            </button>

            <a href="#desktop" className="qr-trigger-btn" style={{ textDecoration: 'none' }}>
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2">
                <rect x="2" y="3" width="20" height="14" rx="2" />
                <line x1="8" y1="21" x2="16" y2="21" />
                <line x1="12" y1="17" x2="12" y2="21" />
              </svg>
              <span>Mac &amp; Windows</span>
            </a>
          </div>

          <div className="hero-trust-bar">
            <div className="trust-item">
              <span className="trust-stat"><span className="pink">1.</span> START</span>
              <span className="trust-desc">Account, Passkeys &amp; Safety</span>
            </div>
            <div className="trust-item">
              <span className="trust-stat"><span className="blue">2.</span> CREATE</span>
              <span className="trust-desc">4K Live, Looks &amp; Studio</span>
            </div>
            <div className="trust-item">
              <span className="trust-stat"><span className="pink">3.</span> OVA AI</span>
              <span className="trust-desc">Power-Button &amp; Desktop Skills</span>
            </div>
            <div className="trust-item">
              <span className="trust-stat"><span className="blue">4.</span> EARN</span>
              <span className="trust-desc">M-Pesa, MoMo &amp; 3D Shops</span>
            </div>
          </div>
        </div>

        <PhoneMockup />
      </div>
    </section>
  );
}
