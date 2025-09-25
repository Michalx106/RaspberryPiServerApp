import SwiftUI
import WebKit
import Combine

/// Obserwator motywu strony internetowej renderowanej w widoku WWW.
final class WebThemeObserver: ObservableObject {
    @Published var colorScheme: ColorScheme?
    @Published var isLoading: Bool = true

    func updateColorScheme(with value: String) {
        switch value.lowercased() {
        case "dark":
            if colorScheme != .dark { colorScheme = .dark }
        case "light":
            if colorScheme != .light { colorScheme = .light }
        default:
            if colorScheme != nil { colorScheme = nil }
        }
    }
}

/// SwiftUI wrapper dla `WKWebView`, który monitoruje motyw strony i informuje o tym aplikację.
struct AdaptiveWebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var themeObserver: WebThemeObserver

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true

        let userContentController = WKUserContentController()
        userContentController.addUserScript(Self.themeDetectionScript)

        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences = preferences
        configuration.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.contentInset = .zero
        webView.scrollView.scrollIndicatorInsets = .zero

        context.coordinator.connect(webView: webView, userContentController: userContentController)
        context.coordinator.loadIfNeeded()

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.webView = uiView
        context.coordinator.loadIfNeeded()
    }
}

extension AdaptiveWebView {
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        fileprivate static let messageName = "themeObserver"

        private let parent: AdaptiveWebView
        private weak var userContentController: WKUserContentController?
        fileprivate weak var webView: WKWebView?
        private var isInitialLoadPerformed = false

        init(parent: AdaptiveWebView) {
            self.parent = parent
        }

        func connect(webView: WKWebView, userContentController: WKUserContentController) {
            self.webView = webView
            self.userContentController = userContentController
            userContentController.add(self, name: Self.messageName)
        }

        func loadIfNeeded() {
            guard let webView = webView, !isInitialLoadPerformed else { return }
            isInitialLoadPerformed = true
            let request = URLRequest(url: parent.url, cachePolicy: .reloadRevalidatingCacheData)
            webView.load(request)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.messageName, let value = message.body as? String else { return }
            DispatchQueue.main.async { [weak self] in
                self?.parent.themeObserver.updateColorScheme(with: value)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.themeObserver.isLoading = true
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.themeObserver.isLoading = false
                self?.requestThemeRefresh()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.themeObserver.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.themeObserver.isLoading = false
            }
        }

        private func requestThemeRefresh() {
            let javascript = "window.__appThemeObserver?.evaluate && window.__appThemeObserver.evaluate();"
            webView?.evaluateJavaScript(javascript, completionHandler: nil)
        }

        deinit {
            userContentController?.removeScriptMessageHandler(forName: Self.messageName)
        }
    }
}

private extension AdaptiveWebView {
    static var themeDetectionScript: WKUserScript {
        let source = """
        (function() {
            if (window.__appThemeObserver) { return; }

            const MESSAGE_NAME = '\(Coordinator.messageName)';
            const postMessage = (mode) => {
                try {
                    const handler = window.webkit &&
                        window.webkit.messageHandlers &&
                        window.webkit.messageHandlers[MESSAGE_NAME];

                    if (handler && typeof handler.postMessage === 'function') {
                        handler.postMessage(mode);
                    }
                } catch (error) {
                    console.error('Theme bridge error', error);
                }
            };

            const normalizeMode = (value) => {
                if (!value) { return null; }
                const normalized = value.toString().toLowerCase();
                if (normalized.includes('dark')) { return 'dark'; }
                if (normalized.includes('light')) { return 'light'; }
                return null;
            };

            const resolveMode = () => {
                const html = document.documentElement;
                const body = document.body;

                const attributes = [
                    html?.dataset?.theme,
                    body?.dataset?.theme,
                    html?.getAttribute('data-theme'),
                    body?.getAttribute('data-theme'),
                ].filter(Boolean);
                for (const attribute of attributes) {
                    const normalized = normalizeMode(attribute);
                    if (normalized) { return normalized; }
                }

                const classNames = [
                    ...(html?.classList ?? []),
                    ...(body?.classList ?? []),
                ];
                for (const className of classNames) {
                    const normalized = normalizeMode(className);
                    if (normalized) { return normalized; }
                }

                if (window.matchMedia) {
                    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
                }

                return 'light';
            };

            const dispatch = () => {
                const mode = resolveMode();
                postMessage(mode);
            };

            const mediaQuery = window.matchMedia ? window.matchMedia('(prefers-color-scheme: dark)') : null;
            const handleMediaChange = () => dispatch();

            if (mediaQuery) {
                if (typeof mediaQuery.addEventListener === 'function') {
                    mediaQuery.addEventListener('change', handleMediaChange);
                } else if (typeof mediaQuery.addListener === 'function') {
                    mediaQuery.addListener(handleMediaChange);
                }
            }

            const mutationObserver = new MutationObserver(dispatch);
            mutationObserver.observe(document.documentElement, { attributes: true, attributeFilter: ['class', 'data-theme'] });
            const bodyObserverOptions = { attributes: true, attributeFilter: ['class', 'data-theme'] };

            if (document.body) {
                mutationObserver.observe(document.body, bodyObserverOptions);
            } else {
                document.addEventListener('DOMContentLoaded', () => {
                    if (document.body) {
                        mutationObserver.observe(document.body, bodyObserverOptions);
                        dispatch();
                    }
                });
            }

            window.__appThemeObserver = {
                evaluate: dispatch
            };

            dispatch();
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }
}

