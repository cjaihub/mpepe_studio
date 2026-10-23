/**
 * ONEOVA - DOCUMENTATION & SHOWCASE INTERACTIVE ENGINE
 * Brand colors: #007AFF (brandBlue), #FF2D87 (brandPink)
 */

document.addEventListener('DOMContentLoaded', () => {
  initPhoneSimulator();
  initDocsNavigation();
  initCodeCopyButtons();
  initApiTester();
  initDownloadModal();
  initDocSearch();
  initKeyboardShortcuts();
});

/* ==========================================================================
   1. PHONE EMULATOR SIMULATOR
   ========================================================================== */
function initPhoneSimulator() {
  const simButtons = document.querySelectorAll('.sim-tab-btn');
  const simScreens = document.querySelectorAll('.sim-screen-view');
  const simNavItems = document.querySelectorAll('.sim-nav-item');

  function switchScreen(screenId) {
    // Update pills
    simButtons.forEach(btn => {
      btn.classList.toggle('active', btn.dataset.screen === screenId);
    });

    // Update screen views
    simScreens.forEach(screen => {
      screen.classList.toggle('active', screen.id === `sim-${screenId}`);
    });

    // Update bottom nav active indicator
    simNavItems.forEach(item => {
      item.classList.toggle('active', item.dataset.nav === screenId);
    });
  }

  // Pill click handlers
  simButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      switchScreen(btn.dataset.screen);
    });
  });

  // Bottom nav click handlers
  simNavItems.forEach(item => {
    item.addEventListener('click', () => {
      if (item.dataset.nav) {
        switchScreen(item.dataset.nav);
      }
    });
  });

  // Feed tabs inside simulator (Following / For You / Biz)
  const feedTabs = document.querySelectorAll('.sim-feed-tab');
  feedTabs.forEach(tab => {
    tab.addEventListener('click', () => {
      feedTabs.forEach(t => t.classList.remove('active'));
      tab.classList.add('active');
    });
  });

  // Like button pulse animation
  const likeBtn = document.querySelector('.sim-rail-btn[data-action="like"]');
  if (likeBtn) {
    let liked = false;
    likeBtn.addEventListener('click', () => {
      liked = !liked;
      const icon = likeBtn.querySelector('.rail-icon');
      const count = likeBtn.querySelector('.rail-count');
      if (liked) {
        icon.style.color = '#FF2D87';
        icon.style.transform = 'scale(1.25)';
        count.textContent = '14.3k';
      } else {
        icon.style.color = '#FFFFFF';
        icon.style.transform = 'scale(1)';
        count.textContent = '14.2k';
      }
    });
  }
}

/* ==========================================================================
   2. DOCUMENTATION NAVIGATION & ARTICLE SWITCHER
   ========================================================================== */
