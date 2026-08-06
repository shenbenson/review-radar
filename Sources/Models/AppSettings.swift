import Foundation

struct AppSettings: Codable, Sendable, Equatable {
    /// Poll cadence in seconds. Default 60; 30 is safe for personal use.
    var refreshIntervalSeconds: Int = 60
    var maxPRs: Int = 50
    var launchAtLogin: Bool = false
    var showNotifications: Bool = true
    var notifyMyPRReviews: Bool = true
    var notifyMyPRMerged: Bool = true
    var notifyMyPRCIGreen: Bool = true
    var customSoundPath: String = ""
    var excludeDraftsToReview: Bool = false
    var excludeDraftsMyPRs: Bool = false
    var botAllowList: [String: Bool] = [:]
    /// Keys are normalized lowercase `org/slug`.
    var teamFilters: [String: Bool] = [:]
    var repoIncludes: String = ""
    var repoExcludes: String = ""
    var orgIncludes: String = ""
    var showBotPRs: Bool = true
    var showTeamReviews: Bool = true
    /// CI green and still waiting on review (both queues).
    var showOnlyNeedsReview: Bool = false
    var showMyPRs: Bool = true
    var sortOption: PRSortOption = .updatedNewest
    var popoverTab: PopoverTab = .toReview
    /// PR id → hide until this date (`distantFuture` = muted indefinitely).
    var snoozedPRs: [String: Date] = [:]

