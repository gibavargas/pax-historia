import SwiftUI
import WebKit

@MainActor
struct NativeWebGameView {
    private let bridge = FoundationModelBridge()

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        let platform = Platform.current
        let bootstrap = """
        window.__PAX_APPLE_HOST__ = true;
        window.__PAX_NATIVE_RUNTIME__ = { mode: "apple", platform: "\(platform)" };
        try { localStorage.setItem("api_provider", "apple-foundation"); } catch (_) {}
        """

        userContentController.add(WeakScriptMessageDelegate(bridge), name: "foundationModel")
        userContentController.addUserScript(
            WKUserScript(
                source: bootstrap,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )

        configuration.userContentController = userContentController
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = false
        bridge.webView = webView

        #if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = true
        #endif

        return webView
    }

    fileprivate func loadGame(into webView: WKWebView) {
        guard let indexURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "dist") else {
            webView.loadHTMLString(
                "<html><body style='font-family:-apple-system;background:#050403;color:white;padding:24px'>Missing bundled web build. Run npm run build before building the Apple target.</body></html>",
                baseURL: nil
            )
            return
        }

        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
    }
}

#if os(iOS)
extension NativeWebGameView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let webView = makeWebView()
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        loadGame(into: webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif

#if os(macOS)
extension NativeWebGameView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let webView = makeWebView()
        loadGame(into: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif

private enum Platform {
    static var current: String {
        #if os(iOS)
        return "iOS"
        #elseif os(macOS)
        return "macOS"
        #else
        return "Apple"
        #endif
    }
}

private final class WeakScriptMessageDelegate: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(_ delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}
