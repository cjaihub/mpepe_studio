import React, { useState, useRef } from 'react';

export default function AboutUs({ onOpenDownload, onSelectDoc }) {
  const [isPlaying, setIsPlaying] = useState(true);
  const [isMuted, setIsMuted] = useState(true);
  const [showFullSpecs, setShowFullSpecs] = useState(false);
  const videoRef = useRef(null);

  const togglePlay = () => {
    if (videoRef.current) {
      if (videoRef.current.paused) {
        videoRef.current.play();
        setIsPlaying(true);
      } else {
        videoRef.current.pause();
        setIsPlaying(false);
      }
    }
  };

  const toggleMute = () => {
    if (videoRef.current) {
      videoRef.current.muted = !isMuted;
      setIsMuted(!isMuted);
    }
  };

  const handleFullscreen = () => {
    if (videoRef.current) {
      if (videoRef.current.requestFullscreen) {
        videoRef.current.requestFullscreen();
      }
    }
  };

  return (
    <section className="about-us-section" id="about">
      {/* Background Ambient Pink & Blue Rays */}
      <div className="about-pink-glow-ray" aria-hidden="true" />
      <div className="about-blue-glow-ray" aria-hidden="true" />

      <div className="about-container">
        {/* Section Header */}
        <div className="about-header-block">
          <div className="about-tag-pill">
            <span className="about-pulse-dot"></span>
            <span>THE ONEOVA MANIFESTO · BUILT FOR 100M+ CREATORS</span>
          </div>

          <h2 className="about-hero-title">
            Pioneering the Post-Desktop Era of{' '}
            <span className="hero-title-gradient">Short-Form Expression</span>
          </h2>

          <p className="about-hero-desc">
            Traditional creation is fractured across four clumsy tools: a camera app, an expensive desktop editor, a separate live broadcasting setup, and tedious manual uploads across social platforms. Oneova was built from first principles to eliminate that friction: giving every creator a Hollywood-grade 4K studio, real-time collaboration rooms, and 1-tap universal social distribution right in their pocket.
          </p>
        </div>

        {/* ==========================================================================
            SUPER POWERFUL VIDEO SPOTLIGHT THEATER
           ========================================================================== */}
        <div className="about-video-theater-wrap">
          <div className="theater-ambient-backlight" aria-hidden="true" />

          <div className="theater-card-chassis">
            {/* Top Theater Header Bar */}
            <div className="theater-top-bar">
              <div className="theater-status-group">
                <span className="live-dot-pink"></span>
                <span className="theater-feed-label">ONEOVA PRO FEED ENGINE</span>
                <span className="theater-badge-hd">4K 60FPS</span>
              </div>
              <div className="theater-controls-group">
                <button
                  className="theater-btn-mini"
                  onClick={toggleMute}
                  title={isMuted ? "Unmute Audio" : "Mute Audio"}
                >
                  {isMuted ? (
                    <>
                      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><path d="M11 5L6 9H2v6h4l5 4V5z"/><line x1="23" y1="9" x2="17" y2="15"/><line x1="17" y1="9" x2="23" y2="15"/></svg>
                      <span>Unmute Sound</span>
                    </>
                  ) : (
                    <>
                      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><path d="M11 5L6 9H2v6h4l5 4V5z"/><path d="M19.07 4.93a10 10 0 0 1 0 14.14"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/></svg>
                      <span>Sound On 🔊</span>
                    </>
                  )}
                </button>
                <button
                  className="theater-btn-mini"
                  onClick={handleFullscreen}
                  title="Expand to Fullscreen"
                >
                  <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><path d="M8 3H5a2 2 0 0 0-2 2v3m18 0V5a2 2 0 0 0-2-2h-3m0 18h3a2 2 0 0 0 2-2v-3M3 16v3a2 2 0 0 0 2 2h3"/></svg>
                  <span>Fullscreen</span>
                </button>
              </div>
            </div>

            {/* Video Screen Frame */}
            <div className="theater-screen-surface" onClick={togglePlay}>
              <video
                ref={videoRef}
                className="theater-video-element"
                src="/assets/oneova_promo.mp4"
                poster="/assets/images/oneova_reel_bg.jpg"
                autoPlay
                loop
                muted={isMuted}
                playsInline
              />

              {/* Theater Dark Vignettes */}
              <div className="theater-vignette-overlay" />

              {/* Center Play/Pause Overlay Indicator when paused */}
              {!isPlaying && (
                <div className="theater-center-play-badge">
                  <svg width="32" height="32" viewBox="0 0 24 24" fill="#FFFFFF"><polygon points="5 3 19 12 5 21 5 3"/></svg>
                  <span>Click to Resume Experience</span>
                </div>
              )}

              {/* Floating Feature Tags on Video */}
              <div className="theater-feature-pill-left">
                <span className="pill-dot-pink"></span>
                <span>Sub-180ms Zero-Latency Engine</span>
              </div>

              <div className="theater-feature-pill-right">
                <span className="pill-dot-blue"></span>
                <span>Hardware HEVC/H.264 Encoder</span>
              </div>
            </div>

            {/* Theater Bottom Status & Caption Bar */}
            <div className="theater-bottom-status-bar">
              <div className="theater-bottom-meta">
                <span className="theater-meta-title">The Oneova Revolution</span>
                <span className="theater-meta-sub">Next-Generation Mobile Video Architecture & Real-Time Broadcasting</span>
              </div>
              <div className="theater-action-links">
                <button className="theater-cta-btn" onClick={onOpenDownload}>
                  <span>Get App & Create</span>
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M5 12h14"/><path d="m12 5 7 7-7 7"/></svg>
                </button>
              </div>
            </div>
          </div>
        </div>

        {/* ==========================================================================
            PERFORMANCE & SCALE METRICS (LIVE COUNTER CARDS)
           ========================================================================== */}
        <div className="about-stats-grid">
          <div className="about-stat-card">
            <span className="stat-number pink">&lt; 180ms</span>
            <span className="stat-label">Global Live Broadcast Latency</span>
            <p className="stat-desc">Ultra-responsive WebRTC glass-to-glass streaming for interactive PK battles and live Q&A.</p>
          </div>

          <div className="about-stat-card">
            <span className="stat-number blue">60 FPS</span>
            <span className="stat-label">Silky Smooth Feed Engine</span>
            <p className="stat-desc">Hardware-accelerated viewport virtualization with zero scroll stutter or video buffering.</p>
          </div>

          <div className="about-stat-card">
            <span className="stat-number pink">4K HDR</span>
            <span className="stat-label">Mobile Studio Master Export</span>
            <p className="stat-desc">Multi-track magnetic timeline with instant AI subject cutout without requiring desktop computers.</p>
          </div>

          <div className="about-stat-card">
            <span className="stat-number blue">1-TAP</span>
            <span className="stat-label">Universal Multi-Platform Sharing</span>
            <p className="stat-desc">Simultaneous 4-way direct distribution to TikTok, YouTube Shorts, Instagram Reels, and X.</p>
          </div>
        </div>

        {/* ==========================================================================
            THE 4 CORE ARCHITECTURAL PILLARS
           ========================================================================== */}
        <div className="about-pillars-block">
          <div className="pillars-header">
            <span className="pillars-eyebrow">OUR CORE PILLARS</span>
            <h3 className="pillars-title">Built for the Demands of Modern Creators</h3>
            <p className="pillars-desc">Every layer of Oneova is engineered to give creators total sovereignty, velocity, and reach.</p>
          </div>

          <div className="pillars-grid">
            {/* Pillar 1 */}
            <div className="pillar-card highlight-pink">
              <div className="pillar-num-badge">01</div>
              <div className="pillar-icon-box">📹</div>
              <h4 className="pillar-card-title">Live Broadcast Studio</h4>
              <p className="pillar-card-desc">
                Transform any smartphone into a production broadcast studio. Stream with interactive co-host split battles, instant virtual fan gifting, dynamic stage lighting filters, and lossless 4K local master capture.
              </p>
              <div className="pillar-tag-list">
                <span className="p-tag">PK Battle Duels</span>
                <span className="p-tag">Instant Gifting</span>
                <span className="p-tag">Safe Moderation</span>
              </div>
            </div>

            {/* Pillar 2 */}
            <div className="pillar-card">
              <div className="pillar-num-badge">02</div>
              <div className="pillar-icon-box">🎙️</div>
              <h4 className="pillar-card-title">Drop-In Creator Rooms</h4>
              <p className="pillar-card-desc">
                Host live drop-in podcast stages, community townhalls, and backstage greenrooms. Features crystal-clear spatial voice isolation, audience raise-hand queues, and synchronized media scrubbing for video teams.
              </p>
              <div className="pillar-tag-list">
                <span className="p-tag">Spatial Audio</span>
                <span className="p-tag">Backstage Greenroom</span>
                <span className="p-tag">Stage Hands</span>
              </div>
            </div>

            {/* Pillar 3 */}
            <div className="pillar-card highlight-pink">
              <div className="pillar-num-badge">03</div>
              <div className="pillar-icon-box">✂️</div>
              <h4 className="pillar-card-title">Pro Mobile Studio & AI Lab</h4>
              <p className="pillar-card-desc">
                Edit frame-accurate short-form videos with magnetic timeline snapping, on-device AI rotoscoping that isolates subjects without green screens, and automatic karaoke-style animated captions.
              </p>
              <div className="pillar-tag-list">
                <span className="p-tag">AI Subject Cutout</span>
                <span className="p-tag">Magnetic Timeline</span>
                <span className="p-tag">Auto Captions</span>
              </div>
            </div>

            {/* Pillar 4 */}
            <div className="pillar-card">
              <div className="pillar-num-badge">04</div>
              <div className="pillar-icon-box">🌐</div>
              <h4 className="pillar-card-title">1-Tap Universal Sharing</h4>
              <p className="pillar-card-desc">
                Eliminate hours of manual re-exporting. Publish simultaneously to TikTok, YouTube Shorts, Instagram Reels, and X with intelligent focal point aspect-ratio reframing and preserved audio attribution.
              </p>
              <div className="pillar-tag-list">
                <span className="p-tag">TikTok Sync</span>
                <span className="p-tag">Shorts & Reels</span>
                <span className="p-tag">Audio Attribution</span>
              </div>
            </div>
          </div>
        </div>

        {/* ==========================================================================
            CREATOR BILL OF RIGHTS & TRUST PHILOSOPHY
           ========================================================================== */}
        <div className="about-trust-manifesto-card">
          <div className="trust-manifesto-left">
            <span className="manifesto-tag">CREATOR SOVEREIGNTY</span>
            <h3 className="manifesto-title">The Oneova Creator Bill of Rights</h3>
            <p className="manifesto-text">
              We reject predatory algorithmic black boxes, arbitrary shadow-banning, and platform rent-seeking. Oneova is built with transparent, verifiable rules of engagement — proving that your voice, creativity, and presence is the reason you matter.
            </p>
            <ul className="manifesto-points">
              <li>
                <span className="m-icon">🛡️</span>
                <span><strong>Audio Attribution Protection:</strong> Your original sounds and remix discs are permanently credited to your handle across all platforms.</span>
              </li>
              <li>
                <span className="m-icon">🔒</span>
                <span><strong>Full Data Sovereignty:</strong> Export your 4K master files, audience statistics, and community links at any time with zero walled gardens.</span>
              </li>
              <li>
                <span className="m-icon">⚖️</span>
                <span><strong>TikTok & FTC Standard Aligned:</strong> Commercial disclosures (#ad, #sponsored) and synthetic AI media watermarking are transparently honored.</span>
              </li>
            </ul>
          </div>

          <div className="trust-manifesto-right">
            <div className="guarantee-box">
              <span className="guarantee-icon">⚡</span>
              <span className="guarantee-title">Zero Friction Guarantee</span>
              <span className="guarantee-desc">From camera capture to 4-platform viral publish in under 3 minutes.</span>
              <button className="btn-primary guarantee-btn" onClick={onOpenDownload}>
                Install Oneova Studio
              </button>
            </div>
          </div>
        </div>

        {/* ==========================================================================
            OUR EVOLUTION TIMELINE
           ========================================================================== */}
        <div className="about-timeline-section">
          <div className="timeline-title-wrap">
            <span className="timeline-eyebrow">ROADMAP & MILESTONES</span>
            <h3 className="timeline-main-title">The Architecture of Progress</h3>
          </div>

          <div className="timeline-cards-row">
            <div className="timeline-milestone-card">
              <div className="milestone-year pink">2024</div>
              <div className="milestone-heading">Genesis Architecture</div>
              <p className="milestone-desc">Core 60 FPS mobile reel engine, zero-buffering prefetch cache, and high-performance real-time cloud data layer.</p>
            </div>

            <div className="timeline-milestone-card">
              <div className="milestone-year blue">2025</div>
              <div className="milestone-heading">Live Studio & Spatial Rooms</div>
              <p className="milestone-desc">Sub-180ms WebRTC live broadcasting, PK duel split-screens, and drop-in audio collaboration rooms.</p>
            </div>

            <div className="timeline-milestone-card active-now">
              <div className="milestone-year pink">2026 NOW</div>
              <div className="milestone-heading">AI Lab & Universal Share</div>
              <p className="milestone-desc">On-device neural rotoscoping, automated karaoke captions, and 1-tap simultaneous 4-platform universal publishing.</p>
            </div>
          </div>
        </div>

        {/* Bottom Call to Action */}
        <div className="about-bottom-cta">
          <div className="about-bottom-cta-inner">
            <h3>Ready to Join the Next Generation of Creators?</h3>
            <p>Download Oneova on iOS and Android today to experience the revolution.</p>
            <div className="cta-btn-wrap">
              <button className="btn-primary" onClick={onOpenDownload}>
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path><polyline points="7 10 12 15 17 10"></polyline><line x1="12" y1="15" x2="12" y2="3"></line></svg>
                <span>Get Oneova App</span>
              </button>
              <button className="btn-secondary" onClick={() => onSelectDoc('mobile-editor')}>
                <span>Read Studio Docs</span>
                <span className="btn-arrow">→</span>
              </button>
            </div>
          </div>
        </div>

      </div>
    </section>
  );
}
