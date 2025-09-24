import Foundation
import SwiftUI

@MainActor
final class StatusDashboardViewModel: ObservableObject {
    @Published private(set) var bundle: StatusBundle?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdate: Date?

    private let service: StatusService
    private let historyLimit: Int
    private let fallbackInterval: TimeInterval
    private var autoRefreshTask: Task<Void, Never>?

    init(service: StatusService, historyLimit: Int = 120, fallbackInterval: TimeInterval = 5, initialBundle: StatusBundle? = nil) {
        self.service = service
        self.historyLimit = historyLimit
        self.fallbackInterval = fallbackInterval
        self.bundle = initialBundle
        self.lastUpdate = initialBundle?.serverDate ?? initialBundle?.generatedAt
    }

    deinit {
        stop()
    }

    func start() {
        guard autoRefreshTask == nil else { return }

        autoRefreshTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.refresh()

                let interval = self.bundle.map { TimeInterval($0.streamInterval) } ?? self.fallbackInterval
                let clampedInterval = interval.clamped(to: 1...60)

                try? await Task.sleep(nanoseconds: UInt64(clampedInterval * 1_000_000_000))
            }
        }
    }

    func stop() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    func manualRefresh() async {
        await refresh()
    }

    private func refresh() async {
        if isLoading { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await service.fetchStatusBundle(historyLimit: historyLimit)

            withAnimation(.easeInOut(duration: 0.2)) {
                bundle = response
                errorMessage = nil
            }

            lastUpdate = response.serverDate ?? response.generatedAt ?? Date()
        } catch is CancellationError {
            // Ignore task cancellations triggered by lifecycle events.
        } catch {
            errorMessage = userFriendlyMessage(for: error)
        }
    }

    private func userFriendlyMessage(for error: Error) -> String {
        if let serviceError = error as? StatusService.ServiceError {
            return serviceError.localizedDescription
        }

        if let urlError = error as? URLError {
            return urlError.localizedDescription
        }

        return error.localizedDescription.isEmpty
            ? "Wystąpił nieoczekiwany błąd."
            : error.localizedDescription
    }
}

private extension TimeInterval {
    func clamped(to range: ClosedRange<TimeInterval>) -> TimeInterval {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
