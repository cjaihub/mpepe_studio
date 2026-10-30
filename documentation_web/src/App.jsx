import React, { useState, useRef, useEffect, Suspense, lazy } from 'react';
import Navbar from './components/Navbar';
import Hero from './components/Hero';
import FeaturesGrid from './components/FeaturesGrid';
import AboutUs from './components/AboutUs';
import DocsPortal from './components/DocsPortal';
import FloatingVideoWidget from './components/FloatingVideoWidget';
import OvaAssistantWidget from './components/OvaAssistantWidget';
import WaveBackground from './components/WaveBackground';
import Footer from './components/Footer';
import { usePlatformDocs, useCmsAdminAuth } from './services/platformCmsClient';

const DownloadModal = lazy(() => import('./components/DownloadModal'));
const PolicyModal = lazy(() => import('./components/PolicyModal'));
const AdminCmsModal = lazy(() => import('./components/AdminCmsModal'));

export default function App() {
  const { docs, isLiveConnected, liveOverrideCount } = usePlatformDocs({ includeDrafts: false });
  const { isAdmin } = useCmsAdminAuth();

  const [currentDocId, setCurrentDocId] = useState('live-studio');
  const [isDownloadOpen, setIsDownloadOpen] = useState(false);
  const [isPolicyOpen, setIsPolicyOpen] = useState(false);
  const [policyTab, setPolicyTab] = useState('guidelines');
  const [isOvaAssistantOpen, setIsOvaAssistantOpen] = useState(() => {
    try {
      return new URLSearchParams(window.location.search).get('ask') === '1';
    } catch {
      return false;
    }
  });
  const [isAdminCmsOpen, setIsAdminCmsOpen] = useState(() => {
    try {
      return new URLSearchParams(window.location.search).get('admin') === '1';
    } catch {
      return false;
    }
  });
  const [adminCmsDocId, setAdminCmsDocId] = useState(null);

  const [theme, setTheme] = useState(() => {
    try {
      return localStorage.getItem('oneova_theme') || 'dark';
    } catch {
      return 'dark';
    }
  });
  const searchInputRef = useRef(null);

  // Sync theme attribute with <html> element and persist in localStorage
  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
    try {
      localStorage.setItem('oneova_theme', theme);
    } catch {}
  }, [theme]);

  const handleToggleTheme = () => {
    setTheme((prev) => (prev === 'dark' ? 'light' : 'dark'));
  };

  const handleOpenAdminCms = (docId = null) => {
    setAdminCmsDocId(docId || currentDocId);
    setIsAdminCmsOpen(true);
  };

  const handleOpenOvaAssistant = () => {
    setIsOvaAssistantOpen(true);
  };

  // Global shortcuts: Cmd/Ctrl + K (Search) and Cmd/Ctrl + Shift + E (Live Admin CMS)
  useEffect(() => {
    const handleKeyDown = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        handleSearchFocus();
      } else if ((e.metaKey || e.ctrlKey) && e.shiftKey && e.key.toLowerCase() === 'e') {
        e.preventDefault();
        handleOpenAdminCms();
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [currentDocId]);

  const handleSearchFocus = () => {
    const docsSection = document.getElementById('docs');
    if (docsSection) {
      docsSection.scrollIntoView({ behavior: 'smooth' });
    }
    if (searchInputRef.current) {
      searchInputRef.current.focus();
    }
  };

  const handleSelectDoc = (docId) => {
    setCurrentDocId(docId);
    const docsSection = document.getElementById('docs');
    if (docsSection) {
      docsSection.scrollIntoView({ behavior: 'smooth' });
    }
  };

  const handleOpenPolicy = (tab = 'guidelines') => {
    setPolicyTab(tab);
    setIsPolicyOpen(true);
  };

  return (
    <>
      <WaveBackground theme={theme} />
      <div className="ambient-glow" aria-hidden="true" />

      <Navbar
        theme={theme}
        onToggleTheme={handleToggleTheme}
        onOpenDownload={() => setIsDownloadOpen(true)}
        onSearchFocus={handleSearchFocus}
        onSelectDoc={handleSelectDoc}
        onOpenPolicy={handleOpenPolicy}
        onOpenAdminCms={handleOpenAdminCms}
        onOpenOvaAssistant={handleOpenOvaAssistant}
        isAdmin={isAdmin}
      />

      <main>
        <Hero onOpenDownload={() => setIsDownloadOpen(true)} />

        <FeaturesGrid onSelectDoc={handleSelectDoc} />

        <AboutUs
          onOpenDownload={() => setIsDownloadOpen(true)}
          onSelectDoc={handleSelectDoc}
        />

        <DocsPortal
          docs={docs}
          currentDocId={currentDocId}
          onSelectDoc={handleSelectDoc}
          searchRef={searchInputRef}
          onOpenDownload={() => setIsDownloadOpen(true)}
          onOpenAdminCms={handleOpenAdminCms}
          onOpenOvaAssistant={handleOpenOvaAssistant}
          isLiveConnected={isLiveConnected}
          liveOverrideCount={liveOverrideCount}
          isAdmin={isAdmin}
        />
      </main>

      <FloatingVideoWidget />

      <OvaAssistantWidget
        isOpen={isOvaAssistantOpen}
        onOpen={() => setIsOvaAssistantOpen(true)}
        onClose={() => setIsOvaAssistantOpen(false)}
        docs={docs}
        onSelectDoc={handleSelectDoc}
        currentDocId={currentDocId}
      />

      <Footer
        onSelectDoc={handleSelectDoc}
        onOpenDownload={() => setIsDownloadOpen(true)}
        onOpenPolicy={handleOpenPolicy}
        onOpenAdminCms={handleOpenAdminCms}
        onOpenOvaAssistant={handleOpenOvaAssistant}
        isLiveConnected={isLiveConnected}
      />

      <Suspense fallback={null}>
        {isDownloadOpen && (
          <DownloadModal
            isOpen={isDownloadOpen}
            onClose={() => setIsDownloadOpen(false)}
          />
        )}

        {isPolicyOpen && (
          <PolicyModal
            isOpen={isPolicyOpen}
            initialTab={policyTab}
            docs={docs}
            onOpenAdminCms={handleOpenAdminCms}
            onClose={() => setIsPolicyOpen(false)}
          />
        )}

        {isAdminCmsOpen && (
          <AdminCmsModal
            isOpen={isAdminCmsOpen}
            initialDocId={adminCmsDocId}
            onClose={() => setIsAdminCmsOpen(false)}
          />
        )}
      </Suspense>
    </>
  );
}
