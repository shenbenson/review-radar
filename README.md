# ReviewRadar

A macOS menu bar app that surfaces GitHub pull requests awaiting your review — and tracks **your own PRs**.

It shells out to the [`gh`](https://cli.github.com/) CLI under your existing auth — no separate token setup. Polls on a configurable interval, pauses on system sleep, and posts notifications when something needs attention.

## Changelog

### Recent (`main`)

**Search, snooze & reliability** (`fc105c1`, `914cd54`)

- **Search** in the popover — filter by title, repo, author, or `#number`
- **Snooze / mute** a PR from the row context menu (1 hour, until tomorrow, 1 week, or mute forever); manage in Settings → Filters
- **Separate draft filters** for To Review vs My PRs
- **Honest empty states** when a queue fails to refresh (no more “all caught up” on network errors)
- **Partial fetch banners** name which queue failed
- **CI failures** show “CI unknown” instead of “No checks”; last good CI status is kept when possible
- **Team filter keys** normalized (case-stable `org/slug`)
- **Settings decode** is forward-compatible — adding fields no longer wipes prefs on upgrade
- **Settings flush** on quit so a quick reinstall doesn’t drop unsaved toggles
- **Stable menu bar badge** while typing search (popover no longer slides sideways)
- **Search focus** — no blinking caret until you click the field; click outside to dismiss it

**Dual queues & richer status** (`45ce26c`)

- **To Review** + **My PRs** tabs
- CI rollup, +/− diffs, avatars, draft/ready, review pills
- Sort options; ignore repo from section ⋯
- Notifications for review requests; My PR approved / changes requested / merged / CI green
- Lean GraphQL search + batched CI (avoids GitHub 502s on large review queues)

**Polish** (`b66a3c8`, `8cb38be`)

- Avatar attachments on notifications
- Custom notification sound file

---

## Features

- **To Review** — PRs where your review is requested (personal and/or team)
- **My PRs** — open PRs you authored, with overall review decision + CI
- Menu bar count of pending reviews (independent of search filter)
- Search by title, repo, author, PR number
- Snooze / mute individual PRs
- Draft / Ready, CI rollup, +/− diff, avatars
- Sort by updated, created, repo, or title
- Ignore repos from the list (⋯), row menu, or Settings
- Filters: drafts (per queue), bots (with allowlist), teams, repo/org include + exclude
- Hides PRs **you** already approved (`viewerLatestReview`)
- Notifications (each toggleable):
  - New review requests
  - My PR CI turned green
  - My PR approved / changes requested
  - My PR merged
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

# Prefer quitting the app first so settings can flush
osascript -e 'quit app "ReviewRadar"' 2>/dev/null; sleep 0.5

rm -rf /Applications/ReviewRadar.app
cp -R .build/Build/Products/Release/ReviewRadar.app /Applications/
open /Applications/ReviewRadar.app
```

Ad-hoc signed (`CODE_SIGN_IDENTITY: -`). First launch may need right-click → **Open**.

## Usage

Lives in the menu bar (`LSUIElement`). Icon shows pending review count.

- **Click** — popover with **To Review** / **My PRs** tabs
- **Search** — filter the current tab; click outside the field to hide the caret
- **Sort** — menu in the toolbar
- **Snooze / mute** — right‑click a PR row
- **Ignore repo** — ⋯ on a repo section or row menu
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
