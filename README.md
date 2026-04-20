# Claude Token Manager

A native macOS menu bar app that tracks your Claude Code token usage and API-equivalent costs — powered entirely by local logs.

## What it shows

- **Menu bar icon** (Claude burst) + today's API-equivalent cost (e.g. `$12.40`) or token count. Color shifts to amber/coral when approaching your daily budget.
- **Today's usage** with cost and token breakdown.
- **Model breakdown**: Opus / Sonnet / Haiku cards showing cost and tokens per model.
- **Current 5 h rolling session** with reset countdown.
- **Weekly total** with reset time.
- **Top project** of the day.
- **Project picker**: view usage across all projects or filter to one specific Claude Code project.
- **Daily budget** with threshold notifications at 80 % and 95 %. Set in $ or tokens.
- **Display format toggle**: switch between cost and tokens everywhere in the app.

## Important note

This app measures your Claude Code usage from local logs and calculates costs at Anthropic API rates. **If you're on a Pro or Max subscription, your actual cost is the fixed price of your plan** — the dollar amounts shown are what you *would* pay at API rates. To see your real plan limits, use the "Open claude.ai" link in Preferences.

## Install

### Via Homebrew (recommended)

```bash
brew tap LuCodes/claude-token-manager
brew install --cask claude-token-manager
```

The app lands in `/Applications`. Launch it from the Launchpad or:

```bash
open "/Applications/Claude Token Manager.app"
```

### Manual install

Download the latest `.zip` from the [Releases page](https://github.com/LuCodes/claude-token-manager/releases/latest), unzip, drag to `/Applications`.

First time you open an ad-hoc signed app: right-click → Open → Open.

### Update

```bash
brew upgrade --cask claude-token-manager
```

## Build from source

```bash
git clone https://github.com/LuCodes/claude-token-manager
cd claude-token-manager
./build.sh release
mv "build/Claude Token Manager.app" /Applications/
open "/Applications/Claude Token Manager.app"
```

Requires macOS 13+ and Xcode Command Line Tools (Swift 5.9+).

## Start at login

Enabled by default. Toggle in Preferences (gear icon) → "Lancer au démarrage".

## How it works

Claude Code writes a JSONL transcript for every session to `~/.claude/projects/<project-hash>/<session-id>.jsonl`. Each assistant message includes precise token usage (input, output, cache creation, cache read) plus the model name. This app parses those logs, computes API-equivalent costs using Anthropic's published pricing, aggregates by project and time window, and watches the directory via `FSEvents` so the dropdown updates in real time.

Works on all Claude Code setups — API, Pro, and Max. The logs exist regardless of subscription type.

## Typography

Uses Inter when installed on your system, with a clean fallback to SF Pro. Install Inter from [rsms.me/inter](https://rsms.me/inter/) for the intended look.

## Project layout

```
Sources/
  ClaudeTokenManagerCore/           ← logic layer, no UI
    Models.swift                ← UsageSnapshot, ProjectUsage, ModelUsage, pricing, formatters
    LogScanner.swift            ← JSONL parsing and aggregation
    NotificationManager.swift   ← daily budget notifications with dedup
    UsageStore.swift            ← ObservableObject, FSEvents watcher
  ClaudeTokenManager/               ← SwiftUI layer
    ClaudeTokenManagerApp.swift     ← @main, MenuBarExtra, single-instance guard
    DropdownView.swift          ← main dropdown with model breakdown cards
    PreferencesView.swift       ← settings: format, budget, login, info
    LoginItem.swift             ← SMAppService wrapper
    AppFont.swift               ← Inter/SF Pro helper
    Resources/
      Assets.xcassets/
        MenuBarIcon.imageset/   ← vector PDF, template-rendered
```

## Distribution

To ship signed and notarized so users don't need to right-click → Open:

1. Apple Developer account ($99/year)
2. `codesign --force --deep --sign "Developer ID Application: ..." "build/Claude Token Manager.app"`
3. `xcrun notarytool submit ... --wait` then `xcrun stapler staple ...`
4. Optional: publish a Homebrew cask

## License

MIT — see `LICENSE`.
