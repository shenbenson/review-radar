import SwiftUI

struct PRRowView: View {
    let pr: PullRequest
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("#\(pr.number)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                    if pr.isDraft {
                        inlineBadge("Draft")
                    }
                    if let teamName = pr.teamName {
                        inlineBadge(teamName)
                    }
                    Spacer()
                }

                Text(pr.title)
                    .lineLimit(2)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 4) {
                    Text(pr.author.login)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if pr.authorIsBot {
                        inlineBadge("bot")
                    }
                    Text("\u{00B7}")
                        .foregroundStyle(.quaternary)
                    Text(relativeAge(from: pr.createdAt))
                        .font(.caption)
                        .foregroundStyle(ageColor(from: pr.createdAt))
                    Spacer()
                    reviewStatusPill(pr.reviewStatus)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(HoverBackground())
    }

    private func inlineBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }

    private func reviewStatusPill(_ status: ReviewStatus) -> some View {
        let (text, color): (String, Color) = switch status {
        case .pending: ("Pending", .secondary)
        case .approved: ("Approved", .green)
        case .changesRequested: ("Changes", .orange)
        }
        return Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(status == .pending ? Color.secondary : color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                status == .pending
                    ? AnyShapeStyle(.quaternary)
                    : AnyShapeStyle(color.opacity(0.12)),
                in: Capsule()
            )
    }

    private func relativeAge(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func ageColor(from date: Date) -> Color {
        let hours = Date().timeIntervalSince(date) / 3600
        return switch hours {
        case ..<24: .green
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
            .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
            .onHover { isHovered = $0 }
    }
}
