import React, { useState, useRef, useEffect, Suspense, lazy } from 'react';
import Navbar from './components/Navbar';
import Hero from './components/Hero';
import HelpCenterHub from './components/HelpCenterHub';
import DocsPortal from './components/DocsPortal';
import FeaturesGrid from './components/FeaturesGrid';
import DesktopDownloads from './components/DesktopDownloads';
import AboutUs from './components/AboutUs';
import FloatingVideoWidget from './components/FloatingVideoWidget';
import OvaAssistantWidget from './components/OvaAssistantWidget';
import WaveBackground from './components/WaveBackground';
import Footer from './components/Footer';
import { usePublicPlatformDocs } from './services/publicDocsClient';

const DownloadModal = lazy(() => import('./components/DownloadModal'));
const PolicyModal = lazy(() => import('./components/PolicyModal'));

export default function App() {
  const { docs, isLiveConnected, liveOverrideCount } = usePublicPlatformDocs();

  const [currentDocId, setCurrentDocId] = useState('live-studio');
  const [isDownloadOpen, setIsDownloadOpen] = useState(false);
  const [isPolicyOpen, setIsPolicyOpen] = useState(false);
  const [policyTab, setPolicyTab] = useState('guidelines');
  const [ticketTriggerCount, setTicketTriggerCount] = useState(0);
  const [isOvaAssistantOpen, setIsOvaAssistantOpen] = useState(() => {
    try {
      return new URLSearchParams(window.location.search).get('ask') === '1';
    } catch {
      return false;
    }
  });

  const [theme, setTheme] = useState(() => {
    try {
      return localStorage.getItem('oneova_theme') || 'dark';
    } catch {
      return 'dark';
    }
  });
  const searchInputRef = useRef(null);

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
    try {
      localStorage.setItem('oneova_theme', theme);
    } catch {}
  }, [theme]);

  const handleToggleTheme = () => {
    setTheme((prev) => (prev === 'dark' ? 'light' : 'dark'));
  };

  const handleOpenOvaAssistant = () => {
    setIsOvaAssistantOpen(true);
  };

  const handleOpenHelpCenter = () => {
    const el = document.getElementById('help');
    if (el) el.scrollIntoView({ behavior: 'smooth' });
  };

  const handleOpenTickets = () => {
    setTicketTriggerCount((c) => c + 1);
    const el = document.getElementById('help');
    if (el) el.scrollIntoView({ behavior: 'smooth' });
  };

  useEffect(() => {
    try {
      const path = window.location.pathname.toLowerCase();
      const targetId =
        path === '/desktop' || window.location.hash === '#desktop'
          ? 'desktop'
          : path === '/help' || window.location.hash === '#help'
          ? 'help'
          : path === '/guide' || window.location.hash === '#docs'
          ? 'docs'
          : null;
      if (targetId) {
        setTimeout(() => {
          document.getElementById(targetId)?.scrollIntoView({ behavior: 'smooth' });
        }, 120);
      }
    } catch {}
  }, []);

  // Global Cmd/Ctrl + K quick search shortcut
  useEffect(() => {
    const handleKeyDown = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        handleSearchFocus();
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, []);

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
        onOpenOvaAssistant={handleOpenOvaAssistant}
      />

      <main>
        <Hero
          onOpenDownload={() => setIsDownloadOpen(true)}
          onOpenHelp={handleOpenHelpCenter}
        />

        <HelpCenterHub
          key={`hc-${ticketTriggerCount}`}
          docs={docs}
          onSelectDoc={handleSelectDoc}
          onOpenSupportDrawer={handleOpenOvaAssistant}
          initialTicketOpen={ticketTriggerCount > 0}
        />

        <DocsPortal
          docs={docs}
          currentDocId={currentDocId}
          onSelectDoc={handleSelectDoc}
          searchRef={searchInputRef}
          onOpenDownload={() => setIsDownloadOpen(true)}
          onOpenOvaAssistant={handleOpenOvaAssistant}
          onOpenTickets={handleOpenTickets}
          isLiveConnected={isLiveConnected}
          liveOverrideCount={liveOverrideCount}
        />

        <FeaturesGrid onSelectDoc={handleSelectDoc} />

        <DesktopDownloads />

        <AboutUs
          onOpenDownload={() => setIsDownloadOpen(true)}
          onSelectDoc={handleSelectDoc}
        />
      </main>

      <FloatingVideoWidget />

      <OvaAssistantWidget
        isOpen={isOvaAssistantOpen}
        onOpen={() => setIsOvaAssistantOpen(true)}
        onClose={() => setIsOvaAssistantOpen(false)}
        docs={docs}
        onSelectDoc={handleSelectDoc}
        onOpenTickets={handleOpenTickets}
        currentDocId={currentDocId}
      />

      <Footer
        onSelectDoc={handleSelectDoc}
        onOpenDownload={() => setIsDownloadOpen(true)}
        onOpenPolicy={handleOpenPolicy}
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
            onClose={() => setIsPolicyOpen(false)}
          />
        )}
      </Suspense>
    </>
  );
}
