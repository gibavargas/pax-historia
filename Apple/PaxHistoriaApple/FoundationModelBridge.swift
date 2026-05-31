import Foundation
import WebKit

final class FoundationModelBridge: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?

    private let responder = AppleFoundationModelResponder()
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        do {
            let data: Data
            if let stringBody = message.body as? String {
                data = Data(stringBody.utf8)
            } else if JSONSerialization.isValidJSONObject(message.body) {
                data = try JSONSerialization.data(withJSONObject: message.body)
            } else {
                throw BridgeError.invalidPayload
            }

            let request = try decoder.decode(AppleAIRequest.self, from: data)
            Task { @MainActor in
                let response = await responder.respond(to: request)
                send(response)
            }
        } catch {
            let response = AppleAIResponse(
                availability: "bridge-error",
                error: error.localizedDescription,
                fallbackUsed: true,
                ok: false,
                provider: "apple-foundation",
                recoverySuggestion: "The native WebKit bridge could not decode the Apple AI request. Reload the native app and retry.",
                requestId: "unknown",
                taskKey: nil,
                text: "",
                tokenBudget: nil
            )
            Task { @MainActor in send(response) }
        }
    }

    @MainActor
    private func send(_ response: AppleAIResponse) {
        guard let webView else { return }

        do {
            let data = try encoder.encode(response)
            let json = String(decoding: data, as: UTF8.self)
            webView.evaluateJavaScript("window.__paxAppleAI?.receiveResponse(\(json));")
        } catch {
            webView.evaluateJavaScript("""
            window.__paxAppleAI?.receiveResponse({
              requestId: "\(response.requestId)",
              ok: false,
              error: "Could not encode native AI response.",
              text: ""
            });
            """)
        }
    }

    private enum BridgeError: LocalizedError {
        case invalidPayload

        var errorDescription: String? {
            "The native AI bridge received a payload WebKit could not decode."
        }
    }
}
