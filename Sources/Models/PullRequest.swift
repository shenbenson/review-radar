import Foundation

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
    var isTeamReviewRequested: Bool
    var teamName: String?
    var teamFilterKey: String?

    var authorIsBot: Bool { author.login.hasSuffix("[bot]") }

    struct Author: Codable, Equatable, Sendable, Hashable {
        let login: String
    }

    struct Repository: Codable, Equatable, Sendable, Hashable {
        let name: String
        let nameWithOwner: String
        var owner: String { nameWithOwner.components(separatedBy: "/").first ?? "" }
    }
}

enum ReviewStatus: String, Sendable, Codable, CaseIterable {
    case pending = "REVIEW_REQUIRED"
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
}

struct SearchPRResult: Codable, Sendable {
    let number: Int
    let title: String
    let author: PullRequest.Author
    let repository: PullRequest.Repository
    let isDraft: Bool
    let createdAt: Date
    let updatedAt: Date
    let url: String

    func toPullRequest() -> PullRequest {
        PullRequest(
            number: number, title: title, author: author,
            repository: repository, isDraft: isDraft,
            createdAt: createdAt, updatedAt: updatedAt,
            url: url, reviewStatus: .pending,
            isTeamReviewRequested: false, teamName: nil,
            teamFilterKey: nil
        )
    }
}

struct PRDetails: Sendable {
    let reviewStatus: ReviewStatus
    let isTeamReviewRequested: Bool
    let teamName: String?
    let teamFilterKey: String?
}

struct GitHubTeam: Sendable, Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let slug: String
    let organization: Organization

    struct Organization: Sendable, Codable, Hashable {
        let login: String
    }
}

struct RequestedReviewersResponse: Codable, Sendable {
    let users: [ReviewerUser]
    let teams: [ReviewerTeam]

    struct ReviewerUser: Codable, Sendable {
        let login: String
    }

    struct ReviewerTeam: Codable, Sendable {
        let name: String
        let slug: String
    }
}

struct ReviewResponse: Codable, Sendable {
    let state: String
}

enum AppError: Error, Equatable, Sendable {
    case ghNotInstalled
    case ghNotAuthenticated
    case networkError(String)
    case rateLimited(resetDate: Date)
    case unknown(String)
}
