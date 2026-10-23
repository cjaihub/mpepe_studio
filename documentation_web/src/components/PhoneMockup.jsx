import React, { useState, useRef } from 'react';

export default function PhoneMockup() {
  const [activeScreen, setActiveScreen] = useState('reels');
  const [activeFeedTab, setActiveFeedTab] = useState('forYou');
  const [liked, setLiked] = useState(false);
  const [likeCount, setLikeCount] = useState(42);
  const [bookmarked, setBookmarked] = useState(false);
  const [floatingEmojis, setFloatingEmojis] = useState([]);
  const [liveHearts, setLiveHearts] = useState(['💖', '🔥', '✨']);
  const [isMuted, setIsMuted] = useState(true);
  const [isPlaying, setIsPlaying] = useState(true);
  const reelVideoRef = useRef(null);

  const toggleReelPlay = () => {
    if (reelVideoRef.current) {
      if (reelVideoRef.current.paused) {
        reelVideoRef.current.play();
        setIsPlaying(true);
      } else {
        reelVideoRef.current.pause();
        setIsPlaying(false);
      }
    }
  };

  const toggleReelMute = (e) => {
    e.stopPropagation();
    if (reelVideoRef.current) {
      reelVideoRef.current.muted = !isMuted;
      setIsMuted(!isMuted);
    }
  };

  const handleLike = () => {
    if (!liked) {
      setLiked(true);
      setLikeCount(prev => prev + 1);
      spawnEmoji('💖');
    } else {
      setLiked(false);
      setLikeCount(prev => prev - 1);
    }
  };

  const spawnEmoji = (emoji) => {
    const id = Date.now() + Math.random();
    setFloatingEmojis(prev => [...prev, { id, emoji, left: 60 + Math.random() * 25 }]);
    setTimeout(() => {
      setFloatingEmojis(prev => prev.filter(item => item.id !== id));
    }, 1400);
  };

  return (
    <div className="showcase-stage-card">
      {/* Pink & Blue Ambient Backlight Rays */}
      <div className="stage-pink-ambient-glow" aria-hidden="true" />
      <div className="stage-blue-ambient-glow" aria-hidden="true" />

      {/* Floating Attraction Pill 1: 4K Live Broadcast */}
      <div className="floating-badge-pill top-left">
        <span className="badge-pulse-dot pink"></span>
        <div className="badge-text-group">
          <span className="badge-title">4K LIVE BROADCAST</span>
          <span className="badge-sub">● 14.8k Viewers Streaming</span>
        </div>
      </div>

      {/* Floating Attraction Pill 2: 1-Tap Universal Share */}
      <div className="floating-badge-pill top-right">
        <span className="badge-icon-star">✨</span>
        <div className="badge-text-group">
          <span className="badge-title">1-TAP UNIVERSAL SHARE</span>
          <span className="badge-sub">TikTok · Shorts · Reels · X</span>
        </div>
      </div>

      {/* Floating Attraction Pill 3: Trending Sound */}
      <div className="floating-badge-pill bottom-left">
        <span className="badge-icon-disc">♫</span>
        <div className="badge-text-group">
          <span className="badge-title">ORIGINAL SOUND DISC</span>
          <span className="badge-sub">Oneova Beats (128 BPM)</span>
        </div>
      </div>

      {/* Mode Switcher Tabs */}
      <div className="emulator-controls" role="tablist" aria-label="Mobile Screen Simulator">
        <button
          className={`sim-tab-btn ${activeScreen === 'reels' ? 'active' : ''}`}
          onClick={() => setActiveScreen('reels')}
        >
          <span>⚡ Reels Feed</span>
          <span className="tab-pill-mini pink">Reference</span>
        </button>
        <button
          className={`sim-tab-btn ${activeScreen === 'live' ? 'active' : ''}`}
          onClick={() => setActiveScreen('live')}
        >
          <span>📹 Live Studio</span>
          <span className="tab-pill-mini">PK Mode</span>
        </button>
        <button
          className={`sim-tab-btn ${activeScreen === 'rooms' ? 'active' : ''}`}
          onClick={() => setActiveScreen('rooms')}
        >
          <span>🎙️ Creator Rooms</span>
          <span className="tab-pill-mini">Stage</span>
        </button>
        <button
          className={`sim-tab-btn ${activeScreen === 'editor' ? 'active' : ''}`}
          onClick={() => setActiveScreen('editor')}
        >
          <span>✂️ Mobile Editor</span>
          <span className="tab-pill-mini pink">AI Mask</span>
        </button>
      </div>

      {/* The Phone Mockup Frame with Glowing Pink Shadows */}
      <div className="phone-mockup-frame with-pink-shadows">
        {/* Dynamic Screen Edge Glow */}
        <div className="screen-edge-pink-highlight"></div>

        {/* Flutter DEBUG Banner (Matches Real Android Device in Screenshot) */}
        <div className="flutter-debug-ribbon">
          <span>DEBUG</span>
        </div>

        {/* Android / Dynamic Top Status Bar (Matching Screenshot 8:31, G, Shield, Wi-Fi, Batt) */}
        <div className="phone-status-bar-real">
          <div className="status-left">
            <span className="status-clock">8:31</span>
            <span className="status-icon-g">G</span>
            <svg width="11" height="11" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2L4 5v6.09c0 5.05 3.41 9.76 8 10.91 4.59-1.15 8-5.86 8-10.91V5l-8-3z"/></svg>
          </div>
          <div className="status-right">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor"><path d="M12 3c-4.97 0-9 4.03-9 9 0 2.12.74 4.07 1.97 5.61L12 22l7.03-4.39C20.26 16.07 21 14.12 21 12c0-4.97-4.03-9-9-9z"/></svg>
            <svg width="16" height="11" viewBox="0 0 24 14" fill="currentColor"><rect x="1" y="1" width="18" height="12" rx="3" fill="none" stroke="currentColor" strokeWidth="2"/><rect x="3" y="3" width="12" height="8" rx="1.5"/></svg>
          </div>
        </div>

        {/* Phone Screen Canvas */}
        <div className="phone-screen-content">
          {/* SCREEN 1: REELS FEED (FAITHFUL TO REAL SCREENSHOT WITH PLAYING VIDEO) */}
          {activeScreen === 'reels' && (
            <div className="sim-screen-view reels-screen-view">
              {/* Cinematic Video Element Playing in App */}
              <div className="sim-reel-video-bg" onClick={toggleReelPlay}>
                <video
                  ref={reelVideoRef}
                  className="sim-reel-video-element"
                  src="/assets/oneova_promo.mp4"
                  poster="/assets/images/oneova_reel_bg.jpg"
                  autoPlay
                  loop
                  muted={isMuted}
                  playsInline
                />
                {/* Dark Vignette Shading for High-Contrast Text */}
                <div className="sim-reel-vignette-top" />
                <div className="sim-reel-vignette-bottom" />

                {/* Floating Sound Toggle Pill */}
                <button
                  className="sim-reel-audio-control"
                  onClick={toggleReelMute}
                  aria-label={isMuted ? "Unmute reel sound" : "Mute reel sound"}
                >
                  {isMuted ? (
                    <>
                      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M11 5L6 9H2v6h4l5 4V5z"/><line x1="23" y1="9" x2="17" y2="15"/><line x1="17" y1="9" x2="23" y2="15"/></svg>
                      <span>Sound Off</span>
                    </>
                  ) : (
                    <>
                      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5"><path d="M11 5L6 9H2v6h4l5 4V5z"/><path d="M19.07 4.93a10 10 0 0 1 0 14.14"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/></svg>
                      <span>Sound On 🔊</span>
                    </>
                  )}
                </button>

                {/* Pause Icon when user clicks to pause */}
                {!isPlaying && (
                  <div className="sim-reel-pause-indicator">
                    <svg width="32" height="32" viewBox="0 0 24 24" fill="#FFFFFF"><polygon points="5 3 19 12 5 21 5 3"/></svg>
                  </div>
                )}
              </div>

              {/* Feed Header (Search · Following / For You / Biz · Bell) */}
              <div className="sim-feed-header-real">
                <button className="feed-header-icon-btn" aria-label="Search">
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4"><circle cx="11" cy="11" r="7"></circle><path d="m21 21-4.35-4.35"></path></svg>
                </button>

                <div className="sim-tabs-row-real">
                  <span
                    className={`sim-feed-tab-real ${activeFeedTab === 'following' ? 'active' : ''}`}
                    onClick={() => setActiveFeedTab('following')}
                  >
                    Following
                  </span>
                  <span
                    className={`sim-feed-tab-real ${activeFeedTab === 'forYou' ? 'active' : ''}`}
                    onClick={() => setActiveFeedTab('forYou')}
                  >
                    For You
                  </span>
                  <span
                    className={`sim-feed-tab-real ${activeFeedTab === 'biz' ? 'active' : ''}`}
                    onClick={() => setActiveFeedTab('biz')}
                  >
                    Biz
                  </span>
                </div>

                <div className="feed-header-bell-wrap">
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"></path><path d="M13.73 21a2 2 0 0 1-3.46 0"></path></svg>
                  <span className="bell-badge-dot"></span>
                </div>
              </div>

              {/* Stories Bar with 'Your Story' & 'Alex' Portrait (Matches Screenshot) */}
              <div className="sim-stories-bar-real">
                {/* Story 1: Your Story */}
                <div className="story-item-real">
                  <div className="story-avatar-wrap story-ring-blue">
                    <div className="story-logo-badge">
                      <img src="/assets/images/oneova_logo.jpg" alt="Your Story" className="story-img" />
                    </div>
                    <span className="story-plus-badge">+</span>
                  </div>
                  <span className="story-name-label">Your Story</span>
                </div>

                {/* Story 2: Alex (Exact match with real portrait in screenshot) */}
                <div className="story-item-real">
                  <div className="story-avatar-wrap story-ring-blue">
                    <img src="/assets/images/alex_avatar.jpg" alt="Alex" className="story-img" />
                  </div>
                  <span className="story-name-label">Alex</span>
                </div>

                {/* Story 3: Maya (Pink Ring) */}
                <div className="story-item-real">
                  <div className="story-avatar-wrap story-ring-pink">
                    <div className="story-placeholder-avatar">M</div>
                  </div>
                  <span className="story-name-label">Maya</span>
                </div>

                {/* Story 4: Live Studio (Hot Pink Ring) */}
                <div className="story-item-real">
                  <div className="story-avatar-wrap story-ring-pink">
                    <div className="story-placeholder-avatar live">🔥</div>
                  </div>
                  <span className="story-name-label" style={{ color: 'var(--brand-pink)' }}>Live</span>
                </div>
              </div>

              {/* Bottom Video Metadata & Shopping Pill */}
              <div className="sim-feed-canvas-real">
                {/* Left Side: Author Tag, Caption, Runway Tag, Quick Comments */}
                <div className="sim-author-block-real">
                  <div className="author-tag-pill">
                    <span className="author-u-badge">U</span>
                    <span className="author-username">user_a</span>
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="#007AFF"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/></svg>
                  </div>

                  <p className="author-caption-text">
                    Exploring the new studio features! #oneova #studio ✨
                  </p>

                  {/* Shopping Pill (Matches Screenshot: Shop Runway Pieces (4) >) */}
                  <div className="shopping-runway-pill" onClick={() => spawnEmoji('🛍️')}>
                    <span className="shop-icon">🛍️</span>
                    <span className="shop-text">Shop Runway Pieces (4)</span>
                    <span className="shop-arrow">›</span>
                  </div>

                  {/* Add Comment Input with Quick Reactions (Matches Screenshot) */}
                  <div className="quick-comment-bar-real">
                    <span className="comment-placeholder">Add comment...</span>
                    <div className="comment-emoji-tray">
                      <button className="emoji-btn" onClick={() => spawnEmoji('😍')}>😍</button>
                      <button className="emoji-btn" onClick={() => spawnEmoji('🔥')}>🔥</button>
                      <button className="emoji-btn" onClick={() => spawnEmoji('🚀')}>🚀</button>
                      <button className="emoji-btn" onClick={() => spawnEmoji('🎙️')}>🎙️</button>
                    </div>
                  </div>
                </div>

                {/* Right Action Rail (Matches Screenshot: Avatar U+, Heart, Comment, Bookmark, Share, REMIX, Disc) */}
                <div className="sim-action-rail-real">
                  {/* Avatar U with (+) badge */}
                  <div className="rail-avatar-item">
                    <div className="rail-avatar-circle">U</div>
                    <span className="rail-avatar-plus">+</span>
                  </div>

                  {/* Like Button */}
                  <button className="rail-action-btn" onClick={handleLike} aria-label="Like Video">
                    <div className={`rail-action-icon ${liked ? 'liked' : ''}`}>
                      <svg width="22" height="22" viewBox="0 0 24 24" fill={liked ? '#FF2D87' : 'none'} stroke={liked ? '#FF2D87' : '#FFFFFF'} strokeWidth="2.2"><path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z"></path></svg>
                    </div>
                    <span className="rail-action-count">{likeCount}</span>
                  </button>

                  {/* Comment Button */}
                  <div className="rail-action-btn" onClick={() => spawnEmoji('💬')}>
                    <div className="rail-action-icon">
                      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" strokeWidth="2.2"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"></path></svg>
                    </div>
                    <span className="rail-action-count">5</span>
                  </div>

                  {/* Bookmark Button */}
                  <div className="rail-action-btn" onClick={() => setBookmarked(!bookmarked)}>
                    <div className="rail-action-icon">
                      <svg width="22" height="22" viewBox="0 0 24 24" fill={bookmarked ? '#FF2D87' : 'none'} stroke={bookmarked ? '#FF2D87' : '#FFFFFF'} strokeWidth="2.2"><path d="m19 21-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z"></path></svg>
                    </div>
                    <span className="rail-action-count">{bookmarked ? 1 : 0}</span>
                  </div>

                  {/* Share Button */}
                  <div className="rail-action-btn" onClick={() => spawnEmoji('✨')}>
                    <div className="rail-action-icon">
                      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" strokeWidth="2.2"><circle cx="18" cy="5" r="3"></circle><circle cx="6" cy="12" r="3"></circle><circle cx="18" cy="19" r="3"></circle><line x1="8.59" y1="13.51" x2="15.42" y2="17.49"></line><line x1="15.41" y1="6.51" x2="8.59" y2="10.49"></line></svg>
                    </div>
                    <span className="rail-action-count">0</span>
                  </div>

                  {/* REMIX Button (Matches Screenshot: Glowing Blue/Purple button with stars) */}
                  <div className="rail-remix-btn" onClick={() => spawnEmoji('⚡')}>
                    <div className="remix-icon-badge">
                      <svg width="16" height="16" viewBox="0 0 24 24" fill="#FFFFFF"><path d="M12 2l2.4 7.2h7.6l-6.1 4.5 2.3 7.3-6.2-4.6-6.2 4.6 2.3-7.3-6.1-4.5h7.6z"/></svg>
                    </div>
                    <span className="remix-label">REMIX</span>
                  </div>

                  {/* Spinning Vinyl Sound Disc */}
                  <div className="rail-disc-item">
                    <div className="spinning-vinyl-disc">
                      <img src="/assets/images/oneova_logo.jpg" alt="Disc Album Art" className="disc-art" />
                    </div>
                  </div>
                </div>

                {/* Floating Emojis Animation */}
                {floatingEmojis.map(item => (
                  <div
                    key={item.id}
                    className="floating-spark-emoji"
                    style={{ right: `${item.left}px` }}
                  >
                    {item.emoji}
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* SCREEN 2: LIVE BROADCAST STUDIO */}
          {activeScreen === 'live' && (
            <div className="sim-screen-view">
              <div style={{ position: 'relative', height: '100%', background: 'radial-gradient(circle at 50% 30%, #201224 0%, #08080c 100%)', display: 'flex', flexDirection: 'column', justifyContent: 'space-between', padding: '14px' }}>
                {/* Live Top Bar */}
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '6px', background: 'rgba(0,0,0,0.6)', padding: '5px 12px', borderRadius: '16px', border: '1px solid rgba(255,45,135,0.4)' }}>
                    <span style={{ width: 8, height: 8, borderRadius: '50%', background: 'var(--brand-pink)', boxShadow: '0 0 8px var(--brand-pink)' }}></span>
                    <span style={{ fontSize: '0.72rem', fontWeight: 900, color: '#fff', letterSpacing: '0.5px' }}>LIVE</span>
                    <span style={{ fontSize: '0.7rem', color: '#bbb' }}>• 4.8k viewers</span>
                  </div>
                  <div style={{ display: 'flex', gap: '6px' }}>
                    <div style={{ background: 'var(--brand-pink)', color: '#fff', padding: '5px 10px', borderRadius: '12px', fontSize: '0.68rem', fontWeight: 800 }}>
                      PK BATTLE
                    </div>
                  </div>
                </div>

                {/* Co-Host Split Visual with Neon Pink & Blue Edges (Playing Video in Live Host Feed) */}
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '8px', margin: '14px 0' }}>
                  <div style={{ height: '115px', borderRadius: '12px', overflow: 'hidden', position: 'relative', border: '2px solid var(--brand-blue)', boxShadow: '0 0 15px rgba(0,122,255,0.3)', background: '#000' }}>
                    <video
                      style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                      src="/assets/oneova_promo.mp4"
                      autoPlay
                      loop
                      muted
                      playsInline
                    />
                    <div style={{ position: 'absolute', bottom: 4, left: 6, zIndex: 2 }}>
                      <span style={{ fontSize: '0.62rem', fontWeight: 800, color: '#fff', background: 'rgba(0,0,0,0.6)', padding: '2px 6px', borderRadius: '4px' }}>@host.alex</span>
                    </div>
                  </div>
                  <div style={{ height: '115px', borderRadius: '12px', background: 'radial-gradient(circle at 50% 30%, #301025 0%, #0d0611 100%)', border: '2px solid var(--brand-pink)', boxShadow: '0 0 15px rgba(255,45,135,0.3)', display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', padding: '8px', position: 'relative' }}>
                    <div style={{ position: 'absolute', top: 6, right: 6, background: 'var(--brand-pink)', color: '#fff', fontSize: '0.52rem', fontWeight: 900, padding: '2px 5px', borderRadius: '4px' }}>PK DUEL</div>
                    <span style={{ fontSize: '0.68rem', fontWeight: 700, color: 'var(--brand-pink)' }}>@guest.maya</span>
                  </div>
                </div>

                {/* Floating Hearts & Stream Comments */}
                <div>
                  <div style={{ background: 'rgba(0,0,0,0.6)', padding: '8px 10px', borderRadius: '8px', marginBottom: '10px', borderLeft: '3px solid var(--brand-pink)' }}>
                    <span style={{ fontSize: '0.7rem', fontWeight: 800, color: 'var(--brand-pink)' }}>PINNED: </span>
                    <span style={{ fontSize: '0.7rem', color: '#fff' }}>Welcome to 4K Live Studio! Tap heart for pink sparks ✨</span>
                  </div>

                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <div style={{ background: 'rgba(255,255,255,0.1)', padding: '7px 14px', borderRadius: '18px', fontSize: '0.72rem', color: '#aaa', flex: 1, marginRight: '10px' }}>
                      Say something...
                    </div>
                    <button
                      onClick={() => spawnEmoji('💖')}
                      style={{ background: 'var(--brand-pink)', border: 'none', color: '#fff', width: '36px', height: '36px', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', boxShadow: '0 0 16px var(--brand-pink-glow)' }}
                    >
                      💖
                    </button>
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* SCREEN 3: CREATOR ROOMS */}
          {activeScreen === 'rooms' && (
            <div className="sim-screen-view">
              <div style={{ padding: '16px', background: '#0e0f14', height: '100%', display: 'flex', flexDirection: 'column', gap: '12px' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <span style={{ fontSize: '0.88rem', fontWeight: 900, color: '#fff' }}>CREATOR ROOM</span>
                  <span style={{ fontSize: '0.65rem', color: 'var(--brand-pink)', fontWeight: 800, background: 'rgba(255,45,135,0.15)', padding: '3px 10px', borderRadius: '12px' }}>
                    ● 24 On Stage
                  </span>
                </div>

                <div style={{ fontSize: '0.82rem', fontWeight: 800, color: '#FFFFFF' }}>
                  "Viral Reels Mastery & Live Editing Drop-in"
                </div>

                {/* Stage Speakers */}
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '10px', marginTop: '6px' }}>
                  <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
                    <div style={{ width: 48, height: 48, borderRadius: '50%', border: '2px solid var(--brand-pink)', background: '#222', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '1.2rem', boxShadow: '0 0 10px rgba(255,45,135,0.3)' }}>🎙️</div>
                    <span style={{ fontSize: '0.65rem', fontWeight: 700, color: '#fff', marginTop: '3px' }}>Alex (Host)</span>
                  </div>
                  <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
                    <div style={{ width: 48, height: 48, borderRadius: '50%', border: '2px solid var(--brand-blue)', background: '#222', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '1.2rem' }}>🎬</div>
                    <span style={{ fontSize: '0.65rem', fontWeight: 700, color: '#fff', marginTop: '3px' }}>Maya (Pro)</span>
                  </div>
                  <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
                    <div style={{ width: 48, height: 48, borderRadius: '50%', border: '2px solid var(--brand-pink)', background: '#222', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '1.2rem' }}>🎵</div>
                    <span style={{ fontSize: '0.65rem', fontWeight: 700, color: '#fff', marginTop: '3px' }}>Beats Lab</span>
                  </div>
                </div>

                {/* Backstage Greenroom Card */}
                <div style={{ background: '#161820', border: '1px solid rgba(255,45,135,0.3)', borderRadius: '12px', padding: '12px', marginTop: '8px' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <span style={{ fontSize: '0.78rem', fontWeight: 800, color: 'var(--brand-pink)' }}>Backstage Greenroom</span>
                    <span style={{ fontSize: '0.65rem', color: '#888' }}>Private Channel</span>
                  </div>
                  <div style={{ fontSize: '0.7rem', color: '#ccc', marginTop: '4px' }}>
                    Co-hosts coordinate privately with synchronized frame scrubbing.
                  </div>
                </div>

                <div style={{ marginTop: 'auto', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <button style={{ background: 'var(--brand-pink)', color: '#fff', border: 'none', padding: '8px 16px', borderRadius: '18px', fontSize: '0.75rem', fontWeight: 800, display: 'flex', alignItems: 'center', gap: '6px', cursor: 'pointer', boxShadow: '0 0 12px var(--brand-pink-glow)' }}>
                    <span>✋</span> Raise Hand to Speak
                  </button>
                  <span style={{ fontSize: '0.68rem', color: '#777' }}>142 in audience</span>
                </div>
              </div>
            </div>
          )}

          {/* SCREEN 4: MOBILE EDITOR & UNIVERSAL SHARING */}
          {activeScreen === 'editor' && (
            <div className="sim-screen-view">
              <div className="sim-studio-screen">
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', color: '#fff' }}>
                  <span style={{ fontSize: '0.88rem', fontWeight: 900 }}>PRO MOBILE EDITOR</span>
                  <span style={{ fontSize: '0.72rem', color: 'var(--brand-pink)', fontWeight: 800 }}>4K 60FPS</span>
                </div>

                {/* Active 4K Video Preview Monitor with Rotoscoping Overlay */}
                <div style={{ height: '110px', borderRadius: '10px', overflow: 'hidden', position: 'relative', border: '1.5px solid rgba(255,45,135,0.4)', boxShadow: '0 0 15px rgba(255,45,135,0.2)', background: '#000' }}>
                  <video
                    style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                    src="/assets/oneova_promo.mp4"
                    autoPlay
                    loop
                    muted
                    playsInline
                  />
                  <div style={{ position: 'absolute', top: 6, left: 6, background: 'rgba(0,0,0,0.7)', border: '1px solid var(--brand-pink)', padding: '2px 6px', borderRadius: '4px', fontSize: '0.55rem', fontWeight: 900, color: 'var(--brand-pink)' }}>
                    AI NEURAL MASK ACTIVE
                  </div>
                  <div style={{ position: 'absolute', bottom: 4, right: 6, background: 'rgba(0,0,0,0.6)', padding: '2px 5px', borderRadius: '3px', fontSize: '0.52rem', color: '#fff', fontFamily: 'monospace' }}>
                    00:04.28 / 60FPS
                  </div>
                </div>

                <div className="studio-tool-card" style={{ borderColor: 'rgba(255,45,135,0.4)', boxShadow: '0 0 15px rgba(255,45,135,0.15)' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                    <div className="studio-tool-title" style={{ color: 'var(--brand-pink)' }}>AI Subject Cutout</div>
                    <span style={{ fontSize: '0.65rem', color: 'var(--brand-blue)', fontWeight: 800 }}>ACTIVE</span>
                  </div>
                  <div className="studio-tool-desc">Real-time subject rotoscoping. Place animated 3D text behind subjects.</div>
                </div>

                <div className="studio-tool-card">
                  <div className="studio-tool-title">Multi-Layer Magnetic Timeline</div>
                  <div className="timeline-track">
                    <div className="track-block">Main 4K Video</div>
                    <div className="track-block pink">AI Mask Overlay</div>
                  </div>
                  <div className="timeline-track">
                    <div className="track-block" style={{ width: '80%', background: 'var(--brand-blue)', color: '#fff' }}>Smart Auto-Captions (Karaoke)</div>
                  </div>
                </div>

                <div className="studio-tool-card" style={{ borderColor: 'rgba(0,122,255,0.4)' }}>
                  <div className="studio-tool-title" style={{ color: 'var(--brand-blue)' }}>1-Tap Universal Sharer</div>
                  <div style={{ display: 'flex', gap: '6px', marginTop: '6px' }}>
                    <span style={{ background: '#000', border: '1px solid #333', padding: '3px 6px', borderRadius: '4px', fontSize: '0.62rem', color: '#fff' }}>TikTok</span>
                    <span style={{ background: '#000', border: '1px solid #333', padding: '3px 6px', borderRadius: '4px', fontSize: '0.62rem', color: '#fff' }}>Shorts</span>
                    <span style={{ background: '#000', border: '1px solid #333', padding: '3px 6px', borderRadius: '4px', fontSize: '0.62rem', color: '#fff' }}>Instagram</span>
                    <span style={{ background: '#000', border: '1px solid #333', padding: '3px 6px', borderRadius: '4px', fontSize: '0.62rem', color: '#fff' }}>Facebook</span>
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* Simulated Bottom Navigation (EXACTLY MATCHING ONENUM/ONEOVA BOTTOM NAV IN SCREENSHOT) */}
          <nav className="phone-bottom-nav-real" aria-label="Oneova Bottom Navigation">
            {/* Tab 1: Reels */}
            <button
              className={`sim-nav-btn-real ${activeScreen === 'reels' ? 'active' : ''}`}
              onClick={() => setActiveScreen('reels')}
            >
              <div className="nav-btn-icon-wrap">
                <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4"><path d="m3 9 9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"></path></svg>
              </div>
              <span className="nav-btn-label">Reels</span>
            </button>

            {/* Tab 2: Chat */}
            <button className="sim-nav-btn-real">
              <div className="nav-btn-icon-wrap">
                <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"></path></svg>
                <span className="nav-badge-count">3</span>
              </div>
              <span className="nav-btn-label">Chat</span>
            </button>

            {/* Tab 3: STUDIO (+) (Matches Real Elevated Blue Button with Text STUDIO) */}
            <button
              className="sim-nav-btn-real studio-center-btn"
              onClick={() => setActiveScreen('editor')}
            >
              <div className="studio-pill-glow">
                <span className="studio-plus-icon">+</span>
              </div>
              <span className="nav-btn-label studio-text">STUDIO</span>
            </button>

            {/* Tab 4: AI Lab */}
            <button
              className={`sim-nav-btn-real ${activeScreen === 'rooms' ? 'active' : ''}`}
              onClick={() => setActiveScreen('rooms')}
            >
              <div className="nav-btn-icon-wrap">
                <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><rect width="7" height="7" x="3" y="3" rx="1"></rect><rect width="7" height="7" x="14" y="3" rx="1"></rect><rect width="7" height="7" x="14" y="14" rx="1"></rect><rect width="7" height="7" x="3" y="14" rx="1"></rect></svg>
                <span className="nav-dot-cyan"></span>
              </div>
              <span className="nav-btn-label">AI Lab</span>
            </button>

            {/* Tab 5: Me */}
            <button className="sim-nav-btn-real">
              <div className="nav-btn-icon-wrap">
                <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"><circle cx="12" cy="7" r="4"></circle><path d="M6 21v-2a4 4 0 0 1 4-4h4a4 4 0 0 1 4 4v2"></path></svg>
              </div>
              <span className="nav-btn-label">Me</span>
            </button>
          </nav>
        </div>
      </div>
    </div>
  );
}
