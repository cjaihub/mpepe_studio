#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# Never ship server secrets inside desktop bundles
if grep -qE '^(OPENROUTER_API_KEY|TIKTOK_CLIENT_SECRET|META_APP_SECRET|GEMINI_API_KEY|GOOGLE_AI_API_KEY|[A-Z_]*SECRET[A-Z_]*)=.+' .env 2>/dev/null; then
  echo "ERROR: a server secret is set in .env." >&2
  exit 1
fi

flutter config --enable-macos-desktop
flutter build macos --release

APP_SRC="$ROOT/build/macos/Build/Products/Release/OneOva.app"
DMG_OUT="$ROOT/public/downloads/Oneova-Desktop-macOS.dmg"
STAGING_DIR="$ROOT/build/dmg_staging"
mkdir -p "$ROOT/public/downloads"

if [[ ! -d "$APP_SRC" ]]; then
  echo "ERROR: Built OneOva.app not found at $APP_SRC" >&2
  exit 1
fi

# 1. Update local /Applications/Oneova.app cleanly
pkill -x OneOva >/dev/null 2>&1 || true
sleep 1
rm -rf /Applications/Oneova.app
cp -R "$APP_SRC" /Applications/Oneova.app
echo "Updated /Applications/Oneova.app"

# 2. Build compressed Universal DMG for oneova.web.app/downloads
rm -rf "$STAGING_DIR" "$DMG_OUT"
mkdir -p "$STAGING_DIR"
cp -R "$APP_SRC" "$STAGING_DIR/Oneova.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "Oneova Desktop Assistant" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDBZ \
  "$DMG_OUT"
rm -rf "$STAGING_DIR"

SHA256="$(shasum -a 256 "$DMG_OUT" | awk '{print $1}')"
SIZE_MB="$(du -m "$DMG_OUT" | awk '{print $1}')"
VER="$(grep -E '^version:' pubspec.yaml | sed -E 's/version: *//' | cut -d+ -f1)"

node -e "
const fs = require('fs');
const manifestPath = '$ROOT/public/downloads/manifest.json';
let m = {};
try { m = JSON.parse(fs.readFileSync(manifestPath, 'utf8')); } catch {}
m.version = '$VER';
m.updatedAt = new Date().toISOString().slice(0, 10);
m.macos = Object.assign({}, m.macos || {}, {
  available: true,
  fileName: 'Oneova-Desktop-macOS.dmg',
  url: '/downloads/Oneova-Desktop-macOS.dmg',
  fileSizeLabel: '${SIZE_MB} MB',
  sizeLabel: 'Universal (Apple Silicon + Intel)',
  requirements: 'macOS 12.0 Monterey or newer',
  hotkey: 'Option + Space (⌥Space)',
  startup: 'Auto-launches at login via macOS LaunchAgent',
  sha256: '$SHA256'
});
m.windows = Object.assign({
  available: false,
  fileName: 'Oneova-Desktop-Windows-x64.zip',
  url: 'https://github.com/cjaihub/mpepe_studio/releases/latest/download/Oneova-Desktop-Windows-x64.zip',
  buildRepoUrl: 'https://github.com/cjaihub/mpepe_studio/actions/workflows/desktop-release.yml',
  sizeLabel: 'Windows 10 / 11 (64-bit x64)',
  requirements: 'Windows 10 (1903+) or Windows 11 x64',
  hotkey: 'Alt + Space / Ctrl + Shift + O',
  startup: 'Auto-launches at Windows login (HKCU Run) & System Tray',
  sha256: ''
}, m.windows || {});
fs.writeFileSync(manifestPath, JSON.stringify(m, null, 2));
"

echo "Built $DMG_OUT ($SIZE_MB MB, SHA256 $SHA256)"
