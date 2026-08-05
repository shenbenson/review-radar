import AppKit
import Foundation
import UserNotifications

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private var seenReviewIDs: Set<String> = []
    private var authoredReviewDecisions: [String: ReviewDecision] = [:]
    private var authoredCIStatuses: [String: CIStatus] = [:]
    private var trackedAuthoredPRs: [String: PullRequest] = [:]
    private var isFirstReviewFetch = true
    private var isFirstAuthoredFetch = true
    private var activeSounds: [NSSound] = []

    func requestPermission() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// New review requests. `allIDs` seeds seen-set so filter toggles don't re-notify.
    func processReviewQueue(
        allIDs: Set<String>,
        notifiablePRs: [PullRequest],
        notificationsEnabled: Bool,
        customSoundPath: String
    ) {
        if isFirstReviewFetch {
            seenReviewIDs = allIDs
            isFirstReviewFetch = false
            return
        }

        if notificationsEnabled {
            let newIDs = Set(notifiablePRs.map(\.id)).subtracting(seenReviewIDs)
            for pr in notifiablePRs where newIDs.contains(pr.id) {
                send(
                    id: "review-\(pr.id)",
                    title: "New Review Request",
                    body: "\(pr.author.login) · \(pr.repository.nameWithOwner)#\(pr.number): \(pr.title)",
                    url: pr.url,
                    pr: pr,
                    customSoundPath: customSoundPath
                )
            }
        }

        seenReviewIDs.formUnion(allIDs)
    }

    /// Authored open PRs: review-decision changes, CI green transitions, merges.
    func processAuthoredQueue(
        openAuthoredPRs: [PullRequest],
        notifyReviews: Bool,
        notifyMerged: Bool,
        notifyCIGreen: Bool,
        customSoundPath: String
    ) {
        let currentByID = Dictionary(uniqueKeysWithValues: openAuthoredPRs.map { ($0.id, $0) })

        if isFirstAuthoredFetch {
            authoredReviewDecisions = Dictionary(uniqueKeysWithValues: openAuthoredPRs.map { ($0.id, $0.reviewDecision) })
            authoredCIStatuses = Dictionary(uniqueKeysWithValues: openAuthoredPRs.map { ($0.id, $0.ciStatus) })
            trackedAuthoredPRs = currentByID
            isFirstAuthoredFetch = false
            return
        }

        if notifyReviews {
            for pr in openAuthoredPRs {
                let previous = authoredReviewDecisions[pr.id] ?? .none
                let current = pr.reviewDecision
                guard previous != current else { continue }

                switch current {
                case .approved:
                    send(
                        id: "mine-approved-\(pr.id)-\(current.rawValue)",
                        title: "PR Approved",
                        body: "\(pr.repository.nameWithOwner)#\(pr.number): \(pr.title)",
                        url: pr.url,
                        pr: pr,
                        customSoundPath: customSoundPath
                    )
                case .changesRequested:
                    send(
                        id: "mine-changes-\(pr.id)-\(current.rawValue)",
                        title: "Changes Requested",
                        body: "\(pr.repository.nameWithOwner)#\(pr.number): \(pr.title)",
                        url: pr.url,
                        pr: pr,
                        customSoundPath: customSoundPath
                    )
                case .reviewRequired, .none:
                    break
                }
            }
        }

        if notifyCIGreen {
            for pr in openAuthoredPRs {
                let previous = authoredCIStatuses[pr.id] ?? .unknown
                let current = pr.ciStatus
                // Only when newly all-green, and it wasn't already green.
                guard current == .success, previous != .success else { continue }
                // Skip unknown→success on first sight of a brand-new PR mid-session
                // if we never had a prior reading — still notify if we knew a non-green state.
                guard previous == .pending || previous == .failure || previous == .error || previous == .expected
                else { continue }

                send(
                    id: "mine-ci-green-\(pr.id)-\(pr.updatedAt.timeIntervalSince1970)",
                    title: "CI Passing",
                    body: "\(pr.repository.nameWithOwner)#\(pr.number): \(pr.title)",
                    url: pr.url,
                    pr: pr,
                    customSoundPath: customSoundPath
                )
            }
        }

        if notifyMerged {
            let vanished = trackedAuthoredPRs.keys.filter { currentByID[$0] == nil }
            if !vanished.isEmpty {
                let candidates = vanished.compactMap { trackedAuthoredPRs[$0] }
                Task {
                    await notifyMergedPRs(candidates, customSoundPath: customSoundPath)
                }
            }
        }

        for pr in openAuthoredPRs {
            authoredReviewDecisions[pr.id] = pr.reviewDecision
            authoredCIStatuses[pr.id] = pr.ciStatus
        }
        trackedAuthoredPRs = currentByID
    }

    private func notifyMergedPRs(_ candidates: [PullRequest], customSoundPath: String) async {
        let merged = await Self.mergedPullRequests(among: candidates)
        for pr in merged {
            send(
                id: "mine-merged-\(pr.id)",
                title: "PR Merged",
                body: "\(pr.repository.nameWithOwner)#\(pr.number): \(pr.title)",
                url: pr.url,
                pr: pr,
                customSoundPath: customSoundPath
            )
        }
    }

    /// Returns the subset of PRs whose GitHub state is MERGED.
    private static func mergedPullRequests(among prs: [PullRequest]) async -> [PullRequest] {
        guard !prs.isEmpty else { return [] }
        var merged: [PullRequest] = []
        let chunkSize = 10

        for start in stride(from: 0, to: prs.count, by: chunkSize) {
            let chunk = Array(prs[start..<min(start + chunkSize, prs.count)])
            var fields: [String] = []
            for (i, pr) in chunk.enumerated() {
                let owner = pr.repository.owner.replacingOccurrences(of: "\"", with: "")
                let name = pr.repository.name.replacingOccurrences(of: "\"", with: "")
                fields.append("""
                p\(i): repository(owner: "\(owner)", name: "\(name)") {
                  pullRequest(number: \(pr.number)) { state }
                }
                """)
            }
            let query = "query {\n" + fields.joined(separator: "\n") + "\n}"
            let payload: [String: Any] = ["query": query]
            guard let body = try? JSONSerialization.data(withJSONObject: payload),
                  let result = try? await ProcessRunner.ghJSONInput(
                      ["api", "graphql", "--input", "-"],
                      body: body
                  ),
                  result.exitCode == 0,
                  let root = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any],
                  let data = root["data"] as? [String: Any]
            else { continue }

            for (i, pr) in chunk.enumerated() {
                guard let repo = data["p\(i)"] as? [String: Any],
                      let pull = repo["pullRequest"] as? [String: Any],
                      let state = pull["state"] as? String,
                      state.uppercased() == "MERGED"
                else { continue }
                merged.append(pr)
            }
        }
        return merged
    }

    private func send(
        id: String,
        title: String,
        body: String,
        url: String,
        pr: PullRequest,
        customSoundPath: String
    ) {
        let hasCustomSound = !customSoundPath.isEmpty
            && FileManager.default.fileExists(atPath: customSoundPath)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = hasCustomSound ? nil : .default
        content.userInfo = ["url": url]

        Task {
            if let attachment = await Self.avatarAttachment(for: pr) {
                content.attachments = [attachment]
            }
            let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
            if hasCustomSound { playSound(atPath: customSoundPath) }
        }
    }

    private static func avatarAttachment(for pr: PullRequest) async -> UNNotificationAttachment? {
        guard let url = await resolveAvatarURL(for: pr) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("rr-avatar-\(UUID().uuidString).png")
            try data.write(to: fileURL)
            return try UNNotificationAttachment(identifier: "avatar", url: fileURL, options: nil)
        } catch {
            return nil
        }
    }

    private static func resolveAvatarURL(for pr: PullRequest) async -> URL? {
        if let direct = pr.authorAvatarURL { return direct }
        guard pr.authorIsBot, !pr.author.id.isEmpty else { return nil }
        guard let result = try? await ProcessRunner.gh(
            "api", "graphql",
            "-f", "query=query($id:ID!){node(id:$id){... on Bot{avatarUrl} ... on User{avatarUrl}}}",
            "-f", "id=\(pr.author.id)",
            "--jq", ".data.node.avatarUrl"
        ), result.exitCode == 0 else { return nil }
        return URL(string: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func playSound(atPath path: String) {
        activeSounds.removeAll { !$0.isPlaying }
        guard let sound = NSSound(contentsOf: URL(fileURLWithPath: path), byReference: true) else { return }
        sound.volume = 1.0
        activeSounds.append(sound)
        sound.play()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let urlString = userInfo["url"] as? String,
           let url = URL(string: urlString)
        {
            Task { @MainActor in
                NSWorkspace.shared.open(url)
            }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}
