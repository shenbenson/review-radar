import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem
    private let popover: NSPopover
    private let appState: AppState
    private let settingsWindowController: SettingsWindowController

    init(appState: AppState, settingsWindowController: SettingsWindowController) {
        self.appState = appState
        self.settingsWindowController = settingsWindowController
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()

        super.init()

        popover.contentSize = NSSize(width: 400, height: 520)
        popover.behavior = .transient
        popover.animates = false
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
            _ = appState.pendingCount
            _ = appState.error
            _ = appState.isLoading
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateIcon()
                self?.startObserving()
            }
        }
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }

        if appState.error != nil {
            button.image = NSImage(
                systemSymbolName: "exclamationmark.triangle.fill",
                accessibilityDescription: "Error"
            )
            button.title = ""
        } else if appState.pendingCount == 0 && !appState.isLoading {
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
            let count = appState.pendingCount
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
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
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
        settingsWindowController.showSettings()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // NSMenuDelegate
    nonisolated func menuDidClose(_ menu: NSMenu) {
        Task { @MainActor [weak self] in
            self?.statusItem.menu = nil
        }
    }
}
