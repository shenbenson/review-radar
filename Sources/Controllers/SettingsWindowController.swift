import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func showSettings() {
        if let window, window.isVisible {
            window.title = "Settings"
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let tabVC = NSTabViewController()
        tabVC.tabStyle = .toolbar
        tabVC.title = "Settings"

        let generalHost = NSHostingController(
            rootView: GeneralSettingsView(appState: appState)
                .frame(minWidth: 460, minHeight: 360)
        )
        generalHost.title = "General"
        let generalTab = NSTabViewItem(viewController: generalHost)
        generalTab.label = "General"
        generalTab.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "General")

        let filtersHost = NSHostingController(
            rootView: FiltersSettingsView(appState: appState)
                .frame(minWidth: 460, minHeight: 360)
        )
        filtersHost.title = "Filters"
        let filtersTab = NSTabViewItem(viewController: filtersHost)
        filtersTab.label = "Filters"
        filtersTab.image = NSImage(systemSymbolName: "line.3.horizontal.decrease.circle", accessibilityDescription: "Filters")

        tabVC.addTabViewItem(generalTab)
        tabVC.addTabViewItem(filtersTab)

        let window = NSWindow(contentViewController: tabVC)
        window.delegate = self
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = "Settings"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        if #available(macOS 11.0, *) {
            window.toolbarStyle = .preference
        }
        window.setContentSize(NSSize(width: 480, height: 420))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        // Toolbar-style tabs can reset the title after first layout.
        window.title = "Settings"
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    func windowDidBecomeKey(_ notification: Notification) {
        window?.title = "Settings"
    }
}
