import Foundation

struct StatusBundle: Decodable, Equatable {
    let generatedAt: Date?
    let streamInterval: Int
    let snapshot: StatusSnapshot
    let history: HistoryPayload
    let shelly: ShellyPayload

    var serverDate: Date? {
        snapshot.generatedAt ?? generatedAt
    }
}

struct StatusSnapshot: Decodable, Equatable {
    let time: String?
    let generatedAt: Date?
    let cpuTemperature: String?
    let systemLoad: String?
    let uptime: String?
    let memoryUsage: String?
    let diskUsage: String?
    let services: [ServiceStatus]
}

struct ServiceStatus: Decodable, Identifiable, Equatable {
    let id: String
    let label: String
    let service: String
    let status: String
    let cssClass: String
    let details: String?

    init(id: String, label: String, service: String, status: String, cssClass: String, details: String?) {
        self.id = id
        self.label = label
        self.service = service
        self.status = status
        self.cssClass = cssClass
        self.details = details
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let label = try container.decode(String.self, forKey: .label)
        let service = try container.decode(String.self, forKey: .service)
        let status = try container.decode(String.self, forKey: .status)
        let cssClass = (try? container.decode(String.self, forKey: .cssClass)) ?? "status-unknown"
        let details = try? container.decodeIfPresent(String.self, forKey: .details)

        self.label = label
        self.service = service
        self.status = status
        self.cssClass = cssClass
        self.details = details
        self.id = service.isEmpty ? label : service
    }

    private enum CodingKeys: String, CodingKey {
        case label
        case service
        case status
        case cssClass = "class"
        case details
    }
}

struct HistoryPayload: Decodable, Equatable {
    let generatedAt: Date?
    let enabled: Bool
    let maxEntries: Int
    let maxAge: Int?
    let count: Int
    let limit: Int?
    let entries: [HistoryEntry]

    var isAvailable: Bool {
        enabled && !entries.isEmpty
    }
}

struct HistoryEntry: Decodable, Identifiable, Equatable {
    struct TemperatureMetric: Decodable, Equatable {
        let value: Double?
        let label: String?
    }

    struct PercentageMetric: Decodable, Equatable {
        let percentage: Double?
        let label: String?
    }

    struct SystemLoadMetric: Decodable, Equatable {
        let one: Double?
        let five: Double?
        let fifteen: Double?
        let label: String?
    }

    let generatedAt: Date?
    let time: String?
    let cpuTemperature: TemperatureMetric
    let memoryUsage: PercentageMetric
    let diskUsage: PercentageMetric
    let systemLoad: SystemLoadMetric

    var id: String {
        if let generatedAt {
            return String(generatedAt.timeIntervalSince1970)
        }
        if let time {
            return time
        }
        return UUID().uuidString
    }
}

struct ShellyPayload: Decodable, Equatable {
    let generatedAt: Date?
    let count: Int
    let hasErrors: Bool
    let devices: [ShellyDevice]
    let configError: Bool
    let httpStatus: Int?
    let error: String?
    let message: String?
}

struct ShellyDevice: Decodable, Identifiable, Equatable {
    struct Control: Decodable, Equatable {
        let turnOn: URL?
        let turnOff: URL?
        let toggle: URL?

        enum CodingKeys: String, CodingKey {
            case turnOn = "turn_on"
            case turnOff = "turn_off"
            case toggle
        }
    }

    let id: String
    let label: String
    let state: String
    let description: String?
    let error: String?
    let ok: Bool
    let control: Control?
    let supportsControl: Bool?

    var isOn: Bool {
        state.lowercased() == "on"
    }

    var allowsControl: Bool {
        if let supportsControl {
            return supportsControl
        }

        if let control {
            return control.toggle != nil || (control.turnOn != nil && control.turnOff != nil)
        }

        return true
    }
}

