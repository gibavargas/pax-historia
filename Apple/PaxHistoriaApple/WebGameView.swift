import SwiftUI
import WebKit

@MainActor
struct NativeWebGameView {
    let selectedCountry: PlayerCountry

    private let bridge = FoundationModelBridge()

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        let bootstrap = makeBootstrapScript()

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

    private func makeBootstrapScript() -> String {
        let countryPayload = jsonLiteral([
            "code": selectedCountry.code,
            "name": selectedCountry.name,
        ])
        let runtimeGamePayload = jsonLiteral([
            "country": selectedCountry.name,
            "countryCode": selectedCountry.code,
            "difficulty": "standard",
            "gameDate": "2030-09-15",
            "language": "English",
            "round": 1,
            "startDate": "2025-03-25",
        ] as [String: Any])
        let cacheToken = "native-\(selectedCountry.code)-\(Int(Date().timeIntervalSince1970))"

        return """
        window.__PAX_APPLE_HOST__ = true;
        window.__PAX_NATIVE_RUNTIME__ = {
          mode: "apple",
          platform: "\(Platform.current)",
          selectedCountry: \(countryPayload)
        };
        try {
          localStorage.setItem("api_provider", "apple-foundation");
          localStorage.setItem("pax-native-json:game", JSON.stringify(\(runtimeGamePayload)));
          localStorage.setItem("pax-native-cache-token", "\(cacheToken)");
          localStorage.setItem("pax-native-player-country", JSON.stringify(\(countryPayload)));
        } catch (_) {}
        """
    }

    private func jsonLiteral(_ value: Any) -> String {
        guard
            JSONSerialization.isValidJSONObject(value),
            let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }

        return text
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
