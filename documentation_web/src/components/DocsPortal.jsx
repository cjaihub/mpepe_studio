import React, { useState, useMemo, useEffect, useRef } from 'react';
import { getStandaloneLegalHref, getOfficialPdfHref } from '../data/platformCatalog';

const QUICK_TOPIC_PILLS = [
  { id: 'all', label: 'All Topics', icon: '✨' },
  { id: '4k_live', label: '4K Live & WebRTC', icon: '🎥', query: '4k live' },
  { id: 'looks', label: 'GPU Looks & LUTs', icon: '🎨', query: 'look' },
  { id: 'ova_ai', label: 'Ova AI Lab', icon: '🤖', query: 'ova' },
  { id: 'mpesa', label: 'M-Pesa & Mobile Money', icon: '💳', query: 'm-pesa' },
  { id: 'creator_ip', label: '100% Creator IP', icon: '⚖️', query: 'ownership' },
  { id: 'teen_safety', label: 'Teen Safety 116', icon: '🛡️', query: 'teen' },
  { id: 'privacy', label: 'Zero Data Sales', icon: '🔒', query: 'privacy' },
  { id: 'deletion', label: '2-Tap Deletion', icon: '🗑️', query: 'deletion' },
  { id: 'african_law', label: 'African Laws (ODPC/POPIA)', icon: '🌍', query: 'africa' },
];

const SEARCH_SUGGESTIONS = [
  'M-Pesa payouts',
  '4K Live stream',
  'Who owns reels?',
  'Teen safety 116',
  'Delete account',
  'POPIA / GDPR',
  'GPU LUTs',
  'Zero data sales',
];

/**
 * Real-time Advanced Documentation, Rules & Legal Regulations Portal.
 * Designed with an executive, high-density corporate interface, enhanced tables,
 * non-technical plain language summaries, small table of contents, and Ova AI integration.
 */
