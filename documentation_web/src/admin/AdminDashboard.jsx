import React, { useState } from 'react';
import { useCmsAdminAuth } from '../services/platformCmsClient';
import AdminCmsModal from '../components/AdminCmsModal';
import SupportTicketsAdmin from './SupportTicketsAdmin';
import WishIdeasAdmin from './WishIdeasAdmin';
import './adminDashboard.css';

/**
 * `/admin` — exclusive Oneova admin workspace.
 * All admin data, CMS publishing, feedback moderation, and support tickets
 * are accessible solely here behind Firebase Admin authentication & Firestore rules.
 */
export default function AdminDashboard() {
  const { user, isAdmin, roleLabel, loading, signInEmail, signInGoogle, signOutAdmin } = useCmsAdminAuth();
  const [activeTab, setActiveTab] = useState('feedback'); // 'feedback' | 'tickets' | 'cms'
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const attempt = async (fn) => {
    setBusy(true);
    setError('');
    try {
      await fn();
    } catch (e) {
      setError(e?.message || 'Sign-in failed.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="wa-page">
      <header className="wa-topbar">
        <a href="/" className="wa-brand">Oneova <span>Admin</span></a>
        <nav className="wa-nav" aria-label="Admin Navigation">
          <button
            type="button"
            className={`wa-nav-item ${activeTab === 'feedback' ? 'is-active' : ''}`}
            onClick={() => setActiveTab('feedback')}
          >
            User feedback
          </button>
          <button
            type="button"
            className={`wa-nav-item ${activeTab === 'tickets' ? 'is-active' : ''}`}
            onClick={() => setActiveTab('tickets')}
          >
            Support tickets
          </button>
          <button
            type="button"
            className={`wa-nav-item ${activeTab === 'cms' ? 'is-active' : ''}`}
            onClick={() => setActiveTab('cms')}
          >
            Docs &amp; rules CMS
          </button>
        </nav>
        {user && (
          <div className="wa-user">
            <span>{user.email || user.uid}</span>
            {roleLabel && <span className="wa-tag">{roleLabel}</span>}
            <button type="button" className="wa-link" onClick={signOutAdmin}>Sign out</button>
          </div>
        )}
      </header>

      <main className="wa-main">
        {loading ? (
          <p className="wa-muted wa-center">Checking your admin access…</p>
        ) : !user ? (
          <div className="wa-card wa-gate">
            <h2>Sign in to the admin dashboard</h2>
            <form
              onSubmit={(e) => {
                e.preventDefault();
                attempt(() => signInEmail(email, password));
              }}
            >
              <input className="cms-input" type="email" required placeholder="Email" value={email}
                onChange={(e) => setEmail(e.target.value)} />
              <input className="cms-input" type="password" required placeholder="Password" value={password}
                onChange={(e) => setPassword(e.target.value)} />
              <button type="submit" className="btn-primary" disabled={busy}>{busy ? 'Signing in…' : 'Sign in'}</button>
            </form>
            <button type="button" className="btn-secondary" disabled={busy} onClick={() => attempt(signInGoogle)}>
              Continue with Google
            </button>
            {error && <p className="wa-error">{error}</p>}
          </div>
        ) : !isAdmin ? (
          <div className="wa-card wa-gate">
            <h2>Admin access required</h2>
            <p className="wa-muted">
              {user.email || user.uid} is not an Oneova admin. Ask an owner to set your role to admin.
            </p>
            <button type="button" className="btn-secondary" onClick={signOutAdmin}>Switch account</button>
          </div>
        ) : activeTab === 'cms' ? (
          <AdminCmsModal isOpen embedded onClose={() => setActiveTab('feedback')} />
        ) : activeTab === 'tickets' ? (
          <SupportTicketsAdmin />
        ) : (
          <WishIdeasAdmin />
        )}
      </main>
    </div>
  );
}