const docArticles = {
  'overview': {
    category: 'Getting Started',
    title: 'Oneova Platform Overview',
    badge: 'v2.4 Live',
    updated: 'October 2026',
    html: `
      <h2>The Unified Creator Ecosystem</h2>
      <p><strong>Oneova</strong> is an end-to-end mobile production suite and short-form media hub engineered to replace fragmented creator workflows. Rather than toggling between standalone video editors, AI chatbots, direct messaging apps, and social distribution channels, Oneova brings everything under one high-performance roof.</p>
      
      <div class="callout">
        <div class="callout-title">✦ Oneova Design Philosophy</div>
        <p>Built with Flutter and Riverpod 3, Oneova delivers native 60fps performance on iOS and Android. Every screen is designed in our studio dark aesthetic (#0A0A0A) punctuated by electric Oneova Blue (#007AFF) and energetic Oneova Pink (#FF2D87).</p>
      </div>

      <h2>Core System Pillars</h2>
      <ul>
        <li><strong>Hyper-Fast Video Feed:</strong> Algorithmic, Following, and Business channels powered by Firestore real-time streams and <code>media_kit_video</code> hardware acceleration.</li>
        <li><strong>Full-Fledged Creator Studio:</strong> In-app camera, multi-layer timelines, Mask Engine segmentation, and audio library mastering.</li>
        <li><strong>Gemini Live AI Lab:</strong> Real-time conversational voice assistant, instant scriptwriting, and automated B-roll generation.</li>
        <li><strong>Unified Messaging & WebRTC:</strong> 1:1 DMs, collaboration rooms, and high-fidelity video/voice calling.</li>
        <li><strong>Desktop Integration Bridges:</strong> Direct wireless control and synchronization with Adobe Premiere Pro, DaVinci Resolve, Logic Pro, and FL Studio.</li>
      </ul>
    `
  },
  'getting-started': {
    category: 'Getting Started',
    title: 'Mobile App Installation & Setup',
    badge: 'Quickstart',
    updated: 'October 2026',
    html: `
      <h2>Installing the Oneova Mobile App</h2>
      <p>Oneova is available for both iOS (TestFlight / App Store) and Android (Google Play / Direct APK). Follow these quick steps to get running in seconds.</p>
      
      <h3>1. System Requirements</h3>
      <ul>
        <li><strong>iOS:</strong> iPhone running iOS 16.0 or higher. Compatible with iPhone 12 through iPhone 16 Pro Max.</li>
        <li><strong>Android:</strong> Android 10.0 (API level 29) or higher with OpenGL ES 3.0 support.</li>
        <li><strong>Storage:</strong> 120 MB free disk space for initial installation and cache.</li>
      </ul>

      <h3>2. Download Channels</h3>
      <div class="code-block-wrapper">
        <div class="code-header">
          <span class="code-lang">CLI / CURL</span>
          <button class="copy-code-btn" data-copy="curl -s https://get.oneova.app/latest-apk -o oneova.apk">Copy</button>
        </div>
        <pre class="code-content">curl -s https://get.oneova.app/latest-apk -o oneova.apk
adb install oneova.apk</pre>
      </div>

      <div class="callout pink">
        <div class="callout-title">✦ Initial Launch & Authentication</div>
        <p>Upon opening Oneova, you will experience our signature splash sequence before landing directly on the Short Video Feed (<code>/hub/home</code>). You can sign up using Email/Password, Google Sign-In, or connect your existing creator channels.</p>
      </div>
    `
  },
  'reels-feed': {
    category: 'Feed & Social Architecture',
    title: 'Short-Form Video Engine (/hub/home)',
    badge: 'Core Experience',
    updated: 'October 2026',
    html: `
      <h2>Fullscreen Short-Video Architecture</h2>
      <p>The home screen of Oneova is the <code>ShortVideoFeedScreen</code>, located at route <code>/hub/home</code>. It delivers instant, zero-buffer short-form reel playback backed by <code>VideoPlaybackManager</code> and hardware-accelerated shaders.</p>

      <h2>Feed Modes</h2>
      <p>Users can effortlessly toggle between three distinct content streams at the top of the screen:</p>
      <ul>
        <li><strong>Following:</strong> Content exclusively curated from accounts and creators you follow in real-time.</li>
        <li><strong>For You:</strong> Machine-learning driven discovery stream optimizing for engagement, sound relevance, and creator tier.</li>
        <li><strong>Biz:</strong> Dedicated business feed spotlighting brand partnerships, sponsorships, and marketplace opportunities.</li>
      </ul>

      <div class="callout gold">
        <div class="callout-title">✦ Ephemeral 24h Stories</div>
        <p>A horizontally scrolling stories row sits immediately below the top header, powered by <code>StoryService</code>. Stories support instant camera capture, interactive stickers, and auto-delete after 24 hours.</p>
      </div>

      <h2>Interaction Matrix</h2>
      <p>Every reel provides frictionless creator engagement:</p>
      <ul>
        <li><strong>Author Side Panel:</strong> One-tap follow, profile peek, and direct DM trigger.</li>
        <li><strong>Like & Bookmark:</strong> Real-time optimistic Firestore counter with sound FX.</li>
        <li><strong>Threaded Comments:</strong> Bottom sheet with nested replies, creator badges, and pinned comments.</li>
        <li><strong>Audio Attribution:</strong> Spinning vinyl disc linking directly to the sound track library with remix CTAs.</li>
      </ul>
    `
  },
  'creator-studio': {
    category: 'Creator Studio & Mask Engine',
    title: 'Mobile Creation Suite & Mask Engine',
    badge: 'Production Grade',
    updated: 'October 2026',
    html: `
      <h2>The "+" STUDIO Hub</h2>
      <p>Tapping the central glowing <strong>STUDIO (+)</strong> button on the bottom navigation bar launches the <code>CreationTypeModal</code>, giving creators access to a comprehensive suite of media tools.</p>

      <h2>Key Studio Modules</h2>
      <ul>
        <li><strong>Pro Capture Camera:</strong> 4K 60fps recording, manual shutter, ISO adjustments, grid overlays, and countdown timers.</li>
        <li><strong>Mask Engine Canvas:</strong> Hardware-accelerated segmentation panel (<code>MobileMaskPanel</code>) allowing creators to isolate subjects, apply animated backdrops, and paint custom rotoscope masks on mobile.</li>
        <li><strong>Video Production Dashboard:</strong> Timeline view with multi-clip trimming, transition keyframes, text overlays, and color LUTs.</li>
        <li><strong>Audio Studio:</strong> Beat-matching, multi-track audio layering, vocal isolation, and dynamic EQ.</li>
      </ul>

      <div class="code-block-wrapper">
        <div class="code-header">
          <span class="code-lang">Dart (Flutter)</span>
          <button class="copy-code-btn" data-copy="// Launching Mask Engine Canvas
void openMaskCanvas(BuildContext context, String mediaId) {
  context.push('/studio/mask', extra: {'mediaId': mediaId});
}">Copy</button>
        </div>
        <pre class="code-content"><span style="color:#60A5FA;">void</span> <span style="color:#FFD700;">openMaskCanvas</span>(BuildContext context, String mediaId) {
  context.push(<span style="color:#00FF66;">'/studio/mask'</span>, extra: {<span style="color:#00FF66;">'mediaId'</span>: mediaId});
}</pre>
      </div>
    `
  },
  'ai-lab': {
    category: 'AI Lab & Automation',
    title: 'Gemini Live AI Lab (/hub/ai)',
    badge: 'AI Powered',
    updated: 'October 2026',
    html: `
      <h2>Real-Time AI Innovation</h2>
      <p>The <strong>AI Lab</strong> tab (<code>/hub/ai</code>) is Oneova's dedicated intelligence playground, powered by Google Gemini and proprietary multi-modal models.</p>

      <h2>Built-in Capabilities</h2>
      <ul>
        <li><strong>Gemini Live Voice Mode:</strong> Low-latency bidirectional conversational voice interface. Brainstorm hooks, ask for editing feedback, or request instant script drafts hands-free.</li>
        <li><strong>TikTok & Shorts AI Strategist:</strong> Analyzes trending audio and competitor reels to generate high-retention video formulas.</li>
        <li><strong>AI Voice Personalization:</strong> High-fidelity voice cloning for effortless narration and multi-language dubbing.</li>
        <li><strong>AI Security Gateway:</strong> Secure policy engine that validates and monitors tool execution, protecting sensitive user data.</li>
      </ul>

      <div class="callout pink">
        <div class="callout-title">✦ Privacy & On-Device Safeguards</div>
        <p>All AI voice sessions are end-to-end encrypted. Prompts and workspace assets are processed strictly under user-configured privacy rules with zero unauthorized model training.</p>
      </div>
    `
  },
  'unified-chat': {
    category: 'Communication & Collaboration',
    title: 'Unified Messaging & WebRTC Calling',
    badge: 'E2EE & Live',
    updated: 'October 2026',
    html: `
      <h2>Unified Collaboration Hub</h2>
      <p>Accessible via the <strong>Chat</strong> tab on the navigation bar, the Unified Messaging system connects creators, editors, clients, and collaborators.</p>

      <h2>Feature Set</h2>
      <ul>
        <li><strong>1:1 & Group Direct Messages:</strong> End-to-end encrypted messaging with rich media previews and file attachments.</li>
        <li><strong>WebRTC Call Engine:</strong> High-definition crystal-clear audio and video calling powered by <code>CallEngineService</code>.</li>
        <li><strong>Live Collab Rooms:</strong> Collaborative editing sessions where multiple team members can review video timelines and drop timestamped notes simultaneously.</li>
      </ul>
    `
  },
  'biz-feed': {
    category: 'Business & Monetization',
    title: 'Business Hub & Marketplace (/biz_feed)',
    badge: 'Creator Revenue',
    updated: 'October 2026',
    html: `
      <h2>Monetization & Analytics</h2>
      <p>Oneova empowers creators to turn their passion into a sustainable business via the dedicated <code>/biz_feed</code> portal.</p>

      <h2>Revenue Streams</h2>
      <ul>
        <li><strong>Brand Deals & Sponsorships:</strong> Direct verified marketplace connecting brands with creators without agency fees.</li>
        <li><strong>Integrated Product Tags:</strong> Tag affiliate merchandise and digital goods directly in video reels.</li>
        <li><strong>Analytics Command Center:</strong> Real-time viewer retention graphs, CTR analytics, audio reach metrics, and earnings reports.</li>
      </ul>
    `
  },
  'api-reference': {
    category: 'Developer Reference',
    title: 'Oneova Canonical REST API (v1)',
    badge: 'Developer API',
    updated: 'October 2026',
    html: `
      <h2>REST API Overview</h2>
      <p>The Oneova backend exposes a robust REST API for third-party integrations, CMS syncing, and automated posting pipelines. Base URL: <code>https://api.oneova.app/v1</code></p>

      <div class="api-endpoint-card">
        <div class="endpoint-method-row">
          <span class="method-tag post">POST</span>
          <span class="endpoint-path">/v1/videos</span>
        </div>
        <p>Creates a new video asset entry after media processing is complete.</p>
        <table class="api-table">
          <thead>
            <tr>
              <th>Field</th>
              <th>Type</th>
              <th>Description</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td><span class="param-name">mediaId</span></td>
              <td><span class="param-type">String</span></td>
              <td>Unique media identifier returned from cloud upload.</td>
            </tr>
            <tr>
              <td><span class="param-name">title</span></td>
              <td><span class="param-type">String</span></td>
              <td>Reel caption and title (max 500 chars).</td>
            </tr>
            <tr>
              <td><span class="param-name">mode</span></td>
              <td><span class="param-type">String</span></td>
              <td>Visibility mode: <code>forYou</code>, <code>following</code>, or <code>biz</code>.</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="api-endpoint-card">
        <div class="endpoint-method-row">
          <span class="method-tag post">POST</span>
          <span class="endpoint-path">/v1/messages/send</span>
        </div>
        <p>Sends an encrypted payload to a recipient or group channel.</p>
      </div>

      <div class="api-test-console">
        <div class="console-header">
          <span class="console-title">Interactive API Explorer</span>
          <button class="send-request-btn" id="btn-run-api">Send Test Request</button>
        </div>
        <pre class="response-box" id="api-response-preview">// Click "Send Test Request" to simulate a live API query...</pre>
      </div>
    `
  },
  'architecture': {
    category: 'Developer Reference',
    title: 'Architecture & Desktop Bridges',
    badge: 'Technical Specs',
    updated: 'October 2026',
    html: `
      <h2>Mobile & Desktop Bridge Architecture</h2>
      <p>Oneova bridges mobile immediacy with desktop production power using our native plugin architecture:</p>

      <ul>
        <li><strong>Adobe Premiere Pro Connect:</strong> Native CEP extension with a Node.js daemon executing ExtendScript (<code>.jsx</code>). Syncs mobile timeline edits directly into Premiere project bins.</li>
        <li><strong>DaVinci Resolve Connect:</strong> Native Python bridge hooking into DaVinci's internal API for multi-agent automated color grading.</li>
        <li><strong>Native Audio DAWs:</strong> C++ VST3 and AudioUnit plugin crafted with JUCE framework. Connects Logic Pro, Cubase, and FL Studio directly to Oneova's mobile library.</li>
      </ul>

      <div class="callout gold">
        <div class="callout-title">✦ State Management Standards</div>
        <p>The app strictly leverages <strong>Riverpod 3</strong> using <code>AsyncNotifierProvider</code> and <code>FutureProvider</code>. Navigation is entirely handled through <strong>GoRouter</strong> with full stack back-safety.</p>
      </div>
    `
  }
};

