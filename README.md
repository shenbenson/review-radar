# ReviewRadar

A macOS menu bar app that surfaces GitHub pull requests awaiting your review — and tracks **your own PRs**.

It shells out to the [`gh`](https://cli.github.com/) CLI under your existing auth — no separate token setup. Polls on a configurable interval, pauses on system sleep, and posts notifications when something needs attention.

## Features

- **To Review** — PRs where your review is requested (personal and/or team)
- **My PRs** — open PRs you authored, with overall review decision + CI
- Menu bar count of pending reviews
- Draft / Ready, CI rollup, +/− diff, avatars
- Sort by updated, created, repo, or title
- Ignore repos from the list (⋯) or Settings
- Filters: drafts, bots (with allowlist), teams, repo/org include + exclude
- Hides PRs **you** already approved (`viewerLatestReview`)
- Notifications: new review requests; your PR approved / changes requested
- Custom notification sound
- Settings persist to `~/Library/Application Support/ReviewRadar/settings.json`

## Requirements

- macOS 15 (Sequoia) or later
- Xcode 16+ with the macOS SDK
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- [`gh`](https://cli.github.com/) CLI, authenticated — `brew install gh && gh auth login`

## Build

```sh
xcodegen generate
```

### Debug

```sh
xcodebuild -project ReviewRadar.xcodeproj \
  -scheme ReviewRadar \
  -configuration Debug \
  -derivedDataPath .build build
```

App: `.build/Build/Products/Debug/ReviewRadar.app`

### Release + install

```sh
xcodebuild -project ReviewRadar.xcodeproj \
  -scheme ReviewRadar \
  -configuration Release \
  -derivedDataPath .build build

rm -rf /Applications/ReviewRadar.app
cp -R .build/Build/Products/Release/ReviewRadar.app /Applications/
open /Applications/ReviewRadar.app
```

Ad-hoc signed (`CODE_SIGN_IDENTITY: -`). First launch may need right-click → **Open**.

## Usage

Lives in the menu bar (`LSUIElement`). Icon shows pending review count.

- **Click** — popover with **To Review** / **My PRs** tabs
- **Sort** — menu in the toolbar
- **Ignore repo** — ⋯ on a repo section
- **Settings** — gear or right-click the status item
- Polls every N minutes (default 5); pauses on sleep, refreshes on wake

## Project layout

```
Sources/
  App/         entry point + AppDelegate
  Models/      PullRequest, AppSettings, status types
  State/       AppState — polling, filtering, grouping
  Controllers/ status bar + settings window
  Views/       SwiftUI popover, settings, rows
  Services/    GitHubService (GraphQL via gh), ProcessRunner, NotificationService
  Resources/   App icon asset catalog
```
