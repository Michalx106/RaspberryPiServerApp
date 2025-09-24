import SwiftUI

private enum AppConfig {
    static let baseURL = URL(string: "http://192.168.0.151")!
}

@MainActor
struct ContentView: View {
    @StateObject private var viewModel: StatusDashboardViewModel
    @State private var selectedMetric: HistoryMetric = .cpuTemperature

    init() {
        _viewModel = StateObject(wrappedValue: StatusDashboardViewModel(service: StatusService(baseURL: AppConfig.baseURL)))
    }

    init(viewModel: StatusDashboardViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                Group {
                    if let bundle = viewModel.bundle {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                headerSection(for: bundle)

                                if let error = viewModel.errorMessage {
                                    ErrorBanner(text: error)
                                }

                                MetricsGrid(snapshot: bundle.snapshot)

                                if bundle.history.enabled {
                                    HistorySection(history: bundle.history, selectedMetric: $selectedMetric)
                                }

                                ServicesSection(services: bundle.snapshot.services)

                                ShellySection(
                                    payload: bundle.shelly,
                                    isProcessing: { viewModel.isShellyOperationInProgress(for: $0) },
                                    controlError: { viewModel.shellyError(for: $0) },
                                    onToggle: { device in
                                        await viewModel.toggleShellyDevice(device)
                                    }
                                )
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 24)
                        }
                        .refreshable { await viewModel.manualRefresh() }
                    } else {
                        placeholderView
                    }
                }
            }
            .navigationTitle("Panel Raspberry Pi")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await viewModel.manualRefresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                    .accessibilityLabel("Odśwież dane")
                }
            }
        }
        .navigationViewStyle(.stack)
        .task { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    @ViewBuilder
    private func headerSection(for bundle: StatusBundle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Status Raspberry Pi")
                .font(.title)
                .fontWeight(.bold)

            if let lastUpdate = viewModel.lastUpdate {
                Label {
                    Text("Ostatnia aktualizacja: \(Formatters.fullDate.string(from: lastUpdate)) (\(Text(Formatters.relativeFormatter.localizedString(for: lastUpdate, relativeTo: Date())).italic()))")
                } icon: {
                    Image(systemName: "clock.arrow.2.circlepath")
                        .foregroundColor(.accentColor)
                }
                .font(.subheadline)
                .foregroundStyle(.primary)
            } else if viewModel.isLoading {
                Label("Ładowanie pierwszych danych…", systemImage: "clock.arrow.2.circlepath")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let generatedAt = bundle.snapshot.generatedAt {
                Label("Czas serwera: \(Formatters.time.string(from: generatedAt))", systemImage: "network")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else if let time = bundle.snapshot.time {
                Label("Czas serwera: \(time)", systemImage: "network")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Text("Automatyczne odświeżanie co \(bundle.streamInterval) s")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var placeholderView: some View {
        VStack(spacing: 20) {
            if viewModel.isLoading {
                ProgressView("Ładowanie danych…")
                    .progressViewStyle(.circular)
                    .tint(.accentColor)
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text("Brak danych do wyświetlenia")
                    .font(.headline)

                Text(viewModel.errorMessage ?? "Połącz się z Raspberry Pi, aby zobaczyć aktualny stan urządzenia.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                Button {
                    Task { await viewModel.manualRefresh() }
                } label: {
                    Label("Spróbuj ponownie", systemImage: "arrow.clockwise")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.accentColor.opacity(0.1)))
                }
            }
        }
        .padding()
    }
}

private struct MetricsGrid: View {
    let snapshot: StatusSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Kluczowe metryki", systemImage: "chart.bar")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                MetricCard(title: "Temperatura CPU", value: snapshot.cpuTemperature ?? "Brak danych", systemImage: "thermometer.medium", tint: .red)
                MetricCard(title: "Pamięć RAM", value: snapshot.memoryUsage ?? "Brak danych", systemImage: "memorychip", tint: .blue)
                MetricCard(title: "Miejsce na dysku", value: snapshot.diskUsage ?? "Brak danych", systemImage: "internaldrive", tint: .teal)
                MetricCard(title: "Obciążenie", value: snapshot.systemLoad ?? "Brak danych", systemImage: "gauge", tint: .orange)
                MetricCard(title: "Czas działania", value: snapshot.uptime ?? "Brak danych", systemImage: "clock", tint: .purple)
            }
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemBackground)))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(.quaternaryLabel), lineWidth: 0.6)
        )
    }
}

