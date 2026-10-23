import React, { useState, useRef, useEffect } from 'react';

export default function FloatingVideoWidget() {
  const [isVisible, setIsVisible] = useState(false);
  const [isMinimized, setIsMinimized] = useState(false);
  const [isMuted, setIsMuted] = useState(true);
  const miniVideoRef = useRef(null);

  // Show floating widget after scrolling down past the hero section (e.g. 600px)
  useEffect(() => {
    const handleScroll = () => {
      if (window.scrollY > 500) {
        setIsVisible(true);
      } else {
        setIsVisible(false);
      }
    };
    window.addEventListener('scroll', handleScroll, { passive: true });
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  const scrollToTheater = () => {
    const aboutSection = document.getElementById('about');
    if (aboutSection) {
      aboutSection.scrollIntoView({ behavior: 'smooth' });
    }
  };

  const toggleSound = (e) => {
    e.stopPropagation();
    if (miniVideoRef.current) {
      miniVideoRef.current.muted = !isMuted;
      setIsMuted(!isMuted);
    }
  };

  if (!isVisible) return null;

  return (
    <aside
      className={`floating-video-dock ${isMinimized ? 'minimized' : ''}`}
      aria-label="Oneova Video Preview"
    >
      <div className="dock-halo-pink" aria-hidden="true" />

      {!isMinimized ? (
        <div className="dock-card-body" onClick={scrollToTheater}>
          <div className="dock-top-controls">
            <div className="dock-live-tag">
              <span className="dock-pulse-dot"></span>
              <span>ONEOVA IN MOTION</span>
            </div>
            <div className="dock-actions">
              <button
                className="dock-icon-btn"
                onClick={toggleSound}
                title={isMuted ? "Unmute Sound" : "Mute Sound"}
              >
                {isMuted ? '🔇' : '🔊'}
              </button>
              <button
                className="dock-icon-btn"
                onClick={(e) => {
                  e.stopPropagation();
                  setIsMinimized(true);
                }}
                title="Minimize Preview"
              >
                ✕
              </button>
            </div>
          </div>

          <div className="dock-video-container">
            <video
              ref={miniVideoRef}
              className="dock-video-stream"
              src="/assets/oneova_promo.mp4"
              poster="/assets/images/oneova_reel_bg.jpg"
              autoPlay
              loop
              muted={isMuted}
              playsInline
            />
            <div className="dock-play-badge">
              <span>View Full Cinema</span>
              <span className="dock-arrow">↗</span>
            </div>
          </div>
        </div>
      ) : (
        <button
          className="dock-reopen-pill"
          onClick={() => setIsMinimized(false)}
          title="Watch Oneova Video"
        >
          <span className="dock-pulse-dot"></span>
          <span>Watch Oneova Reel</span>
          <span className="reopen-icon">▶</span>
        </button>
      )}
    </aside>
  );
}
