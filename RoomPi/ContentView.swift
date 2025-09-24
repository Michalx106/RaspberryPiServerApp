//
//  ContentView.swift
//  RoomPi
//
//  Created by Michał Grzesiewicz on 24/09/2025.
//

#Preview {
    ContentView()
}

import SwiftUI
import WebKit
import Combine
import SafariServices

// MARK: - Konfiguracja: ustaw tutaj adres Twojej aplikacji webowej
private let BASE_URL = URL(string: "http://192.168.0.151")!

// MARK: - ViewModel do obserwacji tytułu, progresu i nawigacji
final class WebViewModel: ObservableObject {
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var progress: Double = 0.0
    @Published var title: String = "Ładowanie…"
    fileprivate var webView: WKWebView? // ustawiane po inicjalizacji
}

// MARK: - Wrapper WKWebView
struct WebView: UIViewRepresentable {
    @ObservedObject var model: WebViewModel
    let url: URL
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.limitsNavigationsToAppBoundDomains = false
        // WebRTC / getUserMedia w WKWebView wymaga tego domyślnego configu (i opisów w Info.plist)
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.bounces = true
        
        // Pull to refresh
        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.refresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
        
        // KVO do progresu
        webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
        webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.canGoBack), options: .new, context: nil)
        webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.canGoForward), options: .new, context: nil)
        webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.title), options: .new, context: nil)
        webView.addObserver(context.coordinator, forKeyPath: "loading", options: .new, context: nil)
        
        webView.load(URLRequest(url: url))
        model.webView = webView
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) { }
    
    // MARK: - Coordinator
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: WebView
        init(_ parent: WebView) { self.parent = parent }
        
        // Pull to refresh handler
        @objc func refresh(_ sender: UIRefreshControl) {
            parent.model.webView?.reload()
        }
        
        // KVO
        override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                   change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
            guard let webView = object as? WKWebView else { return }
            DispatchQueue.main.async {
                switch keyPath {
                case #keyPath(WKWebView.estimatedProgress):
                    self.parent.model.progress = webView.estimatedProgress
                    self.parent.model.isLoading = webView.estimatedProgress < 1.0
                case #keyPath(WKWebView.canGoBack):
                    self.parent.model.canGoBack = webView.canGoBack
                case #keyPath(WKWebView.canGoForward):
                    self.parent.model.canGoForward = webView.canGoForward
                case #keyPath(WKWebView.title):
                    self.parent.model.title = webView.title ?? ""
                case "loading":
                    self.parent.model.isLoading = webView.isLoading
                    if !webView.isLoading {
                        webView.scrollView.refreshControl?.endRefreshing()
                    }
                default: break
                }
            }
        }
        
        // Obsługa nawigacji i linków zewnętrznych
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel); return
            }
            
            // Zezwól na http(s) do naszego hosta i pod-ścieżek
            if url.scheme?.hasPrefix("http") == true {
                decisionHandler(.allow)
                return
            }
            
            // Obsłuż schematy tel:, mailto:, itp. otwierając system
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            
            decisionHandler(.allow)
        }
        
        // target="_blank" → otwórz w tym samym webview (albo zewnętrznie po chęci)
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.model.isLoading = true
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.model.isLoading = false
            webView.scrollView.refreshControl?.endRefreshing()
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.model.isLoading = false
            webView.scrollView.refreshControl?.endRefreshing()
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.model.isLoading = false
            webView.scrollView.refreshControl?.endRefreshing()
        }
    }
}

// MARK: - Główny widok z paskiem narzędzi
struct ContentView: View {
    @StateObject private var model = WebViewModel()
    @State private var showingShare = false
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                WebView(model: model, url: BASE_URL)
                    .ignoresSafeArea(edges: .bottom)
                
                // Pasek postępu
                if model.isLoading {
                    ProgressView(value: model.progress)
                        .progressViewStyle(.linear)
                        .padding(.top, 1)
                }
            }
            .navigationTitle(model.title.isEmpty ? "RaspberryPi" : model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button(action: { model.webView?.goBack() }) {
                        Image(systemName: "chevron.backward")
                    }.disabled(!model.canGoBack)
                    
                    Button(action: { model.webView?.goForward() }) {
                        Image(systemName: "chevron.forward")
                    }.disabled(!model.canGoForward)
                    
                    Spacer()
                    
                    Button(action: { model.webView?.reload() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    
                    Button(action: {
                        guard let url = model.webView?.url else { return }
                        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                        if let scene = UIApplication.shared.connectedScenes
                            .compactMap({ $0 as? UIWindowScene })
                            .first(where: { $0.activationState == .foregroundActive }),
                           let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                            if let popover = av.popoverPresentationController {
                                popover.sourceView = root.view
                                popover.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 0, height: 0)
                                popover.permittedArrowDirections = []
                            }
                            root.present(av, animated: true)
                        }
                    }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

