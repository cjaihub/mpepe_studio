import React, { useState, useRef, useEffect } from 'react';
import Navbar from './components/Navbar';
import Hero from './components/Hero';
import FeaturesGrid from './components/FeaturesGrid';
import AboutUs from './components/AboutUs';
import DocsPortal from './components/DocsPortal';
import DownloadModal from './components/DownloadModal';
import PolicyModal from './components/PolicyModal';
import FloatingVideoWidget from './components/FloatingVideoWidget';
import WaveBackground from './components/WaveBackground';
import Footer from './components/Footer';

export default function App() {
  const [currentDocId, setCurrentDocId] = useState('live-studio');
  const [isDownloadOpen, setIsDownloadOpen] = useState(false);
  const [isPolicyOpen, setIsPolicyOpen] = useState(false);
  const [policyTab, setPolicyTab] = useState('guidelines');
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
    setTheme(prev => (prev === 'dark' ? 'light' : 'dark'));
  };

  // Global search shortcut (Cmd + K / Ctrl + K)
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
      {/* Interactive Waves Animation Background (Tracks Mouse & Studio Audio Waves) */}
      <WaveBackground theme={theme} />

      {/* Ambient background glow */}
      <div className="ambient-glow" aria-hidden="true" />

      {/* Sticky Header */}
      <Navbar
        theme={theme}
        onToggleTheme={handleToggleTheme}
        onOpenDownload={() => setIsDownloadOpen(true)}
        onSearchFocus={handleSearchFocus}
        onSelectDoc={handleSelectDoc}
      />

      {/* Main Content Area */}
      <main>
        {/* Hero Section with Call To Action & Interactive Phone Emulator */}
        <Hero onOpenDownload={() => setIsDownloadOpen(true)} />

        {/* Feature Highlights Grid */}
        <FeaturesGrid />

        {/* High Super Powerful About Us & Cinema Spotlight Section */}
        <AboutUs
          onOpenDownload={() => setIsDownloadOpen(true)}
          onSelectDoc={handleSelectDoc}
        />

        {/* Full Documented Interface */}
        <DocsPortal
          currentDocId={currentDocId}
          onSelectDoc={handleSelectDoc}
          searchRef={searchInputRef}
          onOpenDownload={() => setIsDownloadOpen(true)}
        />
      </main>

      {/* Floating Ambient Video Dock Widget */}
      <FloatingVideoWidget />

      {/* Footer */}
      <Footer
        onSelectDoc={handleSelectDoc}
        onOpenDownload={() => setIsDownloadOpen(true)}
        onOpenPolicy={handleOpenPolicy}
      />

      {/* Download Modal with QR Code */}
      <DownloadModal
        isOpen={isDownloadOpen}
        onClose={() => setIsDownloadOpen(false)}
      />

      {/* Interactive Trust, Safety & Policy Modal */}
      <PolicyModal
        isOpen={isPolicyOpen}
        initialTab={policyTab}
        onClose={() => setIsPolicyOpen(false)}
      />
    </>
  );
}
