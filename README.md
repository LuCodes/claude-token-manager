# Claude Token Manager

A native macOS menu bar app that mirrors Claude's plan usage limits — powered by local Claude Code logs.

## What it shows

- **Menu bar icon** (Claude burst) + the hottest percentage across all your usage bars. Color shifts to amber at 80 %, coral at 95 % so you know at a glance.
- **Current 5 h rolling session** with reset countdown.
- **Weekly limits** per model: all models combined / Sonnet only / Opus. Each with its own reset time.
- **Project picker**: view usage across all projects or filter to one specific Claude Code project.
- **Plan picker**: Pro, Max 5×, Max 20×. Usage thresholds adapt to the selected plan.
- **Discreet notifications** at 80 % and 95 %. Silent banner, no sound, one notification per threshold per reset window. Toggle from the gear icon.

## Install

Download the latest `.zip` from the [Releases page](https://github.com/LuCodes/claude-token-manager/releases/latest), unzip, drag to `/Applications`, launch.

First time you open an ad-hoc signed app: right-click → Open → Open. macOS prompts once, then trusts it.

### One-liner install

```bash
curl -L -o /tmp/ctb.zip \
  "https://github.com/LuCodes/claude-token-manager/releases/latest/download/ClaudeTokenManager.zip" && \
  unzip -o /tmp/ctb.zip -d /Applications/ && \
  xattr -dr com.apple.quarantine "/Applications/Claude Token Manager.app" && \
  open "/Applications/Claude Token Manager.app"
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

System Settings → General → Login Items → add *Claude Token Manager*.

## How it works

Claude Code writes a JSONL transcript for every session to `~/.claude/projects/<project-hash>/<session-id>.jsonl`. Each assistant message includes precise token usage (input, output, cache creation, cache read) plus the model. This app parses those logs, aggregates by project and by time window, and watches the directory via `FSEvents` so the dropdown updates in real time.

Works on all Claude Code plans — API, Pro, and Max. The logs exist regardless of subscription type.

**Note on accuracy.** Anthropic doesn't publish exact token caps for subscription plans. The percentages are estimates based on their public communication ("15–35 h Opus per week on Max", etc.). See `Sources/ClaudeTokenManagerCore/PlanLimits.swift` to adjust thresholds for your own plan if needed. The app doesn't see claude.ai or Claude Desktop usage — only Claude Code.

## Typography

The app uses Inter when installed on your system, with a clean fallback to SF Pro. Install Inter from [rsms.me/inter](https://rsms.me/inter/) for the intended look.

## Project layout

```
Sources/
  ClaudeTokenManagerCore/           ← logic layer, no UI
    Models.swift                ← UsageSnapshot, ProjectUsage, ModelUsage, pricing
    LogScanner.swift            ← JSONL parsing and aggregation
    PlanLimits.swift            ← plan thresholds + window math
    NotificationManager.swift   ← threshold notifications with dedup
    UsageStore.swift            ← ObservableObject, FSEvents watcher
  ClaudeTokenManager/               ← SwiftUI layer
    ClaudeTokenManagerApp.swift     ← @main, MenuBarExtra, dynamic menu bar label
    DropdownView.swift          ← main dropdown
    PreferencesView.swift       ← gear-icon settings panel
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
