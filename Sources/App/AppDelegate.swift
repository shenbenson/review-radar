import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var statusBarController: StatusBarController?
    var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settingsWindowController = SettingsWindowController(appState: appState)
        statusBarController = StatusBarController(appState: appState, settingsWindowController: settingsWindowController!)
        appState.startPolling()
    }
}
