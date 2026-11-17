import AuthenticationServices
import Carbon
import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate, ASWebAuthenticationPresentationContextProviding {
  private var webAuthSession: ASWebAuthenticationSession?
  private var windowChannel: FlutterMethodChannel?
  private var statusItem: NSStatusItem?
  private var hotKeyRefSpace: EventHotKeyRef?
  private var hotKeyRefO: EventHotKeyRef?
  private var hotKeyHandlerRef: EventHandlerRef?
  private var isHudMode = false
  private var savedStudioFrame: NSRect?
  private weak var startupMenuItem: NSMenuItem?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    var windowFrame = self.frame
    if windowFrame.width < 560 || windowFrame.height < 720 {
      windowFrame.size = NSSize(width: max(windowFrame.width, 560), height: max(windowFrame.height, 740))
    }
    self.minSize = NSSize(width: 480, height: 210)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.delegate = self

    RegisterGeneratedPlugins(registry: flutterViewController)

    let messenger = flutterViewController.engine.binaryMessenger

    let oauthChannel = FlutterMethodChannel(
      name: "oneova/desktop_oauth",
      binaryMessenger: messenger
    )
    oauthChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "disposed", message: "Window unavailable", details: nil))
        return
      }
      if call.method == "launchWebAuth" {
        guard
          let args = call.arguments as? [String: Any],
          let urlString = args["url"] as? String,
          let callbackScheme = args["callbackScheme"] as? String,
          let authURL = URL(string: urlString)
        else {
          result(FlutterError(code: "invalid_args", message: "Missing url or callbackScheme", details: nil))
          return
        }

        self.webAuthSession?.cancel()
        let session = ASWebAuthenticationSession(
          url: authURL,
          callbackURLScheme: callbackScheme
        ) { callbackURL, error in
          self.webAuthSession = nil
          if let callbackURL = callbackURL {
            result(callbackURL.absoluteString)
          } else if let authErr = error as? ASWebAuthenticationSessionError,
                    authErr.code == .canceledLogin {
            result(FlutterError(code: "canceled", message: "Sign-in was canceled.", details: nil))
          } else {
            result(
              FlutterError(
                code: "oauth_failed",
                message: error?.localizedDescription ?? "Authentication failed",
                details: nil
              )
            )
          }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.webAuthSession = session
        if !session.start() {
          self.webAuthSession = nil
          result(FlutterError(code: "start_failed", message: "Unable to open browser sheet", details: nil))
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let desktopWinChannel = FlutterMethodChannel(
      name: "com.oneova.app/desktop_window",
      binaryMessenger: messenger
    )
    self.windowChannel = desktopWinChannel
    desktopWinChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "disposed", message: "Window unavailable", details: nil))
        return
      }
      switch call.method {
      case "setHudMode":
        let args = call.arguments as? [String: Any]
        let enable = (args?["hud"] as? Bool) ?? true
        self.applyHudMode(enable)
        result(true)
      case "toggleHud":
        self.toggleHudFromAnywhere()
        result(true)
      case "showStudio":
        self.applyHudMode(false)
        self.bringToFront(source: "studio")
        result(true)
      case "hideToTray":
        self.orderOut(nil)
        result(true)
      case "getStartupEnabled":
        result(self.isLaunchAgentEnabled())
      case "setStartupEnabled":
        let args = call.arguments as? [String: Any]
        let enable = (args?["enabled"] as? Bool) ?? true
        let ok = self.setLaunchAgentEnabled(enable)
        self.startupMenuItem?.state = self.isLaunchAgentEnabled() ? .on : .off
        result(ok)
      case "getState":
        result([
          "hud": self.isHudMode,
          "startup": self.isLaunchAgentEnabled(),
          "hotkey": "Option+Space / Cmd+Shift+O",
          "platform": "macos",
        ])
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    setupStatusBarItem()
    registerGlobalHotKeys()

    if CommandLine.arguments.contains("--startup") {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
        self?.orderOut(nil)
      }
    }

    super.awakeFromNib()
  }

  // Hide to Menu Bar instead of quitting so global hotkey Option+Space works everywhere.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if AppDelegate.explicitQuit { return true }
    self.orderOut(nil)
    return false
  }

  private func setupStatusBarItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let btn = item.button {
      if #available(macOS 11.0, *),
         let img = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Ova") {
        img.isTemplate = true
        btn.image = img
        btn.imagePosition = .imageLeading
      }
      btn.title = " Ova"
      btn.toolTip = "Oneova Desktop Assistant (⌥Space anywhere)"
    }

    let menu = NSMenu()
    let hudItem = NSMenuItem(title: "Summon Ova HUD (⌥Space)", action: #selector(onMenuSummonHud), keyEquivalent: "")
    hudItem.target = self
    menu.addItem(hudItem)

    let studioItem = NSMenuItem(title: "Open Full Oneova Studio", action: #selector(onMenuOpenStudio), keyEquivalent: "")
    studioItem.target = self
    menu.addItem(studioItem)

    menu.addItem(NSMenuItem.separator())

    let startItem = NSMenuItem(title: "Launch on Startup", action: #selector(onMenuToggleStartup), keyEquivalent: "")
    startItem.target = self
    startItem.state = isLaunchAgentEnabled() ? .on : .off
    self.startupMenuItem = startItem
    menu.addItem(startItem)

    menu.addItem(NSMenuItem.separator())

    let quitItem = NSMenuItem(title: "Quit Oneova", action: #selector(onMenuQuit), keyEquivalent: "q")
    quitItem.target = self
    menu.addItem(quitItem)

    item.menu = menu
    self.statusItem = item
  }

  @objc private func onMenuSummonHud() {
    applyHudMode(true)
    bringToFront(source: "menubar_hud")
  }

  @objc private func onMenuOpenStudio() {
    applyHudMode(false)
    bringToFront(source: "menubar_studio")
  }

  @objc private func onMenuToggleStartup() {
    let next = !isLaunchAgentEnabled()
    _ = setLaunchAgentEnabled(next)
    startupMenuItem?.state = isLaunchAgentEnabled() ? .on : .off
  }

  @objc private func onMenuQuit() {
    AppDelegate.explicitQuit = true
    NSApp.terminate(nil)
  }

  private func bringToFront(source: String) {
    self.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    windowChannel?.invokeMethod("onWindowEvent", arguments: [
      "event": "summon",
      "source": source,
      "hud": isHudMode,
    ])
  }

  func toggleHudFromAnywhere() {
    if self.isVisible && isHudMode {
      self.orderOut(nil)
      return
    }
    applyHudMode(true)
    bringToFront(source: "global_hotkey")
  }

  private func applyHudMode(_ hud: Bool) {
    if hud == isHudMode && self.isVisible { return }
    if hud && !isHudMode {
      savedStudioFrame = self.frame
    }
    isHudMode = hud

    if hud {
      self.level = .floating
      self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      self.titlebarAppearsTransparent = true
      self.titleVisibility = .hidden
      self.isMovableByWindowBackground = true
      self.styleMask.insert(.fullSizeContentView)
      self.standardWindowButton(.closeButton)?.isHidden = true
      self.standardWindowButton(.miniaturizeButton)?.isHidden = true
      self.standardWindowButton(.zoomButton)?.isHidden = true

      let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
      let hudW: CGFloat = min(740, screenFrame.width - 48)
      let hudH: CGFloat = 250
      let x = screenFrame.midX - hudW / 2
      let y = screenFrame.minY + 34
      self.setFrame(NSRect(x: x, y: y, width: hudW, height: hudH), display: true, animate: true)
    } else {
      self.level = .normal
      self.collectionBehavior = [.managed]
      self.titleVisibility = .visible
      self.isMovableByWindowBackground = false
      self.standardWindowButton(.closeButton)?.isHidden = false
      self.standardWindowButton(.miniaturizeButton)?.isHidden = false
      self.standardWindowButton(.zoomButton)?.isHidden = false
      if let prev = savedStudioFrame {
        self.setFrame(prev, display: true, animate: true)
      } else {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let w: CGFloat = min(1160, screenFrame.width - 60)
        let h: CGFloat = min(780, screenFrame.height - 60)
        self.setFrame(
          NSRect(x: screenFrame.midX - w / 2, y: screenFrame.midY - h / 2, width: w, height: h),
          display: true,
          animate: true
        )
      }
    }

    windowChannel?.invokeMethod("onWindowEvent", arguments: [
      "event": "modeChanged",
      "hud": isHudMode,
    ])
  }

  private func registerGlobalHotKeys() {
    var eventSpec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    InstallEventHandler(
      GetApplicationEventTarget(),
      { (_, _, userData) -> OSStatus in
        guard let userData = userData else { return noErr }
        let win = Unmanaged<MainFlutterWindow>.fromOpaque(userData).takeUnretainedValue()
        DispatchQueue.main.async {
          win.toggleHudFromAnywhere()
        }
        return noErr
      },
      1,
      &eventSpec,
      selfPtr,
      &hotKeyHandlerRef
    )

    // Hotkey 1: Option + Space (keyCode 49 = Space, optionKey = 0x0800)
    let id1 = EventHotKeyID(signature: OSType(0x4F4E4531), id: 1) // 'ONE1'
    RegisterEventHotKey(49, UInt32(optionKey), id1, GetApplicationEventTarget(), 0, &hotKeyRefSpace)

    // Hotkey 2: Cmd + Shift + O (keyCode 31 = O)
    let id2 = EventHotKeyID(signature: OSType(0x4F4E4532), id: 2) // 'ONE2'
    RegisterEventHotKey(31, UInt32(cmdKey | shiftKey), id2, GetApplicationEventTarget(), 0, &hotKeyRefO)
  }

  private var launchAgentUrl: URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent("Library/LaunchAgents/com.oneova.desktop.plist")
  }

  private func isLaunchAgentEnabled() -> Bool {
    FileManager.default.fileExists(atPath: launchAgentUrl.path)
  }

  private func setLaunchAgentEnabled(_ enabled: Bool) -> Bool {
    let url = launchAgentUrl
    if !enabled {
      do {
        if FileManager.default.fileExists(atPath: url.path) {
          try FileManager.default.removeItem(at: url)
        }
        return true
      } catch {
        return false
      }
    }

    guard let exe = Bundle.main.executablePath else { return false }
    let plist: [String: Any] = [
      "Label": "com.oneova.desktop",
      "ProgramArguments": [exe, "--startup"],
      "RunAtLoad": true,
      "KeepAfterLaunch": false,
      "ProcessType": "Interactive",
    ]
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
      try data.write(to: url, options: .atomic)
      return true
    } catch {
      return false
    }
  }

  deinit {
    if let r = hotKeyRefSpace { UnregisterEventHotKey(r) }
    if let r = hotKeyRefO { UnregisterEventHotKey(r) }
    if let h = hotKeyHandlerRef { RemoveEventHandler(h) }
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    return self
  }
}
