import SwiftUI

struct PopoverView: View {
    @Bindable var appState: AppState
    var onOpenSettings: () -> Void
    @State private var collapsedSections: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            filterChipBar
            Divider()
            contentView
            Divider()
            footerView
        }
        .frame(width: 400, height: 520)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("Pending Reviews")
                .font(.headline)
            Spacer()
            Button {
                Task { await appState.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(appState.isRefreshing ? 360 : 0))
                    .animation(
                        appState.isRefreshing
                            ? .linear(duration: 1).repeatForever(autoreverses: false)
                            : .default,
                        value: appState.isRefreshing
                    )
            }
            .buttonStyle(.borderless)
            .disabled(appState.isRefreshing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Filter Chips

    private var filterChipBar: some View {
        HStack(spacing: 8) {
            FilterChip(
                title: "Bot PRs",
                isOn: $appState.settings.showBotPRs
            )
            FilterChip(
                title: "Team Reviews",
                isOn: $appState.settings.showTeamReviews
            )
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        if appState.isLoading && appState.pullRequests.isEmpty {
            loadingView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = appState.error {
            ErrorStateView(error: error) {
                Task { await appState.refresh() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if appState.filteredPRs.isEmpty {
            emptyView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            prListView
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Fetching pull requests...")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("No pending reviews")
                .font(.headline)
            Text("You're all caught up!")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
    }

    private var prListView: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ForEach(appState.groupedPRs, id: \.repo) { group in
                    repoSection(repo: group.repo, prs: group.prs)
                }
            }
        }
        .scrollIndicators(.automatic)
    }

    private func repoSection(repo: String, prs: [PullRequest]) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if collapsedSections.contains(repo) {
                        collapsedSections.remove(repo)
                    } else {
                        collapsedSections.insert(repo)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: collapsedSections.contains(repo) ? "chevron.right" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Text(repo)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(prs.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !collapsedSections.contains(repo) {
                ForEach(prs) { pr in
                    PRRowView(pr: pr) {
                        appState.openPR(pr)
                    }
                    if pr.id != prs.last?.id {
                        Divider().padding(.leading, 16)
                    }
                }
            }

            Divider()
        }
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
                Image(systemName: "gear")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
