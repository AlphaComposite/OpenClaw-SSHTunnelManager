import Foundation

enum SSHTunnelError: LocalizedError {
    case alreadyRunning
    case processStartFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Tunnel is already running"
        case .processStartFailed(let reason):
            return "Failed to start SSH process: \(reason)"
        }
    }
}

class SSHTunnelProcess {
    private var process: Process?
    private let configuration: TunnelConfiguration
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?

    var onTermination: ((Int32) -> Void)?
    var onOutput: ((String) -> Void)?

    var isRunning: Bool {
        process?.isRunning ?? false
    }

    init(configuration: TunnelConfiguration) {
        self.configuration = configuration
    }

    func start() throws {
        guard process == nil || !(process?.isRunning ?? false) else {
            throw SSHTunnelError.alreadyRunning
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")

        var arguments: [String] = [
            "-N",
            "-L", "\(configuration.localPort):\(configuration.remoteHost):\(configuration.remotePort)",
            "-o", "ServerAliveInterval=\(configuration.serverAliveInterval)",
            "-o", "ServerAliveCountMax=3",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=10",
            "-o", "BatchMode=yes",
        ]

        if configuration.sshPort != 22 {
            arguments += ["-p", "\(configuration.sshPort)"]
        }

        if !configuration.sshKeyPath.isEmpty {
            let expandedPath = NSString(string: configuration.sshKeyPath).expandingTildeInPath
            arguments += ["-i", expandedPath]
        }

        arguments.append("\(configuration.sshUser)@\(configuration.sshHost)")

        proc.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    self?.onOutput?(trimmed)
                }
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    self?.onOutput?(trimmed)
                }
            }
        }

        proc.terminationHandler = { [weak self] process in
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                self?.onTermination?(process.terminationStatus)
            }
        }

        self.outputPipe = outPipe
        self.errorPipe = errPipe
        self.process = proc

        try proc.run()
    }

    func stop() {
        guard let proc = process, proc.isRunning else { return }
        proc.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [weak self] in
            if self?.process?.isRunning == true {
                self?.process?.interrupt()
            }
        }
    }

    deinit {
        stop()
    }
}
