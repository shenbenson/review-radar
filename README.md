# ReviewRadar

A macOS menu bar app that surfaces GitHub pull requests awaiting your review.

It shells out to the [`gh`](https://cli.github.com/) CLI under your existing auth — no separate token setup, no OAuth dance. Polls on a configurable interval, pauses on system sleep, and posts a notification when a new PR shows up.

Features:

- Menu bar status item with a count of pending reviews
- Filters: hide drafts, hide bots (with per-bot allowlist), team review allowlist, repo / org include + exclude lists
- PRs you've already approved are hidden automatically
- Auto-discovers bots and teams from your live PR list and `gh api /user/teams`
- Settings persist to `~/Library/Application Support/ReviewRadar/settings.json`

## Requirements

- macOS 15 (Sequoia) or later
- Xcode 16+ with the macOS SDK
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- [`gh`](https://cli.github.com/) CLI, authenticated — `brew install gh && gh auth login`

## Build

Regenerate the Xcode project from `project.yml` (only needed after editing `project.yml` or adding files):

```sh
xcodegen generate
```

### Debug build

Open `ReviewRadar.xcodeproj` in Xcode and run, or:

```sh
xcodebuild -project ReviewRadar.xcodeproj \
  -scheme ReviewRadar \
  -configuration Debug \
  -derivedDataPath .build build
```

The app will be at `.build/Build/Products/Debug/ReviewRadar.app`.

### Release build + install to /Applications

```sh
xcodebuild -project ReviewRadar.xcodeproj \
  -scheme ReviewRadar \
  -configuration Release \
  -derivedDataPath .build build

rm -rf /Applications/ReviewRadar.app
cp -R .build/Build/Products/Release/ReviewRadar.app /Applications/
open /Applications/ReviewRadar.app
```

The build is ad-hoc signed (`CODE_SIGN_IDENTITY: -`). On first launch macOS may block it with a Gatekeeper warning — right-click the app in `/Applications` and choose **Open**, then confirm.

## Usage

Once launched, ReviewRadar lives in the menu bar (no Dock icon — it's an `LSUIElement` app). The icon shows the count of PRs awaiting your review.

- **Click the menu bar icon** to open the popover with PRs grouped by repo. Click a row to open the PR in your browser.
- **Settings** are reachable from the popover. Configure refresh interval, notifications, launch-at-login, draft visibility, bot allowlist, team allowlist, and repo/org filters.
- **Notifications** fire when a new PR enters your review queue (toggle in Settings; macOS will prompt for permission on first run).

The app polls every N minutes (default 5, configurable). On system sleep it stops polling; on wake it resumes immediately.

## Project layout

```
Sources/
  App/         entry point + AppDelegate
  Models/      PullRequest, AppSettings, error types
  State/       AppState — polling, filtering, grouping
  Controllers/ status bar + settings window
  Views/       SwiftUI views (popover, settings, rows, filter chips)
  Services/    GitHubService (gh wrapper), ProcessRunner, NotificationService
```
