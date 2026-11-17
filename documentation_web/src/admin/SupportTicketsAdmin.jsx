import React, { useEffect, useMemo, useState } from 'react';
import {
  addDoc,
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

const STATUS_OPTIONS = ['escalated_human', 'open', 'in_progress', 'resolved', 'closed'];

/**
 * Real-time Admin Support Queue & Live Chat Handoff (`/admin` → Support Tickets tab).
 * Prioritizes live AI escalations (`escalated_human`) and streams real-time chat
 * messages with users right inside the admin workspace.
 */
export default function SupportTicketsAdmin() {
  const [tickets, setTickets] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const [searchText, setSearchText] = useState('');
  const [selectedId, setSelectedId] = useState(null);
  const [chatMessages, setChatMessages] = useState([]);
  const [liveMsgText, setLiveMsgText] = useState('');
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
    const list = tickets.filter((t) => {
      if (statusFilter !== 'all' && t.status !== statusFilter) return false;
      if (!q) return true;
      return (
        String(t.trackingCode || '').toLowerCase().includes(q) ||
        String(t.subject || '').toLowerCase().includes(q) ||
        String(t.message || '').toLowerCase().includes(q) ||
        String(t.aiSummary || '').toLowerCase().includes(q) ||
        String(t.category || '').toLowerCase().includes(q) ||
        String(t.contactEmail || '').toLowerCase().includes(q)
      );
    });
    // Pin live human escalation requests at the top cleanly
    return list.sort((a, b) => {
      const aUrgent = a.status === 'escalated_human' || a.unreadByAdmin ? 1 : 0;
      const bUrgent = b.status === 'escalated_human' || b.unreadByAdmin ? 1 : 0;
      return bUrgent - aUrgent;
    });
  }, [tickets, statusFilter, searchText]);

  const selected = useMemo(
    () => tickets.find((t) => t.id === selectedId) || filtered[0] || null,
    [tickets, selectedId, filtered]
  );

  // Real-time subcollection listener for live user <-> admin chat
  useEffect(() => {
    if (!selected?.id) {
      setChatMessages([]);
      return undefined;
    }
    const q = query(
      collection(cmsDb, 'support_tickets', selected.id, 'messages'),
      orderBy('createdAt', 'asc'),
      limit(100)
    );
    return onSnapshot(
      q,
      (snap) => {
        setChatMessages(snap.docs.map((d) => ({ id: d.id, ...d.data() })));
      },
      () => {}
    );
  }, [selected?.id]);

  const handleJoinLiveChat = async () => {
    if (!selected) return;
    setBusy(true);
    try {
      const user = cmsAuth.currentUser;
      const adminName = String(user?.displayName || user?.email || 'Oneova Support Admin').slice(0, 120);
      await addDoc(collection(cmsDb, 'support_tickets', selected.id, 'messages'), {
        senderRole: 'admin',
        senderUid: user?.uid || '',
        senderName: adminName,
        text: `${adminName} has joined the live support chat. How can I assist you right now?`,
        actionTaken: 'admin_joined_live',
        createdAt: serverTimestamp(),
      });
      await updateDoc(doc(cmsDb, 'support_tickets', selected.id), {
        status: 'in_progress',
        needsHuman: true,
        handledByUid: user?.uid || '',
        handledByName: adminName,
        unreadByAdmin: false,
        unreadByUser: true,
        lastMessagePreview: `${adminName} joined live chat`,
        lastMessageAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
    } catch (err) {
      setError(err?.message || 'Could not join live session.');
    } finally {
      setBusy(false);
    }
  };

  const handleSendAdminMessage = async (e) => {
    e?.preventDefault();
    const clean = liveMsgText.trim();
    if (!selected || !clean) return;
    setBusy(true);
    try {
      const user = cmsAuth.currentUser;
      const adminName = String(user?.displayName || user?.email || 'Oneova Support').slice(0, 120);
      await addDoc(collection(cmsDb, 'support_tickets', selected.id, 'messages'), {
        senderRole: 'admin',
        senderUid: user?.uid || '',
        senderName: adminName,
        text: clean.slice(0, 2000),
        actionTaken: 'admin_reply',
        createdAt: serverTimestamp(),
      });
      await updateDoc(doc(cmsDb, 'support_tickets', selected.id), {
        status: selected.status === 'resolved' || selected.status === 'closed' ? selected.status : 'in_progress',
        adminReply: clean.slice(0, 2000),
        repliedByUid: user?.uid || '',
        repliedByName: adminName,
        handledByUid: user?.uid || '',
        handledByName: adminName,
        unreadByAdmin: false,
        unreadByUser: true,
        lastMessagePreview: clean.slice(0, 260),
        lastMessageAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
      setLiveMsgText('');
    } catch (err) {
      setError(err?.message || 'Failed to send reply.');
    } finally {
      setBusy(false);
    }
  };

  const handleSetStatus = async (nextStatus) => {
    if (!selected) return;
    setBusy(true);
    try {
      const user = cmsAuth.currentUser;
      await updateDoc(doc(cmsDb, 'support_tickets', selected.id), {
        status: nextStatus,
        needsHuman: nextStatus === 'escalated_human' || nextStatus === 'in_progress',
        handledByUid: user?.uid || '',
        handledByName: String(user?.displayName || user?.email || 'Oneova Support').slice(0, 120),
        unreadByAdmin: false,
        updatedAt: serverTimestamp(),
      });
    } catch (err) {
      setError(err?.message || 'Could not update ticket status.');
    } finally {
      setBusy(false);
    }
  };

  const handleDelete = async (ticket) => {
    const ok = window.confirm(`Delete support ticket ${ticket.trackingCode || ticket.id}?`);
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

  const liveHumanCount = tickets.filter((t) => t.status === 'escalated_human' || t.unreadByAdmin).length;

  return (
    <div className="wa-layout">
      <div className="wa-card">
        <span className="wa-eyebrow">LIVE SUPPORT QUEUE</span>
        <h3>Support &amp; Escalations</h3>
        <div className="wa-stats">
          <div>
            <strong>{tickets.length}</strong>
            <span>Total</span>
          </div>
          <div>
            <strong style={{ color: liveHumanCount > 0 ? 'var(--brand-pink)' : undefined }}>
              {liveHumanCount}
            </strong>
            <span>Live Needed</span>
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
            placeholder="Search by OVA-... code, AI summary, topic..."
            value={searchText}
            onChange={(e) => setSearchText(e.target.value)}
          />
        </div>

        {error && <p className="wa-error">{error}</p>}
        {loading ? (
          <p className="wa-muted">Connecting to real-time support stream…</p>
        ) : filtered.length === 0 ? (
          <p className="wa-muted">No support sessions match this filter.</p>
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
                    <span
                      className={`wa-pill ${
                        t.status === 'escalated_human' || t.unreadByAdmin
                          ? 'wa-pill-urgent'
                          : 'wa-pill-planned'
                      }`}
                    >
                      {t.status === 'escalated_human' ? 'LIVE HUMAN' : t.status}
                    </span>
                    <span className="wa-muted">{t.category}</span>
                    <span className="wa-right wa-muted">{timeAgo(t.updatedAt || t.createdAt)}</span>
                  </div>
                  <strong>{t.subject}</strong>
                  <p className="wa-muted" style={{ margin: 0 }}>
                    {String(t.lastMessagePreview || t.message || '').slice(0, 110)}
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
              <span className="wa-eyebrow">
                {selected.trackingCode} {selected.uid ? '· SIGNED-IN USER' : '· GUEST'}
              </span>
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
            {selected.handledByName ? ` · Assigned: ${selected.handledByName}` : ''}
          </p>

          {selected.aiSummary && (
            <div className="wa-ai-brief">
              <strong>✦ AI Agent Diagnostic Brief</strong>
              <p>{selected.aiSummary}</p>
            </div>
          )}

          <div className="wa-live-controls-bar">
            <button
              type="button"
              className="btn-primary wa-small-btn"
              disabled={busy}
              onClick={handleJoinLiveChat}
            >
              👤 Join Live Chat Now
            </button>
            <div className="wa-status-row">
              {STATUS_OPTIONS.map((st) => (
                <button
                  key={st}
                  type="button"
                  disabled={busy}
                  className={`wa-status-btn ${selected.status === st ? 'is-active' : ''}`}
                  onClick={() => handleSetStatus(st)}
                >
                  {st.replace('_', ' ')}
                </button>
              ))}
            </div>
          </div>

          <h4>Real-Time Conversation</h4>
          <div className="wa-chat-stream">
            {chatMessages.length === 0 ? (
              <div className="wa-chat-item user">
                <small>Initial Request</small>
                <p>{selected.message}</p>
              </div>
            ) : (
              chatMessages.map((m) => (
                <div key={m.id} className={`wa-chat-item ${m.senderRole || 'user'}`}>
                  <small>
                    {m.senderRole === 'admin'
                      ? `👤 ${m.senderName || 'Human Admin'}`
                      : m.senderRole === 'ai'
                      ? '✦ Oneova AI'
                      : 'Creator / Visitor'}
                  </small>
                  <p>{m.text}</p>
                </div>
              ))
            )}
          </div>

          <form onSubmit={handleSendAdminMessage} className="wa-reply-form">
            <textarea
              rows={3}
              className="cms-input wa-textarea"
              placeholder="Write a real-time message directly to this user’s open support drawer..."
              value={liveMsgText}
              onChange={(e) => setLiveMsgText(e.target.value)}
            />
            <div className="wa-actions">
              <button
                type="submit"
                className="btn-primary wa-small-btn"
                disabled={busy || !liveMsgText.trim()}
              >
                {busy ? 'Sending…' : 'Send Live Reply'}
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
          </form>
        </div>
      )}
    </div>
  );
}
