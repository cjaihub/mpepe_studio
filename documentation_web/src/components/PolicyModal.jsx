import React, { useState, useEffect } from 'react';

export default function PolicyModal({ isOpen, onClose, initialTab = 'guidelines' }) {
  const [activeTab, setActiveTab] = useState(initialTab);
  const [searchFilter, setSearchFilter] = useState('');

  useEffect(() => {
    if (initialTab) {
      setActiveTab(initialTab);
    }
  }, [initialTab]);

  useEffect(() => {
    const handleKeyDown = (e) => {
      if (e.key === 'Escape' && isOpen) {
        onClose();
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, onClose]);

  if (!isOpen) return null;

  return (
    <div className="policy-modal-overlay" role="dialog" aria-modal="true" onClick={onClose}>
      <div className="policy-modal-container" onClick={(e) => e.stopPropagation()}>
        {/* Header Bar */}
        <div className="policy-modal-header">
          <div className="policy-header-brand">
            <div className="policy-badge-icon">🛡️</div>
            <div>
              <div className="policy-title-row">
                <h2 className="policy-modal-title">Trust, Safety & Legal Center</h2>
                <span className="policy-standard-pill">TikTok & Meta Standard</span>
              </div>
              <p className="policy-subtitle">
                Official regulatory disclosures, community guidelines, and creator terms for the Oneova ecosystem.
              </p>
            </div>
          </div>
          <button className="policy-close-btn" onClick={onClose} aria-label="Close modal">✕</button>
        </div>

        {/* Tab Navigation */}
        <div className="policy-tab-bar">
          <button
            className={`policy-tab-btn ${activeTab === 'guidelines' ? 'active' : ''}`}
            onClick={() => setActiveTab('guidelines')}
          >
            <span>📜 Community Guidelines</span>
            <span className="tab-indicator-badge pink">Verified</span>
          </button>
          <button
            className={`policy-tab-btn ${activeTab === 'privacy' ? 'active' : ''}`}
            onClick={() => setActiveTab('privacy')}
          >
            <span>🔒 Privacy Policy</span>
            <span className="tab-indicator-badge blue">GDPR / CCPA</span>
          </button>
          <button
            className={`policy-tab-btn ${activeTab === 'terms' ? 'active' : ''}`}
            onClick={() => setActiveTab('terms')}
          >
            <span>⚖️ Terms of Service</span>
            <span className="tab-indicator-badge pink">Creator Rights</span>
          </button>
          <button
            className={`policy-tab-btn ${activeTab === 'deletion' ? 'active' : ''}`}
            onClick={() => setActiveTab('deletion')}
          >
            <span>🗑️ Data Deletion</span>
            <span className="tab-indicator-badge">Self-Serve</span>
          </button>
        </div>

        {/* Modal Body with Scrollable Text */}
        <div className="policy-modal-body">
          {activeTab === 'guidelines' && (
            <div className="policy-section-content">
              <div className="policy-callout pink">
                <div className="callout-header">
                  <span className="callout-icon">✦</span>
                  <strong>TikTok-Standard Community Governance</strong>
                </div>
                <p>
                  Oneova is committed to an authentic, uplifting, and safe environment. We enforce strict automated moderation, proactive reporting, and creator-first transparency across all Live Broadcasts, Creator Rooms, and Reels.
                </p>
              </div>

              <h3>1. Absolute Zero-Tolerance Rules</h3>
              <ul>
                <li><strong>Harassment & Bullying:</strong> Targeted hostility, doxxing, non-consensual sharing of personal information, or hate speech targeting race, gender, religion, or orientation results in immediate suspension and device banning.</li>
                <li><strong>Harmful & Dangerous Content:</strong> Glorification of self-harm, dangerous viral challenges, or promotion of illegal activities is strictly banned.</li>
                <li><strong>Child Safety & Minor Protection:</strong> Strict verification protocols safeguard underage users. Minors cannot broadcast live without verified parental oversight.</li>
              </ul>

              <h3>2. Commercial Disclosure & FTC Compliance</h3>
              <ul>
                <li><strong>Mandatory Sponsorship Tags:</strong> Any content incentivized by a brand, product gifting, or financial sponsorship must use Oneova's built-in <code>#ad</code> or <code>#sponsored</code> commercial toggle.</li>
                <li><strong>Deceptive Marketing:</strong> Financial scams, fake giveaways, and unverified medical claims result in permanent account termination.</li>
              </ul>

              <h3>3. Original Media & Copyright Protection</h3>
              <ul>
                <li><strong>Audio Rights:</strong> Music used in Reels and Live streams must be selected from the Oneova Licensed Sound Library or registered by original sound creators.</li>
                <li><strong>Duets & Remixes:</strong> When you remix another creator's reel or audio disc, attribution is permanently pinned to your post. Original creators can disable remixing on any reel at will.</li>
              </ul>
            </div>
          )}

          {activeTab === 'privacy' && (
            <div className="policy-section-content">
              <div className="policy-callout blue">
                <div className="callout-header">
                  <span className="callout-icon">🔒</span>
                  <strong>End-to-End Encryption & Creator Privacy</strong>
                </div>
                <p>
                  Your media, drafts, and camera streams belong to you. Oneova never sells your private data, location telemetry, or unpublished editor drafts to third-party data brokers.
                </p>
              </div>

              <h3>1. Data We Collect to Power Pro Features</h3>
              <ul>
                <li><strong>Profile & Identity:</strong> Username, verified creator badge status, email or phone authentication for secure login.</li>
                <li><strong>Live Streaming & Audio Feeds:</strong> Live camera video and room audio are processed exclusively for real-time delivery with zero unauthorized archival.</li>
                <li><strong>Mobile Editor Telemetry:</strong> AI subject cutout processing runs entirely locally on your device hardware whenever supported.</li>
              </ul>

              <h3>2. Data Retention & Third-Party Sharing</h3>
              <ul>
                <li>We do not sell user data. Aggregated analytics are only used to optimize stream delivery and bandwidth caching.</li>
                <li>Cross-platform publishing to TikTok, YouTube, Instagram, and Facebook transmits only the assets you explicitly select during export.</li>
              </ul>
            </div>
          )}

          {activeTab === 'terms' && (
            <div className="policy-section-content">
              <div className="policy-callout pink">
                <div className="callout-header">
                  <span className="callout-icon">⚖️</span>
                  <strong>Creator Ownership & Fair Monetization</strong>
                </div>
                <p>
                  By creating on Oneova, you retain 100% intellectual property ownership of your original video, audio masters, and creative projects.
                </p>
              </div>

              <h3>1. Creator Rights & Licensing</h3>
              <ul>
                <li>You grant Oneova a non-exclusive, worldwide license solely to distribute, display, and stream your public content to your audience.</li>
                <li>You can remove, unlist, or delete your content at any time; deletion takes effect immediately across all global edge nodes.</li>
              </ul>

              <h3>2. Virtual Gifting & Creator Payouts</h3>
              <ul>
                <li>Audience members can send virtual gifts during 4K Live Broadcasts and inside Creator Rooms.</li>
                <li>Gift tokens are converted directly into creator earnings and can be withdrawn to connected payout methods subject to verified identity and fraud review.</li>
              </ul>
            </div>
          )}

          {activeTab === 'deletion' && (
            <div className="policy-section-content">
              <div className="policy-callout">
                <div className="callout-header">
                  <span className="callout-icon">🗑️</span>
                  <strong>Instant Self-Service Data Deletion</strong>
                </div>
                <p>
                  You have full autonomy over your account and media footprint. Request immediate automated deletion from inside the mobile app or via web submission.
                </p>
              </div>

              <h3>How to Delete Your Oneova Account & Data:</h3>
              <ol style={{ paddingLeft: '20px', margin: '14px 0', color: 'var(--text-secondary)' }}>
                <li>Open the Oneova mobile app and tap your <strong>Profile (Me)</strong> tab.</li>
                <li>Tap <strong>Settings & Privacy</strong> (gear icon in the top right).</li>
                <li>Navigate to <strong>Account Security & Privacy Controls</strong>.</li>
                <li>Select <strong>Delete Account & Purge Media</strong> and confirm with your security PIN.</li>
              </ol>
              <p>
                All uploaded videos, drafts, messages, and followers are permanently purged from all production databases within 24 hours.
              </p>
            </div>
          )}
        </div>

        {/* Modal Footer */}
        <div className="policy-modal-footer">
          <div className="policy-footer-note">
            Last updated: October 2026 • Compliant with FTC, GDPR & TikTok Trust Standards
          </div>
          <div style={{ display: 'flex', gap: '10px' }}>
            <a
              href={activeTab === 'privacy' ? '/privacy.html' : activeTab === 'terms' ? '/terms.html' : '/privacy.html'}
              className="btn-secondary"
              style={{ fontSize: '0.82rem', padding: '8px 14px' }}
              target="_blank"
              rel="noreferrer"
            >
              Open Full Page ↗
            </a>
            <button
              className="btn-primary"
              style={{ fontSize: '0.82rem', padding: '8px 18px' }}
              onClick={onClose}
            >
              Done & Close
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
