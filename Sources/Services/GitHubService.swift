import Foundation

actor GitHubService {
    private var userTeams: [GitHubTeam] = []
    private var lastTeamFetch: Date?
    private var viewerLogin: String?
    /// Skip `gh version` / `gh auth status` on every poll once healthy.
    private var lastHealthOK: Date?
    private static let healthCacheTTL: TimeInterval = 10 * 60

    // Keep search lean — nested commits/statusCheckRollup on large
    // review-requested searches reliably 502s GitHub's gateway.
    private static let prSearchQuery = """
    query($searchQuery: String!, $limit: Int!) {
      viewer { login }
      search(query: $searchQuery, type: ISSUE, first: $limit) {
        nodes {
          ... on PullRequest {
            number
            title
            url
            isDraft
            createdAt
            updatedAt
            additions
            deletions
            reviewDecision
            author {
              __typename
              login
              ... on User { id avatarUrl }
              ... on Bot { id avatarUrl }
            }
            repository {
              name
              nameWithOwner
              owner { login }
            }
            viewerLatestReview { state }
            reviewRequests(first: 15) {
              nodes {
                requestedReviewer {
                  __typename
                  ... on User { login }
                  ... on Team {
                    name
                    slug
                    combinedSlug
                  }
                }
              }
            }
          }
        }
      }
    }
    """

    private static let ciBatchPrefix = "query {"
    private static let ciBatchSuffix = "}"

    // MARK: - Health Checks

    /// Cheap gate before polling. Cached so we don't spawn two `gh` processes every refresh.
    func ensureGHReady() async -> AppError? {
        if let last = lastHealthOK, Date().timeIntervalSince(last) < Self.healthCacheTTL {
            return nil
        }
        guard let ver = try? await ProcessRunner.gh("version"), ver.exitCode == 0 else {
            return .ghNotInstalled
        }
        guard let auth = try? await ProcessRunner.gh("auth", "status"), auth.exitCode == 0 else {
            return .ghNotAuthenticated
        }
        lastHealthOK = Date()
        return nil
    }

    func invalidateHealthCache() {
        lastHealthOK = nil
    }

    // MARK: - Fetch queues

    func fetchReviewQueue(limit: Int) async throws -> [PullRequest] {
        try await searchPullRequests(
            query: "is:open is:pr review-requested:@me",
            limit: limit,
            queue: .review
        )
    }

    func fetchAuthoredQueue(limit: Int) async throws -> [PullRequest] {
        try await searchPullRequests(
            query: "is:open is:pr author:@me",
            limit: limit,
            queue: .authored
        )
    }

    /// Cached teams (refreshed at most every 30 min during PR fetches).
    func cachedTeams() -> [GitHubTeam] { userTeams }

    private func searchPullRequests(query: String, limit: Int, queue: PRQueue) async throws -> [PullRequest] {
        let clamped = min(max(limit, 1), 100)
        async let teamsRefresh: Void = refreshTeamsIfNeeded()
        let result = try await graphql(
            query: Self.prSearchQuery,
            variables: [
                "searchQuery": .string(query),
                "limit": .int(clamped),
            ]
        )
        _ = await teamsRefresh

        let decoded = try decodeGraphQL(result)
        if let login = decoded.data?.viewer?.login {
            viewerLogin = login
            lastHealthOK = Date()
        }

        let nodes = decoded.data?.search?.nodes ?? []
        let prs = nodes.compactMap { node -> PullRequest? in
            guard let node, node.number != nil else { return nil }
            return node.toPullRequest(queue: queue, viewerLogin: viewerLogin, userTeams: userTeams)
        }
        return await attachCIStatus(to: prs)
    }

    /// Fetch CI rollup in GraphQL batches (kept out of search to avoid gateway 502s).
    /// Failed batches mark PRs as `.unavailable` (not `.unknown` / "No checks").
    private func attachCIStatus(to prs: [PullRequest]) async -> [PullRequest] {
        guard !prs.isEmpty else { return prs }
        let chunkSize = 25
        let chunks: [[PullRequest]] = stride(from: 0, to: prs.count, by: chunkSize).map { start in
            Array(prs[start..<min(start + chunkSize, prs.count)])
        }

        // Run a few CI batches at a time — each batch is a separate `gh` process.
        var statuses: [String: CIStatus] = [:]
        statuses.reserveCapacity(prs.count)
        let maxConcurrent = 3
        var next = 0
        while next < chunks.count {
            let end = min(next + maxConcurrent, chunks.count)
            let batch = Array(chunks[next..<end])
            next = end

            await withTaskGroup(of: [String: CIStatus].self) { group in
                for chunk in batch {
                    group.addTask {
                        await self.fetchCIStatusChunk(chunk)
                    }
                }
                for await partial in group {
                    statuses.merge(partial) { _, new in new }
                }
            }
        }

        return prs.map { pr in
            var copy = pr
            copy.ciStatus = statuses[pr.id] ?? .unavailable
            return copy
        }
    }

    private func fetchCIStatusChunk(_ chunk: [PullRequest]) async -> [String: CIStatus] {
        var fields: [String] = []
        for (i, pr) in chunk.enumerated() {
            let owner = pr.repository.owner.replacingOccurrences(of: "\"", with: "")
            let name = pr.repository.name.replacingOccurrences(of: "\"", with: "")
            fields.append("""
            p\(i): repository(owner: "\(owner)", name: "\(name)") {
              pullRequest(number: \(pr.number)) {
                commits(last: 1) {
                  nodes {
                    commit {
                      statusCheckRollup { state }
                    }
                  }
                }
              }
            }
            """)
        }
        let query = "query {\n" + fields.joined(separator: "\n") + "\n}"
        guard let stdout = try? await graphql(query: query, variables: [:]),
              let data = try? JSONSerialization.jsonObject(with: Data(stdout.utf8)) as? [String: Any],
              let root = data["data"] as? [String: Any]
        else {
            return Dictionary(uniqueKeysWithValues: chunk.map { ($0.id, CIStatus.unavailable) })
        }

        var statuses: [String: CIStatus] = [:]
        for (i, pr) in chunk.enumerated() {
            guard let repo = root["p\(i)"] as? [String: Any],
                  let pull = repo["pullRequest"] as? [String: Any],
                  let commits = pull["commits"] as? [String: Any],
                  let nodes = commits["nodes"] as? [[String: Any]],
                  let commit = nodes.last?["commit"] as? [String: Any]
            else {
                statuses[pr.id] = .unavailable
                continue
            }
            let state = (commit["statusCheckRollup"] as? [String: Any])?["state"] as? String
            statuses[pr.id] = mapCIState(state)
        }
        return statuses
    }

    private func mapCIState(_ state: String?) -> CIStatus {
        switch state?.uppercased() {
        case "SUCCESS": .success
        case "FAILURE": .failure
        case "PENDING": .pending
        case "ERROR": .error
        case "EXPECTED": .expected
        default: .unknown
        }
    }

    /// GraphQL via JSON stdin, with retries on transient gateway errors.
    private func graphql(query: String, variables: [String: JSONValue], attempts: Int = 3) async throws -> String {
        let payload: [String: Any] = [
            "query": query,
            "variables": Dictionary(uniqueKeysWithValues: variables.map { ($0.key, $0.value.foundationValue) }),
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)

        var lastError: AppError = .unknown("GraphQL request failed")
        for attempt in 1...attempts {
            let result = try await ProcessRunner.ghJSONInput(
                ["api", "graphql", "--input", "-"],
                body: body
            )

            if result.exitCode == 0, !result.stdout.isEmpty {
                // GitHub sometimes returns 200 with errors array for partial failures
                return result.stdout
            }

            let err = classifyError(stderr: result.stderr, stdout: result.stdout)
            lastError = err
            if case .ghNotAuthenticated = err { lastHealthOK = nil }
            if isTransient(err), attempt < attempts {
                try? await Task.sleep(for: .milliseconds(400 * attempt))
                continue
            }
            throw err
        }
        throw lastError
    }

    private func isTransient(_ error: AppError) -> Bool {
        switch error {
        case .networkError: return true
        case .unknown(let message):
            let m = message.lowercased()
            return m.contains("502") || m.contains("503") || m.contains("504")
                || m.contains("bad gateway") || m.contains("timeout")
                || m.contains("temporarily") || m.contains("server error")
        case .rateLimited: return false
        default: return false
        }
    }

    private enum JSONValue {
        case string(String)
        case int(Int)

        var foundationValue: Any {
            switch self {
            case .string(let s): return s
            case .int(let i): return i
            }
        }
    }

    // MARK: - Teams

    func fetchUserTeams() async -> [GitHubTeam] {
        do {
            let result = try await ProcessRunner.gh("api", "/user/teams", "--paginate")
            guard result.exitCode == 0 else { return userTeams }
            let teams = try JSONDecoder().decode([GitHubTeam].self, from: Data(result.stdout.utf8))
            userTeams = teams
            lastTeamFetch = Date()
            return teams
        } catch {
            return userTeams
        }
    }

    private func refreshTeamsIfNeeded() async {
        let thirtyMinutes: TimeInterval = 30 * 60
        if lastTeamFetch == nil || Date().timeIntervalSince(lastTeamFetch!) > thirtyMinutes {
            _ = await fetchUserTeams()
        }
    }

    // MARK: - Decoding

    private func decodeGraphQL(_ stdout: String) throws -> GraphQLResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = ISO8601DateFormatter.fractional.date(from: string)
                ?? ISO8601DateFormatter.standard.date(from: string)
            {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }

        let response = try decoder.decode(GraphQLResponse.self, from: Data(stdout.utf8))
        if let message = response.errors?.first?.message {
            throw classifyError(stderr: message, stdout: stdout)
        }
        return response
    }

    // MARK: - Error Classification

    private func classifyError(stderr: String, stdout: String) -> AppError {
        let combined = stderr + stdout
        if combined.localizedCaseInsensitiveContains("rate limit")
            || combined.localizedCaseInsensitiveContains("API rate limit")
            || combined.contains("403")
        {
            if let range = combined.range(of: #"resets? in (\d+)"#, options: .regularExpression),
               let seconds = Int(combined[range].components(separatedBy: CharacterSet.decimalDigits.inverted).joined())
            {
                return .rateLimited(resetDate: Date().addingTimeInterval(TimeInterval(seconds)))
            }
            return .rateLimited(resetDate: Date().addingTimeInterval(60))
        }
        if combined.localizedCaseInsensitiveContains("not logged")
            || combined.localizedCaseInsensitiveContains("auth login")
            || combined.localizedCaseInsensitiveContains("authentication")
            || combined.localizedCaseInsensitiveContains("Bad credentials")
        {
            return .ghNotAuthenticated
        }
        if combined.localizedCaseInsensitiveContains("command not found")
            || combined.localizedCaseInsensitiveContains("not installed")
            || combined.localizedCaseInsensitiveContains("No such file")
        {
            return .ghNotInstalled
        }
        if combined.localizedCaseInsensitiveContains("Could not resolve host")
            || combined.localizedCaseInsensitiveContains("network")
            || combined.localizedCaseInsensitiveContains("timeout")
            || combined.contains("502")
            || combined.contains("503")
            || combined.contains("504")
            || combined.localizedCaseInsensitiveContains("Bad Gateway")
            || combined.localizedCaseInsensitiveContains("Service Unavailable")
        {
            return .networkError(stderr.isEmpty ? stdout : stderr)
        }
        return .unknown(stderr.isEmpty ? stdout : stderr)
    }
}

