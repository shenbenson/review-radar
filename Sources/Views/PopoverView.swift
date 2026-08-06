import AppKit
import SwiftUI

struct PopoverView: View {
    @Bindable var appState: AppState
    var onOpenSettings: () -> Void
    @State private var collapsedSections: Set<String> = []
    @FocusState private var searchFocused: Bool

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
            searchRow
            Divider()
            toolbarRow
            Divider()
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            Divider()
            footerView
        }
        .frame(width: 420, height: 560)
        .background(.background)
        .onAppear { resignSearchFocus() }
        .background(SearchFocusDismisser(onDismiss: resignSearchFocus))
    }

    private func resignSearchFocus() {
        searchFocused = false
        // Only resign within the popover window — don't promote it to key.
        guard let window = NSApp.windows.first(where: {
            $0.isVisible && String(describing: type(of: $0)).contains("Popover")
        }) ?? NSApp.keyWindow else { return }

        LazyFocusTextField.resetFocusGate(in: window.contentView)
        if window.firstResponder is NSTextView || window.firstResponder is NSTextField {
            window.makeFirstResponder(nil)
        }
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
        let queueHint: String = {
            switch (appState.reviewQueueFailed, appState.authoredQueueFailed) {
            case (true, true): return "Both queues failed."
            case (true, false): return "Couldn't refresh To Review."
            case (false, true): return "Couldn't refresh My PRs."
            case (false, false): return ""
            }
        }()

        let detail: String = {
            switch error {
            case .rateLimited(let date):
                let s = max(0, Int(date.timeIntervalSinceNow))
                return "Rate limited · retries in \(s)s."
            case .networkError:
                return "Network error."
            case .ghNotAuthenticated:
                return "GitHub auth expired."
            case .ghNotInstalled:
                return "gh CLI missing."
            case .unknown(let msg):
                return msg.isEmpty ? "Refresh failed." : msg
            }
        }()

        let showing = "Showing last results."
        if queueHint.isEmpty {
            return "\(detail) \(showing)"
        }
        return "\(queueHint) \(detail) \(showing)"
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

    // MARK: - Search

    private var searchRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            ClickToFocusTextField(
                text: $appState.searchQuery,
                placeholder: "Search title, repo, author…",
                isFocused: $searchFocused
            )
            .frame(maxWidth: .infinity, minHeight: 16, maxHeight: 18)
            Button {
                appState.searchQuery = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(appState.hasActiveSearch ? 1 : 0)
            .disabled(!appState.hasActiveSearch)
            .frame(width: 16, height: 16)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(height: 32)
    }

    // MARK: - Toolbar

    private var toolbarRow: some View {
        HStack(spacing: 8) {
            if appState.settings.popoverTab == .toReview {
                FilterChip(title: "Bots", isOn: $appState.settings.showBotPRs)
                FilterChip(title: "Teams", isOn: $appState.settings.showTeamReviews)
            }
            FilterChip(title: "Review ready", isOn: $appState.settings.showOnlyNeedsReview)

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
            .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(height: 32)
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
        let tab = appState.settings.popoverTab
        let queueFailed = tab == .toReview ? appState.reviewQueueFailed : appState.authoredQueueFailed
        let rawEmpty = tab == .toReview ? appState.reviewPullRequests.isEmpty : appState.authoredPullRequests.isEmpty

        let icon: String
        let title: String
        let subtitle: String

        if queueFailed && rawEmpty {
            icon = "exclamationmark.triangle"
            title = tab == .toReview ? "Couldn't refresh reviews" : "Couldn't refresh My PRs"
            subtitle = "Check the banner above or retry."
        } else if appState.hasActiveSearch {
            icon = "magnifyingglass"
            title = "No matches"
            subtitle = "Nothing matches “\(appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines))”"
        } else if queueFailed {
            icon = "exclamationmark.triangle"
            title = tab == .toReview ? "Couldn't refresh reviews" : "Couldn't refresh My PRs"
            subtitle = "Showing last results may be incomplete."
        } else {
            icon = tab == .toReview ? "checkmark.circle" : "tray"
            title = tab == .toReview ? "No pending reviews" : "No open PRs"
            subtitle = tab == .toReview ? "You're all caught up" : "Nothing authored by you right now"
        }

        return VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .foregroundStyle(.secondary)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if queueFailed {
                Button("Retry") {
                    Task { await appState.refresh() }
                }
                .controlSize(.small)
            }
        }
    }

    private func prListView(_ groups: [(repo: String, prs: [PullRequest])]) -> some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groups, id: \.repo) { group in
                    Section {
                        if !collapsedSections.contains(group.repo) {
                            ForEach(group.prs) { pr in
                                PRRowView(
                                    pr: pr,
                                    style: appState.settings.popoverTab,
                                    onTap: { appState.openPR(pr) },
                                    onSnooze: { appState.snoozePR(pr, duration: $0) },
                                    onMute: { appState.mutePR(pr) },
                                    onIgnoreRepo: { appState.ignoreRepo(pr.repository.nameWithOwner) }
                                )
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

/// Plain search field that refuses first responder until the user clicks it
/// (stops the blinking caret when the popover opens).
private struct ClickToFocusTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isFocused: FocusState<Bool>.Binding

    func makeNSView(context: Context) -> LazyFocusTextField {
        let field = LazyFocusTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.stringValue = text
        return field
    }

    func updateNSView(_ field: LazyFocusTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        field.placeholderString = placeholder
        if !isFocused.wrappedValue {
            field.refuseFocusUntilClick = true
            if field.window?.firstResponder === field
                || field.window?.firstResponder === field.currentEditor()
            {
                field.window?.makeFirstResponder(nil)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ClickToFocusTextField

        init(_ parent: ClickToFocusTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.isFocused.wrappedValue = true
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            parent.isFocused.wrappedValue = false
            (obj.object as? LazyFocusTextField)?.refuseFocusUntilClick = true
        }
    }
}

/// NSTextField that ignores automatic first-responder assignment until clicked.
private final class LazyFocusTextField: NSTextField {
    var refuseFocusUntilClick = true

    override var acceptsFirstResponder: Bool {
        !refuseFocusUntilClick
    }

    override func becomeFirstResponder() -> Bool {
        guard !refuseFocusUntilClick else { return false }
        return super.becomeFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        refuseFocusUntilClick = false
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    static func resetFocusGate(in root: NSView?) {
        guard let root else { return }
        if let field = root as? LazyFocusTextField {
            field.refuseFocusUntilClick = true
        }
        for child in root.subviews {
            resetFocusGate(in: child)
        }
    }
}

/// Clears search focus when the user clicks outside any NSText field/view.
private struct SearchFocusDismisser: NSViewRepresentable {
    var onDismiss: @MainActor () -> Void

    func makeNSView(context: Context) -> NSView {
        context.coordinator.onDismiss = onDismiss
        context.coordinator.install()
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onDismiss = onDismiss
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        var onDismiss: (() -> Void)?
        private var monitor: Any?

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self else { return event }
                if self.shouldDismiss(for: event) {
                    let dismiss = self.onDismiss
                    DispatchQueue.main.async {
                        dismiss?()
                    }
                }
                return event
            }
        }

        func teardown() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        nonisolated private func shouldDismiss(for event: NSEvent) -> Bool {
            guard let window = event.window else { return false }
            let point = event.locationInWindow
            guard let hit = window.contentView?.hitTest(point) else { return true }
            return !isTextInput(hit)
        }

        nonisolated private func isTextInput(_ view: NSView) -> Bool {
            var current: NSView? = view
            while let v = current {
                if v is NSTextField || v is NSTextView { return true }
                current = v.superview
            }
            return false
        }
    }
}
