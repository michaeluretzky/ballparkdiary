import SwiftUI
import WebKit

/// Renders an SVG logo from a URL inside a transparent WKWebView.
/// Fetches the SVG data inline so it loads reliably without cross-origin
/// restrictions, then embeds it in an HTML page with a transparent background.
struct SVGWebView: UIViewRepresentable {
    let url: URL
    var onLoaded: (() -> Void)? = nil
    var onFailed: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, onLoaded: onLoaded, onFailed: onFailed)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        // Suppress verbose WKWebView logging that can cause issues
        config.suppressesIncrementalRendering = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.isUserInteractionEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // Prevent WKWebView from intercepting parent scroll
        webView.scrollView.isUserInteractionEnabled = false

        context.coordinator.load(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.targetURL != url {
            context.coordinator.targetURL = url
            context.coordinator.load(in: webView)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.cancel()
        webView.stopLoading()
        webView.navigationDelegate = nil
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        var targetURL: URL
        let onLoaded: (() -> Void)?
        let onFailed: (() -> Void)?
        private var task: URLSessionDataTask?
        private var hasCalledLoaded = false
        private var hasCalledFailed = false

        init(url: URL, onLoaded: (() -> Void)?, onFailed: (() -> Void)?) {
            self.targetURL = url
            self.onLoaded = onLoaded
            self.onFailed = onFailed
        }

        func load(in webView: WKWebView) {
            cancel()
            hasCalledLoaded = false
            hasCalledFailed = false

            task = URLSession.shared.dataTask(with: targetURL) { [weak self] data, _, error in
                guard let self else { return }
                if let data, let svgStr = String(data: data, encoding: .utf8),
                   !svgStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let html = """
                    <!DOCTYPE html>
                    <html>
                    <head>
                    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
                    <style>
                    * { margin: 0; padding: 0; box-sizing: border-box; }
                    html, body {
                        width: 100%; height: 100%;
                        background: transparent !important;
                        display: flex;
                        align-items: center;
                        justify-content: center;
                        padding: 2px;
                    }
                    svg {
                        width: 100% !important;
                        height: 100% !important;
                        display: block;
                        filter: drop-shadow(0 0 1px rgba(255,255,255,0.8))
                                drop-shadow(0 1px 1px rgba(255,255,255,0.5));
                    }
                    </style>
                    </head>
                    <body>\(svgStr)</body>
                    </html>
                    """
                    DispatchQueue.main.async {
                        webView.loadHTMLString(html, baseURL: self.targetURL)
                    }
                } else {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, !self.hasCalledFailed else { return }
                        self.hasCalledFailed = true
                        self.onFailed?()
                    }
                }
            }
            task?.resume()
        }

        func cancel() {
            task?.cancel()
            task = nil
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !hasCalledLoaded else { return }
            hasCalledLoaded = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.onLoaded?()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if !hasCalledFailed { hasCalledFailed = true; onFailed?() }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if !hasCalledFailed { hasCalledFailed = true; onFailed?() }
        }
    }
}