function initDocsNavigation() {
  const docNavButtons = document.querySelectorAll('.doc-nav-btn');
  const breadcrumbCategory = document.getElementById('doc-crumb-cat');
  const breadcrumbCurrent = document.getElementById('doc-crumb-curr');
  const articleTitle = document.getElementById('doc-article-title');
  const articleBadge = document.getElementById('doc-article-badge');
  const articleMeta = document.getElementById('doc-article-meta');
  const articleBody = document.getElementById('doc-article-body');

  function renderArticle(docId) {
    const data = docArticles[docId];
    if (!data) return;

    // Update active nav button
    docNavButtons.forEach(btn => {
      btn.classList.toggle('active', btn.dataset.doc === docId);
    });

    // Update breadcrumbs & headers
    if (breadcrumbCategory) breadcrumbCategory.textContent = data.category;
    if (breadcrumbCurrent) breadcrumbCurrent.textContent = data.title;
    if (articleTitle) articleTitle.textContent = data.title;
    if (articleBadge) articleBadge.textContent = data.badge;
    if (articleMeta) articleMeta.textContent = `Updated ${data.updated} • 4 min read`;
    if (articleBody) articleBody.innerHTML = data.html;

    // Re-attach copy buttons and API explorer
    initCodeCopyButtons();
    initApiTester();

    // Scroll smoothly to top of doc pane on mobile/small screens
    const mainPane = document.querySelector('.docs-main-pane');
    if (mainPane && window.innerWidth < 860) {
      mainPane.scrollIntoView({ behavior: 'smooth' });
    }
  }

  docNavButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      renderArticle(btn.dataset.doc);
    });
  });

  // Mobile drawer toggle
  const mobileMenuToggle = document.getElementById('mobile-menu-toggle');
  const docsSidebar = document.querySelector('.docs-sidebar');
  if (mobileMenuToggle && docsSidebar) {
    mobileMenuToggle.addEventListener('click', () => {
      docsSidebar.classList.toggle('mobile-open');
    });
  }
}

