import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var reviewPullRequests: [PullRequest] = []
    var authoredPullRequests: [PullRequest] = []
    var isLoading = false
    var lastUpdated: Date?
    var error: AppError?
    var bannerError: AppError?
    /// Which queue(s) failed on the last refresh (for precise empty/banner copy).
    var reviewQueueFailed = false
    var authoredQueueFailed = false
    var discoveredBots: Set<String> = []
    var teams: [GitHubTeam] = []
    var searchQuery = ""
    var settings: AppSettings {
        didSet {
            if settings != oldValue {
                settingsManager.scheduleSave(settings)
            }
        }
    }
    var isRefreshing = false

    let github = GitHubService()
    let notificationService = NotificationService()
    private let settingsManager = SettingsManager()
    private var pollTask: Task<Void, Never>?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var rateLimitWaitUntil: Date?

    init() {
        settings = settingsManager.load()
        setupSleepWakeObservers()
    }

    // MARK: - Filtered & Grouped

    var filteredReviewPRs: [PullRequest] {
        reviewPRsMatching(applySearch: true)
    }

    var filteredAuthoredPRs: [PullRequest] {
        authoredPRsMatching(applySearch: true)
    }

    /// Counts for tabs (respect search).
    var pendingCount: Int { filteredReviewPRs.count }
    var myPRCount: Int { filteredAuthoredPRs.count }

    /// Menu-bar badge — ignores search so typing doesn't resize the status item / move the popover.
    var menuBarPendingCount: Int { reviewPRsMatching(applySearch: false).count }

    private func reviewPRsMatching(applySearch: Bool) -> [PullRequest] {
        let base = reviewPullRequests.filter { pr in
            if settings.excludeDraftsToReview && pr.isDraft { return false }
            if pr.reviewStatus == .approved { return false }
            if !settings.showTeamReviews && pr.isTeamReviewRequested && !pr.isDirectReviewRequested {
                return false
            }
            if let key = pr.teamFilterKey, !settings.isTeamFilterEnabled(key) {
                if !pr.isDirectReviewRequested { return false }
            }
            return true
        }
        let common = applyCommonFilters(base)
        return applySearch ? self.applySearch(common) : common
    }

    private func authoredPRsMatching(applySearch: Bool) -> [PullRequest] {
        let base = authoredPullRequests.filter { pr in
            if settings.excludeDraftsMyPRs && pr.isDraft { return false }
            return true
        }
        let common = applyCommonFilters(base)
        return applySearch ? self.applySearch(common) : common
    }

    private func applyCommonFilters(_ prs: [PullRequest]) -> [PullRequest] {
        let includes = settings.repoIncludeList
        let excludes = settings.repoExcludeList
        let orgs = settings.orgIncludeList

        return prs.filter { pr in
            if settings.isSnoozed(pr.id) { return false }

            if !settings.showBotPRs && pr.authorIsBot {
                if settings.botAllowList[pr.author.login] != true { return false }
            }

            if !includes.isEmpty && !containsCI(includes, pr.repository.nameWithOwner) { return false }
            if containsCI(excludes, pr.repository.nameWithOwner) { return false }
            if !orgs.isEmpty && !containsCI(orgs, pr.repository.owner) { return false }

            return true
        }
    }

    private func applySearch(_ prs: [PullRequest]) -> [PullRequest] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return prs }
        return prs.filter { pr in
            pr.title.localizedCaseInsensitiveContains(q)
                || pr.repository.nameWithOwner.localizedCaseInsensitiveContains(q)
                || pr.author.login.localizedCaseInsensitiveContains(q)
                || "\(pr.number)".contains(q)
                || "#\(pr.number)".localizedCaseInsensitiveContains(q)
        }
    }

    private func containsCI(_ list: [String], _ value: String) -> Bool {
        list.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
    }

    var groupedReviewPRs: [(repo: String, prs: [PullRequest])] {
        group(settings.sortOption.sorted(filteredReviewPRs))
    }

    var groupedAuthoredPRs: [(repo: String, prs: [PullRequest])] {
        group(settings.sortOption.sorted(filteredAuthoredPRs))
    }

    private func group(_ prs: [PullRequest]) -> [(repo: String, prs: [PullRequest])] {
        if settings.sortOption == .repoName {
            let grouped = Dictionary(grouping: prs) { $0.repository.nameWithOwner }
            return grouped.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
                .map { (repo: $0.key, prs: $0.value) }
        }

        var order: [String] = []
        var map: [String: [PullRequest]] = [:]
        for pr in prs {
            let key = pr.repository.nameWithOwner
            if map[key] == nil {
                order.append(key)
                map[key] = []
            }
            map[key, default: []].append(pr)
        }
        return order.map { (repo: $0, prs: map[$0] ?? []) }
    }

    var hasActiveSearch: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var activeSnoozes: [(id: String, until: Date)] {
        let now = Date()
        return settings.snoozedPRs
            .filter { $0.value > now }
            .map { (id: $0.key, until: $0.value) }
            .sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }

    // MARK: - Polling

    func startPolling() {
        notificationService.requestPermission()
        pollTask?.cancel()
        pollTask = Task {
            await refresh()
            while !Task.isCancelled {
                if let waitUntil = rateLimitWaitUntil {
                    let delay = waitUntil.timeIntervalSinceNow
                    if delay > 0 {
                        try? await Task.sleep(for: .seconds(delay))
                    }
                    rateLimitWaitUntil = nil
                } else {
                    try? await Task.sleep(for: .seconds(settings.refreshInterval))
                }
                guard !Task.isCancelled else { break }
                await refresh()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func restartPolling() {
        startPolling()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let hasData = !reviewPullRequests.isEmpty || !authoredPullRequests.isEmpty
        isLoading = !hasData
        if !hasData { error = nil }
        bannerError = nil
        reviewQueueFailed = false
        authoredQueueFailed = false
        settings.pruneExpiredSnoozes()

        do {
            let installed = await github.checkGHInstalled()
            guard installed else {
                presentError(.ghNotInstalled, hasData: hasData)
                finishRefresh()
                return
            }

            let authenticated = await github.checkGHAuthenticated()
            guard authenticated else {
                presentError(.ghNotAuthenticated, hasData: hasData)
                finishRefresh()
                return
            }

            let limit = settings.maxPRs
            let includeAuthored = settings.showMyPRs

            var reviews: [PullRequest]?
            var authored: [PullRequest]?
            var reviewError: AppError?
            var authoredError: AppError?

            do {
                reviews = try await github.fetchReviewQueue(limit: limit)
            } catch let appError as AppError {
                reviewError = appError
            } catch {
                reviewError = .unknown(error.localizedDescription)
            }

            if includeAuthored {
                do {
                    authored = try await github.fetchAuthoredQueue(limit: limit)
                } catch let appError as AppError {
                    authoredError = appError
                } catch {
                    authoredError = .unknown(error.localizedDescription)
                }
            } else {
                authored = []
            }

            reviewQueueFailed = reviews == nil
            authoredQueueFailed = includeAuthored && authored == nil

            if reviews == nil && authored == nil {
                let err = reviewError ?? authoredError ?? .unknown("Failed to fetch pull requests")
                if case .rateLimited(let reset) = err {
                    rateLimitWaitUntil = reset
                }
                presentError(err, hasData: hasData)
                finishRefresh()
                return
            }

            if let reviews {
                for pr in reviews where pr.authorIsBot {
                    if !discoveredBots.contains(pr.author.login) {
                        discoveredBots.insert(pr.author.login)
                        if settings.botAllowList[pr.author.login] == nil {
                            settings.botAllowList[pr.author.login] = false
                        }
                    }
                }
                reviewPullRequests = mergeCI(previous: reviewPullRequests, incoming: reviews)
            }

            if let authored {
                authoredPullRequests = mergeCI(previous: authoredPullRequests, incoming: authored)
            }

            let fetchedTeams = await github.fetchUserTeams()
            if !fetchedTeams.isEmpty {
                teams = fetchedTeams
                for team in fetchedTeams {
                    if settings.teamFilters[team.filterKey] == nil
                        && !settings.teamFilters.keys.contains(where: {
                            TeamFilterKey.normalize($0) == team.filterKey
                        })
                    {
                        settings.setTeamFilter(team.filterKey, enabled: true)
                    }
                }
            }

            lastUpdated = Date()
            error = nil

            if let fetchError = reviewError ?? authoredError {
                if case .rateLimited(let reset) = fetchError {
                    rateLimitWaitUntil = reset
                }
                bannerError = fetchError
            } else {
                bannerError = nil
            }

            notificationService.processReviewQueue(
                allIDs: Set(reviewPullRequests.map(\.id)),
                notifiablePRs: filteredReviewPRs,
                notificationsEnabled: settings.showNotifications,
                customSoundPath: settings.customSoundPath
            )
            notificationService.processAuthoredQueue(
                openAuthoredPRs: authoredPullRequests,
                notifyReviews: settings.notifyMyPRReviews,
                notifyMerged: settings.notifyMyPRMerged,
                notifyCIGreen: settings.notifyMyPRCIGreen,
                customSoundPath: settings.customSoundPath
            )
        } catch let appError as AppError {
            if case .rateLimited(let reset) = appError {
                rateLimitWaitUntil = reset
            }
            presentError(appError, hasData: hasData)
        } catch {
            presentError(.unknown(error.localizedDescription), hasData: hasData)
        }

        finishRefresh()
    }

    /// Keep last-known CI when a refresh couldn't load checks for that PR.
    private func mergeCI(previous: [PullRequest], incoming: [PullRequest]) -> [PullRequest] {
        let oldByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        return incoming.map { pr in
            guard pr.ciStatus == .unavailable,
                  let old = oldByID[pr.id],
                  old.ciStatus != .unavailable
            else { return pr }
            var copy = pr
            copy.ciStatus = old.ciStatus
            return copy
        }
    }

    private func presentError(_ appError: AppError, hasData: Bool) {
        if hasData {
            bannerError = appError
        } else {
            error = appError
        }
    }

    private func finishRefresh() {
        isLoading = false
        isRefreshing = false
    }

    // MARK: - Sleep/Wake

    private func setupSleepWakeObservers() {
        let ws = NSWorkspace.shared.notificationCenter

        sleepObserver = ws.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stopPolling() }
        }

        wakeObserver = ws.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.startPolling() }
        }
    }

    // MARK: - Actions

    func openPR(_ pr: PullRequest) {
        if let url = URL(string: pr.url) {
            NSWorkspace.shared.open(url)
        }
    }

    func ignoreRepo(_ nameWithOwner: String) {
        settings.ignoreRepo(nameWithOwner)
    }

    func snoozePR(_ pr: PullRequest, duration: SnoozeDuration) {
        settings.snoozePR(pr.id, until: duration.deadline())
    }

    func mutePR(_ pr: PullRequest) {
        settings.mutePR(pr.id)
    }

    func unsnoozePR(id: String) {
        settings.unsnoozePR(id)
    }

    func clearAllSnoozes() {
        settings.snoozedPRs = [:]
    }

    // MARK: - Notification Sound

    func importCustomSound(from url: URL) {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        if let path = settingsManager.importSound(from: url) {
            settings.customSoundPath = path
        }
    }

    func clearCustomSound() {
        settingsManager.clearSound()
        settings.customSoundPath = ""
    }

    func flushSettings() {
        settingsManager.scheduleSave(settings)
        settingsManager.flush()
    }
}

enum SnoozeDuration: String, CaseIterable, Identifiable {
    case oneHour
    case untilTomorrow
    case oneWeek

    var id: String { rawValue }

    var label: String {
        switch self {
        case .oneHour: "1 hour"
        case .untilTomorrow: "Until tomorrow"
        case .oneWeek: "1 week"
        }
    }

    func deadline(from now: Date = Date()) -> Date {
        switch self {
        case .oneHour:
            return now.addingTimeInterval(60 * 60)
        case .untilTomorrow:
            let cal = Calendar.current
            let startOfToday = cal.startOfDay(for: now)
            return cal.date(byAdding: .day, value: 1, to: startOfToday) ?? now.addingTimeInterval(24 * 60 * 60)
        case .oneWeek:
            return now.addingTimeInterval(7 * 24 * 60 * 60)
        }
    }
}
