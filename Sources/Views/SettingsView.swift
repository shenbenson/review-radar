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
                .disabled(!appState.settings.showNotifications)
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
