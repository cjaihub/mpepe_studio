#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <shlobj.h>
#include <shobjidl.h>

#include <algorithm>
#include <optional>
#include <sstream>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "ole32.lib")

namespace {
constexpr UINT kTrayCallbackMsg = WM_APP + 101;
constexpr int kHotKeyAltSpace = 1;
constexpr int kHotKeyCtrlShiftO = 2;
constexpr UINT_PTR kMenuSummonHud = 4001;
constexpr UINT_PTR kMenuOpenStudio = 4002;
constexpr UINT_PTR kMenuToggleStartup = 4003;
constexpr UINT_PTR kMenuQuit = 4004;
constexpr wchar_t kRunRegPath[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kRunRegName[] = L"OneovaDesktopAssistant";
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project, bool start_hidden)
    : project_(project), start_hidden_(start_hidden) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  SetupWindowChannel();
  SetupTrayIcon();
  RegisterGlobalHotKeys();

  flutter_controller_->engine()->SetNextFrameCallback([this]() {
    if (start_hidden_) {
      ::ShowWindow(GetHandle(), SW_HIDE);
    } else {
      this->Show();
    }
  });
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::SetupWindowChannel() {
  window_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "com.oneova.app/desktop_window",
      &flutter::StandardMethodCodec::GetInstance());

  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        const auto& method = call.method_name();
        const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());

        if (method == "setHudMode") {
          bool hud = true;
          if (args) {
            auto it = args->find(flutter::EncodableValue("hud"));
            if (it != args->end()) {
              if (const auto* b = std::get_if<bool>(&it->second)) hud = *b;
            }
          }
          ApplyHudMode(hud);
          result->Success(flutter::EncodableValue(true));
        } else if (method == "toggleHud") {
          ToggleHudFromAnywhere();
          result->Success(flutter::EncodableValue(true));
        } else if (method == "showStudio") {
          ApplyHudMode(false);
          BringToFront("studio");
          result->Success(flutter::EncodableValue(true));
        } else if (method == "hideToTray") {
          ::ShowWindow(GetHandle(), SW_HIDE);
          result->Success(flutter::EncodableValue(true));
        } else if (method == "getStartupEnabled") {
          result->Success(flutter::EncodableValue(IsStartupEnabled()));
        } else if (method == "setStartupEnabled") {
          bool enabled = true;
          if (args) {
            auto it = args->find(flutter::EncodableValue("enabled"));
            if (it != args->end()) {
              if (const auto* b = std::get_if<bool>(&it->second)) enabled = *b;
            }
          }
          result->Success(flutter::EncodableValue(SetStartupEnabled(enabled)));
        } else if (method == "getState") {
          flutter::EncodableMap map;
          map[flutter::EncodableValue("hud")] = flutter::EncodableValue(is_hud_mode_);
          map[flutter::EncodableValue("startup")] = flutter::EncodableValue(IsStartupEnabled());
          map[flutter::EncodableValue("hotkey")] = flutter::EncodableValue("Alt+Space / Ctrl+Shift+O");
          map[flutter::EncodableValue("platform")] = flutter::EncodableValue("windows");
          result->Success(flutter::EncodableValue(map));
        } else if (method == "getPermissionsStatus") {
          result->Success(flutter::EncodableValue(CollectPermissionsStatus()));
        } else if (method == "requestPermission") {
          std::string key = "all";
          if (args) {
            auto it = args->find(flutter::EncodableValue("permission"));
            if (it != args->end()) {
              if (const auto* s = std::get_if<std::string>(&it->second)) key = *s;
            }
          }
          RequestWindowsPermission(key);
          result->Success(flutter::EncodableValue(CollectPermissionsStatus()));
        } else if (method == "openPermissionSettings") {
          std::string pane = "privacy";
          if (args) {
            auto it = args->find(flutter::EncodableValue("pane"));
            if (it != args->end()) {
              if (const auto* s = std::get_if<std::string>(&it->second)) pane = *s;
            }
          }
          OpenWindowsSettingsPane(pane);
          result->Success(flutter::EncodableValue(true));
        } else if (method == "authorizeStorageFolder") {
          auto paths = PromptAuthorizedFolder();
          flutter::EncodableList list;
          for (const auto& p : paths) {
            list.push_back(flutter::EncodableValue(p));
          }
          result->Success(flutter::EncodableValue(list));
        } else if (method == "resetStalePermissions") {
          result->Success(flutter::EncodableValue(CollectPermissionsStatus()));
        } else {
          result->NotImplemented();
        }
      });
}

