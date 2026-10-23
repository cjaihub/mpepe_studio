import React from 'react';
import PhoneMockup from './PhoneMockup';

export default function Hero({ onOpenDownload }) {
  return (
    <section className="hero-section" id="showcase">
      <div className="hero-grid">
        {/* Left Column: High-Impact Call to Action */}
        <div className="hero-content">
          <div className="status-pill">
            <span className="status-dot-pulse"></span>
            <span>A GLOBAL REVOLUTION IN SOCIAL CONNECTION · THE FUTURE BELONGS TO EVERYONE</span>
          </div>

          <h1 className="hero-title">
            The Future of Social Media & Interaction.
            <span className="hero-title-gradient">Reimagined For Everyone.</span>
          </h1>

          <p className="hero-subtitle">
            Break free from outdated feeds and passive algorithms. Oneova brings humanity together through real-time 4K live broadcasts, drop-in collaboration stages, on-device AI rotoscoping, and universal multi-platform distribution. Step into the next era of communication where your voice, presence, and creativity have true power.
          </p>

          {/* CTA Download Buttons */}
          <div className="hero-cta-group">
            <button className="app-store-btn" onClick={onOpenDownload} aria-label="Download for iOS">
              <span className="store-icon">
                <svg width="24" height="24" viewBox="0 0 24 24" fill="currentColor"><path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M15.97 6.85c.67-.82 1.13-1.96.99-3.11-1 .04-2.18.67-2.88 1.48-.61.71-1.15 1.87-.99 2.98 1.11.09 2.21-.57 2.88-1.35z"/></svg>
              </span>
              <div className="store-text-wrap">
                <span className="store-label">Download for</span>
                <span className="store-name">Apple iOS</span>
              </div>
            </button>

            <button className="app-store-btn android" onClick={onOpenDownload} aria-label="Download for Android">
              <span className="store-icon">
                <svg width="24" height="24" viewBox="0 0 24 24" fill="currentColor"><path d="M17.523 15.3414c-.5511 0-.9993-.4486-.9993-.9997s.4482-.9993.9993-.9993c.551 0 .9996.4482.9996.9993.0001.5511-.4486.9997-.9996.9997m-11.046 0c-.5511 0-.9993-.4486-.9993-.9997s.4482-.9993.9993-.9993c.5511 0 .9997.4482.9997.9993 0 .5511-.4486.9997-.9997.9997m11.4045-6.02l1.9973-3.4592a.416.416 0 00-.1521-.5676.416.416 0 00-.5676.1521l-2.0223 3.503C15.5902 8.4116 13.8533 8.125 12 8.125c-1.8533 0-3.5902.2866-5.1368.8247L4.8409 5.4467a.4161.4161 0 00-.5676-.1521.4157.4157 0 00-.1521.5676l1.9973 3.4592C2.6889 11.1867.3432 14.6589 0 18.7845h24c-.3432-4.1256-2.6889-7.5978-6.1185-9.4631"/></svg>
              </span>
              <div className="store-text-wrap">
                <span className="store-label">Download for</span>
                <span className="store-name">Google Play & APK</span>
              </div>
            </button>

            <button className="qr-trigger-btn" onClick={onOpenDownload}>
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><rect width="5" height="5" x="3" y="3" rx="1"></rect><rect width="5" height="5" x="16" y="3" rx="1"></rect><rect width="5" height="5" x="3" y="16" rx="1"></rect><path d="M21 16h-3a2 2 0 0 0-2 2v3"></path><path d="M21 21v.01"></path><path d="M12 7v3a2 2 0 0 1-2 2H7"></path><path d="M3 12h.01"></path><path d="M12 3h.01"></path><path d="M12 16v.01"></path><path d="M16 12h1"></path><path d="M21 12v.01"></path><path d="M12 21v-1"></path></svg>
              <span>Scan QR Code</span>
            </button>
          </div>

          {/* Performance Trust Indicators (Strict Brand Blue & Pink) */}
          <div className="hero-trust-bar">
            <div className="trust-item">
              <span className="trust-stat"><span className="pink">4K</span> LIVE</span>
              <span className="trust-desc">Low-Latency WebRTC</span>
            </div>
            <div className="trust-item">
              <span className="trust-stat"><span className="blue">ROOMS</span></span>
              <span className="trust-desc">Drop-in Global Stages</span>
            </div>
            <div className="trust-item">
              <span className="trust-stat"><span className="pink">AI</span> LAB</span>
              <span className="trust-desc">Instant Rotoscoping</span>
            </div>
            <div className="trust-item">
              <span className="trust-stat"><span className="blue">1-TAP</span></span>
              <span className="trust-desc">Universal Multi-Share</span>
            </div>
          </div>
        </div>

        {/* Right Column: Interactive Phone Mockup */}
        <PhoneMockup />
      </div>
    </section>
  );
}
