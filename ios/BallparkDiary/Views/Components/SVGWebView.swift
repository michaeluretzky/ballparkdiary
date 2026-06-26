import SwiftUI
import WebKit

/// Renders an SVG logo from a URL inside a transparent WKWebView.
/// Wraps the SVG in an HTML page so it fills the view reliably and
/// renders with a transparent background.
struct SVGWebView: UIViewRepresentable {
    let url: URL
    var onLoaded: (() -> Void)? = nil
    var onFailed: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onLoaded: onLoaded, onFailed: onFailed)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.isUserInteractionEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.currentURL != url else { return }
        context.coordinator.currentURL = url
        context.coordinator.hasLoaded = false

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>
        * { margin: 0; padding: 0; }
        html, body { width: 100%; height: 100%; background: transparent; }
        img { display: block; width: 100%; height: 100%; object-fit: contain; }
        </style>
        </head>
        <body>
        <img src="\(url.absoluteString)" />
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: nil)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        var currentURL: URL?
        var hasLoaded = false
        let onLoaded: (() -> Void)?
        let onFailed: (() -> Void)?

        init(onLoaded: (() -> Void)?, onFailed: (() -> Void)?) {
            self.onLoaded = onLoaded
            self.onFailed = onFailed
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !hasLoaded else { return }
            hasLoaded = true
            // Brief delay so the <img> has time to decode and paint
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.onLoaded?()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if !hasLoaded { onFailed?() }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onFailed?()
        }
    }
}
