import AuthenticationServices
import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, ASWebAuthenticationPresentationContextProviding {
  private var webAuthSession: ASWebAuthenticationSession?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    var windowFrame = self.frame
    if windowFrame.width < 560 || windowFrame.height < 720 {
      windowFrame.size = NSSize(width: max(windowFrame.width, 560), height: max(windowFrame.height, 740))
    }
    self.minSize = NSSize(width: 480, height: 640)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let oauthChannel = FlutterMethodChannel(
      name: "oneova/desktop_oauth",
      binaryMessenger: flutterViewController.engine.binaryMessenger
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

    super.awakeFromNib()
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    return self
  }
}
