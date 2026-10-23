import React, { useState, useMemo } from 'react';
import { docArticles } from '../data/docsData';

export default function DocsPortal({ currentDocId, onSelectDoc, searchRef, onOpenDownload }) {
  const [searchQuery, setSearchQuery] = useState('');

  const currentDoc = docArticles[currentDocId] || docArticles['live-studio'];

  // Categories list - 100% Product Focused
  const categories = [
    {
      name: 'Live & Broadcasting',
      items: ['live-studio', 'creator-rooms']
    },
    {
      name: 'Reels & Mobile Editing',
      items: ['mobile-editor', 'reels-feed']
    },
    {
      name: 'Distribution & Safety',
      items: ['universal-sharing', 'community-standards']
    }
  ];

  // Filtered categories based on search query
  const filteredCategories = useMemo(() => {
    if (!searchQuery.trim()) return categories;
    const q = searchQuery.toLowerCase();

    return categories.map(cat => ({
      ...cat,
      items: cat.items.filter(id => {
        const doc = docArticles[id];
        return doc && (doc.title.toLowerCase().includes(q) || doc.category.toLowerCase().includes(q));
      })
    })).filter(cat => cat.items.length > 0);
  }, [searchQuery]);

  // Previous & Next navigation
  const docKeys = Object.keys(docArticles);
  const currentIndex = docKeys.indexOf(currentDocId);
  const prevDoc = currentIndex > 0 ? docArticles[docKeys[currentIndex - 1]] : null;
  const nextDoc = currentIndex < docKeys.length - 1 ? docArticles[docKeys[currentIndex + 1]] : null;

  return (
    <section className="docs-portal-section" id="docs">
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
              placeholder="Search features, guides, rules..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
            />
          </div>

          {filteredCategories.map(cat => (
            <div className="nav-category" key={cat.name}>
              <div className="category-title">{cat.name}</div>
              <ul className="category-items">
                {cat.items.map(docId => {
                  const doc = docArticles[docId];
                  if (!doc) return null;
                  const isActive = docId === currentDocId;
                  return (
                    <li key={docId}>
                      <button
                        className={`doc-nav-btn ${isActive ? 'active' : ''}`}
                        onClick={() => onSelectDoc(docId)}
                      >
                        <span>{doc.title}</span>
                        {doc.badge && <span className="pill">{doc.badge}</span>}
                      </button>
                    </li>
                  );
                })}
              </ul>
            </div>
          ))}
        </aside>

        {/* Main Content Pane */}
        <main className="docs-main-pane" id="docs-main-content">
          {/* Breadcrumbs */}
          <nav className="doc-breadcrumbs" aria-label="Breadcrumb">
            <span>Features</span>
            <span>/</span>
            <span>{currentDoc.category}</span>
            <span>/</span>
            <span className="current">{currentDoc.title}</span>
          </nav>

          {/* Header */}
          <header className="doc-article-header">
            <h1 className="doc-article-title">{currentDoc.title}</h1>
            <div className="doc-article-meta">
              <span className="meta-badge">{currentDoc.badge}</span>
              <span>Updated {currentDoc.updated} • {currentDoc.readTime}</span>
            </div>
          </header>

          {/* Article Content */}
          <article
            className="doc-content"
            dangerouslySetInnerHTML={{ __html: currentDoc.content }}
          />

          {/* Pagination (Prev / Next) */}
          <div className="doc-pagination">
            {prevDoc ? (
              <button className="pagination-btn" onClick={() => onSelectDoc(prevDoc.id)}>
                <span className="pagination-label">← Previous Feature</span>
                <span className="pagination-title">{prevDoc.title}</span>
              </button>
            ) : <div style={{ width: '48%' }}></div>}

            {nextDoc ? (
              <button className="pagination-btn" onClick={() => onSelectDoc(nextDoc.id)} style={{ textAlign: 'right' }}>
                <span className="pagination-label">Next Feature →</span>
                <span className="pagination-title">{nextDoc.title}</span>
              </button>
            ) : <div style={{ width: '48%' }}></div>}
          </div>
        </main>

        {/* Right Table of Contents */}
        <aside className="docs-toc-pane" aria-label="Table of Contents">
          <div className="toc-title">Feature Guide</div>
          <ul className="toc-links">
            <li><a href="#showcase" className="toc-link">Product Showcase</a></li>
            <li><a href="#features" className="toc-link">Core Innovations</a></li>
            <li><a href="#docs" className="toc-link">Feature Documentation</a></li>
            <li><button className="toc-link" style={{ background: 'transparent', border: 'none' }} onClick={onOpenDownload}>Download Mobile App</button></li>
          </ul>

          <div style={{ marginTop: '40px', padding: '16px', background: 'var(--dark-surface)', border: '1px solid var(--border-color)', borderRadius: 'var(--radius-md)' }}>
            <div style={{ fontSize: '0.75rem', fontWeight: 800, color: 'var(--brand-pink)', textTransform: 'uppercase', marginBottom: '6px' }}>
              Oneova Creator App
            </div>
            <p style={{ fontSize: '0.78rem', color: 'var(--text-secondary)', lineHeight: 1.5, marginBottom: '12px' }}>
              Experience the 4K Live Studio, Creator Rooms, and Mobile Editor on your phone today.
            </p>
            <button
              className="btn-primary"
              style={{ width: '100%', fontSize: '0.78rem', padding: '8px 12px' }}
              onClick={onOpenDownload}
            >
              Get App Free
            </button>
          </div>
        </aside>
      </div>
    </section>
  );
}
