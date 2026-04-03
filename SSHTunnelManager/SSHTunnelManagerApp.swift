import SwiftUI
import Combine

@main
struct SSHTunnelManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private enum StatusIndicatorColor: Equatable {
        case gray
        case yellow
        case green
        case red

        var nsColor: NSColor {
            switch self {
            case .gray: return .systemGray
            case .yellow: return .systemYellow
            case .green: return .systemGreen
            case .red: return .systemRed
            }
        }
    }

    private struct StatusItemAppearance: Equatable {
        let color: StatusIndicatorColor
        let title: String
    }

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let tunnelManager = TunnelManager()
    private var cancellables = Set<AnyCancellable>()
    private var lastStatusItemAppearance: StatusItemAppearance?

    private var showConnectionCount: Bool {
        get { !UserDefaults.standard.bool(forKey: "hideConnectionCount") }
        set {
            UserDefaults.standard.set(!newValue, forKey: "hideConnectionCount")
            updateStatusIcon()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        observeStatusChanges()
    }

    func applicationWillTerminate(_ notification: Notification) {
        tunnelManager.disconnectAll()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateStatusIcon()
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 480)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: StatusPopoverView(tunnelManager: tunnelManager)
        )
    }

    private func observeStatusChanges() {
        tunnelManager.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusIcon()
            }
            .store(in: &cancellables)
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }

        let statuses = tunnelManager.tunnels.map { $0.status }
        let total = statuses.count
        let connectedCount = statuses.filter { $0 == .connected }.count
        let isTransient = statuses.contains { $0 == .connecting || $0 == .reconnecting }

        let color: StatusIndicatorColor
        if total == 0 {
            color = .gray
        } else if isTransient {
            color = .yellow
        } else if connectedCount > 0 {
            color = .green
        } else {
            color = .red
        }

        let title: String
        if showConnectionCount && total > 0 {
            title = " \(connectedCount)/\(total)"
        } else {
            title = ""
        }

        let appearance = StatusItemAppearance(color: color, title: title)
        guard appearance != lastStatusItemAppearance else { return }
        lastStatusItemAppearance = appearance

        let circleSize = NSSize(width: 18, height: 18)
        let circleImage = NSImage(size: circleSize, flipped: false) { _ in
            color.nsColor.setFill()
            let diameter: CGFloat = 10
            let circleRect = NSRect(
                x: (circleSize.width - diameter) / 2,
                y: (circleSize.height - diameter) / 2,
                width: diameter,
                height: diameter
            )
            NSBezierPath(ovalIn: circleRect).fill()
            return true
        }
        circleImage.isTemplate = false
        button.image = circleImage
        button.title = title
    }

    // MARK: - Click Handling

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Context Menu

    private func showContextMenu() {
        let menu = NSMenu()

        let countItem = NSMenuItem(
            title: "Show Connection Count",
            action: #selector(toggleShowCount),
            keyEquivalent: ""
        )
        countItem.target = self
        countItem.state = showConnectionCount ? .on : .off
        menu.addItem(countItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Disconnect All & Quit",
            action: #selector(disconnectAndQuit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Clear the menu so left-click goes back to popover
        statusItem.menu = nil
    }

    @objc private func toggleShowCount() {
        showConnectionCount.toggle()
    }

    @objc private func disconnectAndQuit() {
        tunnelManager.disconnectAll()
        NSApplication.shared.terminate(nil)
    }
}