export default function DocsPortal({
  docs = [],
  currentDocId,
  onSelectDoc,
  searchRef,
  onOpenDownload,
  onOpenAdminCms,
  onOpenOvaAssistant,
  isLiveConnected = false,
  liveOverrideCount = 0,
  isAdmin = false,
}) {
  const [searchQuery, setSearchQuery] = useState('');
  const [activeTrack, setActiveTrack] = useState('all'); // 'all' | 'features' | 'rules' | 'legal' | 'compliance'
  const [activeTopic, setActiveTopic] = useState('all');
  const [copiedLink, setCopiedLink] = useState(false);
  const [showMatrixTable, setShowMatrixTable] = useState(false);
  const [activeSectionId, setActiveSectionId] = useState('');

  const docMap = useMemo(() => {
    const m = new Map();
    docs.forEach((d) => m.set(d.id, d));
    return m;
  }, [docs]);

  const currentDoc =
    docMap.get(currentDocId) ||
    docs[0] || {
      id: 'live-studio',
      docType: 'feature',
      category: 'Live & Broadcasting',
      title: '4K Live Broadcast Studio & PK Stage',
      badge: '4K LIVE',
      inShort: '',
      version: 'v1.0',
      effectiveDate: 'October 25, 2026',
      readTime: '5 min read',
      sections: [],
    };

  // Scroll spy to highlight active section in TOC
  useEffect(() => {
    const handleScroll = () => {
      const sections = (currentDoc.sections || [])
        .map((_, idx) => document.getElementById(`doc-sec-${idx + 1}`))
        .filter(Boolean);

      const scrollPos = window.scrollY + 200;
      for (let i = sections.length - 1; i >= 0; i--) {
        const sec = sections[i];
        if (sec.offsetTop <= scrollPos) {
          setActiveSectionId(sec.id);
          return;
        }
      }
      if (sections[0]) {
        setActiveSectionId(sections[0].id);
      }
    };

    window.addEventListener('scroll', handleScroll, { passive: true });
    handleScroll();
    return () => window.removeEventListener('scroll', handleScroll);
  }, [currentDoc]);

  // Track filter logic
  const trackFilteredDocs = useMemo(() => {
    const q = searchQuery.trim().toLowerCase();
    return docs.filter((d) => {
      // Track filter
      if (activeTrack === 'features' && d.docType !== 'feature') return false;
      if (activeTrack === 'rules' && d.policyTab !== 'guidelines' && d.policyTab !== 'safety' && d.policyTab !== 'biz') {
        if (d.docType === 'feature') return false;
        if (d.policyTab === 'terms' || d.policyTab === 'deletion' || d.policyTab === 'law_enforcement' || d.policyTab === 'africa') return false;
      }
      if (activeTrack === 'legal' && d.policyTab !== 'terms' && d.policyTab !== 'deletion' && d.policyTab !== 'law_enforcement') {
        if (d.docType === 'feature' || d.policyTab === 'guidelines' || d.policyTab === 'safety' || d.policyTab === 'biz' || d.policyTab === 'africa') return false;
      }
      if (activeTrack === 'compliance' && d.policyTab !== 'africa') {
        if (d.docType === 'feature' || d.policyTab !== 'africa') return false;
      }

      // Query filter
      if (!q) return true;
      if (
        d.title.toLowerCase().includes(q) ||
        d.category.toLowerCase().includes(q) ||
        d.badge.toLowerCase().includes(q) ||
        d.inShort.toLowerCase().includes(q)
      ) {
        return true;
      }
      return (d.sections || []).some(
        (s) =>
          (s.heading || '').toLowerCase().includes(q) ||
          (s.summary || '').toLowerCase().includes(q) ||
          (s.callout || '').toLowerCase().includes(q) ||
          (s.bullets || []).some((b) => b.toLowerCase().includes(q))
      );
    });
  }, [docs, activeTrack, searchQuery]);

  const groupedCategories = useMemo(() => {
    const map = new Map();
    for (const d of trackFilteredDocs) {
      const cat = d.category || 'General';
      if (!map.has(cat)) map.set(cat, []);
      map.get(cat).push(d);
    }
    return Array.from(map.entries()).map(([name, items]) => ({ name, items }));
  }, [trackFilteredDocs]);

  const currentIndex = trackFilteredDocs.findIndex((d) => d.id === currentDoc.id);
  const prevDoc = currentIndex > 0 ? trackFilteredDocs[currentIndex - 1] : null;
  const nextDoc =
    currentIndex >= 0 && currentIndex < trackFilteredDocs.length - 1
      ? trackFilteredDocs[currentIndex + 1]
      : null;

  const standaloneLegalHref = getStandaloneLegalHref(currentDoc);
  const officialPdfHref = getOfficialPdfHref(currentDoc);

  const featureCount = docs.filter((d) => d.docType === 'feature').length;
  const communityCount = docs.filter((d) => d.policyTab === 'guidelines' || d.policyTab === 'safety' || d.policyTab === 'biz').length;
  const legalCount = docs.filter((d) => d.policyTab === 'terms' || d.policyTab === 'deletion' || d.policyTab === 'law_enforcement').length;
  const complianceCount = docs.filter((d) => d.policyTab === 'africa').length;

  const handleTrackSwitch = (track) => {
    setActiveTrack(track);
    setActiveTopic('all');
    if (track === 'features' && currentDoc.docType !== 'feature') {
      const firstFeature = docs.find((d) => d.docType === 'feature');
      if (firstFeature) onSelectDoc(firstFeature.id);
    } else if (track === 'rules' && currentDoc.policyTab !== 'guidelines') {
      const firstRule = docs.find((d) => d.policyTab === 'guidelines');
      if (firstRule) onSelectDoc(firstRule.id);
    } else if (track === 'legal' && currentDoc.policyTab !== 'terms') {
      const firstLegal = docs.find((d) => d.policyTab === 'terms');
      if (firstLegal) onSelectDoc(firstLegal.id);
    } else if (track === 'compliance' && currentDoc.policyTab !== 'africa') {
      const firstComp = docs.find((d) => d.policyTab === 'africa');
      if (firstComp) onSelectDoc(firstComp.id);
    }
  };

  const handleTopicClick = (topic) => {
    setActiveTopic(topic.id);
    if (topic.id === 'all') {
      setSearchQuery('');
    } else if (topic.query) {
      setSearchQuery(topic.query);
      if (searchRef?.current) {
        searchRef.current.focus();
      }
    }
  };

  const handleCopyLink = () => {
    try {
      const url = `${window.location.origin}${window.location.pathname}#${currentDoc.id}`;
      navigator.clipboard.writeText(url);
      setCopiedLink(true);
      setTimeout(() => setCopiedLink(false), 2000);
    } catch (_) {}
  };

  return (
    <section className="docs-portal-section" id="docs">
      {/* Top Portal Banner with Executive Corporate Sizing */}
      <div className="docs-portal-banner">
        <div className="docs-banner-top">
          <div>
            <div className="docs-banner-tag-row">
              <span className="section-tag pink">REAL-TIME UNIFIED KNOWLEDGE &amp; GOVERNANCE HUB</span>
              <span className="executive-verified-badge">
                <span className="badge-shield-icon">🛡️</span>
                <span>Africa-First · Globally Compliant</span>
              </span>
            </div>
            <h2 className="docs-banner-heading">
              Platform Features, Community Rules &amp; Global Regulations
            </h2>
            <p className="docs-banner-sub">
              Every feature guide, plain-language creator rule, and African &amp; international statutory protection—synchronized live in real time with the Oneova App.
            </p>
          </div>
          <div className="docs-banner-actions">
            <div className="docs-sync-indicator" title="Connected to Firestore platform_cms_docs">
              <span className={`sync-dot ${isLiveConnected ? 'online' : 'offline'}`} />
              <span>
                {isLiveConnected
                  ? `Live Synced with App${liveOverrideCount > 0 ? ` · ${liveOverrideCount} Cloud Live` : ''}`
                  : 'Offline-Ready Baseline Active'}
              </span>
            </div>
            {onOpenOvaAssistant && (
              <button
                type="button"
                className="banner-ova-btn"
                onClick={() => onOpenOvaAssistant(`Tell me about ${currentDoc.title}`)}
                title="Ask Ova AI Assistant about this document"
              >
                <span>✨ Ask Ova AI</span>
              </button>
            )}
            {isAdmin && onOpenAdminCms && (
              <button
                type="button"
                className="cms-open-trigger-btn"
                onClick={() => onOpenAdminCms(currentDoc.id)}
              >
                <span>✎ Edit Live in CMS</span>
              </button>
            )}
          </div>
        </div>

        {/* Master Multi-Track Advanced Switcher */}
        <div className="docs-track-switcher" role="tablist" aria-label="Documentation Tracks">
          <button
            type="button"
            className={`docs-track-btn ${activeTrack === 'all' ? 'active' : ''}`}
            onClick={() => handleTrackSwitch('all')}
          >
            All Knowledge ({docs.length})
          </button>
          <button
            type="button"
            className={`docs-track-btn ${activeTrack === 'features' ? 'active' : ''}`}
            onClick={() => handleTrackSwitch('features')}
          >
            Platform Features ({featureCount})
          </button>
          <button
            type="button"
            className={`docs-track-btn ${activeTrack === 'rules' ? 'active' : ''}`}
            onClick={() => handleTrackSwitch('rules')}
          >
            Community &amp; Safety ({communityCount || 3})
          </button>
          <button
            type="button"
            className={`docs-track-btn ${activeTrack === 'legal' ? 'active' : ''}`}
            onClick={() => handleTrackSwitch('legal')}
          >
            Terms &amp; IP Rights ({legalCount || 3})
          </button>
          <button
            type="button"
            className={`docs-track-btn ${activeTrack === 'compliance' ? 'active' : ''}`}
            onClick={() => handleTrackSwitch('compliance')}
          >
            Global Laws ({complianceCount || 2})
          </button>
        </div>

        {/* Horizontal Quick-Filter Topic Pills */}
        <div className="docs-topic-pills-bar" role="toolbar" aria-label="Quick Topic Filters">
          {QUICK_TOPIC_PILLS.map((pill) => (
            <button
              key={pill.id}
              type="button"
              className={`topic-pill-btn ${activeTopic === pill.id ? 'active' : ''}`}
              onClick={() => handleTopicClick(pill)}
            >
              <span className="pill-icon">{pill.icon}</span>
              <span className="pill-label">{pill.label}</span>
            </button>
          ))}
          <button
            type="button"
            className="matrix-toggle-pill-btn"
            onClick={() => setShowMatrixTable(!showMatrixTable)}
            title="Toggle Executive Comparison Matrix"
          >
            <span>📊 {showMatrixTable ? 'Hide Matrix' : 'Executive Matrix Table'}</span>
          </button>
        </div>

        {/* Optional Collapsible Enhanced Executive Comparison Matrix Table */}
        {showMatrixTable && (
          <div className="executive-matrix-wrapper">
            <div className="matrix-header-row">
              <div className="matrix-title">
                <span className="matrix-title-icon">📊</span>
                <strong>At-A-Glance Executive Policy &amp; Architecture Matrix</strong>
              </div>
              <span className="matrix-sub">Updated October 2026 · Real-Time Certified</span>
            </div>
            <div className="enhanced-table-container">
              <table className="enhanced-executive-table">
                <thead>
                  <tr>
                    <th>Domain</th>
                    <th>Core Capability</th>
                    <th>Plain Language Guarantee</th>
                    <th>Statutory &amp; Technical Shield</th>
                    <th>Action</th>
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    <td><span className="table-badge blue">4K LIVE</span></td>
                    <td><strong>Live Studio &amp; PK Battles</strong></td>
                    <td>High-resolution broadcast with beauty &amp; looks embedded directly into the video stream for all viewers.</td>
                    <td>Adaptive Simulcast (WebRTC), E2EE Media Keys, ADPF Thermal Headroom.</td>
                    <td><button type="button" className="table-jump-btn" onClick={() => onSelectDoc('live-studio')}>Open Doc →</button></td>
                  </tr>
                  <tr>
                    <td><span className="table-badge pink">CREATOR IP</span></td>
                    <td><strong>Terms of Service</strong></td>
                    <td>You own 100% of your uploaded reels and live broadcasts; Oneova never claims ownership.</td>
                    <td>Non-exclusive license only, SIM-recycle protection, statutory consumer preservation.</td>
                    <td><button type="button" className="table-jump-btn" onClick={() => onSelectDoc('policy-terms-of-service')}>Open Doc →</button></td>
                  </tr>
                  <tr>
                    <td><span className="table-badge green">ZERO SALES</span></td>
                    <td><strong>Privacy Policy</strong></td>
                    <td>We never sell personal data, phone numbers, or private chats; zero PIN storage.</td>
                    <td>Kenya ODPC, Nigeria NDPA, South Africa POPIA, EU GDPR, AI Privacy Firewall.</td>
                    <td><button type="button" className="table-jump-btn" onClick={() => onSelectDoc('policy-privacy')}>Open Doc →</button></td>
                  </tr>
                  <tr>
                    <td><span className="table-badge pink">SAFETY</span></td>
                    <td><strong>Teen &amp; Child Safety</strong></td>
                    <td>CSAM zero tolerance, 13–17 protective privacy defaults, and direct 116 emergency helplines.</td>
                    <td>Mandatory NCMEC reporting, AU child protection frameworks, COPPA compliance.</td>
                    <td><button type="button" className="table-jump-btn" onClick={() => onSelectDoc('policy-child-safety')}>Open Doc →</button></td>
                  </tr>
                  <tr>
                    <td><span className="table-badge blue">PAYOUTS</span></td>
                    <td><strong>Wallet &amp; Mobile Money</strong></td>
                    <td>Cash out directly to M-Pesa, MTN MoMo, Airtel, card, or bank in your local currency.</td>
                    <td>Central-bank-licensed payment rails, KYC/AML fraud shields, zero hidden conversion markups.</td>
                    <td><button type="button" className="table-jump-btn" onClick={() => onSelectDoc('wallet-biz-commerce')}>Open Doc →</button></td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        )}
      </div>

      <div className="docs-outer-container">
        {/* Left Sidebar */}
        <aside className="docs-sidebar" aria-label="Documentation Navigation">
          <div className="docs-search-box">
            <span className="search-input-icon">🔍</span>
            <input
              ref={searchRef}
              type="text"
              className="docs-search-input"
              id="docs-search-input"
              placeholder="Search 4K Live, Looks, M-Pesa, POPIA, teens..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
            />
            {searchQuery && (
              <button
                type="button"
                className="search-clear-btn"
                onClick={() => setSearchQuery('')}
                aria-label="Clear search"
              >
                ✕
              </button>
            )}
            <kbd className="search-kbd-tag">⌘K</kbd>
          </div>

          {/* Quick Search Keyword Chips */}
          <div className="search-quick-tags">
            <span className="search-tags-label">Quick:</span>
            {SEARCH_SUGGESTIONS.slice(0, 4).map((tag, idx) => (
              <button
                key={idx}
                type="button"
                className="search-tag-chip"
                onClick={() => setSearchQuery(tag)}
              >
                {tag}
              </button>
            ))}
          </div>

          {searchQuery && (
            <div className="search-results-count-bar">
              <span>Found {trackFilteredDocs.length} matching {trackFilteredDocs.length === 1 ? 'document' : 'documents'}</span>
            </div>
          )}

          {groupedCategories.length === 0 ? (
            <div className="docs-empty-state">
              <span className="empty-state-icon">🔍</span>
              <p>No documents match “{searchQuery}”.</p>
              {onOpenOvaAssistant && (
                <button
                  type="button"
                  className="btn-primary empty-ask-btn"
                  onClick={() => onOpenOvaAssistant(searchQuery)}
                >
                  ✨ Ask Ova AI about “{searchQuery}”
                </button>
              )}
            </div>
          ) : (
            groupedCategories.map((cat) => (
              <div className="nav-category" key={cat.name}>
                <div className="category-title">{cat.name}</div>
                <ul className="category-items">
                  {cat.items.map((doc) => {
                    const isActive = doc.id === currentDoc.id;
                    return (
                      <li key={doc.id}>
                        <button
                          type="button"
                          className={`doc-nav-btn ${isActive ? 'active' : ''}`}
                          onClick={() => onSelectDoc(doc.id)}
                        >
                          <span className="doc-nav-title-text">{doc.title}</span>
                          {doc.badge && (
                            <span className={`pill ${doc.isAccentBadge ? 'pink' : ''}`}>
                              {doc.badge}
                            </span>
                          )}
                        </button>
                      </li>
                    );
                  })}
                </ul>
              </div>
            ))
          )}
        </aside>

        {/* Main Content Pane */}
        <main className="docs-main-pane" id="docs-main-content">
          {/* Breadcrumbs */}
          <nav className="doc-breadcrumbs" aria-label="Breadcrumb">
            <span>
              {currentDoc.docType === 'feature'
                ? 'Platform Features'
                : currentDoc.docType === 'regulation'
                ? 'Regulations & Compliance'
                : 'Rules & Policies'}
            </span>
            <span>/</span>
            <span>{currentDoc.category}</span>
            <span>/</span>
            <span className="current">{currentDoc.title}</span>
          </nav>

          {/* Header */}
          <header className="doc-article-header">
            <div className="doc-header-top-row">
              <h1 className="doc-article-title">{currentDoc.title}</h1>
              <div className="header-action-buttons-group">
                {onOpenOvaAssistant && (
                  <button
                    type="button"
                    className="doc-ask-ova-pill-btn"
                    onClick={() => onOpenOvaAssistant(`Explain ${currentDoc.title} in plain English`)}
                    title="Ask Ova AI about this document"
                  >
                    <span>✨ Ask Ova</span>
                  </button>
                )}
                {isAdmin && onOpenAdminCms && (
                  <button
                    type="button"
                    className="doc-inline-edit-btn"
                    onClick={() => onOpenAdminCms(currentDoc.id)}
                    title="Edit this document in real time (syncs App + Website)"
                  >
                    ✎ Edit Live
                  </button>
                )}
              </div>
            </div>
            <div className="doc-article-meta">
              <span className={`meta-badge ${currentDoc.isAccentBadge ? 'pink' : ''}`}>
                {currentDoc.badge}
              </span>
              <span>
                {currentDoc.version || 'v1.0'} • Effective {currentDoc.effectiveDate || 'Oct 2026'} •{' '}
                {currentDoc.readTime || '4 min read'}
              </span>
              {currentDoc.isLiveFromCloud && (
                <span className="doc-cloud-live-tag">● Live Cloud Version</span>
              )}
            </div>
          </header>

          {/* Non-Technical "In Plain Language" Card */}
          <div className="doc-plain-language-card">
            <div className="plain-lang-top">
              <div className="plain-lang-badge">
                <span className="plain-lang-icon">✦</span>
                <strong>IN PLAIN LANGUAGE</strong>
              </div>
              <span className="plain-lang-hint">What this means for everyday creators &amp; users</span>
            </div>
            <p className="plain-lang-body">
              {currentDoc.inShort || 'Authoritative specification and operating terms verified for real-time synchronization across all Oneova surfaces.'}
            </p>
            <div className="plain-lang-footer">
              <div className="plain-lang-tag">
                <span>🛡️ High-Trust Protection Guarantee</span>
              </div>
              {onOpenOvaAssistant && (
                <button
                  type="button"
                  className="plain-lang-ova-link"
                  onClick={() => onOpenOvaAssistant(`Help me understand ${currentDoc.title}`)}
                >
                  Have questions? Ask Ova Assistant →
                </button>
              )}
            </div>
          </div>

          {/* Structured Sections OR Custom HTML Override */}
          {currentDoc.htmlOverride ? (
            <article
              className="doc-content"
              dangerouslySetInnerHTML={{ __html: currentDoc.htmlOverride }}
            />
          ) : (
            <article className="doc-content">
              {(currentDoc.sections || []).map((sec, idx) => (
                <section
                  key={idx}
                  id={`doc-sec-${idx + 1}`}
                  className="doc-structured-section"
                >
                  {sec.heading && <h2>{sec.heading}</h2>}
                  {sec.summary && <p className="section-summary-text">{sec.summary}</p>}
                  {sec.callout && (
                    <div className={`callout ${currentDoc.isAccentBadge ? 'pink' : ''}`}>
                      <div className="callout-title">Key Highlight</div>
                      <p style={{ marginBottom: 0 }}>{sec.callout}</p>
                    </div>
                  )}
                  {Array.isArray(sec.bullets) && sec.bullets.length > 0 && (
                    <ul className="section-bullets-list">
                      {sec.bullets.map((bullet, bIdx) => {
                        const colonIdx = bullet.indexOf(':');
                        if (colonIdx > 0 && colonIdx < 48) {
                          const lead = bullet.slice(0, colonIdx + 1);
                          const rest = bullet.slice(colonIdx + 1);
                          return (
                            <li key={bIdx}>
                              <strong>{lead}</strong>
                              {rest}
                            </li>
                          );
                        }
                        return <li key={bIdx}>{bullet}</li>;
                      })}
                    </ul>
                  )}
                </section>
              ))}
            </article>
          )}

          {/* Action Bar for Standalone Printable Legal Page */}
          {standaloneLegalHref && (
            <div className="doc-legal-actions-bar">
              <div>
                <strong>Official Legal Instrument &amp; Print Edition</strong>
                <span>
                  Open the full standalone statutory document or print/save as PDF.
                </span>
              </div>
              <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap' }}>
                {officialPdfHref && (
                  <a
                    href={officialPdfHref}
                    download
                    target="_blank"
                    rel="noreferrer"
                    className="btn-secondary"
                    style={{ fontSize: '0.8rem', padding: '7px 13px' }}
                  >
                    ⬇ Official PDF
                  </a>
                )}
                <a
                  href={standaloneLegalHref}
                  target="_blank"
                  rel="noreferrer"
                  className="btn-secondary"
                  style={{ fontSize: '0.8rem', padding: '7px 13px' }}
                >
                  Open Standalone Document ↗
                </a>
                <a
                  href="/legal.html"
                  target="_blank"
                  rel="noreferrer"
                  className="btn-primary"
                  style={{ fontSize: '0.8rem', padding: '7px 13px' }}
                >
                  Legal &amp; Compliance Center ↗
                </a>
              </div>
            </div>
          )}

          {/* Pagination (Prev / Next) */}
          <div className="doc-pagination">
            {prevDoc ? (
              <button
                type="button"
                className="pagination-btn"
                onClick={() => onSelectDoc(prevDoc.id)}
              >
                <span className="pagination-label">← Previous</span>
                <span className="pagination-title">{prevDoc.title}</span>
              </button>
            ) : (
              <div style={{ width: '48%' }} />
            )}

            {nextDoc ? (
              <button
                type="button"
                className="pagination-btn"
                onClick={() => onSelectDoc(nextDoc.id)}
                style={{ textAlign: 'right' }}
              >
                <span className="pagination-label">Next →</span>
                <span className="pagination-title">{nextDoc.title}</span>
              </button>
            ) : (
              <div style={{ width: '48%' }} />
            )}
          </div>
        </main>

        {/* Small Enhanced Table of Contents (TOC) with Easy Navigation */}
        <aside className="docs-toc-pane" aria-label="Table of Contents">
          <div className="toc-header-bar">
            <span className="toc-title">ON THIS PAGE</span>
            <span className="toc-reading-badge">{currentDoc.readTime || '4 min'}</span>
          </div>

          <ul className="toc-links">
            {(currentDoc.sections || []).map((sec, idx) => {
              const secId = `doc-sec-${idx + 1}`;
              const isActive = activeSectionId === secId;
              return sec.heading ? (
                <li key={idx}>
                  <a
                    href={`#${secId}`}
                    className={`toc-link ${isActive ? 'active' : ''}`}
                    onClick={(e) => {
                      e.preventDefault();
                      const target = document.getElementById(secId);
                      if (target) {
                        target.scrollIntoView({ behavior: 'smooth' });
                        setActiveSectionId(secId);
                      }
                    }}
                  >
                    <span className="toc-bullet-indicator" aria-hidden="true" />
                    <span className="toc-heading-text">{sec.heading}</span>
                  </a>
                </li>
              ) : null;
            })}
          </ul>

          {/* TOC Quick Action Toolbar */}
          <div className="toc-quick-actions-bar">
            <button
              type="button"
              className="toc-action-btn"
              onClick={handleCopyLink}
              title="Copy direct link to this document"
            >
              <span>{copiedLink ? '✓ Copied!' : '📋 Copy Link'}</span>
            </button>
            {officialPdfHref && (
              <a
                href={officialPdfHref}
                download
                className="toc-action-btn"
                title="Download official vector PDF"
              >
                <span>⬇ Official PDF</span>
              </a>
            )}
            <button
              type="button"
              className="toc-action-btn"
              onClick={() => window.print()}
              title="Print document or save as PDF"
            >
              <span>🖨️ Print / PDF</span>
            </button>
          </div>

          {/* Interactive Ova AI Prompt Card */}
          {onOpenOvaAssistant && (
            <div className="toc-ova-card">
              <div className="toc-ova-top">
                <span className="toc-ova-sparkle">✨</span>
                <strong>Need Plain Language Help?</strong>
              </div>
              <p className="toc-ova-desc">
                Ask Ova Assistant to explain clauses, creator earnings, or privacy rules in simple everyday terms.
              </p>
              <button
                type="button"
                className="btn-primary toc-ova-trigger-btn"
                onClick={() => onOpenOvaAssistant(`Explain ${currentDoc.title} in simple terms`)}
              >
                <span>Ask Ova AI</span>
                <span>→</span>
              </button>
            </div>
          )}

          <div className="toc-app-sync-card">
            <div className="toc-sync-label">
              App ↔ Web Live Sync
            </div>
            <p className="toc-sync-desc">
              All rules are available offline inside the Oneova Mobile App (Me → Settings → Rules, Docs &amp; Legal).
            </p>
            <button
              type="button"
              className="btn-secondary toc-app-btn"
              onClick={onOpenDownload}
            >
              Get Oneova App Free
            </button>
          </div>
        </aside>
      </div>
    </section>
  );
}
