import Foundation
import Combine

enum ConnectResult {
    case success
    case portConflict(existingTunnel: TunnelState)
}

class TunnelManager: ObservableObject {
    @Published var tunnels: [TunnelState] = []

    private var processes: [UUID: SSHTunnelProcess] = [:]
    private var reconnectTimers: [UUID: DispatchSourceTimer] = [:]
    private var healthCheckTimer: DispatchSourceTimer?
    private var tunnelCancellables = Set<AnyCancellable>()
    private var stoppingTunnelIDs = Set<UUID>()

    private let configKey = "SavedTunnelConfigurations"

    init() {
        loadConfigurations()
        startHealthCheck()
    }

    // MARK: - Configuration Persistence

    func loadConfigurations() {
        guard let data = UserDefaults.standard.data(forKey: configKey),
              let configs = try? JSONDecoder().decode([TunnelConfiguration].self, from: data) else {
            return
        }
        tunnels = configs.map { TunnelState(configuration: $0) }
        setupTunnelObservers()
    }

    func saveConfigurations() {
        let configs = tunnels.map { $0.configuration }
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }

    private func setupTunnelObservers() {
        tunnelCancellables.removeAll()
        for tunnel in tunnels {
            tunnel.objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &tunnelCancellables)
        }
    }

    // MARK: - Tunnel Management

    func addTunnel(_ config: TunnelConfiguration) {
        let state = TunnelState(configuration: config)
        tunnels.append(state)
        setupTunnelObservers()
        saveConfigurations()
    }

    func removeTunnel(_ tunnel: TunnelState) {
        disconnect(tunnel) { [weak self] in
            guard let self else { return }
            self.tunnels.removeAll { $0.id == tunnel.id }
            self.setupTunnelObservers()
            self.saveConfigurations()
        }
    }

    func updateTunnel(_ tunnel: TunnelState, with config: TunnelConfiguration) {
        let wasConnected = tunnel.status == .connected

        let applyUpdate = { [weak self] in
            guard let self else { return }
            tunnel.configuration = config
            self.saveConfigurations()
            if wasConnected {
                self.connect(tunnel)
            }
        }

        if tunnel.status != .disconnected {
            disconnect(tunnel, completion: applyUpdate)
        } else {
            applyUpdate()
        }
    }

    // MARK: - Connection Control

    @discardableResult
    func connect(_ tunnel: TunnelState) -> ConnectResult {
        guard tunnel.status == .disconnected else { return .success }
        guard !stoppingTunnelIDs.contains(tunnel.id) else {
            tunnel.addLog("Waiting for previous SSH process to stop...")
            return .success
        }

        // Check for active port conflict
        if let conflict = activeTunnelOnPort(tunnel.configuration.localPort, excluding: tunnel.id) {
            return .portConflict(existingTunnel: conflict)
        }

        tunnel.status = .connecting
        tunnel.reconnectAttempts = 0
        tunnel.addLog("Connecting to \(tunnel.configuration.sshUser)@\(tunnel.configuration.sshHost)...")
        objectWillChange.send()
        startSSHProcess(for: tunnel)
        return .success
    }

    /// Disconnect the conflicting tunnel and connect the new one.
    func switchTo(_ tunnel: TunnelState, from existing: TunnelState) {
        disconnect(existing) { [weak self] in
            self?.connect(tunnel)
        }
    }

    /// Returns an active (connected/connecting/reconnecting) tunnel on the given local port, if any.
    func activeTunnelOnPort(_ port: Int, excluding id: UUID) -> TunnelState? {
        tunnels.first { $0.id != id && $0.configuration.localPort == port && $0.status != .disconnected }
    }

    func disconnect(_ tunnel: TunnelState, completion: (() -> Void)? = nil) {
        cancelReconnectTimer(for: tunnel.id)

        let wasActive = tunnel.status != .disconnected
        tunnel.status = .disconnected
        tunnel.connectedSince = nil
        if wasActive {
            tunnel.addLog("Disconnected by user")
        }
        objectWillChange.send()

        guard let process = processes[tunnel.id] else {
            completion?()
            return
        }

        stoppingTunnelIDs.insert(tunnel.id)
        process.stop { [weak self] in
            self?.processes.removeValue(forKey: tunnel.id)
            self?.stoppingTunnelIDs.remove(tunnel.id)
            completion?()
        }
    }

    func reconnect(_ tunnel: TunnelState) {
        disconnect(tunnel) { [weak self] in
            self?.connect(tunnel)
        }
    }

    func connectAll() {
        for tunnel in tunnels where tunnel.status == .disconnected {
            connect(tunnel)
        }
    }

    func disconnectAll() {
        for tunnel in tunnels where tunnel.status != .disconnected {
            disconnect(tunnel)
        }
    }

    // MARK: - SSH Process

    private func startSSHProcess(for tunnel: TunnelState) {
        let process = SSHTunnelProcess(configuration: tunnel.configuration)

        process.onOutput = { [weak tunnel] message in
            tunnel?.addLog(message)
        }

        process.onTermination = { [weak self, weak tunnel] exitCode in
            guard let self = self, let tunnel = tunnel else { return }
            self.handleTermination(tunnel: tunnel, exitCode: exitCode)
        }

        do {
            try process.start()
            processes[tunnel.id] = process

            // SSH -N produces no output on success. If the process survives 3 seconds,
            // consider it connected (auth failure / refused exits immediately).
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self, weak tunnel] in
                guard let self = self, let tunnel = tunnel else { return }
                if self.processes[tunnel.id]?.isRunning == true &&
                    (tunnel.status == .connecting || tunnel.status == .reconnecting) {
                    tunnel.status = .connected
                    tunnel.connectedSince = Date()
                    tunnel.reconnectAttempts = 0
                    tunnel.addLog("Connected successfully")
                    self.objectWillChange.send()
                }
            }
        } catch {
            tunnel.status = .disconnected
            tunnel.addLog("Failed to start: \(error.localizedDescription)")
            objectWillChange.send()
        }
    }

    private func handleTermination(tunnel: TunnelState, exitCode: Int32) {
        processes.removeValue(forKey: tunnel.id)

        // If user already set status to disconnected (via disconnect()), don't override
        guard tunnel.status != .disconnected else { return }

        tunnel.lastDisconnect = Date()
        tunnel.connectedSince = nil

        if exitCode == 0 {
            tunnel.addLog("SSH process exited normally")
        } else {
            tunnel.addLog("SSH process exited with code \(exitCode)")
        }

        if tunnel.configuration.autoReconnect {
            tunnel.status = .reconnecting
            tunnel.reconnectAttempts += 1
            objectWillChange.send()
            scheduleReconnect(for: tunnel)
        } else {
            tunnel.status = .disconnected
            objectWillChange.send()
        }
    }

    // MARK: - Auto-Reconnect

    private func scheduleReconnect(for tunnel: TunnelState) {
        cancelReconnectTimer(for: tunnel.id)

        let delay = min(pow(2.0, Double(tunnel.reconnectAttempts - 1)), 30.0)
        tunnel.addLog("Reconnecting in \(Int(delay))s (attempt #\(tunnel.reconnectAttempts))...")

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self, weak tunnel] in
            guard let self = self, let tunnel = tunnel else { return }
            guard tunnel.status == .reconnecting else { return }

            // If another tunnel now owns this port, stop trying
            if let conflict = self.activeTunnelOnPort(tunnel.configuration.localPort, excluding: tunnel.id) {
                tunnel.addLog("Port \(tunnel.configuration.localPort) now in use by \"\(conflict.configuration.displayName)\" — stopping reconnect")
                tunnel.status = .disconnected
                self.objectWillChange.send()
                return
            }

            tunnel.addLog("Attempting reconnection...")
            self.startSSHProcess(for: tunnel)
        }
        timer.resume()
        reconnectTimers[tunnel.id] = timer
    }

    private func cancelReconnectTimer(for id: UUID) {
        reconnectTimers[id]?.cancel()
        reconnectTimers.removeValue(forKey: id)
    }

    // MARK: - Health Check

    private func startHealthCheck() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [weak self] in
            self?.performHealthCheck()
        }
        timer.resume()
        healthCheckTimer = timer
    }

    private func performHealthCheck() {
        for tunnel in tunnels where tunnel.status == .connected {
            if processes[tunnel.id]?.isRunning != true {
                tunnel.addLog("Health check: SSH process not running")
                handleTermination(tunnel: tunnel, exitCode: -1)
            }
        }
    }

    deinit {
        healthCheckTimer?.cancel()
        for timer in reconnectTimers.values {
            timer.cancel()
        }
        for process in processes.values {
            process.stop()
        }
    }
}
