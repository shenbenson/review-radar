import ServiceManagement
import SwiftUI

// MARK: - General Settings

struct GeneralSettingsView: View {
    @Bindable var appState: AppState

    private let intervalOptions = [1, 2, 5, 10, 15]

    var body: some View {
        Form {
            Section("Refresh") {
                Picker("Refresh interval", selection: $appState.settings.refreshIntervalMinutes) {
                    ForEach(intervalOptions, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }

                HStack {
                    Text("Max PRs")
                    Spacer()
                    TextField("", value: $appState.settings.maxPRs, format: .number)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                        .onSubmit {
                            appState.settings.maxPRs = max(10, min(200, appState.settings.maxPRs))
                        }
                    Stepper("", value: $appState.settings.maxPRs, in: 10...200, step: 10)
                        .labelsHidden()
                }
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
                Toggle("Show notifications for new review requests", isOn: $appState.settings.showNotifications)
            }

        }
        .formStyle(.grouped)
        .onChange(of: appState.settings.refreshIntervalMinutes) { _, _ in
            appState.restartPolling()
        }
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
                Toggle("Exclude draft PRs", isOn: $appState.settings.excludeDrafts)
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
                    ForEach(appState.teams) { team in
                        let key = "\(team.organization.login)/\(team.slug)"
                        Toggle("\(team.organization.login)/\(team.name)", isOn: Binding(
                            get: { appState.settings.teamFilters[key] ?? true },
                            set: { appState.settings.teamFilters[key] = $0 }
                        ))
                    }
                }
            }

            Section("Repositories") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Include repos (one per line)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $appState.settings.repoIncludes)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 60)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Exclude repos (one per line)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $appState.settings.repoExcludes)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 60)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Include orgs (one per line)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $appState.settings.orgIncludes)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 60)
                }
            }
        }
        .formStyle(.grouped)
    }
}
