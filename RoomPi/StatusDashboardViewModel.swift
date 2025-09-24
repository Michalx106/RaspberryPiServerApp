import Foundation
import Combine
import SwiftUI

@MainActor
final class StatusDashboardViewModel: ObservableObject {
    @Published private(set) var bundle: StatusBundle?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var shellyOperations: Set<String> = []
    @Published private(set) var shellyControlErrors: [String: String] = [:]

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

    func start() {
        guard autoRefreshTask == nil else { return }

        autoRefreshTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.refresh(updateLoadingState: true)

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
        await refresh(updateLoadingState: true)
    }

    func toggleShellyDevice(_ device: ShellyDevice) async {
        let deviceID = device.id

        guard !shellyOperations.contains(deviceID) else { return }

        shellyOperations.insert(deviceID)
        shellyControlErrors[deviceID] = nil
        defer { shellyOperations.remove(deviceID) }

        do {
            let command: StatusService.ShellyCommand = device.isOn ? .turnOff : .turnOn
            let response = try await service.sendShellyCommand(
                deviceID: deviceID,
                command: command,
                overrideURL: shellyOverrideURL(for: device, command: command)
            )

            if response.isSuccessful == false {
                shellyControlErrors[deviceID] = response.message ?? "Nie udało się wykonać polecenia."
                return
            }

            shellyControlErrors[deviceID] = nil

            await refresh(updateLoadingState: false)
        } catch is CancellationError {
            // Ignore task cancellations triggered by lifecycle events.
        } catch {
            shellyControlErrors[deviceID] = userFriendlyMessage(for: error)
        }
    }

    private func shellyOverrideURL(for device: ShellyDevice, command: StatusService.ShellyCommand) -> URL? {
        guard let control = device.control else {
            return nil
        }

        switch command {
        case .turnOn:
            return control.turnOn ?? control.toggle
        case .turnOff:
            return control.turnOff ?? control.toggle
        case .toggle:
            return control.toggle
        }
    }

    func isShellyOperationInProgress(for deviceID: String) -> Bool {
        shellyOperations.contains(deviceID)
    }

    func shellyError(for deviceID: String) -> String? {
        shellyControlErrors[deviceID]
    }

    private func refresh(updateLoadingState: Bool) async {
        if isLoading {
            if updateLoadingState {
                return
            }

            while isLoading {
                try? await Task.sleep(nanoseconds: 100_000_000)

                if Task.isCancelled {
                    return
                }
            }
        }

        if updateLoadingState {
            isLoading = true
            errorMessage = nil
        }

        defer {
            if updateLoadingState {
                isLoading = false
            }
        }

        do {
            let response = try await service.fetchStatusBundle(historyLimit: historyLimit)

            withAnimation(.easeInOut(duration: 0.2)) {
                bundle = response
                if updateLoadingState {
                    errorMessage = nil
                }
            }

            lastUpdate = response.serverDate ?? response.generatedAt ?? Date()
        } catch is CancellationError {
            // Ignore task cancellations triggered by lifecycle events.
        } catch {
            if updateLoadingState {
                errorMessage = userFriendlyMessage(for: error)
            }
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
