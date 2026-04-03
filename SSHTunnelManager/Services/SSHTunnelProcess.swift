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
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")

        let sshArguments = makeSSHArguments()
        proc.arguments = ["-c", makeWrapperScript(parentPID: getpid()), "ssh-wrapper"] + sshArguments

        var environment = ProcessInfo.processInfo.environment
        environment["SSH_AUTH_SOCK"] = nil
        environment["SSH_AGENT_PID"] = nil
        environment["SSH_ASKPASS_REQUIRE"] = "never"
        proc.environment = environment

        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = FileHandle.nullDevice

        let errPipe = Pipe()
        proc.standardError = errPipe

        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }

            guard let str = String(data: data, encoding: .utf8) else { return }
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            self?.onOutput?(trimmed)
        }

        proc.terminationHandler = { [weak self] process in
            errPipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                self?.onTermination?(process.terminationStatus)
            }
        }

        self.errorPipe = errPipe
        self.process = proc

        try proc.run()
    }

    private func makeSSHArguments() -> [String] {
        var arguments: [String] = [
            "-N",
            "-n",
            "-T",
            "-L", "\(configuration.localPort):\(configuration.remoteHost):\(configuration.remotePort)",
            "-o", "ServerAliveInterval=\(configuration.serverAliveInterval)",
            "-o", "ServerAliveCountMax=3",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=10",
            "-o", "BatchMode=yes",
            "-o", "IdentityAgent=none",
        ]

        if configuration.sshPort != 22 {
            arguments += ["-p", "\(configuration.sshPort)"]
        }

        if !configuration.sshKeyPath.isEmpty {
            let expandedPath = NSString(string: configuration.sshKeyPath).expandingTildeInPath
            arguments += ["-i", expandedPath, "-o", "IdentitiesOnly=yes"]
        }

        arguments.append("\(configuration.sshUser)@\(configuration.sshHost)")
        return arguments
    }

    private func makeWrapperScript(parentPID: Int32) -> String {
        """
        original_parent_pid=\(parentPID)
        parent_pid=\(parentPID)
        wrapper_pid=$$
        child_pid=

        kill_tree() {
          signal_name="$1"
          target_pid="$2"
          if [ -z "$target_pid" ]; then
            return
          fi

          for descendant_pid in $(pgrep -P "$target_pid" 2>/dev/null); do
            kill_tree "$signal_name" "$descendant_pid"
          done

          kill -"$signal_name" "$target_pid" 2>/dev/null || true
        }

        cleanup_child_tree() {
          if [ -z "$child_pid" ]; then
            return
          fi

          # Verify we're still the original wrapper process
          current_ppid=$(ps -o ppid= -p "$wrapper_pid" 2>/dev/null | tr -d '[:space:]')
          if [ "$current_ppid" != "$original_parent_pid" ] && [ -n "$current_ppid" ]; then
            # Our PID has been recycled; don't signal potentially unrelated processes
            return
          fi

          kill_tree TERM "$child_pid"
          sleep 1

          # Re-check before SIGKILL
          current_ppid=$(ps -o ppid= -p "$wrapper_pid" 2>/dev/null | tr -d '[:space:]')
          if [ "$current_ppid" != "$original_parent_pid" ] && [ -n "$current_ppid" ]; then
            return
          fi

          kill_tree KILL "$child_pid"
        }

        trap 'cleanup_child_tree; exit 0' TERM INT HUP

        /usr/bin/ssh "$@" &
        child_pid=$!

        while kill -0 "$child_pid" 2>/dev/null; do
          # Check if original parent is still alive
          if ! kill -0 "$parent_pid" 2>/dev/null; then
            cleanup_child_tree
            wait "$child_pid" 2>/dev/null || true
            exit 0
          fi

          # Verify our wrapper PPID hasn't changed (PID recycling check)
          current_ppid=$(ps -o ppid= -p "$wrapper_pid" 2>/dev/null | tr -d '[:space:]')
          if [ -n "$current_ppid" ] && [ "$current_ppid" != "$original_parent_pid" ]; then
            # Our PID was recycled; exit without cleanup
            exit 0
          fi

          sleep 1
        done

        wait "$child_pid"
        exit $?
        """
    }

    func stop() {
        guard let proc = process, proc.isRunning else { return }
        let wrapperPID = proc.processIdentifier
        let parentPID = getpid()

        signalDescendants(of: wrapperPID, signal: SIGTERM)
        proc.terminate()

        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [weak self] in
            // Verify the wrapper PID hasn't been recycled before sending SIGKILL
            guard self?.isProcessStillChild(pid: wrapperPID, expectedParent: parentPID) == true else {
                return
            }

            self?.signalDescendants(of: wrapperPID, signal: SIGKILL)
            if self?.process?.isRunning == true {
                self?.process?.interrupt()
            }
            // SIGKILL fallback for truly hung processes (e.g. network wedge)
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let pid = self?.process?.processIdentifier, pid != 0,
                      self?.process?.isRunning == true else { return }

                // Final check before SIGKILL
                if self?.isProcessStillChild(pid: pid, expectedParent: parentPID) == true {
                    kill(pid, SIGKILL)
                }
            }
        }
    }

    private func signalDescendants(of parentPID: Int32, signal: Int32) {
        for childPID in childProcessIDs(of: parentPID) {
            signalProcessTree(rootPID: childPID, signal: signal)
        }
    }

    private func signalProcessTree(rootPID: Int32, signal: Int32) {
        for childPID in childProcessIDs(of: rootPID) {
            signalProcessTree(rootPID: childPID, signal: signal)
        }

        guard rootPID > 0 else { return }
        kill(rootPID, signal)
    }

    private func childProcessIDs(of parentPID: Int32) -> [Int32] {
        let proc = Process()
        let pipe = Pipe()

        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        proc.arguments = ["-P", "\(parentPID)"]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return []
        }

        guard proc.terminationStatus == 0 else { return [] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32($0) }
    }

    private func isProcessStillChild(pid: Int32, expectedParent: Int32) -> Bool {
        let proc = Process()
        let pipe = Pipe()

        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-o", "ppid=", "-p", "\(pid)"]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return false
        }

        guard proc.terminationStatus == 0 else { return false }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return false }

        let ppid = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return ppid == "\(expectedParent)"
    }

    deinit {
        stop()
    }
}