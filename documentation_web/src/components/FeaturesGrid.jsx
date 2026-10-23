import React from 'react';

export default function FeaturesGrid() {
  return (
    <section className="showcase-section" id="features">
      <div className="section-header-center">
        <span className="section-tag pink">PRO CREATOR PLATFORM</span>
        <h2 className="section-title">Built to Revolutionize Mobile Content & Live Streaming</h2>
        <p className="section-desc">
          Oneova converges live interactive broadcasting, drop-in collaboration rooms, cinema-grade mobile editing, and universal social sharing into a single, high-performance ecosystem.
        </p>
      </div>

      <div className="features-grid">
        {/* Card 1: Live Broadcast */}
        <div className="feature-card highlight-pink">
          <div className="feature-icon-box pink">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><circle cx="12" cy="12" r="10"></circle><polygon points="10 8 16 12 10 16 10 8"></polygon></svg>
          </div>
          <h3 className="feature-title">Live Broadcast Studio</h3>
          <p className="feature-description">
            Broadcast in 4K with ultra-low latency. Host split-screen co-host battles (PK Mode), receive real-time animated fan gifts, and pin featured audience Q&A onto your stream.
          </p>
          <div className="feature-tags-wrap">
            <span className="f-badge">4K Mobile Live</span>
            <span className="f-badge">Co-Host Battles</span>
            <span className="f-badge">Fan Gifts & Tipping</span>
          </div>
        </div>

        {/* Card 2: Creator Rooms */}
        <div className="feature-card">
          <div className="feature-icon-box">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"></path><circle cx="9" cy="7" r="4"></circle><path d="M23 21v-2a4 4 0 0 0-3-3.87"></path><path d="M16 3.13a4 4 0 0 1 0 7.75"></path></svg>
          </div>
          <h3 className="feature-title">Interactive Creator Rooms</h3>
          <p className="feature-description">
            Drop-in audio and video collaboration spaces. Feature main stage speakers, private backstage greenrooms for co-hosts, hand-raise audience seats, and live media review.
          </p>
          <div className="feature-tags-wrap">
            <span className="f-badge">Drop-in Stage</span>
            <span className="f-badge">Backstage Greenroom</span>
            <span className="f-badge">Spatial Audio</span>
          </div>
        </div>

        {/* Card 3: Pro Mobile Editor */}
        <div className="feature-card highlight-pink">
          <div className="feature-icon-box pink">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M12 20h9"></path><path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z"></path></svg>
          </div>
          <h3 className="feature-title">Pro Mobile Editor & AI Masking</h3>
          <p className="feature-description">
            Multi-layer magnetic video timeline with one-tap AI subject rotoscoping. Place animated text behind subjects, generate automatic karaoke captions, and grade with cinematic LUTs.
          </p>
          <div className="feature-tags-wrap">
            <span className="f-badge">Multi-Layer Timeline</span>
            <span className="f-badge">AI Rotoscoping</span>
            <span className="f-badge">Auto Captions</span>
          </div>
        </div>

        {/* Card 4: Universal 1-Tap Sharing */}
        <div className="feature-card">
          <div className="feature-icon-box">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><circle cx="18" cy="5" r="3"></circle><circle cx="6" cy="12" r="3"></circle><circle cx="18" cy="19" r="3"></circle><line x1="8.59" y1="13.51" x2="15.42" y2="17.49"></line><line x1="15.41" y1="6.51" x2="8.59" y2="10.49"></line></svg>
          </div>
          <h3 className="feature-title">Universal 1-Tap Sharing</h3>
          <p className="feature-description">
            Simultaneously export and publish to TikTok, YouTube Shorts, Instagram Reels, Facebook Reels, and X with smart aspect ratio reformatting and preserved audio attribution.
          </p>
          <div className="feature-tags-wrap">
            <span className="f-badge">TikTok & Shorts</span>
            <span className="f-badge">Meta Reels Sync</span>
            <span className="f-badge">Smart Reframing</span>
          </div>
        </div>

        {/* Card 5: High-FPS Reels */}
        <div className="feature-card">
          <div className="feature-icon-box">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><rect width="18" height="18" x="3" y="3" rx="2"></rect><path d="m9 8 7 4-7 4Z"></path></svg>
          </div>
          <h3 className="feature-title">High-Velocity Reels Feed</h3>
          <p className="feature-description">
            Zero-buffer 60 FPS reel playback with distinct Following, For You, and Business streams. Discover trending audio through spinning sound discs and 24-hour ephemeral stories.
          </p>
          <div className="feature-tags-wrap">
            <span className="f-badge">Zero-Buffering</span>
            <span className="f-badge">Sound Disc Discovery</span>
            <span className="f-badge">24h Stories</span>
          </div>
        </div>

        {/* Card 6: Safety & Integrity */}
        <div className="feature-card highlight-pink">
          <div className="feature-icon-box pink">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"></path></svg>
          </div>
          <h3 className="feature-title">Community Standards & Trust</h3>
          <p className="feature-description">
            TikTok and Meta aligned community guidelines. Proactive hate speech protection, mandatory sponsored content disclosures (#ad), and strict copyright protection for creators.
          </p>
          <div className="feature-tags-wrap">
            <span className="f-badge">TikTok Standards</span>
            <span className="f-badge">FTC Compliance</span>
            <span className="f-badge">Creator Rights</span>
          </div>
        </div>
      </div>
    </section>
  );
}
