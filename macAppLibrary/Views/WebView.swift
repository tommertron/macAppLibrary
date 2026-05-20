import SwiftUI
import WebKit

/// Minimal SwiftUI wrapper around `WKWebView` for previewing locally-generated
/// HTML. Link activations are intercepted and opened in the user's browser
/// (we don't want navigation inside the preview window).
struct WebView: NSViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.navigationDelegate = context.coordinator
        // Transparent background so the SwiftUI window chrome doesn't flash white.
        view.setValue(false, forKey: "drawsBackground")
        view.loadHTMLString(html, baseURL: nil)
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Only reload if the HTML actually changed; loadHTMLString is expensive.
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            nsView.loadHTMLString(html, baseURL: nil)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
