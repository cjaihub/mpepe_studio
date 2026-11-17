import React, { useEffect, useMemo, useState } from 'react';
import {
  collection,
  deleteDoc,
  doc,
  limit,
  onSnapshot,
  orderBy,
  query,
  serverTimestamp,
  updateDoc,
} from 'firebase/firestore';
import { cmsAuth, cmsDb } from '../services/platformCmsClient';
import { timeAgo } from './wishAdminClient';

const STATUS_OPTIONS = ['open', 'in_progress', 'resolved', 'closed'];

/**
 * Admin-only Support Tickets queue (`/admin` → Support Tickets tab).
 * Backed by Firestore `support_tickets` created exclusively via `submitSupportTicket`.
 */
export default function SupportTicketsAdmin() {
  const [tickets, setTickets] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const [searchText, setSearchText] = useState('');
  const [selectedId, setSelectedId] = useState(null);
  const [replyText, setReplyText] = useState('');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    const q = query(
      collection(cmsDb, 'support_tickets'),
      orderBy('updatedAt', 'desc'),
      limit(200)
    );
    return onSnapshot(
      q,
      (snap) => {
        setTickets(snap.docs.map((d) => ({ id: d.id, ...d.data() })));
        setLoading(false);
        setError('');
      },
      (err) => {
        setError(err?.message || 'Unable to load support tickets.');
        setLoading(false);
      }
    );
  }, []);

  const filtered = useMemo(() => {
    const q = searchText.trim().toLowerCase();
    return tickets.filter((t) => {
      if (statusFilter !== 'all' && t.status !== statusFilter) return false;
      if (!q) return true;
      return (
        String(t.trackingCode || '').toLowerCase().includes(q) ||
        String(t.subject || '').toLowerCase().includes(q) ||
        String(t.message || '').toLowerCase().includes(q) ||
        String(t.category || '').toLowerCase().includes(q) ||
        String(t.contactEmail || '').toLowerCase().includes(q)
      );
    });
  }, [tickets, statusFilter, searchText]);

  const selected = useMemo(
    () => tickets.find((t) => t.id === selectedId) || filtered[0] || null,
    [tickets, selectedId, filtered]
  );

  useEffect(() => {
    if (selected) {
      setReplyText(selected.adminReply || '');
    }
  }, [selected?.id]);

  const handleSaveReply = async (nextStatus = null) => {
    if (!selected) return;
    setBusy(true);
    try {
      const user = cmsAuth.currentUser;
      await updateDoc(doc(cmsDb, 'support_tickets', selected.id), {
        status: nextStatus || selected.status || 'in_progress',
        adminReply: String(replyText || '').trim().slice(0, 2000),
        repliedByUid: user?.uid || '',
        repliedByName: String(
          user?.displayName || user?.email || 'Oneova Support'
        ).slice(0, 120),
        updatedAt: serverTimestamp(),
      });
    } catch (err) {
      setError(err?.message || 'Could not update ticket.');
    } finally {
      setBusy(false);
    }
  };

  const handleDelete = async (ticket) => {
    const ok = window.confirm(
      `Delete support ticket ${ticket.trackingCode || ticket.id}?`
    );
    if (!ok) return;
    setBusy(true);
    try {
      await deleteDoc(doc(cmsDb, 'support_tickets', ticket.id));
      if (selectedId === ticket.id) setSelectedId(null);
    } catch (err) {
      setError(err?.message || 'Delete failed.');
    } finally {
      setBusy(false);
    }
  };

  const openCount = tickets.filter((t) => t.status === 'open').length;

  return (
    <div className="wa-layout">
      <div className="wa-card">
        <span className="wa-eyebrow">HELP CENTER QUEUE</span>
        <h3>Support Tickets</h3>
        <div className="wa-stats">
          <div>
            <strong>{tickets.length}</strong>
            <span>Total</span>
          </div>
          <div>
            <strong>{openCount}</strong>
            <span>Open</span>
          </div>
        </div>
        <div className="wa-status-row" style={{ marginTop: 10 }}>
          {['all', ...STATUS_OPTIONS].map((s) => (
            <button
              key={s}
              type="button"
              className={`wa-status-btn ${statusFilter === s ? 'is-active' : ''}`}
              onClick={() => setStatusFilter(s)}
            >
              {s.replace('_', ' ')}
            </button>
          ))}
        </div>
      </div>

      <div className="wa-card">
        <div className="wa-toolbar">
          <input
            type="search"
            className="cms-input"
            placeholder="Search by code (OVA-...), subject, email..."
            value={searchText}
            onChange={(e) => setSearchText(e.target.value)}
          />
        </div>

        {error && <p className="wa-error">{error}</p>}
        {loading ? (
          <p className="wa-muted">Loading support tickets…</p>
        ) : filtered.length === 0 ? (
          <p className="wa-muted">No support tickets match the current filter.</p>
        ) : (
          <ul className="wa-ideas">
            {filtered.map((t) => (
              <li key={t.id}>
                <button
                  type="button"
                  className={`wa-idea ${selected?.id === t.id ? 'is-active' : ''}`}
                  onClick={() => setSelectedId(t.id)}
                >
                  <div className="wa-idea-top">
                    <span className="wa-pill">{t.trackingCode || t.id}</span>
                    <span className="wa-pill wa-pill-planned">{t.status}</span>
                    <span className="wa-muted">{t.category}</span>
                    <span className="wa-right wa-muted">
                      {timeAgo(t.updatedAt || t.createdAt)}
                    </span>
                  </div>
                  <strong>{t.subject}</strong>
                  <p className="wa-muted" style={{ margin: 0 }}>
                    {String(t.message || '').slice(0, 110)}
                  </p>
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>

      {selected && (
        <div className="wa-card wa-col-detail wa-detail">
          <div className="wa-card-head">
            <div>
              <span className="wa-eyebrow">{selected.trackingCode}</span>
              <h3>{selected.subject}</h3>
            </div>
            <button
              type="button"
              className="wa-x"
              onClick={() => setSelectedId(null)}
              aria-label="Close detail"
            >
              ✕
            </button>
          </div>
          <p className="wa-muted">
            Category: {selected.category}
            {selected.contactEmail ? ` · Email: ${selected.contactEmail}` : ''}
          </p>
          <p className="wa-body">{selected.message}</p>

          <h4>Status</h4>
          <div className="wa-status-row">
            {STATUS_OPTIONS.map((st) => (
              <button
                key={st}
                type="button"
                disabled={busy}
                className={`wa-status-btn ${selected.status === st ? 'is-active' : ''}`}
                onClick={() => handleSaveReply(st)}
              >
                {st.replace('_', ' ')}
              </button>
            ))}
          </div>

          <h4>Official Support Reply</h4>
          <textarea
            rows={4}
            className="cms-input wa-textarea"
            placeholder="Write an official response visible via the user's tracking code + PIN..."
            value={replyText}
            onChange={(e) => setReplyText(e.target.value)}
          />

          <div className="wa-actions">
            <button
              type="button"
              className="btn-primary wa-small-btn"
              disabled={busy}
              onClick={() => handleSaveReply(selected.status === 'open' ? 'resolved' : null)}
            >
              {busy ? 'Saving…' : 'Save Reply'}
            </button>
            <button
              type="button"
              className="wa-link wa-danger"
              disabled={busy}
              onClick={() => handleDelete(selected)}
            >
              Delete Ticket
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