enum HistoryMetric: String, CaseIterable, Identifiable {
    case cpuTemperature
    case memoryUsage
    case diskUsage
    case systemLoad

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpuTemperature:
            return "Temperatura"
        case .memoryUsage:
            return "Pamięć"
        case .diskUsage:
            return "Dysk"
        case .systemLoad:
            return "Obciążenie"
        }
    }

    var symbolName: String {
        switch self {
        case .cpuTemperature:
            return "thermometer.medium"
        case .memoryUsage:
            return "memorychip"
        case .diskUsage:
            return "internaldrive"
        case .systemLoad:
            return "gauge"
        }
    }

    func numericValue(from entry: HistoryEntry) -> Double? {
        switch self {
        case .cpuTemperature:
            return entry.cpuTemperature.value
        case .memoryUsage:
            return entry.memoryUsage.percentage
        case .diskUsage:
            return entry.diskUsage.percentage
        case .systemLoad:
            return entry.systemLoad.one
        }
    }

    func formattedLabel(from entry: HistoryEntry) -> String? {
        switch self {
        case .cpuTemperature:
            return entry.cpuTemperature.label
        case .memoryUsage:
            return entry.memoryUsage.label
        case .diskUsage:
            return entry.diskUsage.label
        case .systemLoad:
            return entry.systemLoad.label
        }
    }
}

extension StatusBundle {
    static var preview: StatusBundle {
        let now = Date()
        let services = [
            ServiceStatus(id: "nginx.service", label: "Nginx", service: "nginx.service", status: "Aktywna", cssClass: "status-ok", details: nil),
            ServiceStatus(id: "php-fpm.service", label: "PHP-FPM", service: "php8.2-fpm.service", status: "Aktywna", cssClass: "status-ok", details: nil),
            ServiceStatus(id: "mosquitto.service", label: "MQTT", service: "mosquitto.service", status: "Błąd", cssClass: "status-error", details: "Process exited")
        ]

        let historyEntries: [HistoryEntry] = (0..<24).compactMap { index in
            let date = Calendar.current.date(byAdding: .minute, value: -(23 - index) * 30, to: now)
            return HistoryEntry(
                generatedAt: date,
                time: DateFormatter.localizedString(from: date ?? now, dateStyle: .none, timeStyle: .short),
                cpuTemperature: .init(value: Double.random(in: 40...65), label: String(format: "%.1f °C", Double.random(in: 40...65))),
                memoryUsage: .init(percentage: Double.random(in: 20...80), label: "3.2 / 8 GB"),
                diskUsage: .init(percentage: Double.random(in: 40...70), label: "29 / 64 GB"),
                systemLoad: .init(one: Double.random(in: 0.4...1.6), five: Double.random(in: 0.3...1.1), fifteen: Double.random(in: 0.2...0.8), label: "0.65, 0.55, 0.40")
            )
        }

        let snapshot = StatusSnapshot(
            time: DateFormatter.localizedString(from: now, dateStyle: .none, timeStyle: .medium),
            generatedAt: now,
            cpuTemperature: "52.1 °C",
            systemLoad: "0.62, 0.55, 0.48",
            uptime: "2 d 4 h 11 min",
            memoryUsage: "3.4 / 8 GB (42%)",
            diskUsage: "29 / 64 GB (45%)",
            services: services
        )

        let history = HistoryPayload(
            generatedAt: now,
            enabled: true,
            maxEntries: 360,
            maxAge: nil,
            count: historyEntries.count,
            limit: 120,
            entries: historyEntries
        )

        let shelly = ShellyPayload(
            generatedAt: now,
            count: 2,
            hasErrors: false,
            devices: [
                ShellyDevice(
                    id: "boiler",
                    label: "Boiler",
                    state: "on",
                    description: "Włączone",
                    error: nil,
                    ok: true,
                    control: .init(
                        turnOn: URL(string: "https://example.com/boiler/on"),
                        turnOff: URL(string: "https://example.com/boiler/off"),
                        toggle: nil
                    ),
                    supportsControl: true
                ),
                ShellyDevice(
                    id: "gate",
                    label: "Brama",
                    state: "off",
                    description: "Wyłączone",
                    error: nil,
                    ok: true,
                    control: .init(
                        turnOn: URL(string: "https://example.com/gate/on"),
                        turnOff: URL(string: "https://example.com/gate/off"),
                        toggle: nil
                    ),
                    supportsControl: true
                )
            ],
            configError: false,
            httpStatus: 200,
            error: nil,
            message: nil
        )

        return StatusBundle(
            generatedAt: now,
            streamInterval: 5,
            snapshot: snapshot,
            history: history,
            shelly: shelly
        )
    }
}
