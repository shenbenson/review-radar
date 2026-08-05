import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem
    private let popover: NSPopover
    private let appState: AppState
    private let settingsWindowController: SettingsWindowController
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

    init(appState: AppState, settingsWindowController: SettingsWindowController) {
        self.appState = appState
        self.settingsWindowController = settingsWindowController
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()

        super.init()

        popover.contentSize = NSSize(width: 420, height: 560)
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(appState: appState, onOpenSettings: { [weak self] in
                self?.settingsWindowController.showSettings()
            })
        )

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "arrow.triangle.pull",
                accessibilityDescription: "ReviewRadar"
            )
            button.imagePosition = .imageLeading
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        startObserving()
        updateIcon()
    }

    private func startObserving() {
        withObservationTracking {
            _ = appState.menuBarPendingCount
            _ = appState.error
            _ = appState.bannerError
            _ = appState.isLoading
            _ = appState.reviewPullRequests
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateIcon()
                self?.startObserving()
            }
        }
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let count = appState.menuBarPendingCount

        if appState.error != nil && appState.reviewPullRequests.isEmpty {
            button.image = NSImage(
                systemSymbolName: "exclamationmark.triangle.fill",
                accessibilityDescription: "Error"
            )
            button.title = ""
        } else if count == 0 && !appState.isLoading {
            button.image = NSImage(
                systemSymbolName: "checkmark.circle",
                accessibilityDescription: "No pending reviews"
            )
            button.title = ""
        } else {
            button.image = NSImage(
                systemSymbolName: "arrow.triangle.pull",
                accessibilityDescription: "Pending reviews"
            )
            button.title = count > 0 ? "\(count)" : ""
        }
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            closePopover()
        } else {
            // Do not makeKey() here — that breaks NSPopover.transient outside-click dismiss.
            // Clicking the search field will make the window key when the user wants to type.
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            installOutsideClickMonitors()
        }
    }

    private func closePopover() {
        removeOutsideClickMonitors()
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    /// Transient popovers stop auto-closing once they become key (e.g. search focused).
    /// Global + local monitors restore reliable outside-click dismiss.
    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover()
            }
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            let popoverWindow = self.popover.contentViewController?.view.window
            // Click in another of our windows (e.g. Settings) or no window → close.
            if event.window == nil || (event.window !== popoverWindow && event.window !== self.statusItem.button?.window) {
                self.closePopover()
            }
            return event
        }
    }

    private func removeOutsideClickMonitors() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
    }

    private func showMenu() {
        closePopover()
        let menu = NSMenu()
        menu.delegate = self

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit ReviewRadar", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    @objc private func openSettings() {
        closePopover()
        settingsWindowController.showSettings()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    nonisolated func menuDidClose(_ menu: NSMenu) {
        Task { @MainActor [weak self] in
            self?.statusItem.menu = nil
        }
    }
}

extension StatusBarController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        removeOutsideClickMonitors()
    }
}