void FlutterWindow::SetupTrayIcon() {
  HWND hwnd = GetHandle();
  if (!hwnd) return;
  ZeroMemory(&tray_icon_, sizeof(tray_icon_));
  tray_icon_.cbSize = sizeof(NOTIFYICONDATAW);
  tray_icon_.hWnd = hwnd;
  tray_icon_.uID = 1001;
  tray_icon_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  tray_icon_.uCallbackMessage = kTrayCallbackMsg;
  tray_icon_.hIcon = ::LoadIconW(::GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON));
  wcsncpy_s(tray_icon_.szTip, L"Oneova Desktop Assistant (Alt+Space)", _TRUNCATE);
  tray_added_ = ::Shell_NotifyIconW(NIM_ADD, &tray_icon_) == TRUE;
}

void FlutterWindow::RemoveTrayIcon() {
  if (tray_added_) {
    ::Shell_NotifyIconW(NIM_DELETE, &tray_icon_);
    tray_added_ = false;
  }
}

void FlutterWindow::ShowTrayContextMenu() {
  HWND hwnd = GetHandle();
  HMENU menu = ::CreatePopupMenu();
  if (!menu) return;

  ::AppendMenuW(menu, MF_STRING, kMenuSummonHud, L"Summon Ova HUD (Alt+Space)");
  ::AppendMenuW(menu, MF_STRING, kMenuOpenStudio, L"Open Full Oneova Studio");
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  UINT flags = MF_STRING | (IsStartupEnabled() ? MF_CHECKED : MF_UNCHECKED);
  ::AppendMenuW(menu, flags, kMenuToggleStartup, L"Launch on Windows Startup");
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(menu, MF_STRING, kMenuQuit, L"Quit Oneova");

  POINT pt;
  ::GetCursorPos(&pt);
  ::SetForegroundWindow(hwnd);
  ::TrackPopupMenu(menu, TPM_RIGHTBUTTON | TPM_BOTTOMALIGN, pt.x, pt.y, 0, hwnd, nullptr);
  ::DestroyMenu(menu);
}

void FlutterWindow::RegisterGlobalHotKeys() {
  HWND hwnd = GetHandle();
  if (!hwnd) return;
  ::RegisterHotKey(hwnd, kHotKeyAltSpace, MOD_ALT | MOD_NOREPEAT, VK_SPACE);
  ::RegisterHotKey(hwnd, kHotKeyCtrlShiftO, MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT, 'O');
}

void FlutterWindow::UnregisterGlobalHotKeys() {
  HWND hwnd = GetHandle();
  if (!hwnd) return;
  ::UnregisterHotKey(hwnd, kHotKeyAltSpace);
  ::UnregisterHotKey(hwnd, kHotKeyCtrlShiftO);
}

void FlutterWindow::BringToFront(const char* source) {
  HWND hwnd = GetHandle();
  if (!hwnd) return;
  if (!::IsWindowVisible(hwnd)) {
    ::ShowWindow(hwnd, SW_SHOW);
  }
  if (::IsIconic(hwnd)) {
    ::ShowWindow(hwnd, SW_RESTORE);
  }
  ::SetForegroundWindow(hwnd);
  if (window_channel_) {
    flutter::EncodableMap ev;
    ev[flutter::EncodableValue("event")] = flutter::EncodableValue("summon");
    ev[flutter::EncodableValue("source")] = flutter::EncodableValue(source);
    ev[flutter::EncodableValue("hud")] = flutter::EncodableValue(is_hud_mode_);
    window_channel_->InvokeMethod("onWindowEvent", std::make_unique<flutter::EncodableValue>(ev));
  }
}

void FlutterWindow::ToggleHudFromAnywhere() {
  HWND hwnd = GetHandle();
  if (hwnd && ::IsWindowVisible(hwnd) && is_hud_mode_) {
    ::ShowWindow(hwnd, SW_HIDE);
    return;
  }
  ApplyHudMode(true);
  BringToFront("global_hotkey");
}