    var refreshInterval: TimeInterval {
        TimeInterval(max(30, refreshIntervalSeconds))
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

    // Forward-compatible decode: missing keys keep defaults instead of failing the whole file.
    init() {}

    private enum CodingKeys: String, CodingKey {
        case refreshIntervalSeconds, refreshIntervalMinutes, maxPRs, launchAtLogin
        case showNotifications, notifyMyPRReviews, notifyMyPRMerged, notifyMyPRCIGreen
        case customSoundPath
        case excludeDrafts // legacy single toggle
        case excludeDraftsToReview, excludeDraftsMyPRs
        case botAllowList, teamFilters
        case repoIncludes, repoExcludes, orgIncludes
        case showBotPRs, showTeamReviews, showOnlyNeedsReview, showMyPRs
        case sortOption, popoverTab, snoozedPRs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()

        if let seconds = try c.decodeIfPresent(Int.self, forKey: .refreshIntervalSeconds) {
            refreshIntervalSeconds = max(30, seconds)
        } else if let minutes = try c.decodeIfPresent(Int.self, forKey: .refreshIntervalMinutes) {
            refreshIntervalSeconds = max(30, minutes * 60)
        } else {
            refreshIntervalSeconds = defaults.refreshIntervalSeconds
        }
        maxPRs = try c.decodeIfPresent(Int.self, forKey: .maxPRs) ?? defaults.maxPRs
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        showNotifications = try c.decodeIfPresent(Bool.self, forKey: .showNotifications) ?? defaults.showNotifications
        notifyMyPRReviews = try c.decodeIfPresent(Bool.self, forKey: .notifyMyPRReviews) ?? defaults.notifyMyPRReviews
        notifyMyPRMerged = try c.decodeIfPresent(Bool.self, forKey: .notifyMyPRMerged) ?? defaults.notifyMyPRMerged
        notifyMyPRCIGreen = try c.decodeIfPresent(Bool.self, forKey: .notifyMyPRCIGreen) ?? defaults.notifyMyPRCIGreen
        customSoundPath = try c.decodeIfPresent(String.self, forKey: .customSoundPath) ?? defaults.customSoundPath
        let legacyExcludeDrafts = try c.decodeIfPresent(Bool.self, forKey: .excludeDrafts)
        excludeDraftsToReview = try c.decodeIfPresent(Bool.self, forKey: .excludeDraftsToReview)
            ?? legacyExcludeDrafts
            ?? defaults.excludeDraftsToReview
        excludeDraftsMyPRs = try c.decodeIfPresent(Bool.self, forKey: .excludeDraftsMyPRs)
            ?? legacyExcludeDrafts
            ?? defaults.excludeDraftsMyPRs
        botAllowList = try c.decodeIfPresent([String: Bool].self, forKey: .botAllowList) ?? defaults.botAllowList
        teamFilters = try c.decodeIfPresent([String: Bool].self, forKey: .teamFilters) ?? defaults.teamFilters
        repoIncludes = try c.decodeIfPresent(String.self, forKey: .repoIncludes) ?? defaults.repoIncludes
        repoExcludes = try c.decodeIfPresent(String.self, forKey: .repoExcludes) ?? defaults.repoExcludes
        orgIncludes = try c.decodeIfPresent(String.self, forKey: .orgIncludes) ?? defaults.orgIncludes
        showBotPRs = try c.decodeIfPresent(Bool.self, forKey: .showBotPRs) ?? defaults.showBotPRs
        showTeamReviews = try c.decodeIfPresent(Bool.self, forKey: .showTeamReviews) ?? defaults.showTeamReviews
        showOnlyNeedsReview = try c.decodeIfPresent(Bool.self, forKey: .showOnlyNeedsReview) ?? defaults.showOnlyNeedsReview
        showMyPRs = try c.decodeIfPresent(Bool.self, forKey: .showMyPRs) ?? defaults.showMyPRs
        sortOption = try c.decodeIfPresent(PRSortOption.self, forKey: .sortOption) ?? defaults.sortOption
        popoverTab = try c.decodeIfPresent(PopoverTab.self, forKey: .popoverTab) ?? defaults.popoverTab
        snoozedPRs = try c.decodeIfPresent([String: Date].self, forKey: .snoozedPRs) ?? defaults.snoozedPRs
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(refreshIntervalSeconds, forKey: .refreshIntervalSeconds)
        try c.encode(maxPRs, forKey: .maxPRs)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
        try c.encode(showNotifications, forKey: .showNotifications)
        try c.encode(notifyMyPRReviews, forKey: .notifyMyPRReviews)
        try c.encode(notifyMyPRMerged, forKey: .notifyMyPRMerged)
        try c.encode(notifyMyPRCIGreen, forKey: .notifyMyPRCIGreen)
        try c.encode(customSoundPath, forKey: .customSoundPath)
        try c.encode(excludeDraftsToReview, forKey: .excludeDraftsToReview)
        try c.encode(excludeDraftsMyPRs, forKey: .excludeDraftsMyPRs)
        try c.encode(botAllowList, forKey: .botAllowList)
        try c.encode(teamFilters, forKey: .teamFilters)
        try c.encode(repoIncludes, forKey: .repoIncludes)
        try c.encode(repoExcludes, forKey: .repoExcludes)
        try c.encode(orgIncludes, forKey: .orgIncludes)
        try c.encode(showBotPRs, forKey: .showBotPRs)
        try c.encode(showTeamReviews, forKey: .showTeamReviews)
        try c.encode(showOnlyNeedsReview, forKey: .showOnlyNeedsReview)
        try c.encode(showMyPRs, forKey: .showMyPRs)
        try c.encode(sortOption, forKey: .sortOption)
        try c.encode(popoverTab, forKey: .popoverTab)
        try c.encode(snoozedPRs, forKey: .snoozedPRs)
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

    mutating func normalize() {
        if teamFilters.keys.contains(where: { $0 != TeamFilterKey.normalize($0) }) {
            var merged: [String: Bool] = [:]
            for (key, value) in teamFilters {
                let nk = TeamFilterKey.normalize(key)
                merged[nk] = (merged[nk] ?? true) && value
            }
            teamFilters = merged
        }
        pruneExpiredSnoozes()
    }

    mutating func pruneExpiredSnoozes(now: Date = Date()) {
        snoozedPRs = snoozedPRs.filter { $0.value > now }
    }

    func isSnoozed(_ prID: String, now: Date = Date()) -> Bool {
        guard let until = snoozedPRs[prID] else { return false }
        return until > now
    }

    mutating func snoozePR(_ prID: String, until: Date) {
        snoozedPRs[prID] = until
    }

    mutating func mutePR(_ prID: String) {
        snoozedPRs[prID] = .distantFuture
    }

    mutating func unsnoozePR(_ prID: String) {
        snoozedPRs.removeValue(forKey: prID)
    }

    func isTeamFilterEnabled(_ key: String) -> Bool {
        let nk = TeamFilterKey.normalize(key)
        if let value = teamFilters[nk] { return value }
        if let match = teamFilters.first(where: { TeamFilterKey.normalize($0.key) == nk }) {
            return match.value
        }
        return true
    }

    mutating func setTeamFilter(_ key: String, enabled: Bool) {
        teamFilters[TeamFilterKey.normalize(key)] = enabled
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
    private var pendingSettings: AppSettings?

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
        guard let data = try? Data(contentsOf: fileURL) else {
            return AppSettings()
        }
        do {
            var settings = try JSONDecoder().decode(AppSettings.self, from: data)
            settings.normalize()
            return settings
        } catch {
            // Never silently wipe a corrupt/unreadable file — keep a backup.
            let backup = fileURL.deletingPathExtension().appendingPathExtension("bak.json")
            try? data.write(to: backup, options: .atomic)
            return AppSettings()
        }
    }

    func scheduleSave(_ settings: AppSettings) {
        pendingSettings = settings
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.flush()
            }
        }
    }

    /// Write immediately (call on quit / before reinstall kill).
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard let settings = pendingSettings else { return }
        pendingSettings = nil
        if let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
