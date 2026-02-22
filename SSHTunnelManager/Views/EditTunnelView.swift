import SwiftUI
import AppKit

struct EditTunnelView: View {
    @ObservedObject var tunnelManager: TunnelManager
    var existingConfig: TunnelConfiguration?
    var onDismiss: () -> Void
    var onBulkImported: (() -> Void)?

    @State private var name = ""
    @State private var sshUser = ""
    @State private var sshHost = ""
    @State private var sshPort = "22"
    @State private var localPort = ""
    @State private var remoteHost = "127.0.0.1"
    @State private var remotePort = ""
    @State private var sshKeyPath = ""
    @State private var autoReconnect = true
    @State private var serverAliveInterval = "15"

    @State private var showPrefillBanner = false
    @State private var prefillSnapshot: FieldSnapshot?

    private struct FieldSnapshot {
        let name, sshUser, sshHost, sshPort, localPort, remoteHost, remotePort, sshKeyPath: String
    }

    private var isEditing: Bool { existingConfig != nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if showPrefillBanner {
                prefillBannerView
                Divider()
            }
            formContent
        }
        .onAppear {
            populateFields()
            tryPrefillFromClipboard()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("Cancel") { onDismiss() }
                .buttonStyle(.borderless)

            Spacer()

            Text(isEditing ? "Edit Tunnel" : "New Tunnel")
                .font(.headline)

            Spacer()

            Button("Save") { save() }
                .buttonStyle(.borderless)
                .fontWeight(.medium)
                .disabled(!isValid)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Form

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                formSection("General") {
                    formField("Name", text: $name, placeholder: "My Tunnel")
                }

                formSection("SSH Connection") {
                    HStack(spacing: 8) {
                        formField("User", text: $sshUser, placeholder: "root")
                        formField("Host", text: $sshHost, placeholder: "192.168.1.1")
                    }
                    HStack(spacing: 8) {
                        formField("SSH Port", text: $sshPort, placeholder: "22")
                            .frame(width: 80)
                        formField("Key Path", text: $sshKeyPath, placeholder: "~/.ssh/id_rsa (optional)")
                    }
                }

                formSection("Port Forwarding") {
                    HStack(spacing: 8) {
                        formField("Local Port", text: $localPort, placeholder: "8080")
                        formField("Remote Host", text: $remoteHost, placeholder: "127.0.0.1")
                        formField("Remote Port", text: $remotePort, placeholder: "8080")
                    }
                }

                formSection("Options") {
                    Toggle("Auto-Reconnect", isOn: $autoReconnect)
                        .toggleStyle(.switch)
                        .controlSize(.small)

                    HStack {
                        Text("Keep-Alive Interval")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("15", text: $serverAliveInterval)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 50)
                        Text("seconds")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)
        }
    }

    private func formSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            content()
        }
    }

    private func formField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
        }
    }

    // MARK: - Validation

    private var isValid: Bool {
        !sshUser.trimmingCharacters(in: .whitespaces).isEmpty &&
        !sshHost.trimmingCharacters(in: .whitespaces).isEmpty &&
        Int(sshPort) != nil &&
        Int(localPort) != nil && Int(localPort)! > 0 &&
        !remoteHost.trimmingCharacters(in: .whitespaces).isEmpty &&
        Int(remotePort) != nil && Int(remotePort)! > 0
    }

    // MARK: - Clipboard Prefill

    private var prefillBannerView: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .foregroundColor(.accentColor)
            Text("Prefilled from clipboard")
            Spacer()
            Button("Undo") {
                if let snap = prefillSnapshot {
                    name = snap.name
                    sshUser = snap.sshUser
                    sshHost = snap.sshHost
                    sshPort = snap.sshPort
                    localPort = snap.localPort
                    remoteHost = snap.remoteHost
                    remotePort = snap.remotePort
                    sshKeyPath = snap.sshKeyPath
                }
                showPrefillBanner = false
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.08))
    }

    private func tryPrefillFromClipboard() {
        guard existingConfig == nil else { return }
        guard let raw = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return }

        let parsed = SSHCommandParser.parse(raw)
        guard !parsed.isEmpty else { return }

        if parsed.count > 1 {
            // Multiple tunnels: bulk-import all and dismiss
            for tunnel in parsed {
                tunnelManager.addTunnel(tunnel.toConfiguration())
            }
            onBulkImported?() ?? onDismiss()
            return
        }

        // Single tunnel: prefill the form
        let t = parsed[0]
        prefillSnapshot = FieldSnapshot(
            name: name, sshUser: sshUser, sshHost: sshHost,
            sshPort: sshPort, localPort: localPort,
            remoteHost: remoteHost, remotePort: remotePort,
            sshKeyPath: sshKeyPath
        )

        sshUser = t.sshUser
        sshHost = t.sshHost
        if let p = t.sshPort { sshPort = String(p) }
        localPort = String(t.localPort)
        remoteHost = t.remoteHost
        remotePort = String(t.remotePort)
        if let key = t.keyPath { sshKeyPath = key }
        if name.isEmpty { name = t.suggestedName }

        showPrefillBanner = true
    }

    // MARK: - Actions

    private func populateFields() {
        guard let config = existingConfig else { return }
        name = config.name
        sshUser = config.sshUser
        sshHost = config.sshHost
        sshPort = "\(config.sshPort)"
        localPort = "\(config.localPort)"
        remoteHost = config.remoteHost
        remotePort = "\(config.remotePort)"
        sshKeyPath = config.sshKeyPath
        autoReconnect = config.autoReconnect
        serverAliveInterval = "\(config.serverAliveInterval)"
    }

    private func save() {
        var config = existingConfig ?? TunnelConfiguration()
        config.name = name.trimmingCharacters(in: .whitespaces)
        config.sshUser = sshUser.trimmingCharacters(in: .whitespaces)
        config.sshHost = sshHost.trimmingCharacters(in: .whitespaces)
        config.sshPort = Int(sshPort) ?? 22
        config.localPort = Int(localPort) ?? 0
        config.remoteHost = remoteHost.trimmingCharacters(in: .whitespaces)
        config.remotePort = Int(remotePort) ?? 0
        config.sshKeyPath = sshKeyPath.trimmingCharacters(in: .whitespaces)
        config.autoReconnect = autoReconnect
        config.serverAliveInterval = Int(serverAliveInterval) ?? 15

        if isEditing {
            if let tunnel = tunnelManager.tunnels.first(where: { $0.id == config.id }) {
                tunnelManager.updateTunnel(tunnel, with: config)
            }
        } else {
            tunnelManager.addTunnel(config)
        }

        onDismiss()
    }
}
