import React, { useEffect, useState } from 'react';
import { loadDesktopManifest } from './desktopManifest';

export default function DownloadModal({ isOpen, onClose }) {
  const [manifest, setManifest] = useState(null);

  useEffect(() => {
    const handleKeyDown = (e) => {
      if (e.key === 'Escape' && isOpen) {
        onClose();
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, onClose]);

  useEffect(() => {
    if (!isOpen) return;
    let alive = true;
    loadDesktopManifest().then((m) => {
      if (alive) setManifest(m);
    });
    return () => {
      alive = false;
    };
  }, [isOpen]);

  if (!isOpen) return null;

  const macUrl = manifest?.macos?.url || '/downloads/Oneova-Desktop-macOS.dmg';
  const winAvailable = manifest?.windows?.available === true;
  const winUrl =
    manifest?.windows?.url ||
    'https://github.com/cjaihub/mpepe_studio/releases/latest/download/Oneova-Desktop-Windows-x64.zip';

  return (
    <div className="modal-overlay" role="dialog" aria-modal="true" aria-labelledby="modal-title" onClick={onClose}>
      <div className="modal-card" onClick={(e) => e.stopPropagation()}>
        <button className="modal-close-btn" onClick={onClose} aria-label="Close dialog">✕</button>

        <h2 className="modal-title" style={{ fontSize: '1.65rem', fontWeight: 900, marginBottom: '8px' }} id="modal-title">
          Get Oneova — Mobile &amp; Desktop
        </h2>
        <p style={{ fontSize: '0.88rem', color: 'var(--text-secondary)', marginBottom: '18px', lineHeight: 1.5 }}>
          Install Oneova on your phone or download the autonomous Desktop Assistant for macOS and Windows.
        </p>

        <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
          <a
            href={macUrl}
            download="Oneova-Desktop-macOS.dmg"
            className="btn-primary"
            style={{ width: '100%', textAlign: 'center', textDecoration: 'none' }}
          >
             Download Desktop Assistant for macOS (.dmg)
          </a>

          <a
            href={winUrl}
            download={winAvailable ? (manifest?.windows?.fileName || 'Oneova-Desktop-Windows-x64.zip') : undefined}
            target={winAvailable ? undefined : '_blank'}
            rel={winAvailable ? undefined : 'noreferrer'}
            className="btn-secondary"
            style={{ width: '100%', textAlign: 'center', textDecoration: 'none', borderColor: '#FF2D87' }}
          >
            ⊞ Download Desktop Assistant for Windows (.zip / .exe)
          </a>

          <a
            href="#desktop"
            onClick={onClose}
            className="btn-secondary"
            style={{ width: '100%', textAlign: 'center', textDecoration: 'none' }}
          >
            View Desktop Specs, Hotkeys &amp; Studio Skills
          </a>

          <a
            href="https://play.google.com/store/apps/details?id=com.oneova.app"
            target="_blank"
            rel="noreferrer"
            className="btn-secondary"
            style={{ width: '100%', textAlign: 'center', textDecoration: 'none' }}
          >
            Android on Google Play (Power-Button Ova + Live Screen Translate)
          </a>
        </div>
      </div>
    </div>
  );
}
