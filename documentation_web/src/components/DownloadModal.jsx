import React, { useEffect } from 'react';

export default function DownloadModal({ isOpen, onClose }) {
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
    <div className="modal-overlay" role="dialog" aria-modal="true" aria-labelledby="modal-title" onClick={onClose}>
      <div className="modal-card" onClick={(e) => e.stopPropagation()}>
        <button className="modal-close-btn" onClick={onClose} aria-label="Close dialog">✕</button>
        
        <h2 className="modal-title" style={{ fontSize: '1.8rem', fontWeight: 900, marginBottom: '8px' }} id="modal-title">
          Get Oneova Mobile
        </h2>
        <p style={{ fontSize: '0.9rem', color: 'var(--text-secondary)', marginBottom: '16px' }}>
          Scan the QR code with your phone camera or select your platform below to download immediately.
        </p>

        {/* High-Resolution SVG QR Code */}
        <div className="qr-code-box">
          <svg viewBox="0 0 100 100" fill="#000000">
            {/* Position Markers */}
            <rect x="5" y="5" width="30" height="30" fill="#000000"/>
            <rect x="9" y="9" width="22" height="22" fill="#FFFFFF"/>
            <rect x="13" y="13" width="14" height="14" fill="#000000"/>

            <rect x="65" y="5" width="30" height="30" fill="#000000"/>
            <rect x="69" y="9" width="22" height="22" fill="#FFFFFF"/>
            <rect x="73" y="13" width="14" height="14" fill="#000000"/>

            <rect x="5" y="65" width="30" height="30" fill="#000000"/>
            <rect x="9" y="69" width="22" height="22" fill="#FFFFFF"/>
            <rect x="13" y="73" width="14" height="14" fill="#000000"/>

            {/* Stylized QR Matrix Dots */}
            <rect x="42" y="8" width="5" height="5"/>
            <rect x="52" y="8" width="5" height="5"/>
            <rect x="42" y="18" width="5" height="5"/>
            <rect x="47" y="24" width="5" height="5"/>
            <rect x="52" y="24" width="5" height="5"/>

            <rect x="8" y="42" width="5" height="5"/>
            <rect x="18" y="42" width="5" height="5"/>
            <rect x="28" y="42" width="5" height="5"/>
            <rect x="8" y="52" width="5" height="5"/>

            <rect x="42" y="42" width="16" height="16" fill="#007AFF" rx="4"/>
            <circle cx="50" cy="50" r="5" fill="#FFFFFF"/>

            <rect x="65" y="42" width="5" height="5"/>
            <rect x="75" y="42" width="5" height="5"/>
            <rect x="85" y="42" width="5" height="5"/>
            <rect x="70" y="52" width="5" height="5"/>
            <rect x="80" y="52" width="5" height="5"/>

            <rect x="42" y="65" width="5" height="5"/>
            <rect x="52" y="65" width="5" height="5"/>
            <rect x="42" y="75" width="5" height="5"/>
            <rect x="47" y="85" width="5" height="5"/>
            <rect x="52" y="85" width="5" height="5"/>

            <rect x="65" y="65" width="5" height="5"/>
            <rect x="75" y="65" width="5" height="5"/>
            <rect x="85" y="75" width="5" height="5"/>
            <rect x="70" y="85" width="5" height="5"/>
            <rect x="85" y="85" width="5" height="5"/>
          </svg>
        </div>

        {/* Download Buttons */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
          <button
            className="btn-primary"
            style={{ width: '100%' }}
            onClick={() => alert('Opening Oneova iOS TestFlight link...')}
          >
            Download for iOS (App Store / TestFlight)
          </button>
          <button
            className="btn-secondary"
            style={{ width: '100%' }}
            onClick={() => alert('Starting Oneova Android APK download...')}
          >
            Download for Android (Google Play / APK)
          </button>
        </div>
      </div>
    </div>
  );
}
