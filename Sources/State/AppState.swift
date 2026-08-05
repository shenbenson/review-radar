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
    var discoveredBots: Set<String> = []
    var teams: [GitHubTeam] = []
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
        applyCommonFilters(reviewPullRequests.filter { pr in
            // Hide PRs you've already approved
            if pr.reviewStatus == .approved { return false }

            if !settings.showTeamReviews && pr.isTeamReviewRequested && !pr.isDirectReviewRequested {
                return false
            }

            if let key = pr.teamFilterKey, let enabled = settings.teamFilters[key], !enabled {
                // Still show if directly requested
                if !pr.isDirectReviewRequested { return false }
            }

            return true
        })
    }

    var filteredAuthoredPRs: [PullRequest] {
        applyCommonFilters(authoredPullRequests)
    }

    private func applyCommonFilters(_ prs: [PullRequest]) -> [PullRequest] {
        let includes = settings.repoIncludeList
        let excludes = settings.repoExcludeList
        let orgs = settings.orgIncludeList

        return prs.filter { pr in
            if settings.excludeDrafts && pr.isDraft { return false }

            if !settings.showBotPRs && pr.authorIsBot {
                if settings.botAllowList[pr.author.login] != true { return false }
            }

            if !includes.isEmpty && !containsCI(includes, pr.repository.nameWithOwner) { return false }
            if containsCI(excludes, pr.repository.nameWithOwner) { return false }
            if !orgs.isEmpty && !containsCI(orgs, pr.repository.owner) { return false }

            return true
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
        // Preserve sort within repo when sorting by repo; otherwise keep global sort order in groups
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

    var pendingCount: Int { filteredReviewPRs.count }
    var myPRCount: Int { filteredAuthoredPRs.count }

    // MARK: - Polling

    func startPolling() {
        notificationService.requestPermission()
        pollTask?.cancel()
        pollTask = Task {
            await refresh()
            while !Task.isCancelled {
                // Honor rate-limit backoff
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

            // Fetch queues independently so one failure doesn't wipe the other.
            var reviews: [PullRequest]?
            var authored: [PullRequest]?
            var fetchError: AppError?

            do {
                reviews = try await github.fetchReviewQueue(limit: limit)
            } catch let appError as AppError {
                fetchError = appError
            } catch {
                fetchError = .unknown(error.localizedDescription)
            }

            if includeAuthored {
                do {
                    authored = try await github.fetchAuthoredQueue(limit: limit)
                } catch let appError as AppError {
                    fetchError = fetchError ?? appError
                } catch {
                    fetchError = fetchError ?? .unknown(error.localizedDescription)
                }
            } else {
                authored = []
            }

            if reviews == nil && authored == nil {
                let err = fetchError ?? .unknown("Failed to fetch pull requests")
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
                reviewPullRequests = reviews
            }

            if let authored {
                authoredPullRequests = authored
            }

            let fetchedTeams = await github.fetchUserTeams()
            if !fetchedTeams.isEmpty {
                teams = fetchedTeams
                for team in fetchedTeams {
                    if settings.teamFilters[team.filterKey] == nil {
                        settings.teamFilters[team.filterKey] = true
                    }
                }
            }

            lastUpdated = Date()
            error = nil
            if let fetchError {
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
}