// MARK: - GraphQL DTOs

private struct GraphQLResponse: Decodable, Sendable {
    let data: GraphQLData?
    let errors: [GraphQLError]?
}

private struct GraphQLError: Decodable, Sendable {
    let message: String
}

private struct GraphQLData: Decodable, Sendable {
    let viewer: GraphQLViewer?
    let search: GraphQLSearch?
}

private struct GraphQLViewer: Decodable, Sendable {
    let login: String
}

private struct GraphQLSearch: Decodable, Sendable {
    let nodes: [GraphQLPullRequest?]
}

private struct GraphQLPullRequest: Decodable, Sendable {
    let number: Int?
    let title: String?
    let url: String?
    let isDraft: Bool?
    let createdAt: Date?
    let updatedAt: Date?
    let additions: Int?
    let deletions: Int?
    let reviewDecision: String?
    let author: GraphQLAuthor?
    let repository: GraphQLRepository?
    let viewerLatestReview: GraphQLReviewState?
    let reviewRequests: GraphQLReviewRequests?
    let commits: GraphQLCommits?

    func toPullRequest(queue: PRQueue, viewerLogin: String?, userTeams: [GitHubTeam]) -> PullRequest? {
        guard let number, let title, let url, let createdAt, let updatedAt,
              let author, let repository
        else { return nil }

        let requests = reviewRequests?.nodes ?? []
        var isDirect = false
        var isTeam = false
        var teamName: String?
        var teamFilterKey: String?

        for node in requests {
            guard let reviewer = node?.requestedReviewer else { continue }
            switch reviewer.typename {
            case "User":
                if let login = reviewer.login,
                   let viewerLogin,
                   login.caseInsensitiveCompare(viewerLogin) == .orderedSame
                {
                    isDirect = true
                } else if reviewer.login != nil {
                    // Another user requested — ignore for our flags
                }
            case "Team":
                isTeam = true
                if teamName == nil {
                    teamName = reviewer.name
                    if let combined = reviewer.combinedSlug, !combined.isEmpty {
                        teamFilterKey = TeamFilterKey.normalize(combined)
                    } else if let slug = reviewer.slug {
                        let owner = repository.owner?.login
                            ?? repository.nameWithOwner?.components(separatedBy: "/").first
                            ?? ""
                        teamFilterKey = TeamFilterKey.make(org: owner, slug: slug)
                    }
                }
                // Prefer a team the user belongs to for filter key / name
                if let slug = reviewer.slug {
                    let owner = repository.owner?.login
                        ?? repository.nameWithOwner?.components(separatedBy: "/").first
                        ?? ""
                    if let match = userTeams.first(where: {
                        $0.slug.caseInsensitiveCompare(slug) == .orderedSame
                            && $0.organization.login.caseInsensitiveCompare(owner) == .orderedSame
                    }) {
                        teamName = match.name
                        teamFilterKey = match.filterKey
                    }
                } else if let combined = reviewer.combinedSlug {
                    let nk = TeamFilterKey.normalize(combined)
                    if let match = userTeams.first(where: { $0.filterKey == nk }) {
                        teamName = match.name
                        teamFilterKey = match.filterKey
                    }
                }
            default:
                break
            }
        }

        // Authored queue: not about "requested of me"
        if queue == .authored {
            isDirect = false
            // keep team flags false unless we want something else
            isTeam = false
            teamName = nil
            teamFilterKey = nil
        }

        return PullRequest(
            number: number,
            title: title,
            author: PullRequest.Author(
                login: author.login ?? "unknown",
                id: author.id ?? "",
                avatarUrl: author.avatarUrl,
                isBot: author.typename == "Bot" || (author.login ?? "").hasSuffix("[bot]")
            ),
            repository: PullRequest.Repository(
                name: repository.name ?? "",
                nameWithOwner: repository.nameWithOwner ?? ""
            ),
            isDraft: isDraft ?? false,
            createdAt: createdAt,
            updatedAt: updatedAt,
            url: url,
            reviewStatus: mapViewerReview(viewerLatestReview?.state),
            reviewDecision: mapReviewDecision(reviewDecision),
            ciStatus: .unknown,
            isDirectReviewRequested: isDirect,
            isTeamReviewRequested: isTeam,
            teamName: teamName,
            teamFilterKey: teamFilterKey,
            additions: additions ?? 0,
            deletions: deletions ?? 0,
            queue: queue
        )
    }

