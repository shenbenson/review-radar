import Foundation

struct AppSettings: Codable, Sendable, Equatable {
    var refreshIntervalMinutes: Int = 5
    var maxPRs: Int = 100
    var launchAtLogin: Bool = false
    var showNotifications: Bool = true
    // Path to a user-chosen sound file; empty means the default system sound.
    var customSoundPath: String = ""
    var excludeDrafts: Bool = false
    var botAllowList: [String: Bool] = [:]
    var teamFilters: [String: Bool] = [:]
    var repoIncludes: String = ""
    var repoExcludes: String = ""
    var orgIncludes: String = ""
    var showBotPRs: Bool = true
    var showTeamReviews: Bool = true

    var refreshInterval: TimeInterval {
        TimeInterval(refreshIntervalMinutes * 60)
    }

    var repoIncludeList: [String] {
        repoIncludes.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var repoExcludeList: [String] {
        repoExcludes.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var orgIncludeList: [String] {
        orgIncludes.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

@MainActor
final class SettingsManager {
    private let fileURL: URL
    private let soundsDir: URL
    private var saveTask: Task<Void, Never>?

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ReviewRadar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("settings.json")
        soundsDir = dir.appendingPathComponent("sounds", isDirectory: true)
    }

    /// Copies a chosen sound file into our config folder so it survives the
    /// original being moved or deleted. Returns the path of the local copy.
    func importSound(from sourceURL: URL) -> String? {
        let fm = FileManager.default
        // Single active sound: clear any previous copies first.
        try? fm.removeItem(at: soundsDir)
        do {
            try fm.createDirectory(at: soundsDir, withIntermediateDirectories: true)
            let dest = soundsDir.appendingPathComponent(sourceURL.lastPathComponent)
            try fm.copyItem(at: sourceURL, to: dest)
            return dest.path
        } catch {
            return nil
        }
    }

    func clearSound() {
        try? FileManager.default.removeItem(at: soundsDir)
    }

    func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return AppSettings()
        }
        return settings
    }

    func scheduleSave(_ settings: AppSettings) {
        saveTask?.cancel()
        saveTask = Task { [fileURL] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(settings) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }
}
