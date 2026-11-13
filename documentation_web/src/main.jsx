import { StrictMode, Suspense, lazy } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.jsx'

// oneova.web.app/admin → admin dashboard (hosting rewrites every path to index.html).
const AdminDashboard = lazy(() => import('./admin/AdminDashboard.jsx'))
const isAdminPath = /^\/admin(\/|$)/.test(window.location.pathname)

if (isAdminPath) {
  let theme = 'dark'
  try {
    theme = localStorage.getItem('oneova_theme') || 'dark'
  } catch {}
  document.documentElement.setAttribute('data-theme', theme)
  document.title = 'Oneova Admin'
}

createRoot(document.getElementById('root')).render(
  <StrictMode>
    {isAdminPath ? (
      <Suspense fallback={null}>
        <AdminDashboard />
      </Suspense>
    ) : (
      <App />
    )}
  </StrictMode>,
)
