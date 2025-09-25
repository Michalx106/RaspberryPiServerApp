import SwiftUI

/// Główny widok aplikacji wyświetlający zawartość panelu WWW.
struct ContentView: View {
    private let dashboardURL = URL(string: "http://192.168.0.151/")!

    @StateObject private var themeObserver = WebThemeObserver()

    var body: some View {
        ZStack {
            AdaptiveWebView(url: dashboardURL, themeObserver: themeObserver)
                .ignoresSafeArea()

            if themeObserver.isLoading {
                ProgressView("Ładowanie strony…")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .background(Color(.systemBackground))
        .preferredColorScheme(themeObserver.colorScheme)
    }
}
