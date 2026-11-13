import React, { useMemo, useState } from 'react';
import {
  useWishIdeas,
  useWishClusters,
  useWishComments,
  useWishInsights,
  setIdeaStatus,
  setIdeaReply,
  postOfficialComment,
  deleteIdea,
  deleteComment,
  refreshSummary,
  timeAgo,
} from './wishAdminClient';

const STATUSES = [
  { id: 'open', label: 'Open' },
  { id: 'planned', label: 'Planned' },
  { id: 'building', label: 'Building' },
  { id: 'shipped', label: 'Shipped' },
  { id: 'declined', label: 'Not now' },
];

const SORTS = [
  { id: 'createdAt', label: 'Newest' },
  { id: 'reactionCount', label: 'Most backed' },
  { id: 'commentCount', label: 'Most discussed' },
];

function StatusPill({ status }) {
  const s = STATUSES.find((x) => x.id === status) || STATUSES[0];
  return <span className={`wa-pill wa-pill-${s.id}`}>{s.label}</span>;
}

function SummaryPanel({ onPickCluster, onPickIdea }) {
  const { data, loading, error } = useWishInsights();
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState('');

  const refresh = async () => {
    setBusy(true);
    setMsg('');
    try {
      await refreshSummary();
      setMsg('Summary refreshed.');
    } catch (e) {
      setMsg(e?.message || 'Could not refresh the summary.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <section className="wa-card wa-summary">
      <div className="wa-card-head">
        <div>
          <span className="wa-eyebrow">AI summary · Vertex AI</span>
          <h3>What users are telling us</h3>
        </div>
        <button type="button" className="btn-secondary wa-small-btn" onClick={refresh} disabled={busy}>
          {busy ? 'Analysing…' : 'Refresh now'}
        </button>
      </div>
      {msg && <p className="wa-muted">{msg}</p>}
      {loading && <p className="wa-muted">Loading summary…</p>}
      {error && <p className="wa-error">{error}</p>}
      {!loading && !data && !error && (
        <p className="wa-muted">No summary yet. It is written every 6 hours, or press “Refresh now”.</p>
      )}
      {data && (
        <>
          <p className="wa-headline">{data.headline}</p>
          {data.mood && <p className="wa-muted">{data.mood}</p>}
          <div className="wa-stats">
            <div><strong>{data.ideaCount ?? 0}</strong><span>posts · 30d</span></div>
            <div><strong>{data.ideasThisWeek ?? 0}</strong><span>this week</span></div>
            <div><strong>{data.clusterCount ?? 0}</strong><span>clusters</span></div>
          </div>

          {(data.topThemes || []).length > 0 && (
            <>
              <h4>Top themes</h4>
              <ul className="wa-list">
                {data.topThemes.map((t) => (
                  <li key={t.clusterId}>
                    <button type="button" className="wa-link" onClick={() => onPickCluster(t.clusterId)}>
                      {t.label}
                    </button>
                    <span className="wa-count">{t.ideas} ideas · {t.reactions} backers</span>
                    <p>{t.why}</p>
                  </li>
                ))}
              </ul>
            </>
          )}

          {(data.trendingAsks || []).length > 0 && (
            <>
              <h4>Trending this week</h4>
              <ul className="wa-list">
                {data.trendingAsks.map((t) => (
                  <li key={t.ideaId}>
                    <button type="button" className="wa-link" onClick={() => onPickIdea(t.ideaId)}>
                      {t.title}
                    </button>
                    <p>{t.why}</p>
                  </li>
                ))}
              </ul>
            </>
          )}

          {(data.suggestedFeatures || []).length > 0 && (
            <>
              <h4>New feature ideas from the AI</h4>
              <div className="wa-suggest-grid">
                {data.suggestedFeatures.map((f, i) => (
                  <div key={`${f.title}-${i}`} className="wa-suggest">
                    <div className="wa-suggest-top">
                      <strong>{f.title}</strong>
                      <span className="wa-tag">{f.effort} · impact {f.impact}/10</span>
                    </div>
                    <p>{f.pitch}</p>
                    {f.buildsOn && <p className="wa-muted">Builds on: {f.buildsOn}</p>}
                  </div>
                ))}
              </div>
            </>
          )}
          <p className="wa-muted wa-foot">Updated {timeAgo(data.generatedAt) || 'just now'}</p>
        </>
      )}
    </section>
  );
}

function ClusterList({ clusters, active, onPick }) {
  return (
    <section className="wa-card">
      <div className="wa-card-head">
        <div>
          <span className="wa-eyebrow">Clusters</span>
          <h3>Similar feedback, grouped</h3>
        </div>
      </div>
      {clusters.error && <p className="wa-error">{clusters.error}</p>}
      {!clusters.loading && clusters.items.length === 0 && <p className="wa-muted">No clusters yet.</p>}
      <ul className="wa-clusters">
        <li>
          <button type="button" className={`wa-cluster ${!active ? 'is-active' : ''}`} onClick={() => onPick(null)}>
            <span>All feedback</span>
          </button>
        </li>
        {clusters.items.map((c) => (
          <li key={c.id}>
            <button
              type="button"
              className={`wa-cluster ${active === c.id ? 'is-active' : ''}`}
              onClick={() => onPick(c.id)}
            >
              <span>{c.label}</span>
              <span className="wa-count">
                {c.ideaCount ?? 0} · {c.reactionCount ?? 0}♥
              </span>
            </button>
          </li>
        ))}
      </ul>
    </section>
  );
}

function IdeaDetail({ idea, onClose }) {
  const comments = useWishComments(idea?.id);
  const [reply, setReply] = useState(idea?.adminReply?.text || '');
  const [comment, setComment] = useState('');
  const [busy, setBusy] = useState('');
  const [err, setErr] = useState('');

  if (!idea) return null;

  const run = async (key, fn) => {
    setBusy(key);
    setErr('');
    try {
      await fn();
    } catch (e) {
      setErr(e?.message || 'That did not work.');
    } finally {
      setBusy('');
    }
  };

  const ai = idea.ai || {};
  return (
    <section className="wa-card wa-detail">
      <div className="wa-card-head">
        <div>
          <span className="wa-eyebrow">{idea.authorName || 'Member'} · {timeAgo(idea.createdAt)}</span>
          <h3>{idea.title}</h3>
        </div>
        <button type="button" className="wa-x" onClick={onClose} aria-label="Close">✕</button>
      </div>
      {idea.body && <p className="wa-body">{idea.body}</p>}

      <div className="wa-tags">
        <StatusPill status={idea.status} />
        {ai.category && <span className="wa-tag">{ai.category}</span>}
        {ai.sentiment && <span className="wa-tag">{ai.sentiment}</span>}
        {ai.impact != null && <span className="wa-tag">impact {ai.impact}/10</span>}
        {ai.clusterLabel && <span className="wa-tag">cluster: {ai.clusterLabel}</span>}
        {ai.duplicateOf && <span className="wa-tag wa-tag-pink">possible duplicate</span>}
        {ai.alreadyExists && <span className="wa-tag wa-tag-pink">exists: {ai.existingFeature}</span>}
        <span className="wa-tag">{idea.reactionCount || 0} backers</span>
        <span className="wa-tag">{idea.commentCount || 0} comments</span>
      </div>
      {ai.summary && <p className="wa-muted">AI: {ai.summary}</p>}
      {(ai.angles || []).length > 0 && (
        <p className="wa-muted">New angles from comments: {ai.angles.join(' · ')}</p>
      )}

      <h4>Status</h4>
      <div className="wa-status-row">
        {STATUSES.map((s) => (
          <button
            key={s.id}
            type="button"
            className={`wa-status-btn ${idea.status === s.id ? 'is-active' : ''}`}
            disabled={busy === 'status'}
            onClick={() => run('status', () => setIdeaStatus(idea.id, s.id))}
          >
            {s.label}
          </button>
        ))}
      </div>

      <h4>Official reply (users see it live)</h4>
      <textarea
        className="cms-input wa-textarea"
        maxLength={1000}
        rows={3}
        placeholder="Thanks — here is what we are doing about this…"
        value={reply}
        onChange={(e) => setReply(e.target.value)}
      />
      <div className="wa-actions">
        <button
          type="button"
          className="btn-primary wa-small-btn"
          disabled={busy === 'reply'}
          onClick={() => run('reply', () => setIdeaReply(idea.id, reply))}
        >
          {busy === 'reply' ? 'Saving…' : 'Save reply'}
        </button>
        {idea.adminReply?.text && (
          <button
            type="button"
            className="btn-secondary wa-small-btn"
            onClick={() => run('reply', () => setIdeaReply(idea.id, ''))}
          >
            Remove reply
          </button>
        )}
      </div>

      <h4>Discussion</h4>
      {comments.items.length === 0 && <p className="wa-muted">No comments yet.</p>}
      <ul className="wa-comments">
        {comments.items.map((c) => (
          <li key={c.id} className={c.isOfficial ? 'is-official' : ''}>
            <div className="wa-comment-top">
              <strong>{c.isOfficial ? 'Oneova team' : c.authorName || 'Member'}</strong>
              <span className="wa-muted">{timeAgo(c.createdAt)}</span>
              {c.ai?.sentiment && <span className="wa-tag">{c.ai.sentiment}</span>}
              <button
                type="button"
                className="wa-link wa-danger"
                onClick={() => run('del', () => deleteComment(idea.id, c.id))}
              >
                Remove
              </button>
            </div>
            <p>{c.text}</p>
          </li>
        ))}
      </ul>
      <textarea
        className="cms-input wa-textarea"
        maxLength={1000}
        rows={2}
        placeholder="Comment as the Oneova team…"
        value={comment}
        onChange={(e) => setComment(e.target.value)}
      />
      <div className="wa-actions">
        <button
          type="button"
          className="btn-primary wa-small-btn"
          disabled={!comment.trim() || busy === 'comment'}
          onClick={() =>
            run('comment', async () => {
              await postOfficialComment(idea.id, comment);
              setComment('');
            })
          }
        >
          Post as team
        </button>
        <button
          type="button"
          className="btn-secondary wa-small-btn wa-danger"
          onClick={() => {
            if (window.confirm('Delete this feedback with its comments and reactions?')) {
              run('delete', async () => {
                await deleteIdea(idea.id);
                onClose();
              });
            }
          }}
        >
          Delete
        </button>
      </div>
      {err && <p className="wa-error">{err}</p>}
    </section>
  );
}

export default function WishIdeasAdmin() {
  const [sort, setSort] = useState('createdAt');
  const [statusFilter, setStatusFilter] = useState('all');
  const [cluster, setCluster] = useState(null);
  const [search, setSearch] = useState('');
  const [selectedId, setSelectedId] = useState(null);

  const ideas = useWishIdeas(sort);
  const clusters = useWishClusters();

  const visible = useMemo(() => {
    const q = search.trim().toLowerCase();
    return ideas.items.filter((i) => {
      if (statusFilter !== 'all' && (i.status || 'open') !== statusFilter) return false;
      if (cluster && i.ai?.clusterId !== cluster) return false;
      if (q && !`${i.title} ${i.body}`.toLowerCase().includes(q)) return false;
      return true;
    });
  }, [ideas.items, statusFilter, cluster, search]);

  const selected = ideas.items.find((i) => i.id === selectedId) || null;

  return (
    <div className="wa-layout">
      <div className="wa-col-side">
        <SummaryPanel onPickCluster={(id) => { setCluster(id); setSelectedId(null); }} onPickIdea={setSelectedId} />
        <ClusterList clusters={clusters} active={cluster} onPick={(id) => { setCluster(id); setSelectedId(null); }} />
      </div>

      <div className="wa-col-main">
        <section className="wa-card">
          <div className="wa-toolbar">
            <input
              className="cms-input"
              placeholder="Search feedback…"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
            <select className="cms-input" value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
              <option value="all">All statuses</option>
              {STATUSES.map((s) => (
                <option key={s.id} value={s.id}>{s.label}</option>
              ))}
            </select>
            <select className="cms-input" value={sort} onChange={(e) => setSort(e.target.value)}>
              {SORTS.map((s) => (
                <option key={s.id} value={s.id}>{s.label}</option>
              ))}
            </select>
          </div>
          {ideas.error && <p className="wa-error">{ideas.error}</p>}
          {ideas.loading && <p className="wa-muted">Loading feedback…</p>}
          {!ideas.loading && visible.length === 0 && <p className="wa-muted">No feedback matches.</p>}
          <ul className="wa-ideas">
            {visible.map((i) => (
              <li key={i.id}>
                <button
                  type="button"
                  className={`wa-idea ${selectedId === i.id ? 'is-active' : ''}`}
                  onClick={() => setSelectedId(i.id)}
                >
                  <div className="wa-idea-top">
                    <StatusPill status={i.status} />
                    {i.ai?.category && <span className="wa-tag">{i.ai.category}</span>}
                    {i.ai?.impact != null && <span className="wa-tag">impact {i.ai.impact}</span>}
                    {i.ai?.duplicateOf && <span className="wa-tag wa-tag-pink">dup</span>}
                    {!i.adminReply?.text && (i.status || 'open') === 'open' && (
                      <span className="wa-dot" title="No team reply yet" />
                    )}
                    <span className="wa-muted wa-right">{timeAgo(i.createdAt)}</span>
                  </div>
                  <strong>{i.title}</strong>
                  {i.ai?.summary && <span className="wa-muted">{i.ai.summary}</span>}
                  <span className="wa-count">
                    {i.reactionCount || 0} backers · {i.commentCount || 0} comments · {i.authorName || 'Member'}
                  </span>
                </button>
              </li>
            ))}
          </ul>
        </section>
      </div>

      {selected && (
        <div className="wa-col-detail">
          <IdeaDetail
            key={`${selected.id}:${selected.adminReply?.text || ''}`}
            idea={selected}
            onClose={() => setSelectedId(null)}
          />
        </div>
      )}
    </div>
  );
}
