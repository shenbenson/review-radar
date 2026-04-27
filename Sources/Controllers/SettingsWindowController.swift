import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func showSettings() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let tabVC = NSTabViewController()
        tabVC.tabStyle = .toolbar

        let generalTab = NSTabViewItem(viewController: NSHostingController(
            rootView: GeneralSettingsView(appState: appState).frame(minWidth: 420, minHeight: 300)
        ))
        generalTab.label = "General"
        generalTab.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)

        let filtersTab = NSTabViewItem(viewController: NSHostingController(
            rootView: FiltersSettingsView(appState: appState).frame(minWidth: 420, minHeight: 300)
        ))
        filtersTab.label = "Filters"
        filtersTab.image = NSImage(systemSymbolName: "line.3.horizontal.decrease.circle", accessibilityDescription: nil)

        tabVC.addTabViewItem(generalTab)
        tabVC.addTabViewItem(filtersTab)

        let window = NSWindow(contentViewController: tabVC)
        window.title = "ReviewRadar Settings"
        window.styleMask = [.titled, .closable]
        window.titleVisibility = .visible
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }
}
