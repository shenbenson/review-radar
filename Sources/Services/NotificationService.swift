import AppKit
import Foundation
import UserNotifications

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private var seenPRIDs: Set<String> = []
    private var isFirstFetch = true

    func requestPermission() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func processNewPRs(_ prs: [PullRequest], notificationsEnabled: Bool, loudSound: Bool) {
        let currentIDs = Set(prs.map(\.id))

        if isFirstFetch {
            seenPRIDs = currentIDs
            isFirstFetch = false
            return
        }

        guard notificationsEnabled else {
            seenPRIDs = currentIDs
            return
        }

        let newIDs = currentIDs.subtracting(seenPRIDs)
        for pr in prs where newIDs.contains(pr.id) {
            sendNotification(for: pr, loudSound: loudSound)
        }
        seenPRIDs = currentIDs
    }

    private func sendNotification(for pr: PullRequest, loudSound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "New Review Request"
        content.body = "\(pr.author.login) requested your review on \(pr.repository.nameWithOwner)#\(pr.number): \(pr.title)"
        // A loud, full-volume NSSound is played separately below; silence the
        // built-in sound in that case so it isn't doubled at notification volume.
        content.sound = loudSound ? nil : .default
        content.userInfo = ["url": pr.url]

        Task {
            if let attachment = await Self.avatarAttachment(for: pr) {
                content.attachments = [attachment]
            }
            let request = UNNotificationRequest(identifier: pr.id, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
            if loudSound { Self.playLoudSound() }
        }
    }

    /// Downloads the PR author's GitHub avatar and wraps it as a notification attachment.
    private static func avatarAttachment(for pr: PullRequest) async -> UNNotificationAttachment? {
        guard let url = pr.authorAvatarURL else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).png")
            try data.write(to: fileURL)
            return try UNNotificationAttachment(identifier: "avatar", url: fileURL, options: nil)
        } catch {
            return nil
        }
    }

    /// Plays an attention-grabbing system sound at full output volume, bypassing
    /// the (often quiet) system notification volume.
    private static func playLoudSound() {
        guard let sound = NSSound(named: "Sosumi") else { return }
        sound.volume = 1.0
        sound.play()
    }

    // Handle notification click — open PR in browser
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
        completionHandler([.banner, .sound])
    }
}
