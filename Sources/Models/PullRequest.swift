import Foundation
import SwiftUI

struct PullRequest: Identifiable, Equatable, Sendable {
    var id: String { "\(repository.nameWithOwner)#\(number)" }
    let number: Int
    let title: String
    let author: Author
    let repository: Repository
    let isDraft: Bool
    let createdAt: Date
    let updatedAt: Date
    let url: String
    var reviewStatus: ReviewStatus
    /// Overall review decision on the PR (useful for authored PRs).
    var reviewDecision: ReviewDecision
    var ciStatus: CIStatus
    var isDirectReviewRequested: Bool
    var isTeamReviewRequested: Bool
    var teamName: String?
    var teamFilterKey: String?
    var additions: Int
    var deletions: Int
    /// Which queue this PR was fetched for.
    var queue: PRQueue

    var authorIsBot: Bool { author.login.hasSuffix("[bot]") || author.isBot }

    var authorAvatarURL: URL? {
        if let url = author.avatarUrl, let parsed = URL(string: url) { return parsed }
        guard !authorIsBot else { return nil }
        return URL(string: "https://github.com/\(author.login).png?size=128")
    }

    struct Author: Codable, Equatable, Sendable, Hashable {
        let login: String
        var id: String = ""
        var avatarUrl: String? = nil
        var isBot: Bool = false
    }

    struct Repository: Codable, Equatable, Sendable, Hashable {
        let name: String
        let nameWithOwner: String
        var owner: String { nameWithOwner.components(separatedBy: "/").first ?? "" }
    }
}

enum PRQueue: String, Sendable, Codable, CaseIterable {
    case review
    case authored
}

enum ReviewStatus: String, Sendable, Codable, CaseIterable {
    case pending
    case approved
    case changesRequested
    case commented
    case dismissed

    var label: String {
        switch self {
        case .pending: "Pending"
        case .approved: "Approved"
        case .changesRequested: "Changes"
        case .commented: "Commented"
        case .dismissed: "Dismissed"
        }
    }
}

enum ReviewDecision: String, Sendable, Codable, CaseIterable {
    case none
    case reviewRequired
    case approved
    case changesRequested

    var label: String {
        switch self {
        case .none: "No reviews"
        case .reviewRequired: "Review required"
        case .approved: "Approved"
        case .changesRequested: "Changes requested"
        }
    }
}

enum CIStatus: String, Sendable, Codable, CaseIterable {
    case unknown
    case unavailable
    case pending
    case success
    case failure
    case error
    case expected

    var label: String {
        switch self {
        case .unknown: "No checks"
        case .unavailable: "CI unknown"
        case .pending: "Pending"
        case .success: "Passing"
        case .failure: "Failing"
        case .error: "Error"
        case .expected: "Expected"
        }
    }

    var systemImage: String {
        switch self {
        case .unknown: "minus.circle"
        case .unavailable: "questionmark.circle"
        case .pending: "clock"
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.circle.fill"
        case .error: "exclamationmark.circle.fill"
        case .expected: "clock"
        }
    }

    var color: Color {
        switch self {
        case .unknown, .unavailable: .secondary
        case .pending, .expected: .yellow
        case .success: .green
        case .failure, .error: .red
        }
    }
}

enum PRSortOption: String, Sendable, Codable, CaseIterable, Identifiable {
    case updatedNewest
    case updatedOldest
    case createdNewest
    case createdOldest
    case repoName
    case title

    var id: String { rawValue }

    var label: String {
        switch self {
        case .updatedNewest: "Updated · newest"
        case .updatedOldest: "Updated · oldest"
        case .createdNewest: "Created · newest"
        case .createdOldest: "Created · oldest"
        case .repoName: "Repository"
        case .title: "Title"
        }
    }

    func sorted(_ prs: [PullRequest]) -> [PullRequest] {
        switch self {
        case .updatedNewest: prs.sorted { $0.updatedAt > $1.updatedAt }
        case .updatedOldest: prs.sorted { $0.updatedAt < $1.updatedAt }
        case .createdNewest: prs.sorted { $0.createdAt > $1.createdAt }
        case .createdOldest: prs.sorted { $0.createdAt < $1.createdAt }
        case .repoName: prs.sorted {
            if $0.repository.nameWithOwner == $1.repository.nameWithOwner {
                return $0.number > $1.number
            }
            return $0.repository.nameWithOwner.localizedCaseInsensitiveCompare($1.repository.nameWithOwner) == .orderedAscending
        }
        case .title: prs.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        }
    }
}

struct GitHubTeam: Sendable, Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let slug: String
    let organization: Organization

    struct Organization: Sendable, Codable, Hashable {
        let login: String
    }

    /// Normalized lowercase `org/slug` for stable filter lookups.
    var filterKey: String { TeamFilterKey.normalize("\(organization.login)/\(slug)") }
}

enum TeamFilterKey {
    static func normalize(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func make(org: String, slug: String) -> String {
        normalize("\(org)/\(slug)")
    }
}

enum AppError: Error, Equatable, Sendable {
    case ghNotInstalled
    case ghNotAuthenticated
    case networkError(String)
    case rateLimited(resetDate: Date)
    case unknown(String)
}
