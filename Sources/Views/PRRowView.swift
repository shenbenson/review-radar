import SwiftUI

struct PRRowView: View {
    let pr: PullRequest
    let style: PopoverTab
    let onTap: () -> Void
    var onSnooze: ((SnoozeDuration) -> Void)?
    var onMute: (() -> Void)?
    var onIgnoreRepo: (() -> Void)?

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                avatar
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("#\(pr.number)")
                            .font(.caption.monospaced().weight(.medium))
                            .foregroundStyle(.tertiary)
                        if pr.isDraft {
                            statusBadge("Draft", color: .secondary)
                        } else {
                            statusBadge("Ready", color: .green)
                        }
                        if style == .toReview, let teamName = pr.teamName {
                            statusBadge(teamName, color: .blue)
                        }
                        Spacer(minLength: 0)
                        Text(relativeAge(from: ageDate))
                            .font(.caption2)
                            .foregroundStyle(ageColor(from: ageDate))
                    }

                    Text(pr.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Text(pr.author.login)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if pr.authorIsBot {
                            statusBadge("bot", color: .secondary)
                        }

                        Spacer(minLength: 4)

                        diffLabel
                        ciPill
                        reviewPill
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(HoverBackground())
        .contextMenu {
            Button("Open") { onTap() }
            Divider()
            Menu("Snooze") {
                ForEach(SnoozeDuration.allCases) { duration in
                    Button(duration.label) {
                        onSnooze?(duration)
                    }
                }
            }
            Button("Mute") {
                onMute?()
            }
            Divider()
            Button("Ignore \(pr.repository.nameWithOwner)") {
                onIgnoreRepo?()
            }
        }
    }

    private var ageDate: Date {
        style == .myPRs ? pr.updatedAt : pr.createdAt
    }

    private var avatar: some View {
        AsyncImage(url: pr.authorAvatarURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                ZStack {
                    Color.primary.opacity(0.06)
                    Text(String(pr.author.login.prefix(1)).uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
    }

    private var diffLabel: some View {
        HStack(spacing: 2) {
            Text("+\(pr.additions)")
                .foregroundStyle(.green)
            Text("-\(pr.deletions)")
                .foregroundStyle(.red)
        }
        .font(.caption2.monospacedDigit().weight(.medium))
        .opacity(pr.additions == 0 && pr.deletions == 0 ? 0.4 : 1)
    }

    private var ciPill: some View {
        HStack(spacing: 3) {
            Image(systemName: pr.ciStatus.systemImage)
                .font(.caption2)
            if pr.ciStatus != .unknown && pr.ciStatus != .success {
                Text(pr.ciStatus.label)
                    .font(.caption2.weight(.medium))
            }
        }
        .foregroundStyle(pr.ciStatus.color)
        .help("CI: \(pr.ciStatus.label)")
    }

    @ViewBuilder
    private var reviewPill: some View {
        if style == .toReview {
            pill(text: viewerReviewLabel, color: viewerReviewColor)
        } else {
            pill(text: pr.reviewDecision.label, color: decisionColor)
        }
    }

    private var viewerReviewLabel: String {
        switch pr.reviewStatus {
        case .pending:
            if pr.isDirectReviewRequested && pr.isTeamReviewRequested {
                return "You + team"
            }
            if pr.isTeamReviewRequested { return "Team" }
            return "Your review"
        default:
            return pr.reviewStatus.label
        }
    }

    private var viewerReviewColor: Color {
        switch pr.reviewStatus {
        case .pending: .secondary
        case .approved: .green
        case .changesRequested: .orange
        case .commented: .blue
        case .dismissed: .secondary
        }
    }

    private var decisionColor: Color {
        switch pr.reviewDecision {
        case .none, .reviewRequired: .secondary
        case .approved: .green
        case .changesRequested: .orange
        }
    }

    private func pill(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
            .lineLimit(1)
    }

    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.12), in: Capsule())
            .lineLimit(1)
    }

    private func relativeAge(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func ageColor(from date: Date) -> Color {
        let hours = Date().timeIntervalSince(date) / 3600
        return switch hours {
        case ..<24: .secondary
        case ..<72: .yellow
        case ..<168: .orange
        default: .red
        }
    }
}

struct HoverBackground: View {
    @State private var isHovered = false

    var body: some View {
        Rectangle()
            .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
            .onHover { isHovered = $0 }
    }
}