    private func mapViewerReview(_ state: String?) -> ReviewStatus {
        switch state?.uppercased() {
        case "APPROVED": .approved
        case "CHANGES_REQUESTED": .changesRequested
        case "COMMENTED": .commented
        case "DISMISSED": .dismissed
        case "PENDING": .pending
        default: .pending
        }
    }

    private func mapReviewDecision(_ decision: String?) -> ReviewDecision {
        switch decision?.uppercased() {
        case "APPROVED": .approved
        case "CHANGES_REQUESTED": .changesRequested
        case "REVIEW_REQUIRED": .reviewRequired
        default: .none
        }
    }

    private func mapCI(_ state: String?) -> CIStatus {
        switch state?.uppercased() {
        case "SUCCESS": .success
        case "FAILURE": .failure
        case "PENDING": .pending
        case "ERROR": .error
        case "EXPECTED": .expected
        default: .unknown
        }
    }
}

private struct GraphQLAuthor: Decodable, Sendable {
    let typename: String?
    let login: String?
    let id: String?
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case typename = "__typename"
        case login, id, avatarUrl
    }
}

private struct GraphQLRepository: Decodable, Sendable {
    let name: String?
    let nameWithOwner: String?
    let owner: GraphQLOwner?
}

private struct GraphQLOwner: Decodable, Sendable {
    let login: String
}

private struct GraphQLReviewState: Decodable, Sendable {
    let state: String?
}

private struct GraphQLReviewRequests: Decodable, Sendable {
    let nodes: [GraphQLReviewRequestNode?]?
}

private struct GraphQLReviewRequestNode: Decodable, Sendable {
    let requestedReviewer: GraphQLRequestedReviewer?
}

private struct GraphQLRequestedReviewer: Decodable, Sendable {
    let typename: String?
    let login: String?
    let name: String?
    let slug: String?
    let combinedSlug: String?

    enum CodingKeys: String, CodingKey {
        case typename = "__typename"
        case login, name, slug, combinedSlug
    }
}

private struct GraphQLCommits: Decodable, Sendable {
    let nodes: [GraphQLCommitNode?]?
}

private struct GraphQLCommitNode: Decodable, Sendable {
    let commit: GraphQLCommit?
}

private struct GraphQLCommit: Decodable, Sendable {
    let statusCheckRollup: GraphQLStatusRollup?
}

private struct GraphQLStatusRollup: Decodable, Sendable {
    let state: String?
}

private extension ISO8601DateFormatter {
    nonisolated(unsafe) static let standard: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
