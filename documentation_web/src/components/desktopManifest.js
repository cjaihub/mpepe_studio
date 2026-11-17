export const DEFAULT_DESKTOP_MANIFEST = {
  version: '1.0.0',
  updatedAt: '2026-11-17',
  macos: {
    available: true,
    fileName: 'Oneova-Desktop-macOS.dmg',
    url: '/downloads/Oneova-Desktop-macOS.dmg',
    fileSizeLabel: '87 MB',
    sizeLabel: 'Universal (Apple Silicon + Intel)',
    requirements: 'macOS 12.0 Monterey or newer',
    hotkey: 'Option + Space (⌥Space)',
    startup: 'Auto-launches at login via macOS LaunchAgent',
    sha256: '',
  },
  windows: {
    available: false,
    fileName: 'Oneova-Desktop-Windows-x64.zip',
    url: 'https://github.com/cjaihub/mpepe_studio/releases/latest',
    buildRepoUrl:
      'https://github.com/cjaihub/mpepe_studio/actions/workflows/desktop-release.yml',
    fileSizeLabel: '',
    sizeLabel: 'Windows 10 / 11 (64-bit x64)',
    requirements: 'Windows 10 (1903+) or Windows 11 x64',
    hotkey: 'Alt + Space / Ctrl + Shift + O',
    startup: 'Auto-launches at Windows login (HKCU Run) & System Tray',
    sha256: '',
  },
};

export async function loadDesktopManifest() {
  let merged = {
    ...DEFAULT_DESKTOP_MANIFEST,
    macos: { ...DEFAULT_DESKTOP_MANIFEST.macos },
    windows: { ...DEFAULT_DESKTOP_MANIFEST.windows },
  };

  try {
    const res = await fetch('/downloads/manifest.json', { cache: 'no-store' });
    if (res.ok) {
      const json = await res.json();
      if (json && typeof json === 'object') {
        merged = {
          ...merged,
          ...json,
          macos: { ...merged.macos, ...(json.macos || {}) },
          windows: { ...merged.windows, ...(json.windows || {}) },
        };
      }
    }
  } catch {
    // Fall back cleanly to DEFAULT_DESKTOP_MANIFEST
  }

  // If Windows isn't statically hosted yet, auto-discover the latest GitHub Release asset.
  if (!merged.windows.available) {
    try {
      const gh = await fetch(
        'https://api.github.com/repos/cjaihub/mpepe_studio/releases/latest',
        { headers: { Accept: 'application/vnd.github+json' } }
      );
      if (gh.ok) {
        const rel = await gh.json();
        const assets = Array.isArray(rel?.assets) ? rel.assets : [];
        const exeAsset = assets.find((a) =>
          /oneova.*windows.*\.exe$/i.test(a?.name || '')
        );
        const zipAsset = assets.find((a) =>
          /oneova.*windows.*\.zip$/i.test(a?.name || '')
        );
        const picked = exeAsset || zipAsset;
        if (picked?.browser_download_url) {
          const mb = picked.size ? `${Math.max(1, Math.round(picked.size / 1048576))} MB` : '';
          merged.windows = {
            ...merged.windows,
            available: true,
            fileName: picked.name,
            url: picked.browser_download_url,
            fileSizeLabel: mb,
            portableZipUrl: zipAsset?.browser_download_url || '',
          };
        }
      }
    } catch {
      // GitHub release may not exist yet; keep fallback guide link
    }
  }

  return merged;
}
