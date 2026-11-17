import React, { useState, useEffect, useMemo } from 'react';
import {
  PLATFORM_BASELINE_DOCS,
  getStandaloneLegalHref,
  getOfficialPdfHref,
} from '../data/platformCatalog';

const POLICY_TABS = [
  { id: 'guidelines', icon: '📜', label: 'Community Rules', pill: 'Anti-Scam', accent: 'pink' },
  { id: 'terms', icon: '⚖️', label: 'Terms of Service', pill: '100% Creator IP', accent: 'blue' },
  { id: 'privacy', icon: '🔒', label: 'Privacy Policy', pill: 'Zero Data Sales', accent: 'pink' },
  { id: 'safety', icon: '🛡️', label: 'Teen & Child Safety', pill: '116 Helplines', accent: 'pink' },
  { id: 'biz', icon: '💳', label: 'Biz & Wallet', pill: 'Mobile Money', accent: 'blue' },
  { id: 'deletion', icon: '🗑️', label: 'Data Deletion', pill: '2-Tap Erase', accent: '' },
  { id: 'law_enforcement', icon: '🏛️', label: 'Law Enforcement', pill: 'Due Process', accent: 'blue' },
  { id: 'africa', icon: '🌍', label: 'Africa & Global Law', pill: 'ODPC · NDPA · POPIA · GDPR', accent: 'pink' },
];

export default function PolicyModal({
  isOpen,
  onClose,
  initialTab = 'guidelines',
  docs = [],
}) {
  const [activeTab, setActiveTab] = useState(initialTab);

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

  const sourceDocs = docs && docs.length > 0 ? docs : PLATFORM_BASELINE_DOCS;

  const activeDoc = useMemo(() => {
    return (
      sourceDocs.find((d) => d.policyTab === activeTab) ||
      PLATFORM_BASELINE_DOCS.find((d) => d.policyTab === activeTab) ||
      sourceDocs.find((d) => d.docType !== 'feature')
    );
  }, [sourceDocs, activeTab]);

  if (!isOpen) return null;

  const standaloneHref = getStandaloneLegalHref(activeDoc) || '/legal.html';
  const officialPdfHref = getOfficialPdfHref(activeDoc);

  return (
    <div className="policy-modal-overlay" role="dialog" aria-modal="true" onClick={onClose}>
      <div className="policy-modal-container" onClick={(e) => e.stopPropagation()}>
        {/* Header Bar */}
        <div className="policy-modal-header">
          <div className="policy-header-brand">
            <div className="policy-badge-icon">🛡️</div>
            <div>
              <div className="policy-title-row">
                <h2 className="policy-modal-title">Trust, Safety & Global Legal Center</h2>
                <span className="policy-standard-pill">
                  {activeDoc?.isLiveFromCloud ? '● Live Cloud Synced' : 'Africa & Global Standard'}
                </span>
              </div>
              <p className="policy-subtitle">
                Plain-language community rules, creator IP terms, privacy protections, and African &
                international statutory compliance—synced live with the Oneova App.
              </p>
            </div>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <button
              type="button"
              className="policy-close-btn"
              onClick={onClose}
              aria-label="Close modal"
            >
              ✕
            </button>
          </div>
        </div>

        {/* Tab Navigation */}
        <div className="policy-tab-bar" style={{ overflowX: 'auto', flexWrap: 'nowrap' }}>
          {POLICY_TABS.map((t) => (
            <button
              key={t.id}
              type="button"
              className={`policy-tab-btn ${activeTab === t.id ? 'active' : ''}`}
              onClick={() => setActiveTab(t.id)}
              style={{ flexShrink: 0 }}
            >
              <span>
                {t.icon} {t.label}
              </span>
              <span className={`tab-indicator-badge ${t.accent}`}>{t.pill}</span>
            </button>
          ))}
        </div>

        {/* Modal Body */}
        <div className="policy-modal-body">
          {activeDoc && (
            <div className="policy-section-content">
              <div className={`policy-callout ${activeDoc.isAccentBadge ? 'pink' : 'blue'}`}>
                <div className="callout-header">
                  <span className="callout-icon">✦</span>
                  <strong>
                    {activeDoc.title} ({activeDoc.version || 'v1.0'})
                  </strong>
                </div>
                <p>
                  <strong>In short: </strong>
                  {activeDoc.inShort}
                </p>
              </div>

              {(activeDoc.sections || []).map((sec, idx) => (
                <div key={idx} style={{ marginBottom: '18px' }}>
                  {sec.heading && <h3>{sec.heading}</h3>}
                  {sec.summary && (
                    <p style={{ marginBottom: '10px', color: 'var(--text-secondary)' }}>
                      {sec.summary}
                    </p>
                  )}
                  {sec.callout && (
                    <div className="policy-callout pink" style={{ marginBottom: '12px' }}>
                      <p style={{ margin: 0 }}>{sec.callout}</p>
                    </div>
                  )}
                  {Array.isArray(sec.bullets) && sec.bullets.length > 0 && (
                    <ul>
                      {sec.bullets.map((b, bIdx) => {
                        const colonIdx = b.indexOf(':');
                        if (colonIdx > 0 && colonIdx < 48) {
                          return (
                            <li key={bIdx}>
                              <strong>{b.slice(0, colonIdx + 1)}</strong>
                              {b.slice(colonIdx + 1)}
                            </li>
                          );
                        }
                        return <li key={bIdx}>{b}</li>;
                      })}
                    </ul>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Modal Footer */}
        <div className="policy-modal-footer">
          <div className="policy-footer-note">
            Effective {activeDoc?.effectiveDate || 'October 25, 2026'} • ODPC · NDPA · POPIA · GDPR ·
            DSA · COPPA Compliant
          </div>
          <div style={{ display: 'flex', gap: '10px', flexWrap: 'wrap' }}>
            {officialPdfHref && (
              <a
                href={officialPdfHref}
                download
                className="btn-secondary"
                style={{ fontSize: '0.82rem', padding: '8px 14px' }}
                target="_blank"
                rel="noreferrer"
              >
                ⬇ Official PDF
              </a>
            )}
            <a
              href={standaloneHref}
              className="btn-secondary"
              style={{ fontSize: '0.82rem', padding: '8px 14px' }}
              target="_blank"
              rel="noreferrer"
            >
              Open Full Legal Page ↗
            </a>
            <button
              type="button"
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
