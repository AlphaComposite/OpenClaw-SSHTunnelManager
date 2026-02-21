import SwiftUI

struct TunnelRowView: View {
    @ObservedObject var tunnel: TunnelState
    var tunnelManager: TunnelManager
    var onSelect: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(tunnel.configuration.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(tunnel.configuration.forwardingDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(tunnel.status.rawValue)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 72, alignment: .trailing)

            quickActionButton

            Button(action: onSelect) {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    @ViewBuilder
    private var quickActionButton: some View {
        switch tunnel.status {
        case .disconnected:
            Button(action: { tunnelManager.connect(tunnel) }) {
                Image(systemName: "play.circle.fill")
                    .foregroundColor(.green)
            }
            .buttonStyle(.borderless)
            .help("Connect")

        case .connected:
            Button(action: { tunnelManager.disconnect(tunnel) }) {
                Image(systemName: "stop.circle.fill")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .help("Disconnect")

        case .connecting, .reconnecting:
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)
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
