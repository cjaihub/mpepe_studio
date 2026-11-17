$ErrorActionPreference = "Stop"

$Root = (Resolve-Path "$PSScriptRoot\..\..").Path
Set-Location $Root

if (Test-Path ".env") {
  $bad = Select-String -Path ".env" -Pattern '^(OPENROUTER_API_KEY|TIKTOK_CLIENT_SECRET|META_APP_SECRET|GEMINI_API_KEY|GOOGLE_AI_API_KEY|[A-Z_]*SECRET[A-Z_]*)=.+'
  if ($bad) {
    throw "Refusing build: server secret present in .env"
  }
}

flutter config --enable-windows-desktop
flutter build windows --release

$ReleaseDir = "$Root\build\windows\x64\runner\Release"
$OutDir = "$Root\public\downloads"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$ZipOut = "$OutDir\Oneova-Desktop-Windows-x64.zip"
if (Test-Path $ZipOut) { Remove-Item $ZipOut -Force }
Compress-Archive -Path "$ReleaseDir\*" -DestinationPath $ZipOut -CompressionLevel Optimal

$Hash = (Get-FileHash $ZipOut -Algorithm SHA256).Hash.ToLower()
$SizeMb = [Math]::Round((Get-Item $ZipOut).Length / 1MB, 1)

$ManifestPath = "$OutDir\manifest.json"
$Manifest = @{}
if (Test-Path $ManifestPath) {
  $Manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json -AsHashtable
}

$Manifest["windows"] = @{
  available = $true
  fileName = "Oneova-Desktop-Windows-x64.zip"
  url = "/downloads/Oneova-Desktop-Windows-x64.zip"
  fileSizeLabel = "$SizeMb MB"
  sizeLabel = "Windows 10 / 11 (64-bit x64)"
  requirements = "Windows 10 (1903+) or Windows 11 x64"
  hotkey = "Alt + Space / Ctrl + Shift + O"
  startup = "Auto-launches at Windows login (HKCU Run) & System Tray"
  sha256 = $Hash
}

$Manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $ManifestPath -Encoding UTF8
Write-Host "Built $ZipOut ($SizeMb MB, SHA256 $Hash)"