/* ==========================================================================
   3. CODE COPY BUTTONS
   ========================================================================== */
function initCodeCopyButtons() {
  const copyButtons = document.querySelectorAll('.copy-code-btn');
  copyButtons.forEach(btn => {
    btn.addEventListener('click', async () => {
      const codeText = btn.dataset.copy || btn.parentElement.nextElementSibling?.textContent;
      if (!codeText) return;

      try {
        await navigator.clipboard.writeText(codeText.trim());
        const originalText = btn.textContent;
        btn.textContent = 'Copied!';
        btn.style.borderColor = '#00FF66';
        btn.style.color = '#00FF66';

        setTimeout(() => {
          btn.textContent = originalText;
          btn.style.borderColor = '';
          btn.style.color = '';
        }, 2000);
      } catch (err) {
        console.error('Failed to copy', err);
      }
    });
  });
}

/* ==========================================================================
   4. INTERACTIVE API EXPLORER TESTER
   ========================================================================== */
function initApiTester() {
  const runApiBtn = document.getElementById('btn-run-api');
  const responseBox = document.getElementById('api-response-preview');

  if (runApiBtn && responseBox) {
    runApiBtn.addEventListener('click', () => {
      runApiBtn.disabled = true;
      runApiBtn.textContent = 'Connecting...';
      responseBox.textContent = 'Sending request to https://api.oneova.app/v1/videos...';
      responseBox.style.color = '#9CA3AF';

      setTimeout(() => {
        runApiBtn.disabled = false;
        runApiBtn.textContent = 'Send Test Request';
        responseBox.style.color = '#00FF66';
        responseBox.textContent = JSON.stringify({
          status: 200,
          code: "OK",
          message: "Video asset registered successfully in Oneova feed",
          data: {
            videoId: "vid_98f4b238a",
            title: "Cinematic Color Grade in Oneova Studio",
            feedMode: "forYou",
            playbackUrl: "https://stream.oneova.app/live/vid_98f4b238a/master.m3u8",
            metrics: {
              views: 0,
              likes: 0,
              remixes: 0
            },
            timestamp: new Date().toISOString()
          }
        }, null, 2);
      }, 700);
    });
  }
}

