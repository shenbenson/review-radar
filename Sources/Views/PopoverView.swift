import AppKit
import SwiftUI

struct PopoverView: View {
    @Bindable var appState: AppState
    var onOpenSettings: () -> Void
    @State private var collapsedSections: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            if let banner = appState.bannerError {
                bannerView(banner)
                Divider()
            }
            tabBar
            Divider()
            toolbarRow
            Divider()
            contentView
            Divider()
            footerView
        }
        .frame(width: 420, height: 560)
        .background(.background)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tint)
            Text("ReviewRadar")
                .font(.headline)
            Spacer()
            Button {
                Task { await appState.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .rotationEffect(.degrees(appState.isRefreshing ? 360 : 0))
                    .animation(
                        appState.isRefreshing
                            ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                            : .default,
                        value: appState.isRefreshing
                    )
            }
            .buttonStyle(.borderless)
            .disabled(appState.isRefreshing)
            .help("Refresh")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func bannerView(_ error: AppError) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(bannerText(error))
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer()
            Button("Retry") {
                Task { await appState.refresh() }
            }
            .controlSize(.mini)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }

    private func bannerText(_ error: AppError) -> String {
        switch error {
        case .rateLimited(let date):
            let s = max(0, Int(date.timeIntervalSinceNow))
            return "Rate limited · retries in \(s)s. Showing last results."
        case .networkError:
            return "Network error. Showing last results."
        case .ghNotAuthenticated:
            return "GitHub auth expired. Showing last results."
        case .ghNotInstalled:
            return "gh CLI missing. Showing last results."
        case .unknown(let msg):
            return msg.isEmpty ? "Refresh failed. Showing last results." : msg
        }
    }

    // MARK: - Tabs

    private var tabBar: some View {
        HStack(spacing: 4) {
            tabButton(.toReview, count: appState.pendingCount)
            if appState.settings.showMyPRs {
                tabButton(.myPRs, count: appState.myPRCount)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func tabButton(_ tab: PopoverTab, count: Int) -> some View {
        let selected = appState.settings.popoverTab == tab
        return Button {
            appState.settings.popoverTab = tab
        } label: {
            HStack(spacing: 6) {
                Text(tab.label)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                Text("\(count)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(selected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06), in: Capsule())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(selected ? Color.primary.opacity(0.08) : Color.clear, in: Capsule())
            .foregroundStyle(selected ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Toolbar

    private var toolbarRow: some View {
        HStack(spacing: 8) {
            if appState.settings.popoverTab == .toReview {
                FilterChip(title: "Bots", isOn: $appState.settings.showBotPRs)
                FilterChip(title: "Teams", isOn: $appState.settings.showTeamReviews)
            } else {
                FilterChip(title: "Bots", isOn: $appState.settings.showBotPRs)
            }

            Spacer()

            Menu {
                ForEach(PRSortOption.allCases) { option in
                    Button {
                        appState.settings.sortOption = option
                    } label: {
                        HStack {
                            Text(option.label)
                            if appState.settings.sortOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption2)
                    Text("Sort")
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.05), in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        if appState.isLoading {
            loadingView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = appState.error {
            ErrorStateView(error: error) {
                Task { await appState.refresh() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let groups = currentGroups
            if groups.isEmpty {
                emptyView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                prListView(groups)
            }
        }
    }

    private var currentGroups: [(repo: String, prs: [PullRequest])] {
        switch appState.settings.popoverTab {
        case .toReview: appState.groupedReviewPRs
        case .myPRs: appState.groupedAuthoredPRs
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Fetching pull requests…")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: appState.settings.popoverTab == .toReview ? "checkmark.circle" : "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text(appState.settings.popoverTab == .toReview ? "No pending reviews" : "No open PRs")
                .font(.headline)
            Text(appState.settings.popoverTab == .toReview ? "You're all caught up" : "Nothing authored by you right now")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
    }

    private func prListView(_ groups: [(repo: String, prs: [PullRequest])]) -> some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groups, id: \.repo) { group in
                    Section {
                        if !collapsedSections.contains(group.repo) {
                            ForEach(group.prs) { pr in
                                PRRowView(pr: pr, style: appState.settings.popoverTab) {
                                    appState.openPR(pr)
                                }
                                if pr.id != group.prs.last?.id {
                                    Divider()
                                }
                            }
                        }
                    } header: {
                        repoHeader(repo: group.repo, count: group.prs.count)
                    }
                }
            }
        }
        .scrollIndicators(.automatic)
    }

    private func repoHeader(repo: String, count: Int) -> some View {
        let collapsed = collapsedSections.contains(repo)
        return HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if collapsed {
                        collapsedSections.remove(repo)
                    } else {
                        collapsedSections.insert(repo)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                    Text(repo)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button("Ignore \(repo)") {
                    appState.ignoreRepo(repo)
                }
                Button("Copy name") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(repo, forType: .string)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Repo actions")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            if let lastUpdated = appState.lastUpdated {
                Text("Updated \(lastUpdated, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Not yet updated")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
