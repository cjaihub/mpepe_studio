#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <shellapi.h>

#include <memory>

#include "win32_window.h"

class FlutterWindow : public Win32Window {
 public:
  explicit FlutterWindow(const flutter::DartProject& project, bool start_hidden = false);
  virtual ~FlutterWindow();

 protected:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void SetupWindowChannel();
  void SetupTrayIcon();
  void RemoveTrayIcon();
  void ShowTrayContextMenu();
  void RegisterGlobalHotKeys();
  void UnregisterGlobalHotKeys();
  void ApplyHudMode(bool hud);
  void BringToFront(const char* source);
  void ToggleHudFromAnywhere();
  bool IsStartupEnabled() const;
  bool SetStartupEnabled(bool enabled) const;

  flutter::DartProject project_;
  bool start_hidden_ = false;
  bool explicit_quit_ = false;
  bool is_hud_mode_ = false;
  bool has_saved_studio_rect_ = false;
  RECT saved_studio_rect_{};
  NOTIFYICONDATAW tray_icon_{};
  bool tray_added_ = false;

  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> window_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
