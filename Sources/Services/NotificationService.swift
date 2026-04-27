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

    func processNewPRs(_ prs: [PullRequest], notificationsEnabled: Bool) {
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
            sendNotification(for: pr)
        }
        seenPRIDs = currentIDs
    }

    private func sendNotification(for pr: PullRequest) {
        let content = UNMutableNotificationContent()
        content.title = "New Review Request"
        content.body = "\(pr.author.login) requested your review on \(pr.repository.nameWithOwner)#\(pr.number): \(pr.title)"
        content.sound = .default
        content.userInfo = ["url": pr.url]

        let request = UNNotificationRequest(
            identifier: pr.id,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
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
