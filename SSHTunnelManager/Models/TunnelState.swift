import Foundation
import Combine

enum TunnelStatus: String, Equatable {
    case disconnected = "Disconnected"
    case connecting = "Connecting"
    case connected = "Connected"
    case reconnecting = "Reconnecting"
}

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}

class TunnelState: ObservableObject, Identifiable {
    let id: UUID
    @Published var configuration: TunnelConfiguration
    @Published var status: TunnelStatus = .disconnected
    @Published var lastDisconnect: Date?
    @Published var reconnectAttempts: Int = 0
    @Published var connectedSince: Date?
    @Published var logs: [LogEntry] = []

    init(configuration: TunnelConfiguration) {
        self.id = configuration.id
        self.configuration = configuration
    }

    func addLog(_ message: String) {
        DispatchQueue.main.async {
            self.logs.append(LogEntry(timestamp: Date(), message: message))
            if self.logs.count > 200 {
                self.logs.removeFirst(self.logs.count - 200)
            }
        }
    }

    var lastDisconnectFormatted: String? {
        guard let date = lastDisconnect else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    func uptimeString(relativeTo now: Date) -> String? {
        guard let since = connectedSince else { return nil }
        let interval = now.timeIntervalSince(since)
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}
