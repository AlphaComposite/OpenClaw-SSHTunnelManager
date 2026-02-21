import SwiftUI

struct TunnelDetailView: View {
    @ObservedObject var tunnel: TunnelState
    var tunnelManager: TunnelManager
    var onBack: () -> Void
    var onEdit: () -> Void

    @State private var now = Date()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            statusSection
            Divider()
            actionButtons
            Divider()
            logSection
        }
        .onReceive(timer) { now = $0 }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
            }
            .buttonStyle(.borderless)

            Spacer()

            Text(tunnel.configuration.displayName)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil.circle")
            }
            .buttonStyle(.borderless)
            .help("Edit tunnel configuration")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Status

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
                Text(tunnel.status.rawValue)
                    .font(.title3)
                    .fontWeight(.medium)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                detailRow("Local", "localhost:\(tunnel.configuration.localPort)")
                detailRow("Remote", "\(tunnel.configuration.sshUser)@\(tunnel.configuration.sshHost):\(tunnel.configuration.remotePort)")

                if let uptime = tunnel.uptimeString(relativeTo: now) {
                    detailRow("Uptime", uptime)
                }

                if let lastDisconnect = tunnel.lastDisconnectFormatted {
                    detailRow("Last Disconnect", lastDisconnect)
                }

                if tunnel.reconnectAttempts > 0 {
                    detailRow("Reconnect Attempts", "\(tunnel.reconnectAttempts)")
                }
            }
            .font(.caption)
        }
        .padding(16)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
            Spacer()
        }
    }

    // MARK: - Actions

    private var actionButtons: some View {
        HStack(spacing: 10) {
            switch tunnel.status {
            case .disconnected:
                Button("Connect") { tunnelManager.connect(tunnel) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

            case .connected:
                Button("Disconnect") { tunnelManager.disconnect(tunnel) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button("Reconnect") { tunnelManager.reconnect(tunnel) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

            case .connecting, .reconnecting:
                Button("Cancel") { tunnelManager.disconnect(tunnel) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Spacer()

            Button(role: .destructive, action: {
                tunnelManager.removeTunnel(tunnel)
                onBack()
            }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Delete this tunnel")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Log

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Activity Log")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Clear") {
                    tunnel.logs.removeAll()
                }
                .buttonStyle(.borderless)
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(tunnel.logs) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Text(entry.formattedTimestamp)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 55, alignment: .leading)
                                Text(entry.message)
                                    .font(.system(.caption2, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
                .onChange(of: tunnel.logs.count) { _ in
                    if let last = tunnel.logs.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var statusColor: Color {
        switch tunnel.status {
        case .connected: return .green
        case .connecting: return .yellow
        case .reconnecting: return .orange
        case .disconnected: return .red
        }
    }
}