private struct HistorySection: View {
    let history: HistoryPayload
    @Binding var selectedMetric: HistoryMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Historia metryk", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)

            if history.isAvailable {
                Picker("Metryka", selection: $selectedMetric) {
                    ForEach(HistoryMetric.allCases) { metric in
                        Label(metric.title, systemImage: metric.symbolName)
                            .tag(metric)
                    }
                }
                .pickerStyle(.segmented)

                HistoryChartView(entries: history.entries, metric: selectedMetric)
                    .frame(height: 220)

                if let latest = history.entries.last,
                   let label = selectedMetric.formattedLabel(from: latest) {
                    Text("Ostatnia wartość: \(label)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Historia została wyłączona lub nie zawiera jeszcze danych.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemBackground)))
    }
}

private struct HistoryChartView: View {
    struct DataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    let entries: [HistoryEntry]
    let metric: HistoryMetric

    private var points: [DataPoint] {
        entries.compactMap { entry -> DataPoint? in
            guard let date = entry.generatedAt ?? Formatters.historyFallbackDate(from: entry.time),
                  let value = metric.numericValue(from: entry) else {
                return nil
            }
            return DataPoint(date: date, value: value)
        }
        .sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if points.count >= 2 {
                GeometryReader { geometry in
                    let normalized = normalizedPoints(in: geometry.size)

                    ZStack {
                        areaPath(from: normalized, in: geometry.size)
                            .fill(metric.accentColor.opacity(0.18))

                        linePath(from: normalized)
                            .stroke(metric.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                        ForEach(Array(normalized.enumerated()), id: \.offset) { element in
                            Circle()
                                .fill(metric.accentColor)
                                .frame(width: 6, height: 6)
                                .position(element.element)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: 180)

                if let first = points.first, let last = points.last {
                    HStack {
                        Text(Formatters.chartAxis.string(from: first.date))
                        Spacer()
                        Text(Formatters.chartAxis.string(from: last.date))
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            } else {
                Text("Za mało danych, aby narysować wykres dla tej metryki.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard !points.isEmpty else { return [] }

        let minValue = points.map(\.value).min() ?? 0
        let maxValue = points.map(\.value).max() ?? minValue
        let valueRange = max(maxValue - minValue, 0.001)

        guard let firstDate = points.first?.date else { return [] }
        let lastDate = points.last?.date ?? firstDate
        let timeRange = max(lastDate.timeIntervalSince(firstDate), 1)

        return points.enumerated().map { index, point in
            let relativeX: CGFloat
            if timeRange == 0 {
                relativeX = points.count > 1
                    ? CGFloat(index) / CGFloat(points.count - 1)
                    : 0
            } else {
                relativeX = CGFloat(point.date.timeIntervalSince(firstDate) / timeRange)
            }

            let relativeY: CGFloat
            if valueRange == 0 {
                relativeY = 0.5
            } else {
                relativeY = CGFloat((point.value - minValue) / valueRange)
            }

            let x = relativeX * size.width
            let y = size.height * (1 - relativeY)
            return CGPoint(x: x, y: y)
        }
    }

    private func linePath(from points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    private func areaPath(from points: [CGPoint], in size: CGSize) -> Path {
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: CGPoint(x: first.x, y: size.height))
        path.addLine(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.closeSubpath()
        return path
    }
}

private struct ServicesSection: View {
    let services: [ServiceStatus]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Usługi systemowe", systemImage: "server.rack")
                .font(.headline)

            if services.isEmpty {
                Text("Brak skonfigurowanych usług do monitorowania.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(services) { service in
                    ServiceRow(service: service)

                    if service.id != services.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemBackground)))
    }
}

private struct ServiceRow: View {
    let service: ServiceStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(service.label)
                        .font(.subheadline.weight(.semibold))
                    Text(service.service)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                StatusBadge(text: service.status, color: service.statusColor)
            }

            if let details = service.details, !details.isEmpty {
                Text(details)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct ShellySection: View {
    let payload: ShellyPayload
    let isProcessing: (ShellyDevice.ID) -> Bool
    let controlError: (ShellyDevice.ID) -> String?
    let onToggle: (ShellyDevice) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Urządzenia Shelly", systemImage: "bolt.horizontal.circle")
                .font(.headline)

            if payload.configError {
                WarningBox(text: "Wykryto problem w konfiguracji modułu Shelly. Sprawdź plik config/shelly.php na serwerze.")
            }

            if let message = payload.message {
                WarningBox(text: message)
            } else if payload.hasErrors {
                WarningBox(text: "Niektóre urządzenia zwróciły błędy. Szczegóły znajdziesz poniżej.", style: .caution)
            }

            if payload.devices.isEmpty {
                Text("Brak skonfigurowanych urządzeń Shelly.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(payload.devices) { device in
                    ShellyRow(
                        device: device,
                        isProcessing: isProcessing(device.id),
                        controlError: controlError(device.id),
                        onToggle: {
                            await onToggle(device)
                        }
                    )

                    if device.id != payload.devices.last?.id {
                        Divider()
                    }
                }
            }

            Text("Zmiany stanu są wysyłane bezpośrednio do urządzeń Shelly – dane zostaną automatycznie odświeżone.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemBackground)))
    }
}

private struct ShellyRow: View {
    let device: ShellyDevice
    let isProcessing: Bool
    let controlError: String?
    let onToggle: () async -> Void

    private var canControl: Bool {
        device.allowsControl && device.ok && (device.error?.isEmpty ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.label)
                        .font(.subheadline.weight(.semibold))
                    Text(device.description ?? (device.isOn ? "Włączone" : "Wyłączone"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                StatusBadge(text: device.ok ? "OK" : "Błąd", color: device.ok ? .green : .orange)
            }

            if let error = device.error, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            if device.allowsControl {
                HStack {
                    Label(device.isOn ? "Włączone" : "Wyłączone", systemImage: device.isOn ? "power.circle.fill" : "power.circle")
                        .font(.caption)
                        .foregroundColor(device.isOn ? .green : .secondary)

                    Spacer()

                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                            .tint(.accentColor)
                    } else {
                        Button {
                            Task { await onToggle() }
                        } label: {
                            Label(
                                device.isOn ? "Wyłącz" : "Włącz",
                                systemImage: device.isOn ? "power.circle.fill" : "power.circle"
                            )
                            .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canControl)
                    }
                }
            } else {
                Text("Sterowanie tym urządzeniem nie jest dostępne.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let controlError, !controlError.isEmpty {
                Text(controlError)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
}

private struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.15)))
            .foregroundColor(color)
    }
}

private struct ErrorBanner: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
                .imageScale(.large)

            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.systemYellow).opacity(0.18)))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(.systemYellow).opacity(0.5), lineWidth: 1)
        )
    }
}