/* ==========================================================================
   5. DOWNLOAD MODAL & QR CODE
   ========================================================================== */
function initDownloadModal() {
  const modal = document.getElementById('download-modal');
  const triggers = document.querySelectorAll('.open-download-modal');
  const closeBtn = document.getElementById('modal-close-btn');

  if (!modal) return;

  function openModal() {
    modal.classList.add('open');
    document.body.style.overflow = 'hidden';
  }

  function closeModal() {
    modal.classList.remove('open');
    document.body.style.overflow = '';
  }

  triggers.forEach(t => t.addEventListener('click', openModal));
  if (closeBtn) closeBtn.addEventListener('click', closeModal);

  modal.addEventListener('click', (e) => {
    if (e.target === modal) closeModal();
  });

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && modal.classList.contains('open')) {
      closeModal();
    }
  });
}

/* ==========================================================================
   6. DOC SEARCH FILTER
   ========================================================================== */
function initDocSearch() {
  const searchInput = document.getElementById('docs-search-input');
  const navItems = document.querySelectorAll('.category-items li');

  if (!searchInput) return;

  searchInput.addEventListener('input', (e) => {
    const query = e.target.value.toLowerCase().trim();
    navItems.forEach(item => {
      const text = item.textContent.toLowerCase();
      if (!query || text.includes(query)) {
        item.style.display = 'block';
      } else {
        item.style.display = 'none';
      }
    });
  });
}

/* ==========================================================================
   7. KEYBOARD SHORTCUTS
   ========================================================================== */
function initKeyboardShortcuts() {
  document.addEventListener('keydown', (e) => {
    // Cmd + K or Ctrl + K focuses docs search
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
      e.preventDefault();
      const searchInput = document.getElementById('docs-search-input');
      if (searchInput) {
        searchInput.focus();
        searchInput.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }
    }
  });
}