void FlutterWindow::ApplyHudMode(bool hud) {
  HWND hwnd = GetHandle();
  if (!hwnd) return;
  if (!has_saved_studio_rect_ && !is_hud_mode_) {
    ::GetWindowRect(hwnd, &saved_studio_rect_);
    has_saved_studio_rect_ = true;
  }
  is_hud_mode_ = hud;

  if (hud) {
    if (!has_saved_studio_rect_) {
      ::GetWindowRect(hwnd, &saved_studio_rect_);
      has_saved_studio_rect_ = true;
    }
    LONG style = ::GetWindowLongW(hwnd, GWL_STYLE);
    ::SetWindowLongW(hwnd, GWL_STYLE, (style & ~WS_OVERLAPPEDWINDOW) | WS_POPUP);
    RECT workArea{};
    ::SystemParametersInfoW(SPI_GETWORKAREA, 0, &workArea, 0);
    int screenW = workArea.right - workArea.left;
    int hudW = (screenW > 800) ? 740 : (screenW - 40);
    int hudH = 250;
    int x = workArea.left + (screenW - hudW) / 2;
    int y = workArea.bottom - hudH - 24;
    ::SetWindowPos(hwnd, HWND_TOPMOST, x, y, hudW, hudH,
                   SWP_FRAMECHANGED | SWP_SHOWWINDOW);
  } else {
    LONG style = ::GetWindowLongW(hwnd, GWL_STYLE);
    ::SetWindowLongW(hwnd, GWL_STYLE, (style & ~WS_POPUP) | WS_OVERLAPPEDWINDOW);
    int x = 60, y = 60, w = 1160, h = 760;
    if (has_saved_studio_rect_) {
      x = saved_studio_rect_.left;
      y = saved_studio_rect_.top;
      w = saved_studio_rect_.right - saved_studio_rect_.left;
      h = saved_studio_rect_.bottom - saved_studio_rect_.top;
    }
    ::SetWindowPos(hwnd, HWND_NOTOPMOST, x, y, w, h,
                   SWP_FRAMECHANGED | SWP_SHOWWINDOW);
  }

  if (window_channel_) {
    flutter::EncodableMap ev;
    ev[flutter::EncodableValue("event")] = flutter::EncodableValue("modeChanged");
    ev[flutter::EncodableValue("hud")] = flutter::EncodableValue(is_hud_mode_);
    window_channel_->InvokeMethod("onWindowEvent", std::make_unique<flutter::EncodableValue>(ev));
  }
}

bool FlutterWindow::IsStartupEnabled() const {
  HKEY key = nullptr;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, kRunRegPath, 0, KEY_READ, &key) != ERROR_SUCCESS) {
    return false;
  }
  DWORD type = 0;
  DWORD size = 0;
  LSTATUS res = ::RegQueryValueExW(key, kRunRegName, nullptr, &type, nullptr, &size);
  ::RegCloseKey(key);
  return res == ERROR_SUCCESS && size > 0;
}

