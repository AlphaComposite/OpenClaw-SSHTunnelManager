import Foundation

struct TunnelConfiguration: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var name: String
    var sshUser: String
    var sshHost: String
    var sshPort: Int
    var localPort: Int
    var remoteHost: String
    var remotePort: Int
    var sshKeyPath: String
    var autoReconnect: Bool
    var serverAliveInterval: Int

    init(
        id: UUID = UUID(),
        name: String = "",
        sshUser: String = "",
        sshHost: String = "",
        sshPort: Int = 22,
        localPort: Int = 0,
        remoteHost: String = "127.0.0.1",
        remotePort: Int = 0,
        sshKeyPath: String = "",
        autoReconnect: Bool = true,
        serverAliveInterval: Int = 15
    ) {
        self.id = id
        self.name = name
        self.sshUser = sshUser
        self.sshHost = sshHost
        self.sshPort = sshPort
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.sshKeyPath = sshKeyPath
        self.autoReconnect = autoReconnect
        self.serverAliveInterval = serverAliveInterval
    }

    var displayName: String {
        name.isEmpty ? "\(sshUser)@\(sshHost):\(remotePort)" : name
    }

    var forwardingDescription: String {
        "localhost:\(localPort) → \(remoteHost):\(remotePort)"
    }
}
