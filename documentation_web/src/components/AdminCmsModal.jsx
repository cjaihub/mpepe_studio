import React, { useState, useEffect, useMemo } from 'react';
import {
  useCmsAdminAuth,
  usePlatformDocs,
  saveCmsDoc,
  seedMissingCatalogDocs,
  subscribeRevisions,
  rollbackToRevision,
  deleteCmsDoc,
} from '../services/platformCmsClient';
import { PLATFORM_BASELINE_DOCS } from '../data/platformCatalog';

const EMPTY_DOC = {
  id: '',
  docType: 'feature',
  category: 'Studio, AI & Color Engine',
  policyTab: '',
  title: '',
  badge: 'NEW',
  isAccentBadge: false,
  inShort: '',
  readTime: '4 min read',
  version: 'v1.0',
  effectiveDate: 'October 25, 2026',
  order: 25,
  isPublished: true,
  sections: [
    {
      heading: '1. Overview & Key Capabilities',
      summary: '',
      callout: '',
      bulletsText: '',
    },
  ],
  htmlOverride: '',
};

function docToDraft(doc) {
  if (!doc) return { ...EMPTY_DOC };
  return {
    id: doc.id || '',
    docType: doc.docType || 'policy',
    category: doc.category || 'Community & Safety',
    policyTab: doc.policyTab || '',
    title: doc.title || '',
    badge: doc.badge || 'OFFICIAL',
    isAccentBadge: Boolean(doc.isAccentBadge),
    inShort: doc.inShort || '',
    readTime: doc.readTime || '4 min read',
    version: doc.version || 'v1.0',
    effectiveDate: doc.effectiveDate || 'October 25, 2026',
    order: doc.order ?? 10,
    isPublished: doc.isPublished !== false,
    sections:
      Array.isArray(doc.sections) && doc.sections.length > 0
        ? doc.sections.map((s) => ({
            heading: s.heading || '',
            summary: s.summary || '',
            callout: s.callout || '',
            bulletsText: Array.isArray(s.bullets) ? s.bullets.join('\n') : '',
          }))
        : [
            {
              heading: '1. Key Standards',
              summary: '',
              callout: '',
              bulletsText: '',
            },
          ],
    htmlOverride: doc.htmlOverride || '',
    isLiveFromCloud: Boolean(doc.isLiveFromCloud),
  };
}

function bumpVersionString(v) {
  const cleaned = String(v || 'v1.0').trim().replace(/^v/i, '');
  const parts = cleaned.split('.');
  if (parts.length >= 2) {
    const major = parseInt(parts[0], 10);
    const minor = parseInt(parts[1], 10);
    if (!Number.isNaN(major) && !Number.isNaN(minor)) {
      return `v${major}.${minor + 1}`;
    }
  }
  return 'v1.1';
}