bool FlutterWindow::SetStartupEnabled(bool enabled) const {
  HKEY key = nullptr;
  if (::RegCreateKeyExW(HKEY_CURRENT_USER, kRunRegPath, 0, nullptr, 0, KEY_WRITE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return false;
  }
  LSTATUS res = ERROR_SUCCESS;
  if (enabled) {
    wchar_t exePath[MAX_PATH]{};
    DWORD len = ::GetModuleFileNameW(nullptr, exePath, MAX_PATH);
    if (len == 0) {
      ::RegCloseKey(key);
      return false;
    }
    std::wstring cmd = std::wstring(L"\"") + exePath + L"\" --startup";
    res = ::RegSetValueExW(
        key,
        kRunRegName,
        0,
        REG_SZ,
        reinterpret_cast<const BYTE*>(cmd.c_str()),
        static_cast<DWORD>((cmd.size() + 1) * sizeof(wchar_t)));
  } else {
    res = ::RegDeleteValueW(key, kRunRegName);
    if (res == ERROR_FILE_NOT_FOUND) res = ERROR_SUCCESS;
  }
  ::RegCloseKey(key);
  return res == ERROR_SUCCESS;
}

void FlutterWindow::OnDestroy() {
  UnregisterGlobalHotKeys();
  RemoveTrayIcon();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  Win32Window::OnDestroy();
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam, lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_CLOSE:
      if (!explicit_quit_) {
        ::ShowWindow(hwnd, SW_HIDE);
        return 0;
      }
      break;
    case WM_HOTKEY:
      if (wparam == kHotKeyAltSpace || wparam == kHotKeyCtrlShiftO) {
        ToggleHudFromAnywhere();
        return 0;
      }
      break;
    case kTrayCallbackMsg:
      if (LOWORD(lparam) == WM_LBUTTONUP || LOWORD(lparam) == WM_LBUTTONDBLCLK) {
        ApplyHudMode(false);
        BringToFront("tray_click");
        return 0;
      } else if (LOWORD(lparam) == WM_RBUTTONUP || LOWORD(lparam) == WM_CONTEXTMENU) {
        ShowTrayContextMenu();
        return 0;
      }
      break;
    case WM_COMMAND:
      switch (LOWORD(wparam)) {
        case kMenuSummonHud:
          ApplyHudMode(true);
          BringToFront("tray_hud");
          return 0;
        case kMenuOpenStudio:
          ApplyHudMode(false);
          BringToFront("tray_studio");
          return 0;
        case kMenuToggleStartup:
          SetStartupEnabled(!IsStartupEnabled());
          return 0;
        case kMenuQuit:
          explicit_quit_ = true;
          ::DestroyWindow(hwnd);
          return 0;
      }
      break;
    case WM_FONTCHANGE:
      if (flutter_controller_ && flutter_controller_->engine()) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

namespace {
std::string WideToUtf8(const wchar_t* wstr) {
  if (!wstr || !*wstr) return "";
  int needed = ::WideCharToMultiByte(CP_UTF8, 0, wstr, -1, nullptr, 0, nullptr, nullptr);
  if (needed <= 1) return "";
  std::string out(static_cast<size_t>(needed - 1), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, wstr, -1, out.data(), needed, nullptr, nullptr);
  return out;
}

std::wstring Utf8ToWide(const std::string& str) {
  if (str.empty()) return L"";
  int needed = ::MultiByteToWideChar(CP_UTF8, 0, str.c_str(), -1, nullptr, 0);
  if (needed <= 1) return L"";
  std::wstring out(static_cast<size_t>(needed - 1), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, str.c_str(), -1, out.data(), needed);
  return out;
}

bool IsKnownFolderReadable(REFKNOWNFOLDERID fid) {
  PWSTR path = nullptr;
  if (FAILED(::SHGetKnownFolderPath(fid, 0, nullptr, &path)) || !path) {
    return false;
  }
  DWORD attrs = ::GetFileAttributesW(path);
  ::CoTaskMemFree(path);
  return attrs != INVALID_FILE_ATTRIBUTES;
}

struct WinMonitorCaptureCtx {
  flutter::EncodableList* list;
  int index;
};

BOOL CALLBACK CollectMonitorCallback(HMONITOR mon, HDC, LPRECT, LPARAM lparam) {
  auto* ctx = reinterpret_cast<WinMonitorCaptureCtx*>(lparam);
  MONITORINFOEXW mi{};
  mi.cbSize = sizeof(mi);
  if (::GetMonitorInfoW(mon, &mi)) {
    flutter::EncodableMap m;
    m[flutter::EncodableValue("index")] = flutter::EncodableValue(ctx->index);
    m[flutter::EncodableValue("name")] = flutter::EncodableValue(WideToUtf8(mi.szDevice));
    m[flutter::EncodableValue("x")] = flutter::EncodableValue(static_cast<int>(mi.rcMonitor.left));
    m[flutter::EncodableValue("y")] = flutter::EncodableValue(static_cast<int>(mi.rcMonitor.top));
    m[flutter::EncodableValue("width")] = flutter::EncodableValue(static_cast<int>(mi.rcMonitor.right - mi.rcMonitor.left));
    m[flutter::EncodableValue("height")] = flutter::EncodableValue(static_cast<int>(mi.rcMonitor.bottom - mi.rcMonitor.top));
    m[flutter::EncodableValue("isPrimary")] = flutter::EncodableValue((mi.dwFlags & MONITORINFOF_PRIMARY) != 0);
    ctx->list->push_back(flutter::EncodableValue(m));
    ctx->index++;
  }
  return TRUE;
}

constexpr wchar_t kPermRegPath[] = L"Software\\Oneova\\DesktopAgent";
constexpr wchar_t kPermFoldersVal[] = L"AuthorizedFolders";
}  // namespace

bool FlutterWindow::IsProcessElevated() const {
  HANDLE token = nullptr;
  if (!::OpenProcessToken(::GetCurrentProcess(), TOKEN_QUERY, &token)) {
    return false;
  }
  TOKEN_ELEVATION elev{};
  DWORD size = 0;
  BOOL ok = ::GetTokenInformation(token, TokenElevation, &elev, sizeof(elev), &size);
  ::CloseHandle(token);
  return ok == TRUE && elev.TokenIsElevated != 0;
}

std::vector<std::string> FlutterWindow::LoadAuthorizedFolders() const {
  std::vector<std::string> out;
  HKEY key = nullptr;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, kPermRegPath, 0, KEY_READ, &key) != ERROR_SUCCESS) {
    return out;
  }
  DWORD size = 0;
  if (::RegQueryValueExW(key, kPermFoldersVal, nullptr, nullptr, nullptr, &size) == ERROR_SUCCESS && size > 2) {
    std::wstring raw(size / sizeof(wchar_t), L'\0');
    if (::RegQueryValueExW(key, kPermFoldersVal, nullptr, nullptr, reinterpret_cast<LPBYTE>(raw.data()), &size) == ERROR_SUCCESS) {
      std::string utf8 = WideToUtf8(raw.c_str());
      std::stringstream ss(utf8);
      std::string item;
      while (std::getline(ss, item, '|')) {
        if (!item.empty()) out.push_back(item);
      }
    }
  }
  ::RegCloseKey(key);
  return out;
}

