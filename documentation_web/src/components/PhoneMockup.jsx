import React, { useMemo, useRef, useState } from 'react';

const WALLET_CURRENCIES = {
  KES: { symbol: 'KES', personal: '48,920', business: '184,500', rail: 'M-Pesa STK · Airtel Money' },
  NGN: { symbol: 'NGN', personal: '425,000', business: '1,940,000', rail: 'Bank Transfer · Mobile Rails' },
  GHS: { symbol: 'GHS', personal: '6,840', business: '24,150', rail: 'MTN MoMo · Telecel Cash' },
  UGX: { symbol: 'UGX', personal: '1,380,000', business: '4,890,000', rail: 'MTN MoMo · Airtel Money' },
  USD: { symbol: 'USD', personal: '390.00', business: '1,480.00', rail: 'Bank Rail · Card Checkout' },
};

const ID_PROFILES = {
  KE: { flag: '🇰🇪', country: 'Kenya', name: 'Amina Wanjiku', handle: '@amina.crafts', level: 'Level 3 · Verified Creator & Merchant', idCode: 'OVA-ID-KE-8841' },
  NG: { flag: '🇳🇬', country: 'Nigeria', name: 'Tunde Adeyemi', handle: '@tunde.sound', level: 'Level 3 · Verified Creator & Merchant', idCode: 'OVA-ID-NG-5204' },
  GH: { flag: '🇬🇭', country: 'Ghana', name: 'Kofi Mensah', handle: '@kofi.atelier', level: 'Level 3 · Verified Creator & Merchant', idCode: 'OVA-ID-GH-3197' },
};