export default function AdminCmsModal({ isOpen, onClose, initialDocId = null }) {
  const {
    user,
    isAdmin,
    roleLabel,
    loading: authLoading,
    signInEmail,
    signInGoogle,
    signOutAdmin,
  } = useCmsAdminAuth();

  const { docs: adminDocs, liveOverrideCount } = usePlatformDocs({
    includeDrafts: Boolean(isAdmin),
  });

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [authError, setAuthError] = useState('');
  const [authBusy, setAuthBusy] = useState(false);

  const [filterTrack, setFilterTrack] = useState('all');
  const [searchText, setSearchText] = useState('');
  const [selectedId, setSelectedId] = useState(initialDocId || 'live-studio');
  const [isCreatingNew, setIsCreatingNew] = useState(false);
  const [draft, setDraft] = useState(() => EMPTY_DOC);
  const [changeNote, setChangeNote] = useState('');
  const [rightTab, setRightTab] = useState('preview'); // 'preview' | 'revisions'
  const [revisions, setRevisions] = useState([]);
  const [saving, setSaving] = useState(false);
  const [seeding, setSeeding] = useState(false);
  const [statusBanner, setStatusBanner] = useState(null);

  // Sync selected doc when modal opens with a specific docId
  useEffect(() => {
    if (!isOpen) return;
    const targetId = initialDocId || selectedId || 'live-studio';
    const found = adminDocs.find((d) => d.id === targetId) || adminDocs[0];
    if (found && !isCreatingNew) {
      setSelectedId(found.id);
      setDraft(docToDraft(found));
    }
  }, [isOpen, initialDocId]);

  // Subscribe to revisions for the currently selected existing doc
  useEffect(() => {
    if (!isOpen || !isAdmin || isCreatingNew || !selectedId) {
      setRevisions([]);
      return undefined;
    }
    const unsub = subscribeRevisions(selectedId, (list) => setRevisions(list));
    return () => unsub();
  }, [isOpen, isAdmin, isCreatingNew, selectedId]);

  // Escape key closes modal
  useEffect(() => {
    const onKey = (e) => {
      if (e.key === 'Escape' && isOpen) onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [isOpen, onClose]);

  const filteredList = useMemo(() => {
    const q = searchText.trim().toLowerCase();
    return adminDocs.filter((d) => {
      if (filterTrack === 'feature' && d.docType !== 'feature') return false;
      if (filterTrack === 'policy' && d.docType !== 'policy') return false;
      if (filterTrack === 'regulation' && d.docType !== 'regulation') return false;
      if (filterTrack === 'drafts' && d.isPublished !== false) return false;
      if (!q) return true;
      return (
        d.title.toLowerCase().includes(q) ||
        d.id.toLowerCase().includes(q) ||
        d.category.toLowerCase().includes(q) ||
        d.badge.toLowerCase().includes(q)
      );
    });
  }, [adminDocs, filterTrack, searchText]);

  if (!isOpen) return null;

  const handleSelectDocItem = (docItem) => {
    setIsCreatingNew(false);
    setSelectedId(docItem.id);
    setDraft(docToDraft(docItem));
    setChangeNote('');
    setStatusBanner(null);
  };

  const handleStartNewDoc = () => {
    setIsCreatingNew(true);
    setSelectedId('');
    setDraft({ ...EMPTY_DOC });
    setChangeNote('Created new live documentation article');
    setStatusBanner(null);
  };

  const handleEmailSignIn = async (e) => {
    e.preventDefault();
    setAuthError('');
    setAuthBusy(true);
    try {
      await signInEmail(email, password);
    } catch (err) {
      setAuthError(err?.message || 'Sign-in failed. Verify email & password.');
    } finally {
      setAuthBusy(false);
    }
  };

  const handleGoogleSignIn = async () => {
    setAuthError('');
    setAuthBusy(true);
    try {
      await signInGoogle();
    } catch (err) {
      setAuthError(err?.message || 'Google sign-in was cancelled or blocked.');
    } finally {
      setAuthBusy(false);
    }
  };

  const handleSeedAll = async () => {
    setSeeding(true);
    setStatusBanner(null);
    try {
      const count = await seedMissingCatalogDocs();
      setStatusBanner({
        type: 'success',
        text:
          count === 0
            ? 'All 18 baseline documents are already synced in Firestore.'
            : `Synced ${count} baseline document(s) to Firestore (live on App + Website).`,
      });
    } catch (err) {
      setStatusBanner({
        type: 'error',
        text: err?.message || 'Failed to sync baseline catalog.',
      });
    } finally {
      setSeeding(false);
    }
  };

  const handleSavePublish = async (e) => {
    e.preventDefault();
    setSaving(true);
    setStatusBanner(null);
    try {
      const payload = {
        ...draft,
        sections: draft.sections.map((s) => ({
          heading: s.heading,
          summary: s.summary,
          callout: s.callout,
          bullets: String(s.bulletsText || '')
            .split('\n')
            .map((line) => line.replace(/^[•\-*]\s*/, '').trim())
            .filter(Boolean),
        })),
      };
      const savedId = await saveCmsDoc(payload, changeNote);
      setIsCreatingNew(false);
      setSelectedId(savedId);
      setDraft((prev) => ({ ...prev, id: savedId, isLiveFromCloud: true }));
      setChangeNote('');
      setStatusBanner({
        type: 'success',
        text: `Published "${payload.title}" (${payload.version}) — synced live to Oneova App & Website.`,
      });
    } catch (err) {
      setStatusBanner({
        type: 'error',
        text: err?.message || 'Publish failed. Check required fields and admin permissions.',
      });
    } finally {
      setSaving(false);
    }
  };

  const handleDeleteOrReset = async () => {
    if (!draft.id) return;
    const isBuiltIn = PLATFORM_BASELINE_DOCS.some((b) => b.id === draft.id);
    const ok = window.confirm(
      isBuiltIn
        ? `Reset cloud overrides for "${draft.title}" and restore the verified baseline version on both App and Website?`
        : `Permanently delete custom document "${draft.title}" from both App and Website?`
    );
    if (!ok) return;

    setSaving(true);
    try {
      await deleteCmsDoc(draft.id);
      const fallback =
        PLATFORM_BASELINE_DOCS.find((b) => b.id === draft.id) || PLATFORM_BASELINE_DOCS[0];
      setIsCreatingNew(false);
      setSelectedId(fallback.id);
      setDraft(docToDraft(fallback));
      setStatusBanner({
        type: 'success',
        text: isBuiltIn
          ? `Reset "${draft.title}" back to verified baseline.`
          : `Deleted custom document "${draft.title}".`,
      });
    } catch (err) {
      setStatusBanner({
        type: 'error',
        text: err?.message || 'Delete/reset failed.',
      });
    } finally {
      setSaving(false);
    }
  };

  const handleRollback = async (rev) => {
    const ok = window.confirm(
      `Roll back "${draft.title}" to revision ${rev.version} (${rev.changeNote || 'snapshot'})? This updates the Oneova App & Website immediately.`
    );
    if (!ok) return;

    setSaving(true);
    try {
      await rollbackToRevision(selectedId, rev);
      if (rev.snapshot) {
        setDraft(docToDraft({ ...rev.snapshot, id: selectedId, isLiveFromCloud: true }));
      }
      setStatusBanner({
        type: 'success',
        text: `Rolled back to ${rev.version} live across App & Website.`,
      });
    } catch (err) {
      setStatusBanner({
        type: 'error',
        text: err?.message || 'Rollback failed.',
      });
    } finally {
      setSaving(false);
    }
  };

  const updateSection = (idx, field, val) => {
    setDraft((prev) => {
      const next = [...prev.sections];
      next[idx] = { ...next[idx], [field]: val };
      return { ...prev, sections: next };
    });
  };

  const moveSection = (idx, dir) => {
    setDraft((prev) => {
      const target = idx + dir;
      if (target < 0 || target >= prev.sections.length) return prev;
      const next = [...prev.sections];
      const [item] = next.splice(idx, 1);
      next.splice(target, 0, item);
      return { ...prev, sections: next };
    });
  };

  const addSection = () => {
    setDraft((prev) => ({
      ...prev,
      sections: [
        ...prev.sections,
        {
          heading: `${prev.sections.length + 1}. New Section`,
          summary: '',
          callout: '',
          bulletsText: '',
        },
      ],
    }));
  };

  const removeSection = (idx) => {
    if (draft.sections.length <= 1) return;
    const ok = window.confirm(`Remove section "${draft.sections[idx]?.heading || idx + 1}"?`);
    if (!ok) return;
    setDraft((prev) => ({
      ...prev,
      sections: prev.sections.filter((_, i) => i !== idx),
    }));
  };

  return (
    <div className="cms-modal-overlay" role="dialog" aria-modal="true" onClick={onClose}>
      <div className="cms-modal-shell" onClick={(e) => e.stopPropagation()}>
        {/* Top Executive Bar */}
        <div className="cms-modal-topbar">
          <div className="cms-topbar-left">
            <span className="cms-live-pill">
              <span className="cms-live-dot" />
              REAL-TIME APP ↔ WEB CMS
            </span>
            <h2 className="cms-topbar-title">Oneova Live Documentation, Rules & Regulations Studio</h2>
          </div>
          <div className="cms-topbar-right">
            {user && (
              <div className="cms-user-chip">
                <span>{user.email || user.uid}</span>
                {roleLabel && <span className="cms-role-tag">{roleLabel.toUpperCase()}</span>}
                <button type="button" className="cms-link-btn" onClick={signOutAdmin}>
                  Sign out
                </button>
              </div>
            )}
            <button type="button" className="policy-close-btn" onClick={onClose} aria-label="Close CMS">
              ✕
            </button>
          </div>
        </div>

        {/* Body */}
        {authLoading ? (
          <div className="cms-auth-gate">
            <p className="cms-muted">Verifying Oneova Admin credentials...</p>
          </div>
        ) : !user ? (
          <div className="cms-auth-gate">
            <div className="cms-auth-card">
              <span className="cms-badge-pink">ADMIN AUTHENTICATION REQUIRED</span>
              <h3>Sign in to Edit Live Features, Rules & Legal Docs</h3>
              <p>
                Authorized Oneova Admins, Founders, and Legal Counsel can edit any Feature Guide,
                Community Rule, or African/Global Regulation here. Every save updates both{' '}
                <strong>oneova.app</strong> and the <strong>Oneova Mobile App</strong> in real time.
              </p>

              {authError && <div className="cms-alert error">{authError}</div>}

              <form onSubmit={handleEmailSignIn} className="cms-auth-form">
                <label className="cms-field-label">
                  Admin Email
                  <input
                    type="email"
                    required
                    className="cms-input"
                    placeholder="admin@oneova.app"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                  />
                </label>
                <label className="cms-field-label">
                  Password
                  <input
                    type="password"
                    required
                    className="cms-input"
                    placeholder="••••••••••••"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                  />
                </label>
                <button type="submit" className="btn-primary cms-full-btn" disabled={authBusy}>
                  {authBusy ? 'Signing in...' : 'Sign In with Email'}
                </button>
              </form>

              <div className="cms-divider-or">
                <span>OR</span>
              </div>

              <button
                type="button"
                className="btn-secondary cms-full-btn"
                onClick={handleGoogleSignIn}
                disabled={authBusy}
              >
                Continue with Google Workspace
              </button>
            </div>
          </div>
        ) : !isAdmin ? (
          <div className="cms-auth-gate">
            <div className="cms-auth-card">
              <span className="cms-badge-pink">RESTRICTED ACCESS</span>
              <h3>Admin Role Required</h3>
              <p>
                Signed in as <strong>{user.email || user.uid}</strong> (role:{' '}
                <code>{roleLabel || 'user'}</code>). Only accounts with{' '}
                <code>users/{'{uid}'}.role</code> set to <code>admin</code>, <code>owner</code>, or{' '}
                <code>founder</code> can publish live documentation or legal policy updates.
              </p>
              <div style={{ display: 'flex', gap: '10px', marginTop: '14px' }}>
                <button type="button" className="btn-secondary" onClick={signOutAdmin}>
                  Switch Account
                </button>
                <button type="button" className="btn-primary" onClick={onClose}>
                  Return to Docs
                </button>
              </div>
            </div>
          </div>
        ) : (
          <div className="cms-workspace-grid">
            {/* LEFT PANE: CATALOG */}
            <aside className="cms-catalog-pane">
              <div className="cms-catalog-actions">
                <button type="button" className="btn-primary cms-sm-btn" onClick={handleStartNewDoc}>
                  + New Doc
                </button>
                <button
                  type="button"
                  className="btn-secondary cms-sm-btn"
                  onClick={handleSeedAll}
                  disabled={seeding}
                  title="Push all 18 baseline docs to Firestore"
                >
                  {seeding ? 'Syncing...' : `Sync Cloud (${liveOverrideCount}/18)`}
                </button>
              </div>

              <input
                type="text"
                className="cms-input"
                placeholder="Filter by title, slug, badge..."
                value={searchText}
                onChange={(e) => setSearchText(e.target.value)}
              />

              <div className="cms-filter-chips">
                {[
                  { id: 'all', label: 'All' },
                  { id: 'feature', label: 'Features' },
                  { id: 'policy', label: 'Policies' },
                  { id: 'regulation', label: 'Regulations' },
                  { id: 'drafts', label: 'Drafts' },
                ].map((f) => (
                  <button
                    key={f.id}
                    type="button"
                    className={`cms-chip ${filterTrack === f.id ? 'active' : ''}`}
                    onClick={() => setFilterTrack(f.id)}
                  >
                    {f.label}
                  </button>
                ))}
              </div>

              <div className="cms-doc-list">
                {filteredList.map((item) => {
                  const active = !isCreatingNew && item.id === selectedId;
                  return (
                    <button
                      key={item.id}
                      type="button"
                      className={`cms-doc-row ${active ? 'active' : ''}`}
                      onClick={() => handleSelectDocItem(item)}
                    >
                      <div className="cms-doc-row-top">
                        <span className={`cms-mini-tag ${item.isAccentBadge ? 'pink' : 'blue'}`}>
                          {item.badge}
                        </span>
                        <span className="cms-mini-state">
                          {!item.isPublished
                            ? 'DRAFT'
                            : item.isLiveFromCloud
                            ? '● LIVE'
                            : 'BASE'}
                        </span>
                      </div>
                      <div className="cms-doc-row-title">{item.title}</div>
                      <div className="cms-doc-row-sub">
                        {item.docType.toUpperCase()} · {item.version}
                      </div>
                    </button>
                  );
                })}
              </div>
            </aside>

            {/* CENTER PANE: STRUCTURED EDITOR */}
            <form className="cms-editor-pane" onSubmit={handleSavePublish}>
              {statusBanner && (
                <div className={`cms-alert ${statusBanner.type}`}>{statusBanner.text}</div>
              )}

              <div className="cms-form-row three">
                <label className="cms-field-label">
                  Document Slug ID
                  <input
                    type="text"
                    required
                    readOnly={!isCreatingNew}
                    className="cms-input"
                    placeholder="e.g. ai-live-director"
                    value={draft.id}
                    onChange={(e) => setDraft({ ...draft, id: e.target.value })}
                  />
                </label>

                <label className="cms-field-label">
                  Document Track
                  <select
                    className="cms-input"
                    value={draft.docType}
                    onChange={(e) => setDraft({ ...draft, docType: e.target.value })}
                  >
                    <option value="feature">Platform Feature</option>
                    <option value="policy">User Policy / Rule</option>
                    <option value="regulation">Legal Regulation</option>
                  </select>
                </label>

                <label className="cms-field-label">
                  Policy Modal Tab (optional)
                  <select
                    className="cms-input"
                    value={draft.policyTab}
                    onChange={(e) => setDraft({ ...draft, policyTab: e.target.value })}
                  >
                    <option value="">None (Feature Guide)</option>
                    <option value="guidelines">Community Guidelines</option>
                    <option value="terms">Terms of Service</option>
                    <option value="privacy">Privacy Policy</option>
                    <option value="safety">Child & Teen Safety</option>
                    <option value="biz">Biz & Monetization</option>
                    <option value="deletion">Data Deletion</option>
                    <option value="law_enforcement">Law Enforcement</option>
                    <option value="africa">Africa & Global Law</option>
                  </select>
                </label>
              </div>

              <div className="cms-form-row two">
                <label className="cms-field-label">
                  Title
                  <input
                    type="text"
                    required
                    className="cms-input"
                    value={draft.title}
                    onChange={(e) => setDraft({ ...draft, title: e.target.value })}
                  />
                </label>

                <label className="cms-field-label">
                  Sidebar Category
                  <input
                    type="text"
                    required
                    className="cms-input"
                    value={draft.category}
                    onChange={(e) => setDraft({ ...draft, category: e.target.value })}
                  />
                </label>
              </div>

              <div className="cms-form-row four">
                <label className="cms-field-label">
                  Badge Pill
                  <input
                    type="text"
                    required
                    className="cms-input"
                    value={draft.badge}
                    onChange={(e) => setDraft({ ...draft, badge: e.target.value })}
                  />
                </label>

                <label className="cms-field-label">
                  Version
                  <div style={{ display: 'flex', gap: '6px' }}>
                    <input
                      type="text"
                      className="cms-input"
                      value={draft.version}
                      onChange={(e) => setDraft({ ...draft, version: e.target.value })}
                    />
                    <button
                      type="button"
                      className="cms-bump-btn"
                      onClick={() =>
                        setDraft((prev) => ({
                          ...prev,
                          version: bumpVersionString(prev.version),
                        }))
                      }
                      title="Increment minor version"
                    >
                      +0.1
                    </button>
                  </div>
                </label>

                <label className="cms-field-label">
                  Effective Date
                  <input
                    type="text"
                    className="cms-input"
                    value={draft.effectiveDate}
                    onChange={(e) => setDraft({ ...draft, effectiveDate: e.target.value })}
                  />
                </label>

                <label className="cms-field-label">
                  Sort Order / Read Time
                  <div style={{ display: 'flex', gap: '6px' }}>
                    <input
                      type="number"
                      className="cms-input"
                      style={{ width: '74px' }}
                      value={draft.order}
                      onChange={(e) => setDraft({ ...draft, order: Number(e.target.value) })}
                    />
                    <input
                      type="text"
                      className="cms-input"
                      value={draft.readTime}
                      onChange={(e) => setDraft({ ...draft, readTime: e.target.value })}
                    />
                  </div>
                </label>
              </div>

              <div className="cms-toggle-bar">
                <label className="cms-checkbox-label">
                  <input
                    type="checkbox"
                    checked={draft.isPublished}
                    onChange={(e) => setDraft({ ...draft, isPublished: e.target.checked })}
                  />
                  <span>Published Live (visible to all App & Web users)</span>
                </label>

                <label className="cms-checkbox-label">
                  <input
                    type="checkbox"
                    checked={draft.isAccentBadge}
                    onChange={(e) => setDraft({ ...draft, isAccentBadge: e.target.checked })}
                  />
                  <span>Pink Accent Highlight Badge</span>
                </label>
              </div>

              <label className="cms-field-label">
                Plain-Language “In Short” Summary (renders at top of Mobile & Web cards)
                <textarea
                  rows={2}
                  required
                  className="cms-textarea"
                  value={draft.inShort}
                  onChange={(e) => setDraft({ ...draft, inShort: e.target.value })}
                />
              </label>

              {/* Sections Builder */}
              <div className="cms-sections-header">
                <h4>Structured Sections ({draft.sections.length})</h4>
                <button type="button" className="btn-secondary cms-sm-btn" onClick={addSection}>
                  + Add Section
                </button>
              </div>

              {draft.sections.map((sec, idx) => (
                <div className="cms-section-card" key={idx}>
                  <div className="cms-section-card-head">
                    <span>Section #{idx + 1}</span>
                    <div className="cms-sec-btns">
                      <button
                        type="button"
                        onClick={() => moveSection(idx, -1)}
                        disabled={idx === 0}
                        title="Move Up"
                      >
                        ↑
                      </button>
                      <button
                        type="button"
                        onClick={() => moveSection(idx, 1)}
                        disabled={idx === draft.sections.length - 1}
                        title="Move Down"
                      >
                        ↓
                      </button>
                      <button
                        type="button"
                        className="danger"
                        onClick={() => removeSection(idx)}
                        disabled={draft.sections.length <= 1}
                        title="Delete Section"
                      >
                        ✕
                      </button>
                    </div>
                  </div>

                  <label className="cms-field-label">
                    Section Heading
                    <input
                      type="text"
                      className="cms-input"
                      value={sec.heading}
                      onChange={(e) => updateSection(idx, 'heading', e.target.value)}
                    />
                  </label>

                  <label className="cms-field-label">
                    Overview Paragraph (optional)
                    <textarea
                      rows={2}
                      className="cms-textarea"
                      value={sec.summary}
                      onChange={(e) => updateSection(idx, 'summary', e.target.value)}
                    />
                  </label>

                  <label className="cms-field-label">
                    Highlighted Callout Alert (optional)
                    <input
                      type="text"
                      className="cms-input"
                      placeholder="Important safety or technical highlight..."
                      value={sec.callout}
                      onChange={(e) => updateSection(idx, 'callout', e.target.value)}
                    />
                  </label>

                  <label className="cms-field-label">
                    Bullet Points (one bullet per line)
                    <textarea
                      rows={4}
                      className="cms-textarea"
                      placeholder="Enter one clear rule or capability per line..."
                      value={sec.bulletsText}
                      onChange={(e) => updateSection(idx, 'bulletsText', e.target.value)}
                    />
                  </label>
                </div>
              ))}

              <div className="cms-publish-bar">
                <input
                  type="text"
                  className="cms-input"
                  placeholder="Audit change note (e.g. Updated Kenya ODPC & M-Pesa payout clauses)..."
                  value={changeNote}
                  onChange={(e) => setChangeNote(e.target.value)}
                />
                {!isCreatingNew && (
                  <button
                    type="button"
                    className="btn-secondary cms-danger-btn"
                    onClick={handleDeleteOrReset}
                    disabled={saving}
                  >
                    {PLATFORM_BASELINE_DOCS.some((b) => b.id === draft.id)
                      ? 'Reset to Baseline'
                      : 'Delete'}
                  </button>
                )}
                <button type="submit" className="btn-primary" disabled={saving}>
                  {saving ? 'Publishing...' : 'Publish Live (App + Web)'}
                </button>
              </div>
            </form>

            {/* RIGHT PANE: LIVE PREVIEW & REVISIONS */}
            <aside className="cms-preview-pane">
              <div className="cms-preview-tabs">
                <button
                  type="button"
                  className={`cms-chip ${rightTab === 'preview' ? 'active' : ''}`}
                  onClick={() => setRightTab('preview')}
                >
                  Live Preview
                </button>
                <button
                  type="button"
                  className={`cms-chip ${rightTab === 'revisions' ? 'active' : ''}`}
                  onClick={() => setRightTab('revisions')}
                >
                  Audit History ({revisions.length})
                </button>
              </div>

              {rightTab === 'preview' ? (
                <div className="cms-preview-body">
                  <div className="cms-preview-meta">
                    <span className={`cms-mini-tag ${draft.isAccentBadge ? 'pink' : 'blue'}`}>
                      {draft.badge || 'OFFICIAL'}
                    </span>
                    <span>
                      {draft.version} · {draft.effectiveDate}
                    </span>
                  </div>
                  <h3 className="cms-preview-title">{draft.title || 'Untitled Document'}</h3>
                  <div className="doc-inshort-box" style={{ marginBottom: '14px' }}>
                    <strong>In short: </strong>
                    <span>{draft.inShort || 'Summary appears here...'}</span>
                  </div>
                  {draft.sections.map((s, idx) => {
                    const bullets = String(s.bulletsText || '')
                      .split('\n')
                      .map((l) => l.trim())
                      .filter(Boolean);
                    return (
                      <div key={idx} className="cms-preview-sec">
                        {s.heading && <h4>{s.heading}</h4>}
                        {s.summary && <p>{s.summary}</p>}
                        {s.callout && <div className="callout pink">{s.callout}</div>}
                        {bullets.length > 0 && (
                          <ul>
                            {bullets.map((b, bIdx) => (
                              <li key={bIdx}>{b}</li>
                            ))}
                          </ul>
                        )}
                      </div>
                    );
                  })}
                </div>
              ) : (
                <div className="cms-revisions-list">
                  {revisions.length === 0 ? (
                    <p className="cms-muted">
                      No cloud revisions recorded yet for this document. Publish an edit or click
                      “Sync Cloud” to create the initial audit entry.
                    </p>
                  ) : (
                    revisions.map((rev) => (
                      <div key={rev.id} className="cms-rev-card">
                        <div className="cms-rev-top">
                          <strong>{rev.version}</strong>
                          <span>
                            {rev.createdAt
                              ? rev.createdAt.toLocaleString()
                              : 'Just now'}
                          </span>
                        </div>
                        <div className="cms-rev-note">{rev.changeNote || 'Live update'}</div>
                        <div className="cms-rev-bottom">
                          <span>By {rev.actorName}</span>
                          <button
                            type="button"
                            className="cms-link-btn"
                            onClick={() => handleRollback(rev)}
                          >
                            Rollback ↺
                          </button>
                        </div>
                      </div>
                    ))
                  )}
                </div>
              )}
            </aside>
          </div>
        )}
      </div>
    </div>
  );
}
