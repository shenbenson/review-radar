import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var pullRequests: [PullRequest] = []
    var isLoading = false
    var lastUpdated: Date?
    var error: AppError?
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

    init() {
        settings = settingsManager.load()
        setupSleepWakeObservers()
    }

    // MARK: - Filtered & Grouped PRs

    var filteredPRs: [PullRequest] {
        pullRequests.filter { pr in
            // Hide PRs you've already approved
            if pr.reviewStatus == .approved { return false }

            if settings.excludeDrafts && pr.isDraft { return false }

            if !settings.showBotPRs && pr.authorIsBot {
                if settings.botAllowList[pr.author.login] != true { return false }
            }

            if !settings.showTeamReviews && pr.isTeamReviewRequested && !isDirectReview(pr) {
                return false
            }

            if let key = pr.teamFilterKey, let enabled = settings.teamFilters[key], !enabled {
                return false
            }

            let includes = settings.repoIncludeList
            let excludes = settings.repoExcludeList
            let orgs = settings.orgIncludeList

            if !includes.isEmpty && !includes.contains(pr.repository.nameWithOwner) { return false }
            if excludes.contains(pr.repository.nameWithOwner) { return false }
            if !orgs.isEmpty && !orgs.contains(pr.repository.owner) { return false }

            return true
        }
    }

    private func isDirectReview(_ pr: PullRequest) -> Bool {
        !pr.isTeamReviewRequested
    }

    var groupedPRs: [(repo: String, prs: [PullRequest])] {
        let grouped = Dictionary(grouping: filteredPRs) { $0.repository.nameWithOwner }
        return grouped.sorted { $0.key < $1.key }.map { (repo: $0.key, prs: $0.value) }
    }

    var pendingCount: Int { filteredPRs.count }

    // MARK: - Polling

    func startPolling() {
        notificationService.requestPermission()
        pollTask?.cancel()
        pollTask = Task {
            await refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(settings.refreshInterval))
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
        isLoading = pullRequests.isEmpty
        error = nil

        do {
            // Check gh availability first
            let installed = await github.checkGHInstalled()
            guard installed else {
                error = .ghNotInstalled
                isLoading = false
                isRefreshing = false
                return
            }

            let authenticated = await github.checkGHAuthenticated()
            guard authenticated else {
                error = .ghNotAuthenticated
                isLoading = false
                isRefreshing = false
                return
            }

            var prs = try await github.searchPRs(limit: settings.maxPRs)

            // Track discovered bots
            for pr in prs where pr.authorIsBot {
                if !discoveredBots.contains(pr.author.login) {
                    discoveredBots.insert(pr.author.login)
                    if settings.botAllowList[pr.author.login] == nil {
                        settings.botAllowList[pr.author.login] = false
                    }
                }
            }

            // Enrich with review status and team info
            prs = await github.enrichPRs(prs)

            // Update team list
            let fetchedTeams = await github.fetchUserTeams()
            if !fetchedTeams.isEmpty {
                teams = fetchedTeams
                for team in fetchedTeams {
                    let key = "\(team.organization.login)/\(team.slug)"
                    if settings.teamFilters[key] == nil {
                        settings.teamFilters[key] = true
                    }
                }
            }

            pullRequests = prs
            lastUpdated = Date()
            notificationService.processNewPRs(filteredPRs, notificationsEnabled: settings.showNotifications)
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown(error.localizedDescription)
        }

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

}
