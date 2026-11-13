import React, { useState } from 'react';
import { useCmsAdminAuth } from '../services/platformCmsClient';
import WishIdeasAdmin from './WishIdeasAdmin';
import './adminDashboard.css';

/**
 * oneova.web.app/admin — the Oneova admin dashboard (admin tools live here,
 * not in the app). Access: users/{uid}.role in admin/owner/founder, or the
 * `admin` custom claim; Firestore rules enforce the same.
 */
export default function AdminDashboard() {
  const { user, isAdmin, roleLabel, loading, signInEmail, signInGoogle, signOutAdmin } = useCmsAdminAuth();
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
        <nav className="wa-nav">
          <span className="wa-nav-item is-active">User feedback</span>
          <a className="wa-nav-item" href="/?admin=1">Docs &amp; rules CMS</a>
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
        ) : (
          <WishIdeasAdmin />
        )}
      </main>
    </div>
  );
}
