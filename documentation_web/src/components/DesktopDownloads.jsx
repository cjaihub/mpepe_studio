import React, { useEffect, useState } from 'react';
import {
  DEFAULT_DESKTOP_MANIFEST,
  loadDesktopManifest,
} from './desktopManifest';

export default function DesktopDownloads() {
  const [manifest, setManifest] = useState(DEFAULT_DESKTOP_MANIFEST);
  const [detectedOs, setDetectedOs] = useState('mac');
  const [showWinGuide, setShowWinGuide] = useState(false);

  useEffect(() => {
    const ua = (navigator.userAgent || '').toLowerCase();
    if (ua.includes('win')) setDetectedOs('win');
    else setDetectedOs('mac');

    let alive = true;
    loadDesktopManifest().then((m) => {
      if (alive) setManifest(m);
    });
    return () => {
      alive = false;
    };
  }, []);

  const skills = [
    {
      title: 'DaVinci Resolve Grading & Timeline',
      desc: 'Controls nodes, CDL lift/gamma/gain color grades, LUTs, timeline razor cuts, markers, and Deliver exports.',
      accent: 'blue',
    },
    {
      title: 'Logic Pro & Studio DAW Mixing',
      desc: 'Creates audio & instrument tracks, opens Mixer and Smart Controls, bounces stems, and runs transport hands-free.',
      accent: 'pink',
    },
    {
      title: 'Adobe Creative Cloud Automation',
      desc: 'Runs native ExtendScript & shortcuts across Premiere Pro, After Effects, Photoshop, and Illustrator.',
      accent: 'blue',
    },
    {
      title: 'Starts on Boot · Summons Anywhere',
      desc: 'Sits quietly in your Menu Bar or Windows System Tray, boots automatically, and pops the HUD over any full-screen app.',
      accent: 'pink',
    },
  ];

  const mac = manifest.macos;
  const win = manifest.windows;

  return (
    <section
      id="desktop"
      style={{
        maxWidth: '1160px',
        margin: '0 auto',
        padding: '72px 24px 40px',
        position: 'relative',
        zIndex: 2,
      }}
    >
      <div
        style={{
          borderRadius: '24px',
          padding: '40px 32px',
          background:
            'linear-gradient(145deg, rgba(12,79,168,0.14), rgba(255,45,135,0.08))',
          border: '1px solid rgba(12,79,168,0.35)',
          backdropFilter: 'blur(18px)',
        }}
      >
        <div style={{ textAlign: 'center', maxWidth: '760px', margin: '0 auto 32px' }}>
          <div
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: '8px',
              padding: '6px 14px',
              borderRadius: '999px',
              background: 'rgba(12,79,168,0.18)',
              border: '1px solid rgba(12,79,168,0.4)',
              fontSize: '0.78rem',
              fontWeight: 800,
              letterSpacing: '0.06em',
              marginBottom: '14px',
              color: 'var(--text-primary)',
            }}
          >
            <span style={{ color: '#FF2D87' }}>●</span>
            <span>ONEOVA DESKTOP ASSISTANT · v{manifest.version}</span>
          </div>

          <h2 className="section-title" style={{ marginBottom: '12px' }}>
            Your Computer’s Autonomous AI — For Mac &amp; Windows
          </h2>
          <p style={{ color: 'var(--text-secondary)', fontSize: '1.02rem', lineHeight: 1.6 }}>
            Starts itself automatically when you turn on your computer, wakes from any app with{' '}
            <strong>⌥Space</strong> (Mac) or <strong>Alt+Space</strong> (Windows), speaks in natural human voice via{' '}
            <strong>Vertex Gemini Live</strong>, and knows how to drive <strong>DaVinci Resolve, Logic Pro, Adobe Premiere, After Effects, Photoshop</strong> &amp; your OS.
          </p>
        </div>

        {/* Two OS Cards: macOS + Windows */}
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))',
            gap: '20px',
            marginBottom: '28px',
          }}
        >
          {/* macOS Card */}
          <div
            className="feature-card"
            style={{
              padding: '24px',
              border:
                detectedOs === 'mac'
                  ? '1.5px solid #0C4FA8'
                  : '1px solid rgba(148,163,184,0.2)',
            }}
          >
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '10px' }}>
              <span style={{ fontWeight: 800, fontSize: '1.15rem', color: 'var(--text-primary)' }}>
                 Oneova for macOS
              </span>
              {detectedOs === 'mac' && (
                <span
                  style={{
                    fontSize: '0.72rem',
                    fontWeight: 800,
                    padding: '3px 9px',
                    borderRadius: '999px',
                    background: '#0C4FA8',
                    color: '#FFFFFF',
                  }}
                >
                  RECOMMENDED
                </span>
              )}
            </div>
            <p style={{ fontSize: '0.88rem', color: 'var(--text-secondary)', marginBottom: '12px' }}>
              {mac.sizeLabel} · {mac.requirements}
            </p>
            <ul
              style={{
                fontSize: '0.84rem',
                color: 'var(--text-secondary)',
                paddingLeft: '18px',
                marginBottom: '18px',
                lineHeight: 1.65,
              }}
            >
              <li>Global Hotkey: <strong>{mac.hotkey}</strong></li>
              <li>{mac.startup}</li>
              <li>Native Logic Pro, Final Cut Pro, DaVinci Resolve &amp; Adobe ExtendScript skills</li>
            </ul>
            {mac.available ? (
              <a
                href={mac.url}
                download={mac.fileName}
                className="btn-primary"
                style={{
                  width: '100%',
                  display: 'inline-flex',
                  justifyContent: 'center',
                  alignItems: 'center',
                  textDecoration: 'none',
                  gap: '8px',
                }}
              >
                <span>Download {mac.fileName}</span>
                {mac.fileSizeLabel ? <small>({mac.fileSizeLabel})</small> : null}
              </a>
            ) : (
              <button
                type="button"
                className="btn-secondary"
                style={{ width: '100%' }}
                disabled
              >
                macOS build preparing…
              </button>
            )}
            {mac.sha256 ? (
              <div style={{ marginTop: '8px', fontSize: '0.72rem', color: 'var(--text-secondary)', fontFamily: 'JetBrains Mono, monospace', wordBreak: 'break-all' }}>
                SHA-256: {mac.sha256.slice(0, 20)}…
              </div>
            ) : null}
          </div>

          {/* Windows Card */}
          <div
            className="feature-card highlight-pink"
            style={{
              padding: '24px',
              border:
                detectedOs === 'win'
                  ? '1.5px solid #FF2D87'
                  : '1px solid rgba(148,163,184,0.2)',
            }}
          >
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '10px' }}>
              <span style={{ fontWeight: 800, fontSize: '1.15rem', color: 'var(--text-primary)' }}>
                ⊞ Oneova for Windows
              </span>
              {detectedOs === 'win' && (
                <span
                  style={{
                    fontSize: '0.72rem',
                    fontWeight: 800,
                    padding: '3px 9px',
                    borderRadius: '999px',
                    background: '#FF2D87',
                    color: '#FFFFFF',
                  }}
                >
                  RECOMMENDED
                </span>
              )}
            </div>
            <p style={{ fontSize: '0.88rem', color: 'var(--text-secondary)', marginBottom: '12px' }}>
              {win.sizeLabel} · {win.requirements}
            </p>
            <ul
              style={{
                fontSize: '0.84rem',
                color: 'var(--text-secondary)',
                paddingLeft: '18px',
                marginBottom: '18px',
                lineHeight: 1.65,
              }}
            >
              <li>Global Hotkey: <strong>{win.hotkey}</strong></li>
              <li>{win.startup}</li>
              <li>Win32 FFI mouse/keys, DaVinci Resolve Python API, Adobe COM/JSX &amp; DAW automation</li>
            </ul>
            {win.available ? (
              <a
                href={win.url}
                download={win.fileName}
                className="btn-primary"
                style={{
                  width: '100%',
                  display: 'inline-flex',
                  justifyContent: 'center',
                  alignItems: 'center',
                  textDecoration: 'none',
                  background: '#FF2D87',
                  gap: '8px',
                }}
              >
                <span>Download {win.fileName}</span>
                {win.fileSizeLabel ? <small>({win.fileSizeLabel})</small> : null}
              </a>
            ) : (
              <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                <a
                  href={win.url}
                  target="_blank"
                  rel="noreferrer"
                  className="btn-secondary"
                  style={{
                    width: '100%',
                    display: 'inline-flex',
                    justifyContent: 'center',
                    alignItems: 'center',
                    textDecoration: 'none',
                  }}
                >
                  <span>Windows x64 Release (.zip / .exe)</span>
                </a>
                <button
                  type="button"
                  onClick={() => setShowWinGuide((v) => !v)}
                  style={{
                    background: 'none',
                    border: 'none',
                    color: '#FF2D87',
                    fontSize: '0.78rem',
                    fontWeight: 700,
                    cursor: 'pointer',
                  }}
                >
                  {showWinGuide ? 'Hide local Windows build command ▲' : 'Build Windows .exe locally via PowerShell ▼'}
                </button>
              </div>
            )}
            {showWinGuide && (
              <pre
                style={{
                  marginTop: '10px',
                  padding: '10px',
                  borderRadius: '10px',
                  fontSize: '0.74rem',
                  overflowX: 'auto',
                  background: 'rgba(10,15,29,0.72)',
                  color: '#E2E8F0',
                  fontFamily: 'JetBrains Mono, monospace',
                }}
              >
                {`git clone https://github.com/cjaihub/mpepe_studio.git\npowershell -ExecutionPolicy Bypass -File tools/desktop/build_windows.ps1`}
              </pre>
            )}
          </div>
        </div>

        {/* Pro Creative Skills Strip */}
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))',
            gap: '14px',
          }}
        >
          {skills.map((s) => (
            <div
              key={s.title}
              style={{
                padding: '16px',
                borderRadius: '14px',
                background: 'var(--dark-surface-elevated)',
                border: `1px solid ${s.accent === 'pink' ? 'rgba(255,45,135,0.28)' : 'rgba(12,79,168,0.28)'}`,
              }}
            >
              <div
                style={{
                  fontWeight: 700,
                  fontSize: '0.92rem',
                  color: 'var(--text-primary)',
                  marginBottom: '6px',
                }}
              >
                {s.title}
              </div>
              <div style={{ fontSize: '0.81rem', color: 'var(--text-secondary)', lineHeight: 1.5 }}>
                {s.desc}
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
