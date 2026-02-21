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
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let tunnelManager = TunnelManager()
    private var cancellables = Set<AnyCancellable>()

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
            button.action = #selector(togglePopover)
            button.target = self
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
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusIcon()
            }
            .store(in: &cancellables)
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }

        let statuses = tunnelManager.tunnels.map { $0.status }

        let color: NSColor
        if statuses.isEmpty {
            color = .systemGray
        } else if statuses.allSatisfy({ $0 == .connected }) {
            color = .systemGreen
        } else if statuses.contains(where: { $0 == .connecting || $0 == .reconnecting }) {
            color = .systemYellow
        } else if statuses.contains(where: { $0 == .connected }) {
            // Mixed: some connected, some not
            color = .systemOrange
        } else {
            color = .systemRed
        }

        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            let diameter: CGFloat = 10
            let circleRect = NSRect(
                x: (size.width - diameter) / 2,
                y: (size.height - diameter) / 2,
                width: diameter,
                height: diameter
            )
            NSBezierPath(ovalIn: circleRect).fill()
            return true
        }
        image.isTemplate = false
        button.image = image
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
