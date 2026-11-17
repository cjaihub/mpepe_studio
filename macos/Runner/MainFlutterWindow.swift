import ApplicationServices
import AuthenticationServices
import AVFoundation
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
      case "getPermissionsStatus":
        self.collectPermissionsStatus { status in
          result(status)
        }
      case "requestPermission":
        let args = call.arguments as? [String: Any]
        let key = (args?["permission"] as? String) ?? "all"
        self.requestMacPermission(key) { status in
          result(status)
        }
      case "openPermissionSettings":
        let args = call.arguments as? [String: Any]
        let pane = (args?["pane"] as? String) ?? "accessibility"
        self.openMacPrivacyPane(pane)
        result(true)
      case "authorizeStorageFolder":
        self.promptStorageFolderAccess { folders in
          result(folders)
        }
      case "resetStalePermissions":
        self.resetMacTccEntries {
          self.collectPermissionsStatus { status in
            result(status)
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    self.restoreAuthorizedFolderBookmarks()

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

  // MARK: - macOS Desktop Permissions (Mouse, Keyboard, Other Screens & Storage)

  private static let kAuthorizedFoldersKey = "OneovaAuthorizedFolderPaths"
  private static let kAuthorizedBookmarksKey = "OneovaAuthorizedFolderBookmarks"
  private static var securityScopedUrls: [URL] = []

  private func restoreAuthorizedFolderBookmarks() {
    guard let list = UserDefaults.standard.array(forKey: Self.kAuthorizedBookmarksKey) as? [Data] else {
      return
    }
    for data in list {
      var isStale = false
      if let url = try? URL(
        resolvingBookmarkData: data,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      ) {
        if url.startAccessingSecurityScopedResource() {
          Self.securityScopedUrls.append(url)
        }
      }
    }
  }

  private func checkDirectoryReadable(_ url: URL?) -> Bool {
    guard let url = url else { return false }
    do {
      _ = try FileManager.default.contentsOfDirectory(atPath: url.path)
      return true
    } catch {
      return false
    }
  }

  private func checkFullDiskAccess() -> Bool {
    let fm = FileManager.default
    let home = fm.homeDirectoryForCurrentUser.path
    let probes = [
      "\(home)/Library/Application Support/com.apple.TCC/TCC.db",
      "\(home)/Library/Safari/Bookmarks.plist",
      "/Library/Application Support/com.apple.TCC/TCC.db",
    ]
    for path in probes where fm.fileExists(atPath: path) {
      if fm.isReadableFile(atPath: path) {
        return true
      }
    }
    return false
  }

  private func collectDisplayDescriptors() -> [[String: Any]] {
    let screens = NSScreen.screens
    let primaryHeight = screens.first?.frame.height ?? 1080
    return screens.enumerated().map { idx, scr in
      let frame = scr.frame
      let topY = primaryHeight - frame.maxY
      return [
        "index": idx,
        "name": scr.localizedName,
        "x": Int(frame.origin.x.rounded()),
        "y": Int(topY.rounded()),
        "width": Int(frame.width.rounded()),
        "height": Int(frame.height.rounded()),
        "isPrimary": idx == 0,
      ]
    }
  }

  private func checkAutomationGranted(prompt: Bool) -> Bool {
    let targetDesc = NSAppleEventDescriptor(bundleIdentifier: "com.apple.systemevents")
    guard let aePtr = targetDesc.aeDesc else { return false }
    let status = AEDeterminePermissionToAutomateTarget(
      aePtr,
      AEEventClass(typeWildCard),
      AEEventID(typeWildCard),
      prompt
    )
    return status == noErr
  }

  private func collectPermissionsStatus(completion: @escaping ([String: Any]) -> Void) {
    let accessibility = AXIsProcessTrusted()
    let inputMonitoring = CGPreflightListenEventAccess()
    let screenRecording = CGPreflightScreenCaptureAccess()
    let microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    let displays = collectDisplayDescriptors()
    let authFolders = (UserDefaults.standard.stringArray(forKey: Self.kAuthorizedFoldersKey) ?? [])

    DispatchQueue.global(qos: .userInitiated).async {
      let fm = FileManager.default
      let desktopOk = self.checkDirectoryReadable(fm.urls(for: .desktopDirectory, in: .userDomainMask).first)
      let documentsOk = self.checkDirectoryReadable(fm.urls(for: .documentDirectory, in: .userDomainMask).first)
      let downloadsOk = self.checkDirectoryReadable(fm.urls(for: .downloadsDirectory, in: .userDomainMask).first)
      let volumesList = (try? fm.contentsOfDirectory(atPath: "/Volumes"))?.filter { !$0.hasPrefix(".") } ?? []
      let volumesOk = (try? fm.contentsOfDirectory(atPath: "/Volumes")) != nil
      let fullDisk = self.checkFullDiskAccess()
      let automation = self.checkAutomationGranted(prompt: false)

      let payload: [String: Any] = [
        "platform": "macos",
        "accessibility": accessibility,
        "inputMonitoring": inputMonitoring,
        "screenRecording": screenRecording,
        "automation": automation,
        "microphone": microphone,
        "desktopFolder": desktopOk,
        "documentsFolder": documentsOk,
        "downloadsFolder": downloadsOk,
        "externalVolumes": volumesOk,
        "mountedVolumes": volumesList,
        "fullDiskAccess": fullDisk,
        "isElevated": accessibility && screenRecording,
        "displays": displays,
        "authorizedFolders": authFolders,
      ]
      DispatchQueue.main.async {
        completion(payload)
      }
    }
  }

  private func openMacPrivacyPane(_ pane: String) {
    let anchor: String
    switch pane {
    case "accessibility":
      anchor = "Privacy_Accessibility"
    case "inputMonitoring":
      anchor = "Privacy_ListenEvent"
    case "screenRecording":
      anchor = "Privacy_ScreenCapture"
    case "fullDiskAccess":
      anchor = "Privacy_AllFiles"
    case "storage":
      anchor = "Privacy_FilesAndFolders"
    case "automation":
      anchor = "Privacy_Automation"
    case "microphone":
      anchor = "Privacy_Microphone"
    default:
      anchor = "Privacy"
    }
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
      NSWorkspace.shared.open(url)
    }
  }

  private func requestMacPermission(_ key: String, completion: @escaping ([String: Any]) -> Void) {
    let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String

    if key == "accessibility" || key == "all" {
      let opts = [promptKey: true] as CFDictionary
      let trusted = AXIsProcessTrustedWithOptions(opts)
      if !trusted && key == "accessibility" {
        openMacPrivacyPane("accessibility")
      }
    }

    if key == "inputMonitoring" || key == "all" {
      let ok = CGRequestListenEventAccess()
      if !ok && key == "inputMonitoring" {
        openMacPrivacyPane("inputMonitoring")
      }
    }

    if key == "screenRecording" || key == "all" {
      let ok = CGRequestScreenCaptureAccess()
      if !ok && key == "screenRecording" {
        openMacPrivacyPane("screenRecording")
      }
    }

    if key == "fullDiskAccess" {
      openMacPrivacyPane("fullDiskAccess")
    }

    if key == "microphone" || key == "all" {
      let status = AVCaptureDevice.authorizationStatus(for: .audio)
      if status == .notDetermined {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
          if !granted && key == "microphone" {
            DispatchQueue.main.async { self.openMacPrivacyPane("microphone") }
          }
        }
      } else if status != .authorized && key == "microphone" {
        openMacPrivacyPane("microphone")
      }
    }

    DispatchQueue.global(qos: .userInitiated).async {
      if key == "storage" || key == "all" {
        let fm = FileManager.default
        _ = self.checkDirectoryReadable(fm.urls(for: .desktopDirectory, in: .userDomainMask).first)
        _ = self.checkDirectoryReadable(fm.urls(for: .documentDirectory, in: .userDomainMask).first)
        _ = self.checkDirectoryReadable(fm.urls(for: .downloadsDirectory, in: .userDomainMask).first)
        _ = try? fm.contentsOfDirectory(atPath: "/Volumes")
        if key == "storage" && !self.checkDirectoryReadable(fm.urls(for: .desktopDirectory, in: .userDomainMask).first) {
          DispatchQueue.main.async { self.openMacPrivacyPane("storage") }
        }
      }

      if key == "automation" || key == "all" {
        let autoOk = self.checkAutomationGranted(prompt: true)
        if !autoOk && key == "automation" {
          DispatchQueue.main.async { self.openMacPrivacyPane("automation") }
        }
      }

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
        self.collectPermissionsStatus(completion: completion)
      }
    }
  }

  private func promptStorageFolderAccess(completion: @escaping ([String]) -> Void) {
    let panel = NSOpenPanel()
    panel.title = "Authorize Folder or External Drive for Oneova Agent"
    panel.message = "Select any folder or connected drive (/Volumes/...) that Oneova Desktop Agent may read and write."
    panel.prompt = "Grant Access"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = true
    panel.canCreateDirectories = true

    panel.beginSheetModal(for: self) { response in
      var paths = UserDefaults.standard.stringArray(forKey: Self.kAuthorizedFoldersKey) ?? []
      var bookmarks = (UserDefaults.standard.array(forKey: Self.kAuthorizedBookmarksKey) as? [Data]) ?? []
      if response == .OK {
        for url in panel.urls {
          _ = url.startAccessingSecurityScopedResource()
          Self.securityScopedUrls.append(url)
          if !paths.contains(url.path) {
            paths.append(url.path)
          }
          if let data = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
          ) {
            bookmarks.append(data)
          }
        }
        UserDefaults.standard.set(paths, forKey: Self.kAuthorizedFoldersKey)
        UserDefaults.standard.set(bookmarks, forKey: Self.kAuthorizedBookmarksKey)
      }
      completion(paths)
    }
  }

  private func resetMacTccEntries(completion: @escaping () -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
      let proc = Process()
      proc.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
      proc.arguments = ["reset", "All", "com.oneova.app"]
      try? proc.run()
      proc.waitUntilExit()
      DispatchQueue.main.async {
        completion()
      }
    }
  }
}
