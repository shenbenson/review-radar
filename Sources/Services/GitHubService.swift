import Foundation

actor GitHubService {
    private var detailsCache: [String: PRDetails] = [:]
    private var userTeams: [GitHubTeam] = []
    private var lastTeamFetch: Date?

    // MARK: - Health Checks

    func checkGHInstalled() async -> Bool {
        guard let result = try? await ProcessRunner.gh("version") else { return false }
        return result.exitCode == 0
    }

    func checkGHAuthenticated() async -> Bool {
        guard let result = try? await ProcessRunner.gh("auth", "status") else { return false }
        return result.exitCode == 0
    }

    // MARK: - Search PRs

    func searchPRs(limit: Int) async throws -> [PullRequest] {
        let result = try await ProcessRunner.gh(
            "search", "prs",
            "--review-requested=@me",
            "--state=open",
            "--json", "number,title,author,repository,isDraft,createdAt,updatedAt,url",
            "--limit", "\(limit)"
        )

        if result.exitCode != 0 {
            throw classifyError(stderr: result.stderr, stdout: result.stdout)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let searchResults = try decoder.decode([SearchPRResult].self, from: Data(result.stdout.utf8))
        return searchResults.map { $0.toPullRequest() }
    }

    // MARK: - Enrich PRs with Review Status + Team Info

    func enrichPRs(_ prs: [PullRequest]) async -> [PullRequest] {
        await refreshTeamsIfNeeded()

        return await withTaskGroup(of: (Int, PRDetails?).self, returning: [PullRequest].self) { group in
            for (index, pr) in prs.enumerated() {
                group.addTask { [self] in
                    let details = await self.fetchPRDetails(pr: pr)
                    return (index, details)
                }
            }

            var enriched = prs
            for await (index, details) in group {
                if let details {
                    enriched[index].reviewStatus = details.reviewStatus
                    enriched[index].isTeamReviewRequested = details.isTeamReviewRequested
                    enriched[index].teamName = details.teamName
                    enriched[index].teamFilterKey = details.teamFilterKey
                }
            }
            return enriched
        }
    }

    private func fetchPRDetails(pr: PullRequest) async -> PRDetails? {
        let owner = pr.repository.owner
        let repo = pr.repository.name
        let cacheKey = "\(pr.repository.nameWithOwner)#\(pr.number)@\(pr.updatedAt.timeIntervalSince1970)"

        if let cached = detailsCache[cacheKey] {
            return cached
        }

        async let reviewStatus = fetchReviewStatus(owner: owner, repo: repo, number: pr.number)
        async let teamInfo = fetchTeamReviewInfo(owner: owner, repo: repo, number: pr.number)

        let status = await reviewStatus
        let team = await teamInfo

        let details = PRDetails(
            reviewStatus: status,
            isTeamReviewRequested: team.isTeamReview,
            teamName: team.teamName,
            teamFilterKey: team.teamFilterKey
        )
        detailsCache[cacheKey] = details

        // Evict old entries to prevent unbounded growth
        if detailsCache.count > 500 {
            let sortedKeys = detailsCache.keys.sorted()
            for key in sortedKeys.prefix(100) {
                detailsCache.removeValue(forKey: key)
            }
        }

        return details
    }

    // MARK: - Review Status

    private func fetchReviewStatus(owner: String, repo: String, number: Int) async -> ReviewStatus {
        do {
            let result = try await ProcessRunner.gh(
                "api", "repos/\(owner)/\(repo)/pulls/\(number)/reviews",
                "--jq", "[.[] | select(.state != \"COMMENTED\" and .state != \"DISMISSED\")] | last | .state"
            )
            guard result.exitCode == 0 else { return .pending }
            let state = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            switch state {
            case "APPROVED": return .approved
            case "CHANGES_REQUESTED": return .changesRequested
            default: return .pending
            }
        } catch {
            return .pending
        }
    }

    // MARK: - Team Review Info

    private func fetchTeamReviewInfo(owner: String, repo: String, number: Int) async -> (isTeamReview: Bool, teamName: String?, teamFilterKey: String?) {
        do {
            let result = try await ProcessRunner.gh(
                "api", "repos/\(owner)/\(repo)/pulls/\(number)/requested_reviewers"
            )
            guard result.exitCode == 0 else { return (false, nil, nil) }
            let response = try JSONDecoder().decode(RequestedReviewersResponse.self, from: Data(result.stdout.utf8))

            for team in response.teams {
                let filterKey = "\(owner)/\(team.slug)"
                let isUserTeam = userTeams.contains { t in
                    t.slug == team.slug && t.organization.login.lowercased() == owner.lowercased()
                }
                if isUserTeam {
                    return (true, team.name, filterKey)
                }
            }

            if let firstTeam = response.teams.first {
                return (true, firstTeam.name, "\(owner)/\(firstTeam.slug)")
            }

            return (false, nil, nil)
        } catch {
            return (false, nil, nil)
        }
    }

    // MARK: - Teams

    func fetchUserTeams() async -> [GitHubTeam] {
        do {
            let result = try await ProcessRunner.gh("api", "/user/teams", "--paginate")
            guard result.exitCode == 0 else { return [] }
            let teams = try JSONDecoder().decode([GitHubTeam].self, from: Data(result.stdout.utf8))
            userTeams = teams
            lastTeamFetch = Date()
            return teams
        } catch {
            return []
        }
    }

    private func refreshTeamsIfNeeded() async {
        let thirtyMinutes: TimeInterval = 30 * 60
        if lastTeamFetch == nil || Date().timeIntervalSince(lastTeamFetch!) > thirtyMinutes {
            _ = await fetchUserTeams()
        }
    }

    // MARK: - Error Classification

    private func classifyError(stderr: String, stdout: String) -> AppError {
        let combined = stderr + stdout
        if combined.contains("rate limit") || combined.contains("API rate limit") || combined.contains("403") {
            // Try to parse rate limit reset time
            if let range = combined.range(of: #"resets in (\d+)"#, options: .regularExpression),
               let seconds = Int(combined[range].components(separatedBy: " ").last ?? "")
            {
                return .rateLimited(resetDate: Date().addingTimeInterval(TimeInterval(seconds)))
            }
            return .rateLimited(resetDate: Date().addingTimeInterval(60))
        }
        if combined.contains("not logged") || combined.contains("auth login") || combined.contains("authentication") {
            return .ghNotAuthenticated
        }
        if combined.contains("command not found") || combined.contains("not installed") || combined.contains("No such file") {
            return .ghNotInstalled
        }
        if combined.contains("Could not resolve host") || combined.contains("network") || combined.contains("timeout") {
            return .networkError(stderr)
        }
        return .unknown(stderr.isEmpty ? stdout : stderr)
    }
}
