import Foundation

struct ParsedSSHTunnel {
    var sshUser: String
    var sshHost: String
    var sshPort: Int?
    var keyPath: String?
    var localPort: Int
    var remoteHost: String
    var remotePort: Int

    var suggestedName: String {
        if remotePort == 18789 { return "OpenClaw" }
        return "Tunnel :\(localPort)"
    }

    func toConfiguration() -> TunnelConfiguration {
        TunnelConfiguration(
            name: suggestedName,
            sshUser: sshUser,
            sshHost: sshHost,
            sshPort: sshPort ?? 22,
            localPort: localPort,
            remoteHost: remoteHost,
            remotePort: remotePort,
            sshKeyPath: keyPath ?? "",
            autoReconnect: true,
            serverAliveInterval: 15
        )
    }
}

enum SSHCommandParser {

    /// Parse an SSH command string into one or more tunnel definitions.
    /// Supports multiple -L flags in a single command.
    /// Returns an empty array if the string doesn't look like a valid SSH tunnel command.
    static func parse(_ text: String) -> [ParsedSSHTunnel] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\\n", with: " ")  // handle line continuations
            .replacingOccurrences(of: "\n", with: " ")

        // Must contain "ssh" somewhere
        guard trimmed.lowercased().contains("ssh") else { return [] }

        let tokens = trimmed
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        // Must have at least one -L
        guard tokens.contains("-L") else { return [] }

        // Extract user@host: last non-flag token containing '@' with no '='
        var userHost: (user: String, host: String)?
        for token in tokens.reversed() {
            if token.contains("@"), !token.hasPrefix("-"), !token.contains("=") {
                if let at = token.firstIndex(of: "@") {
                    let user = String(token[..<at])
                    let host = String(token[token.index(after: at)...])
                    if !user.isEmpty, !host.isEmpty {
                        userHost = (user, host)
                        break
                    }
                }
            }
        }

        guard let uh = userHost else { return [] }

        // Extract -p port (optional)
        var sshPort: Int?
        if let pIdx = tokens.firstIndex(of: "-p"), pIdx + 1 < tokens.count {
            sshPort = Int(tokens[pIdx + 1])
        }

        // Extract -i keypath (optional)
        var keyPath: String?
        if let iIdx = tokens.firstIndex(of: "-i"), iIdx + 1 < tokens.count {
            keyPath = tokens[iIdx + 1]
        }

        // Extract ALL -L arguments
        var forwards: [(local: Int, rHost: String, rPort: Int)] = []
        var i = 0
        while i < tokens.count {
            if tokens[i] == "-L", i + 1 < tokens.count {
                if let fwd = parseForwardArg(tokens[i + 1]) {
                    forwards.append(fwd)
                }
                i += 2
            } else {
                i += 1
            }
        }

        guard !forwards.isEmpty else { return [] }

        return forwards.map { fwd in
            ParsedSSHTunnel(
                sshUser: uh.user,
                sshHost: uh.host,
                sshPort: sshPort,
                keyPath: keyPath,
                localPort: fwd.local,
                remoteHost: fwd.rHost,
                remotePort: fwd.rPort
            )
        }
    }

    /// Parse the argument to -L: [bind_address:]port:host:hostport
    private static func parseForwardArg(_ arg: String) -> (local: Int, rHost: String, rPort: Int)? {
        let parts = arg.split(separator: ":").map(String.init)
        switch parts.count {
        case 3:
            // port:host:hostport
            guard let lp = Int(parts[0]), let rp = Int(parts[2]) else { return nil }
            return (lp, parts[1], rp)
        case 4:
            // bind_address:port:host:hostport
            guard let lp = Int(parts[1]), let rp = Int(parts[3]) else { return nil }
            return (lp, parts[2], rp)
        default:
            return nil
        }
    }
}
