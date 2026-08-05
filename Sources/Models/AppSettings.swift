import Foundation

struct AppSettings: Codable, Sendable, Equatable {
    var refreshIntervalMinutes: Int = 5
    var maxPRs: Int = 50
    var launchAtLogin: Bool = false
    var showNotifications: Bool = true
    var notifyMyPRReviews: Bool = true
    var notifyMyPRMerged: Bool = true
    var notifyMyPRCIGreen: Bool = true
    var customSoundPath: String = ""
    var excludeDrafts: Bool = false
    var botAllowList: [String: Bool] = [:]
    var teamFilters: [String: Bool] = [:]
    var repoIncludes: String = ""
    var repoExcludes: String = ""
    var orgIncludes: String = ""
    var showBotPRs: Bool = true
    var showTeamReviews: Bool = true
    var showMyPRs: Bool = true
    var sortOption: PRSortOption = .updatedNewest
    var popoverTab: PopoverTab = .toReview

    var refreshInterval: TimeInterval {
        TimeInterval(refreshIntervalMinutes * 60)
    }

    var repoIncludeList: [String] {
        normalizedLines(repoIncludes)
    }

    var repoExcludeList: [String] {
        normalizedLines(repoExcludes)
    }

    var orgIncludeList: [String] {
        normalizedLines(orgIncludes)
    }

    mutating func ignoreRepo(_ nameWithOwner: String) {
        let key = nameWithOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        var lines = Set(repoExcludeList.map { $0.lowercased() })
        guard !lines.contains(key.lowercased()) else { return }
        if repoExcludes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            repoExcludes = key
        } else {
            repoExcludes += "\n" + key
        }
        lines.insert(key.lowercased())
    }

    private func normalizedLines(_ text: String) -> [String] {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

enum PopoverTab: String, Sendable, Codable, CaseIterable, Identifiable {
    case toReview
    case myPRs

    var id: String { rawValue }

    var label: String {
        switch self {
        case .toReview: "To Review"
        case .myPRs: "My PRs"
        }
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

    func importSound(from sourceURL: URL) -> String? {
        let fm = FileManager.default
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