void FlutterWindow::SaveAuthorizedFolders(const std::vector<std::string>& folders) const {
  HKEY key = nullptr;
  if (::RegCreateKeyExW(HKEY_CURRENT_USER, kPermRegPath, 0, nullptr, 0, KEY_WRITE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return;
  }
  std::string joined;
  for (size_t i = 0; i < folders.size(); ++i) {
    if (i > 0) joined += '|';
    joined += folders[i];
  }
  std::wstring wide = Utf8ToWide(joined);
  ::RegSetValueExW(
      key,
      kPermFoldersVal,
      0,
      REG_SZ,
      reinterpret_cast<const BYTE*>(wide.c_str()),
      static_cast<DWORD>((wide.size() + 1) * sizeof(wchar_t)));
  ::RegCloseKey(key);
}

flutter::EncodableMap FlutterWindow::CollectPermissionsStatus() const {
  flutter::EncodableMap map;
  const bool elevated = IsProcessElevated();
  const bool desktopOk = IsKnownFolderReadable(FOLDERID_Desktop);
  const bool docsOk = IsKnownFolderReadable(FOLDERID_Documents);
  const bool dlOk = IsKnownFolderReadable(FOLDERID_Downloads);

  flutter::EncodableList volumes;
  wchar_t driveBuf[512]{};
  DWORD dlen = ::GetLogicalDriveStringsW(511, driveBuf);
  if (dlen > 0) {
    const wchar_t* cur = driveBuf;
    while (*cur) {
      if (::GetFileAttributesW(cur) != INVALID_FILE_ATTRIBUTES) {
        volumes.push_back(flutter::EncodableValue(WideToUtf8(cur)));
      }
      cur += ::wcslen(cur) + 1;
    }
  }

  flutter::EncodableList displays;
  WinMonitorCaptureCtx mctx{&displays, 0};
  ::EnumDisplayMonitors(nullptr, nullptr, CollectMonitorCallback, reinterpret_cast<LPARAM>(&mctx));

  flutter::EncodableList authFolders;
  for (const auto& f : LoadAuthorizedFolders()) {
    authFolders.push_back(flutter::EncodableValue(f));
  }

  map[flutter::EncodableValue("platform")] = flutter::EncodableValue("windows");
  map[flutter::EncodableValue("accessibility")] = flutter::EncodableValue(true);
  map[flutter::EncodableValue("inputMonitoring")] = flutter::EncodableValue(true);
  map[flutter::EncodableValue("screenRecording")] = flutter::EncodableValue(!displays.empty());
  map[flutter::EncodableValue("automation")] = flutter::EncodableValue(true);
  map[flutter::EncodableValue("microphone")] = flutter::EncodableValue(true);
  map[flutter::EncodableValue("desktopFolder")] = flutter::EncodableValue(desktopOk);
  map[flutter::EncodableValue("documentsFolder")] = flutter::EncodableValue(docsOk);
  map[flutter::EncodableValue("downloadsFolder")] = flutter::EncodableValue(dlOk);
  map[flutter::EncodableValue("externalVolumes")] = flutter::EncodableValue(!volumes.empty());
  map[flutter::EncodableValue("mountedVolumes")] = flutter::EncodableValue(volumes);
  map[flutter::EncodableValue("fullDiskAccess")] = flutter::EncodableValue(elevated);
  map[flutter::EncodableValue("isElevated")] = flutter::EncodableValue(elevated);
  map[flutter::EncodableValue("displays")] = flutter::EncodableValue(displays);
  map[flutter::EncodableValue("authorizedFolders")] = flutter::EncodableValue(authFolders);
  return map;
}

bool FlutterWindow::RequestWindowsPermission(const std::string& key) {
  if (key == "elevation" || key == "fullDiskAccess") {
    if (IsProcessElevated()) return true;
    wchar_t exePath[MAX_PATH]{};
    if (::GetModuleFileNameW(nullptr, exePath, MAX_PATH) == 0) return false;
    HINSTANCE res = ::ShellExecuteW(
        GetHandle(), L"runas", exePath, L"--elevated-takeover", nullptr, SW_SHOWNORMAL);
    if (reinterpret_cast<INT_PTR>(res) > 32) {
      explicit_quit_ = true;
      ::DestroyWindow(GetHandle());
      return true;
    }
    return false;
  }
  if (key == "microphone") {
    OpenWindowsSettingsPane("microphone");
    return true;
  }
  if (key == "storage") {
    OpenWindowsSettingsPane("storage");
    return true;
  }
  return true;
}

void FlutterWindow::OpenWindowsSettingsPane(const std::string& pane) const {
  const wchar_t* uri = L"ms-settings:privacy";
  if (pane == "microphone") {
    uri = L"ms-settings:privacy-microphone";
  } else if (pane == "screenRecording" || pane == "displays") {
    uri = L"ms-settings:display";
  } else if (pane == "storage" || pane == "fullDiskAccess") {
    uri = L"ms-settings:windowsdefender";
  }
  ::ShellExecuteW(GetHandle(), L"open", uri, nullptr, nullptr, SW_SHOWNORMAL);
}

std::vector<std::string> FlutterWindow::PromptAuthorizedFolder() {
  std::vector<std::string> paths = LoadAuthorizedFolders();
  IFileOpenDialog* pfd = nullptr;
  if (FAILED(::CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&pfd))) || !pfd) {
    return paths;
  }
  DWORD options = 0;
  if (SUCCEEDED(pfd->GetOptions(&options))) {
    pfd->SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_ALLOWMULTISELECT);
  }
  pfd->SetTitle(L"Authorize Folder or Drive for Oneova Agent");
  if (SUCCEEDED(pfd->Show(GetHandle()))) {
    IShellItemArray* items = nullptr;
    if (SUCCEEDED(pfd->GetResults(&items)) && items) {
      DWORD count = 0;
      items->GetCount(&count);
      for (DWORD i = 0; i < count; ++i) {
        IShellItem* item = nullptr;
        if (SUCCEEDED(items->GetItemAt(i, &item)) && item) {
          PWSTR pszPath = nullptr;
          if (SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &pszPath)) && pszPath) {
            std::string utf8 = WideToUtf8(pszPath);
            if (!utf8.empty() && std::find(paths.begin(), paths.end(), utf8) == paths.end()) {
              paths.push_back(utf8);
            }
            ::CoTaskMemFree(pszPath);
          }
          item->Release();
        }
      }
      items->Release();
      SaveAuthorizedFolders(paths);
    }
  }
  pfd->Release();
  return paths;
}
