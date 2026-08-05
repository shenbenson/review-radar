import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

// MARK: - General Settings

struct GeneralSettingsView: View {
    @Bindable var appState: AppState

    @State private var showingSoundPicker = false
    @State private var previewSound: NSSound?

    private let intervalOptions = [1, 2, 5, 10, 15]

    private var soundName: String {
        let path = appState.settings.customSoundPath
        return path.isEmpty ? "Default" : (path as NSString).lastPathComponent
    }

    var body: some View {
        Form {
            Section("Refresh") {
                Picker("Refresh interval", selection: $appState.settings.refreshIntervalMinutes) {
                    ForEach(intervalOptions, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }

                HStack {
                    Text("Max PRs per queue")
                    Spacer()
                    TextField("", value: $appState.settings.maxPRs, format: .number)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        .onSubmit {
                            appState.settings.maxPRs = max(10, min(100, appState.settings.maxPRs))
                        }
                    Stepper("", value: $appState.settings.maxPRs, in: 10...100, step: 10)
                        .labelsHidden()
                }

                Picker("Default sort", selection: $appState.settings.sortOption) {
                    ForEach(PRSortOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            }

            Section("Queues") {
                Toggle("Show My PRs tab", isOn: $appState.settings.showMyPRs)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { appState.settings.launchAtLogin },
                    set: { newValue in
                        appState.settings.launchAtLogin = newValue
                        updateLaunchAtLogin(newValue)
                    }
                ))
            }

            Section("Notifications") {
                Toggle("New review requests", isOn: $appState.settings.showNotifications)
                Toggle("My PR CI turned green", isOn: $appState.settings.notifyMyPRCIGreen)
                    .disabled(!appState.settings.showMyPRs)
                Toggle("My PR approved / changes requested", isOn: $appState.settings.notifyMyPRReviews)
                    .disabled(!appState.settings.showMyPRs)
                Toggle("My PR merged", isOn: $appState.settings.notifyMyPRMerged)
                    .disabled(!appState.settings.showMyPRs)

                HStack {
                    Text("Sound")
                    Spacer()
                    Text(soundName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !appState.settings.customSoundPath.isEmpty {
                        Button {
                            playPreview()
                        } label: {
                            Image(systemName: "play.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Preview")
                    }
                    Button("Choose…") { showingSoundPicker = true }
                    if !appState.settings.customSoundPath.isEmpty {
                        Button("Reset") { appState.clearCustomSound() }
                    }
                }
                .disabled(
                    !appState.settings.showNotifications
                        && !appState.settings.notifyMyPRReviews
                        && !appState.settings.notifyMyPRMerged
                        && !appState.settings.notifyMyPRCIGreen
                )
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $showingSoundPicker,
            allowedContentTypes: [.audio]
        ) { result in
            if case let .success(url) = result {
                appState.importCustomSound(from: url)
            }
        }
        .onChange(of: appState.settings.refreshIntervalMinutes) { _, _ in
            appState.restartPolling()
        }
        .onChange(of: appState.settings.showMyPRs) { _, enabled in
            if !enabled && appState.settings.popoverTab == .myPRs {
                appState.settings.popoverTab = .toReview
            }
            Task { await appState.refresh() }
        }
    }

    private func playPreview() {
        let path = appState.settings.customSoundPath
        guard let sound = NSSound(contentsOf: URL(fileURLWithPath: path), byReference: true) else { return }
        sound.volume = 1.0
        previewSound = sound
        sound.play()
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            appState.settings.launchAtLogin = !enabled
        }
    }
}

// MARK: - Filters Settings

struct FiltersSettingsView: View {
    @Bindable var appState: AppState

    var body: some View {
        Form {
            Section("Pull Requests") {
                Toggle("Exclude drafts in To Review", isOn: $appState.settings.excludeDraftsToReview)
                Toggle("Exclude drafts in My PRs", isOn: $appState.settings.excludeDraftsMyPRs)
                Toggle("Exclude bot PRs", isOn: Binding(
                    get: { !appState.settings.showBotPRs },
                    set: { appState.settings.showBotPRs = !$0 }
                ))
            }

            if !appState.discoveredBots.isEmpty {
                Section("Bot Allow List") {
                    Text("Allow specific bots even when bot PRs are excluded:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(appState.discoveredBots.sorted(), id: \.self) { bot in
                        Toggle(bot, isOn: Binding(
                            get: { appState.settings.botAllowList[bot] ?? false },
                            set: { appState.settings.botAllowList[bot] = $0 }
                        ))
                    }
                }
            }

            if !appState.teams.isEmpty {
                Section("Teams") {
                    Text("Uncheck a team to hide its review requests (direct requests still show).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(appState.teams) { team in
                        Toggle("\(team.organization.login)/\(team.name)", isOn: Binding(
                            get: { appState.settings.isTeamFilterEnabled(team.filterKey) },
                            set: { appState.settings.setTeamFilter(team.filterKey, enabled: $0) }
                        ))
                    }
                }
            }

            if !appState.activeSnoozes.isEmpty {
                Section {
                    Text("Hidden from both queues until the time expires (or forever if muted).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(appState.activeSnoozes, id: \.id) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.id)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                Text(snoozeCaption(until: item.until))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Unmute") {
                                appState.unsnoozePR(id: item.id)
                            }
                            .controlSize(.small)
                        }
                    }
                    Button("Clear all") {
                        appState.clearAllSnoozes()
                    }
                } header: {
                    Text("Snoozed / muted PRs")
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("owner/repo — one per line. Only these repos are shown (leave empty for all).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $appState.settings.repoIncludes)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 56)
                }
            } header: {
                Text("Include repositories")
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("owner/repo — one per line. Hidden from both queues. You can also ignore from the popover ⋯ menu.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $appState.settings.repoExcludes)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 72)
                }
            } header: {
                Text("Ignored repositories")
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Organization login — one per line. Only these orgs are shown (leave empty for all).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $appState.settings.orgIncludes)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 56)
                }
            } header: {
                Text("Include organizations")
            }
        }
        .formStyle(.grouped)
    }

    private func snoozeCaption(until: Date) -> String {
        if until == .distantFuture || until.timeIntervalSinceNow > 50 * 365 * 24 * 60 * 60 {
            return "Muted"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Until \(formatter.localizedString(for: until, relativeTo: Date()))"
    }
}
