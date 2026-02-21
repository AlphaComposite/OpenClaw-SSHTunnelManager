import SwiftUI

enum PopoverScreen: Equatable {
    case main
    case detail(UUID)
    case addTunnel
    case editTunnel(UUID)

    static func == (lhs: PopoverScreen, rhs: PopoverScreen) -> Bool {
        switch (lhs, rhs) {
        case (.main, .main): return true
        case (.addTunnel, .addTunnel): return true
        case (.detail(let a), .detail(let b)): return a == b
        case (.editTunnel(let a), .editTunnel(let b)): return a == b
        default: return false
        }
    }
}

struct StatusPopoverView: View {
    @ObservedObject var tunnelManager: TunnelManager
    @State private var screen: PopoverScreen = .main

    var body: some View {
        Group {
            switch screen {
            case .main:
                mainListView

            case .detail(let id):
                if let tunnel = tunnelManager.tunnels.first(where: { $0.id == id }) {
                    TunnelDetailView(
                        tunnel: tunnel,
                        tunnelManager: tunnelManager,
                        onBack: { screen = .main },
                        onEdit: { screen = .editTunnel(id) }
                    )
                } else {
                    mainListView
                }

            case .addTunnel:
                EditTunnelView(
                    tunnelManager: tunnelManager,
                    existingConfig: nil,
                    onDismiss: { screen = .main }
                )

            case .editTunnel(let id):
                if let tunnel = tunnelManager.tunnels.first(where: { $0.id == id }) {
                    EditTunnelView(
                        tunnelManager: tunnelManager,
                        existingConfig: tunnel.configuration,
                        onDismiss: { screen = .detail(id) }
                    )
                } else {
                    mainListView
                }
            }
        }
        .frame(width: 380, height: 480)
    }

    // MARK: - Main List

    private var mainListView: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if tunnelManager.tunnels.isEmpty {
                emptyState
            } else {
                tunnelList
            }

            Divider()
            footer
        }
    }

    private var header: some View {
        HStack {
            Text("SSH Tunnels")
                .font(.headline)
            Spacer()
            Button(action: { screen = .addTunnel }) {
                Image(systemName: "plus.circle")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .help("Add new tunnel")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "network")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("No tunnels configured")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button("Add Tunnel") {
                screen = .addTunnel
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tunnelList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(tunnelManager.tunnels) { tunnel in
                    TunnelRowView(
                        tunnel: tunnel,
                        tunnelManager: tunnelManager,
                        onSelect: { screen = .detail(tunnel.id) }
                    )
                    if tunnel.id != tunnelManager.tunnels.last?.id {
                        Divider().padding(.leading, 40)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Connect All") { tunnelManager.connectAll() }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(!tunnelManager.tunnels.contains { $0.status == .disconnected })

            Button("Disconnect All") { tunnelManager.disconnectAll() }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(!tunnelManager.tunnels.contains { $0.status != .disconnected })

            Spacer()

            Button(action: { NSApplication.shared.terminate(nil) }) {
                Image(systemName: "power")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Quit SSH Tunnel Manager")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