export default function PhoneMockup({
  theme = 'dark',
  showcase = { shops: [], products: [], reels: [], liveConnected: false },
  onOpenOvaAssistant,
  onSelectDoc,
}) {
  const [activeScreen, setActiveScreen] = useState('shops');
  const [activeFeedTab, setActiveFeedTab] = useState('biz');
  const [liked, setLiked] = useState(false);
  const [likeCount, setLikeCount] = useState(128);
  const [bookmarked, setBookmarked] = useState(false);
  const [floatingEmojis, setFloatingEmojis] = useState([]);
  const [isMuted, setIsMuted] = useState(true);
  const [isPlaying, setIsPlaying] = useState(true);
  const [walletKind, setWalletKind] = useState('business');
  const [walletCurrency, setWalletCurrency] = useState('KES');
  const [walletHidden, setWalletHidden] = useState(false);
  const [shopSubMode, setShopSubMode] = useState('live'); // 'live' | 'catalog'
  const [countryKey, setCountryKey] = useState('KE');
  const [ovaTranslated, setOvaTranslated] = useState(false);
  const [lightboxOpen, setLightboxOpen] = useState(false);
  const reelVideoRef = useRef(null);

  const liveShop = useMemo(() => {
    if (showcase?.shops?.length > 0) return showcase.shops[0];
    return {
      name: 'Oneova Creator Store',
      tagline: 'Pan-African Apparel & Crafted Goods',
      bio: 'Verified African business selling directly from Live broadcasts and 3D product rooms.',
      verified: true,
      categories: ['Fashion', 'Crafts'],
      avatarUrl: '/assets/images/oneova_logo.jpg',
    };
  }, [showcase?.shops]);

  const liveProducts = useMemo(() => {
    if (showcase?.products?.length > 0) return showcase.products.slice(0, 3);
    return [
      {
        id: 'demo-1',
        title: 'Handcrafted Leather Sneakers',
        price: 4500,
        currency: 'KES',
        category: 'Footwear',
        inStock: true,
        has3d: true,
      },
      {
        id: 'demo-2',
        title: 'Woven Heritage Jacket',
        price: 6800,
        currency: 'KES',
        category: 'Apparel',
        inStock: true,
        has3d: true,
      },
    ];
  }, [showcase?.products]);

  const liveReel = useMemo(() => {
    if (showcase?.reels?.length > 0) return showcase.reels[0];
    return {
      title: 'Building a borderless African creator economy with Oneova',
      description: 'Go live, showcase 3D shop goods, accept M-Pesa & MoMo in seconds. #oneova #AfricaCreators',
      likeCount: 128,
    };
  }, [showcase?.reels]);

  const walletInfo = WALLET_CURRENCIES[walletCurrency] || WALLET_CURRENCIES.KES;
  const idInfo = ID_PROFILES[countryKey] || ID_PROFILES.KE;

  const toggleReelPlay = () => {
    if (!reelVideoRef.current) return;
    if (reelVideoRef.current.paused) {
      reelVideoRef.current.play();
      setIsPlaying(true);
    } else {
      reelVideoRef.current.pause();
      setIsPlaying(false);
    }
  };

  const toggleReelMute = (e) => {
    e.stopPropagation();
    if (!reelVideoRef.current) return;
    reelVideoRef.current.muted = !isMuted;
    setIsMuted(!isMuted);
  };

  const handleLike = () => {
    if (!liked) {
      setLiked(true);
      setLikeCount((prev) => prev + 1);
      spawnEmoji('💖');
    } else {
      setLiked(false);
      setLikeCount((prev) => prev - 1);
    }
  };

  const spawnEmoji = (emoji) => {
    const id = Date.now() + Math.random();
    setFloatingEmojis((prev) => [...prev, { id, emoji, left: 56 + Math.random() * 28 }]);
    setTimeout(() => {
      setFloatingEmojis((prev) => prev.filter((item) => item.id !== id));
    }, 1300);
  };

  const stagePhoneSrc =
    theme === 'light'
      ? '/assets/images/live-stage-light.png'
      : '/assets/images/live-stage-dark.png';
  const stageWideSrc =
    theme === 'light'
      ? '/assets/images/live-studio-wide-light.png'
      : '/assets/images/live-studio-wide-dark.png';

  return (
    <div className="showcase-stage-card">
      <div className="stage-pink-ambient-glow" aria-hidden="true" />
      <div className="stage-blue-ambient-glow" aria-hidden="true" />

      {/* Africa Creator Economy Floating Callouts */}
      <div className="floating-badge-pill top-left">
        <span className="badge-pulse-dot pink" />
        <div className="badge-text-group">
          <span className="badge-title">AFRICA CREATOR ECONOMY</span>
          <span className="badge-sub">
            {showcase.liveConnected
              ? `● ${showcase.shops.length || 1} Open Biz Shop · ${showcase.products.length || 2} Live Items`
              : 'Live Commerce · 3D Shops · Gifts'}
          </span>
        </div>
      </div>

      <div className="floating-badge-pill top-right">
        <span className="badge-icon-star">💳</span>
        <div className="badge-text-group">
          <span className="badge-title">ONEOVA WALLET &amp; PAY</span>
          <span className="badge-sub">M-Pesa · MoMo · Airtel · Bank</span>
        </div>
      </div>

      <div className="floating-badge-pill bottom-left">
        <span className="badge-icon-disc">🪪</span>
        <div className="badge-text-group">
          <span className="badge-title">ONEOVA GLOBAL ID</span>
          <span className="badge-sub">Verified Creators &amp; Merchants</span>
        </div>
      </div>

      {/* Real App Interface Switcher */}
      <div className="emulator-controls" role="tablist" aria-label="Oneova Live Feature Demo">
        <button
          type="button"
          className={`sim-tab-btn ${activeScreen === 'shops' ? 'active' : ''}`}
          onClick={() => setActiveScreen('shops')}
        >
          <span>🛍️ Live &amp; 3D Shops</span>
          <span className="tab-pill-mini pink">Real UI</span>
        </button>
        <button
          type="button"
          className={`sim-tab-btn ${activeScreen === 'wallet' ? 'active' : ''}`}
          onClick={() => setActiveScreen('wallet')}
        >
          <span>💳 Wallet &amp; Pay</span>
          <span className="tab-pill-mini">MoMo</span>
        </button>
        <button
          type="button"
          className={`sim-tab-btn ${activeScreen === 'globalId' ? 'active' : ''}`}
          onClick={() => setActiveScreen('globalId')}
        >
          <span>🪪 Global ID</span>
          <span className="tab-pill-mini">Verified</span>
        </button>
        <button
          type="button"
          className={`sim-tab-btn ${activeScreen === 'reels' ? 'active' : ''}`}
          onClick={() => setActiveScreen('reels')}
        >
          <span>🎬 Feed &amp; Remix</span>
          <span className="tab-pill-mini pink">Live</span>
        </button>
        <button
          type="button"
          className={`sim-tab-btn ${activeScreen === 'stageWide' ? 'active' : ''}`}
          onClick={() => setActiveScreen('stageWide')}
        >
          <span>🎥 Studio Stage</span>
          <span className="tab-pill-mini">Multi-Guest</span>
        </button>
        <button
          type="button"
          className={`sim-tab-btn ${activeScreen === 'ova' ? 'active' : ''}`}
          onClick={() => setActiveScreen('ova')}
        >
          <span>✦ Ova AI</span>
          <span className="tab-pill-mini pink">Live Help</span>
        </button>
      </div>

      {/* Phone Mockup Frame */}
      <div className="phone-mockup-frame with-pink-shadows">
        <div className="screen-edge-pink-highlight" />

        <div className="phone-status-bar-real">
          <div className="status-left">
            <span className="status-clock">9:41</span>
            <span className="status-icon-g">●</span>
            <span style={{ fontSize: '0.62rem', fontWeight: 700, opacity: 0.85 }}>Oneova</span>
          </div>
          <div className="status-right">
            <span style={{ fontSize: '0.62rem', fontWeight: 700 }}>{walletCurrency}</span>
            <svg width="15" height="11" viewBox="0 0 24 14" fill="currentColor">
              <rect x="1" y="1" width="18" height="12" rx="3" fill="none" stroke="currentColor" strokeWidth="2" />
              <rect x="3" y="3" width="12" height="8" rx="1.5" />
            </svg>
          </div>
        </div>

        <div className="phone-screen-content">
          {/* SCREEN 1: LIVE COMMERCE & 3D SHOPS (REAL REFERENCE PNG + LIVE FIRESTORE DATA) */}
          {activeScreen === 'shops' && (
            <div className="sim-screen-view eco-screen-wrap">
              <div className="eco-subswitch-bar">
                <button
                  type="button"
                  className={`eco-sub-btn ${shopSubMode === 'live' ? 'active' : ''}`}
                  onClick={() => setShopSubMode('live')}
                >
                  Live Commerce Stage
                </button>
                <button
                  type="button"
                  className={`eco-sub-btn ${shopSubMode === 'catalog' ? 'active' : ''}`}
                  onClick={() => setShopSubMode('catalog')}
                >
                  Live Firestore Shop ({liveProducts.length})
                </button>
              </div>

              {shopSubMode === 'live' ? (
                <div className="ref-stage-canvas">
                  <img
                    src={stagePhoneSrc}
                    alt="Oneova Live Broadcast and Presenter Goods 3D Shopping Interface"
                    className="ref-phone-screenshot"
                  />
                  <div className="ref-overlay-actions">
                    <span className="ref-pill-chip">Official UI · Presenter’s Goods 3D Pin</span>
                    <button
                      type="button"
                      className="ref-jump-btn"
                      onClick={() => setShopSubMode('catalog')}
                    >
                      Inspect Live Store →
                    </button>
                  </div>
                </div>
              ) : (
                <div className="eco-card-scroll">
                  <div className="eco-store-banner">
                    <img
                      src={liveShop.avatarUrl || '/assets/images/oneova_logo.jpg'}
                      alt={liveShop.name}
                      className="eco-store-avatar"
                    />
                    <div className="eco-store-info">
                      <div className="eco-store-title-row">
                        <strong>{liveShop.name}</strong>
                        {liveShop.verified && <span className="eco-verified-check">✓</span>}
                      </div>
                      <span>{liveShop.tagline}</span>
                    </div>
                    <span className="eco-live-tag">{showcase.liveConnected ? 'LIVE DATA' : 'OPEN'}</span>
                  </div>

                  {liveShop.bio && <p className="eco-store-bio">{liveShop.bio}</p>}

                  <div className="eco-product-list">
                    {liveProducts.map((p) => (
                      <div key={p.id} className="eco-product-row">
                        {p.imageUrl ? (
                          <img src={p.imageUrl} alt={p.title} className="eco-product-thumb" />
                        ) : (
                          <div className="eco-product-thumb placeholder">🛍️</div>
                        )}
                        <div className="eco-product-meta">
                          <strong>{p.title}</strong>
                          <span>
                            {p.category || 'Biz Item'} {p.has3d ? '· 3D Ready' : ''} · {p.inStock ? 'In Stock' : 'Sold Out'}
                          </span>
                        </div>
                        <button
                          type="button"
                          className="eco-buy-btn"
                          onClick={() => setActiveScreen('wallet')}
                        >
                          {p.currency} {Number(p.price || 0).toLocaleString()}
                        </button>
                      </div>
                    ))}
                  </div>

                  <button
                    type="button"
                    className="eco-full-action-btn"
                    onClick={() => onSelectDoc?.('wallet-biz-commerce')}
                  >
                    Open Your Zero-Blocker Biz Shop Guide →
                  </button>
                </div>
              )}
            </div>
          )}

          {/* SCREEN 2: ONEOVA WALLET & PAY (AFRICAN MOBILE MONEY + BUSINESS BALANCE) */}
          {activeScreen === 'wallet' && (
            <div className="sim-screen-view eco-screen-wrap eco-wallet-screen">
              <div className="eco-wallet-head">
                <div>
                  <span className="eco-eyebrow">ONEOVA WALLET</span>
                  <h4>{walletKind === 'business' ? 'Business & Creator Balance' : 'Personal Balance'}</h4>
                </div>
                <select
                  className="eco-currency-select"
                  aria-label="Select local currency"
                  value={walletCurrency}
                  onChange={(e) => setWalletCurrency(e.target.value)}
                >
                  {Object.keys(WALLET_CURRENCIES).map((c) => (
                    <option key={c} value={c}>
                      {c}
                    </option>
                  ))}
                </select>
              </div>

              <div className="eco-balance-toggle">
                <button
                  type="button"
                  className={walletKind === 'personal' ? 'active' : ''}
                  onClick={() => setWalletKind('personal')}
                >
                  Personal
                </button>
                <button
                  type="button"
                  className={walletKind === 'business' ? 'active' : ''}
                  onClick={() => setWalletKind('business')}
                >
                  Business (Biz)
                </button>
              </div>

              <div className="eco-balance-card">
                <div className="eco-balance-top">
                  <span>Available in {walletInfo.symbol}</span>
                  <button
                    type="button"
                    className="eco-eye-btn"
                    onClick={() => setWalletHidden((v) => !v)}
                  >
                    {walletHidden ? 'Show' : 'Hide'}
                  </button>
                </div>
                <div className="eco-balance-amount">
                  {walletHidden
                    ? '••••••'
                    : `${walletInfo.symbol} ${walletKind === 'business' ? walletInfo.business : walletInfo.personal}`}
                </div>
                <div className="eco-balance-sub">
                  Rails: {walletInfo.rail} · Biometric Protected
                </div>
              </div>

              <div className="eco-wallet-actions-grid">
                <button type="button" className="eco-w-action" onClick={() => spawnEmoji('📲')}>
                  <span>📲</span>
                  <small>Add Money</small>
                </button>
                <button type="button" className="eco-w-action" onClick={() => spawnEmoji('⚡')}>
                  <span>⚡</span>
                  <small>Pay ID</small>
                </button>
                <button type="button" className="eco-w-action" onClick={() => spawnEmoji('📷')}>
                  <span>📷</span>
                  <small>Scan QR</small>
                </button>
                <button type="button" className="eco-w-action" onClick={() => spawnEmoji('🏦')}>
                  <span>🏦</span>
                  <small>Withdraw</small>
                </button>
              </div>

              <div className="eco-ledger-feed">
                <div className="eco-ledger-row">
                  <span>Live Shop Order Escrow</span>
                  <strong className="pos">+{walletInfo.symbol} 1,350</strong>
                </div>
                <div className="eco-ledger-row">
                  <span>Mobile Money Cashout Fee</span>
                  <strong>1.5% flat · Instant</strong>
                </div>
              </div>
            </div>
          )}

          {/* SCREEN 3: ONEOVA GLOBAL ID */}
          {activeScreen === 'globalId' && (
            <div className="sim-screen-view eco-screen-wrap eco-id-screen">
              <div className="eco-wallet-head">
                <div>
                  <span className="eco-eyebrow">ONEOVA GLOBAL ID</span>
                  <h4>Portable Creator Identity</h4>
                </div>
                <div className="eco-country-pills">
                  {Object.keys(ID_PROFILES).map((k) => (
                    <button
                      key={k}
                      type="button"
                      className={countryKey === k ? 'active' : ''}
                      onClick={() => setCountryKey(k)}
                    >
                      {ID_PROFILES[k].flag}
                    </button>
                  ))}
                </div>
              </div>

              <div className="eco-id-credential-card">
                <div className="eco-id-card-top">
                  <span className="eco-id-flag">{idInfo.flag} {idInfo.country}</span>
                  <span className="eco-verified-pill">✓ VERIFIED</span>
                </div>
                <strong className="eco-id-holder">{idInfo.name}</strong>
                <span className="eco-id-handle">{idInfo.handle} · {idInfo.idCode}</span>
                <div className="eco-id-badges-row">
                  <span>Identity KYC ✓</span>
                  <span>Business KYB ✓</span>
                  <span>Biometric Lock ✓</span>
                </div>
              </div>

              <div className="eco-id-checklist">
                <div className="eco-check-item">
                  <span>🛡️</span>
                  <div>
                    <strong>Instant Trust Across Borders</strong>
                    <small>Unlocks 18+ local-currency payouts, Biz store verification, and fan gifts.</small>
                  </div>
                </div>
                <div className="eco-check-item">
                  <span>🔗</span>
                  <div>
                    <strong>Link Up to 3 Creator Handles</strong>
                    <small>Verify all your creator &amp; store accounts with one hardware-backed ID.</small>
                  </div>
                </div>
                <div className="eco-check-item">
                  <span>📱</span>
                  <div>
                    <strong>SIM-Recycle &amp; Keystore Guard</strong>
                    <small>Signed credentials stay inside your phone’s secure vault.</small>
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* SCREEN 4: CREATOR FEED & REMIX */}
          {activeScreen === 'reels' && (
            <div className="sim-screen-view reels-screen-view">
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
                <div className="sim-reel-vignette-top" />
                <div className="sim-reel-vignette-bottom" />

                <button
                  type="button"
                  className="sim-reel-audio-control"
                  onClick={toggleReelMute}
                  aria-label={isMuted ? 'Unmute reel sound' : 'Mute reel sound'}
                >
                  <span>{isMuted ? '🔇 Sound Off' : '🔊 Sound On'}</span>
                </button>

                {!isPlaying && (
                  <div className="sim-reel-pause-indicator">
                    <svg width="32" height="32" viewBox="0 0 24 24" fill="#FFFFFF">
                      <polygon points="5 3 19 12 5 21 5 3" />
                    </svg>
                  </div>
                )}
              </div>

              <div className="sim-feed-header-real">
                <button type="button" className="feed-header-icon-btn" aria-label="Search">
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4">
                    <circle cx="11" cy="11" r="7" />
                    <path d="m21 21-4.35-4.35" />
                  </svg>
                </button>

                <div className="sim-tabs-row-real">
                  {['following', 'forYou', 'biz'].map((tab) => (
                    <span
                      key={tab}
                      className={`sim-feed-tab-real ${activeFeedTab === tab ? 'active' : ''}`}
                      onClick={() => setActiveFeedTab(tab)}
                    >
                      {tab === 'forYou' ? 'For You' : tab === 'biz' ? 'Biz' : 'Following'}
                    </span>
                  ))}
                </div>

                <div className="feed-header-bell-wrap">
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2">
                    <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9" />
                    <path d="M13.73 21a2 2 0 0 1-3.46 0" />
                  </svg>
                  <span className="bell-badge-dot" />
                </div>
              </div>

              <div className="sim-stories-bar-real">
                <div className="story-item-real">
                  <div className="story-avatar-wrap story-ring-blue">
                    <div className="story-logo-badge">
                      <img src="/assets/images/oneova_logo.jpg" alt="Your Story" className="story-img" />
                    </div>
                    <span className="story-plus-badge">+</span>
                  </div>
                  <span className="story-name-label">Your Story</span>
                </div>
                <div className="story-item-real">
                  <div className="story-avatar-wrap story-ring-blue">
                    <img src="/assets/images/alex_avatar.jpg" alt="Alex" className="story-img" />
                  </div>
                  <span className="story-name-label">Alex</span>
                </div>
                <div className="story-item-real" onClick={() => setActiveScreen('shops')}>
                  <div className="story-avatar-wrap story-ring-pink">
                    <div className="story-placeholder-avatar live">🛍️</div>
                  </div>
                  <span className="story-name-label" style={{ color: 'var(--brand-pink)' }}>Shop</span>
                </div>
              </div>

              <div className="sim-feed-canvas-real">
                <div className="sim-author-block-real">
                  <div className="author-tag-pill">
                    <span className="author-u-badge">O</span>
                    <span className="author-username">{liveShop.name}</span>
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="#007AFF">
                      <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z" />
                    </svg>
                  </div>

                  <p className="author-caption-text">{liveReel.title}</p>

                  <div
                    className="shopping-runway-pill"
                    onClick={() => {
                      setShopSubMode('catalog');
                      setActiveScreen('shops');
                    }}
                  >
                    <span className="shop-icon">🛍️</span>
                    <span className="shop-text">Shop {liveShop.name} ({liveProducts.length})</span>
                    <span className="shop-arrow">›</span>
                  </div>
                </div>

                <div className="sim-action-rail-real">
                  <button type="button" className="rail-action-btn" onClick={handleLike} aria-label="Like">
                    <div className={`rail-action-icon ${liked ? 'liked' : ''}`}>
                      <svg width="22" height="22" viewBox="0 0 24 24" fill={liked ? '#FF2D87' : 'none'} stroke={liked ? '#FF2D87' : '#FFFFFF'} strokeWidth="2.2">
                        <path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z" />
                      </svg>
                    </div>
                    <span className="rail-action-count">{likeCount}</span>
                  </button>

                  <div className="rail-action-btn" onClick={() => setBookmarked((v) => !v)}>
                    <div className="rail-action-icon">
                      <svg width="22" height="22" viewBox="0 0 24 24" fill={bookmarked ? '#FF2D87' : 'none'} stroke={bookmarked ? '#FF2D87' : '#FFFFFF'} strokeWidth="2.2">
                        <path d="m19 21-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z" />
                      </svg>
                    </div>
                    <span className="rail-action-count">{bookmarked ? 'Saved' : 'Save'}</span>
                  </div>

                  <div className="rail-remix-btn" onClick={() => spawnEmoji('⚡')}>
                    <div className="remix-icon-badge">★</div>
                    <span className="remix-label">REMIX</span>
                  </div>
                </div>

                {floatingEmojis.map((item) => (
                  <div key={item.id} className="floating-spark-emoji" style={{ right: `${item.left}px` }}>
                    {item.emoji}
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* SCREEN 5: OFFICIAL STUDIO STAGE WIDE REFERENCE */}
          {activeScreen === 'stageWide' && (
            <div className="sim-screen-view eco-screen-wrap">
              <div className="eco-stage-preview-box">
                <div className="eco-stage-head">
                  <strong>Interactive Live Stage</strong>
                  <span>Multi-Guest · Polls · Gifts · Goods</span>
                </div>
                <button
                  type="button"
                  className="eco-wide-thumb-btn"
                  onClick={() => setLightboxOpen(true)}
                  aria-label="Expand full Live Stage reference"
                >
                  <img
                    src={stageWideSrc}
                    alt="Oneova Live Stage multi-guest commerce layout"
                    className="eco-wide-thumb"
                  />
                  <span className="eco-expand-tag">Tap to expand widescreen UI ↗</span>
                </button>
                <div className="eco-stage-bullets">
                  <span>• Host + up to 4 guest panels on stage</span>
                  <span>• Live Presenter’s Goods 3D card &amp; fan Gifts</span>
                  <span>• Clean audience mode, polls, countdowns &amp; raffles</span>
                </div>
              </div>
            </div>
          )}

          {/* SCREEN 6: OVA PERSONAL AI & LIVE DESKTOP HELPER */}
          {activeScreen === 'ova' && (
            <div className="sim-screen-view eco-screen-wrap eco-ova-demo">
              <div className="eco-wallet-head">
                <div>
                  <span className="eco-eyebrow">OVA PERSONAL AI</span>
                  <h4>Power-Button &amp; Screen Assist</h4>
                </div>
              </div>

              <div className="eco-ova-aura-card">
                <div className="eco-ova-chip">Active Over Any App</div>
                <p>
                  {ovaTranslated
                    ? '“Karibu kwa Oneova Shop — Lipa kwa M-Pesa sasa.” (Swahili in-place overlay)'
                    : '“Welcome to Oneova Shop — Pay with M-Pesa in seconds.”'}
                </p>
                <button
                  type="button"
                  className="eco-sub-btn active"
                  onClick={() => setOvaTranslated((v) => !v)}
                >
                  {ovaTranslated ? 'Show Original English' : 'Translate In-Place (Swahili) ✦'}
                </button>
              </div>

              <div className="eco-id-checklist">
                <div className="eco-check-item">
                  <span>🖥️</span>
                  <div>
                    <strong>Mac &amp; Windows Desktop Agent</strong>
                    <small>Starts on boot and runs workflows across your computer (`⌥Space` / `Alt+Space`).</small>
                  </div>
                </div>
                <div className="eco-check-item">
                  <span>🤖</span>
                  <div>
                    <strong>Live AI Support Agent</strong>
                    <small>Checks real Wallet, ID &amp; Shop state and escalates live to a human admin.</small>
                  </div>
                </div>
              </div>

              {onOpenOvaAssistant && (
                <button type="button" className="eco-full-action-btn" onClick={onOpenOvaAssistant}>
                  Open Live Oneova Support Agent Now →
                </button>
              )}
            </div>
          )}

          {/* LOCKED BOTTOM NAVIGATION MATCHING lib/shared/widgets/oneova_bottom_nav.dart */}
          <nav className="phone-bottom-nav-real" aria-label="Oneova Bottom Navigation">
            <button
              type="button"
              className={`sim-nav-btn-real ${activeScreen === 'reels' ? 'active' : ''}`}
              onClick={() => setActiveScreen('reels')}
            >
              <div className="nav-btn-icon-wrap">
                <svg width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.3">
                  <path d="m3 9 9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
                </svg>
              </div>
              <span className="nav-btn-label">Reels</span>
            </button>

            <button
              type="button"
              className={`sim-nav-btn-real ${activeScreen === 'ova' ? 'active' : ''}`}
              onClick={() => setActiveScreen('ova')}
            >
              <div className="nav-btn-icon-wrap">
                <svg width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2">
                  <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
                </svg>
                <span className="nav-badge-count">AI</span>
              </div>
              <span className="nav-btn-label">Chat</span>
            </button>

            <button
              type="button"
              className="sim-nav-btn-real studio-center-btn"
              onClick={() => setActiveScreen('shops')}
            >
              <div className="studio-pill-glow">
                <span className="studio-plus-icon">+</span>
              </div>
              <span className="nav-btn-label studio-text">STUDIO</span>
            </button>

            <button
              type="button"
              className={`sim-nav-btn-real ${activeScreen === 'wallet' ? 'active' : ''}`}
              onClick={() => setActiveScreen('wallet')}
            >
              <div className="nav-btn-icon-wrap">
                <svg width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2">
                  <rect width="20" height="14" x="2" y="5" rx="2" />
                  <line x1="2" x2="22" y1="10" y2="10" />
                </svg>
                <span className="nav-dot-cyan" />
              </div>
              <span className="nav-btn-label">Wallet</span>
            </button>

            <button
              type="button"
              className={`sim-nav-btn-real ${activeScreen === 'globalId' ? 'active' : ''}`}
              onClick={() => setActiveScreen('globalId')}
            >
              <div className="nav-btn-icon-wrap">
                <svg width="21" height="21" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2">
                  <circle cx="12" cy="7" r="4" />
                  <path d="M6 21v-2a4 4 0 0 1 4-4h4a4 4 0 0 1 4 4v2" />
                </svg>
              </div>
              <span className="nav-btn-label">Me</span>
            </button>
          </nav>
        </div>
      </div>

      {/* Expandable Widescreen Studio Reference Lightbox */}
      {lightboxOpen && (
        <div
          className="modal-overlay"
          role="dialog"
          aria-modal="true"
          aria-label="Oneova Live Stage Reference"
          onClick={() => setLightboxOpen(false)}
        >
          <div className="eco-lightbox-card" onClick={(e) => e.stopPropagation()}>
            <div className="eco-lightbox-top">
              <strong>Oneova Live Stage &amp; Presenter’s Goods Reference</strong>
              <button
                type="button"
                className="modal-close-btn"
                onClick={() => setLightboxOpen(false)}
                aria-label="Close Preview"
              >
                ✕
              </button>
            </div>
            <img src={stageWideSrc} alt="Oneova Live Stage Full Screen Reference" className="eco-lightbox-img" />
          </div>
        </div>
      )}
    </div>
  );
}
