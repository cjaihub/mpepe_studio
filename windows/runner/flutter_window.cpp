#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "advapi32.lib")

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

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
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
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