private struct WarningBox: View {
    enum Style {
        case warning
        case caution

        var color: Color {
            switch self {
            case .warning: return .yellow
            case .caution: return .orange
            }
        }
    }

    let text: String
    var style: Style = .warning

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .foregroundColor(style.color)
            Text(text)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(style.color.opacity(0.12)))
    }
}

private enum Formatters {
    static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let chartAxis: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let historyTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = .current
        return formatter
    }()

    static func historyFallbackDate(from timeLabel: String?) -> Date? {
        guard let timeLabel, !timeLabel.isEmpty,
              let timeDate = historyTime.date(from: timeLabel) else { return nil }

        let calendar = Calendar.current
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: Date())
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: timeDate)

        var merged = DateComponents()
        merged.year = dayComponents.year
        merged.month = dayComponents.month
        merged.day = dayComponents.day
        merged.hour = timeComponents.hour
        merged.minute = timeComponents.minute
        merged.second = timeComponents.second

        return calendar.date(from: merged)
    }
}

private extension HistoryMetric {
    var accentColor: Color {
        switch self {
        case .cpuTemperature:
            return .red
        case .memoryUsage:
            return .blue
        case .diskUsage:
            return .teal
        case .systemLoad:
            return .orange
        }
    }
}

private extension ServiceStatus {
    var statusColor: Color {
        if cssClass.contains("ok") { return .green }
        if cssClass.contains("error") { return .red }
        if cssClass.contains("warn") { return .orange }
        if cssClass.contains("off") { return .gray }
        return .secondary
    }
}

#Preview {
    ContentView(viewModel: StatusDashboardViewModel(
        service: StatusService(baseURL: AppConfig.baseURL),
        initialBundle: .preview
    ))
}
