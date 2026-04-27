import SwiftUI

struct ErrorStateView: View {
    let error: AppError
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            switch error {
            case .ghNotInstalled:
                ghNotInstalledView
            case .ghNotAuthenticated:
                ghNotAuthenticatedView
            case .networkError(let message):
                networkErrorView(message)
            case .rateLimited(let resetDate):
                rateLimitedView(resetDate)
            case .unknown(let message):
                unknownErrorView(message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var ghNotInstalledView: some View {
        VStack(spacing: 8) {
            Text("GitHub CLI not found")
                .font(.headline)
            Text("Install gh to use ReviewRadar")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            copyButton("brew install gh")
        }
    }

    private var ghNotAuthenticatedView: some View {
        VStack(spacing: 8) {
            Text("Not authenticated")
                .font(.headline)
            Text("Sign in to GitHub CLI")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            copyButton("gh auth login")
        }
    }

    private func networkErrorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("Network error")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Button("Retry", action: onRetry)
                .controlSize(.small)
        }
    }

    private func rateLimitedView(_ resetDate: Date) -> some View {
        VStack(spacing: 8) {
            Text("Rate limited")
                .font(.headline)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let remaining = max(0, Int(resetDate.timeIntervalSinceNow))
                Text("Resets in \(remaining)s")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func unknownErrorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("Something went wrong")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Button("Retry", action: onRetry)
                .controlSize(.small)
        }
    }

    private func copyButton(_ command: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "doc.on.doc")
                    .font(.caption2)
                Text(command)
                    .font(.system(.caption, design: .monospaced))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
