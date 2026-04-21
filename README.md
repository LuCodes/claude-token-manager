<p align="center">
  <img src="Sources/ClaudeTokenManager/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="Claude Token Manager" width="96" />
</p>

<h1 align="center">Claude Token Manager</h1>

<p align="center">
  Real-time Claude usage in your macOS menu bar.<br/>
  Local Claude Code activity and live claude.ai plan limits, at a glance.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13%2B-black?style=flat-square" alt="macOS 13+" />
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?style=flat-square" alt="Swift 5.9" />
  <img src="https://img.shields.io/github/v/release/LuCodes/claude-token-manager?style=flat-square" alt="Latest release" />
  <img src="https://img.shields.io/github/license/LuCodes/claude-token-manager?style=flat-square" alt="MIT License" />
</p>

<p align="center">
  <img src="docs/screenshots/dropdown-claude-ai.png" alt="Claude Token Manager dropdown showing claude.ai sync mode" width="380" />
</p>

## Install

```bash
brew tap LuCodes/claude-token-manager
brew install --cask claude-token-manager
```

The cask removes the macOS quarantine attribute automatically, so the
app launches directly without the Gatekeeper prompt.

Alternatively, download the latest `.zip` from the
[releases page](https://github.com/LuCodes/claude-token-manager/releases/latest),
unzip, and drop the app in `/Applications`.

## Features

- **Local mode** — Track Claude Code usage from your local JSONL logs.
  Tokens, per-model breakdown (Opus, Sonnet, Haiku), and
  API-equivalent cost using Anthropic's public pricing.
- **claude.ai sync** — Show real plan limits from your claude.ai
  account: current 5-hour session, weekly pools for Sonnet, Opus,
  Claude Design, and any other pool active on your plan. Matches
  claude.ai/settings/usage exactly.
- **Native sign-in** — One click to log in with your claude.ai
  account. No DevTools, no cookie copy-paste. Your credentials are
  managed by macOS WebKit and never leave your Mac.
- **Smart alerts** — macOS notifications when any pool reaches 80 %
  or 95 %. Deduplicated per reset window, so you never get spammed.
- **Daily budget** — Minimalist slider to set a cost cap (in USD),
  with 80 % and 95 % notifications.
- **Native and lightweight** — Pure AppKit + SwiftUI, runs in the
  menu bar, no dock icon, no background services. Single binary,
  zero third-party dependencies.

## Usage

### Local mode

<p align="center">
  <img src="docs/screenshots/dropdown-local.png" alt="Dropdown in local mode showing Claude Code usage" width="380" />
</p>

Local mode works out of the box if you use Claude Code. The app reads
JSONL logs from `~/.claude/projects/` via FSEvents and aggregates
usage across all projects. You can filter by project from the
dropdown.

The app auto-detects custom Claude Code log paths (e.g. if you've
configured Claude Code to store logs in `~/Documents/Claude/` or
elsewhere). You can also set a custom path manually in Preferences.

API-equivalent cost is calculated using Anthropic's public pricing
for input tokens, output tokens, cache reads and cache writes. So you
can compare what your Claude Code activity would cost on the direct
API. If you're on a Pro or Max subscription, this number is purely
informational — your real cost is your fixed monthly price.

### claude.ai sync mode

To see real plan limits, click **Sign in to claude.ai** in
Preferences. A native sign-in window opens where you log in with
your usual claude.ai credentials — exactly like in any browser.

Once signed in, the dropdown switches to the claude.ai layout and
shows your actual percentages — matching what you see at
claude.ai/settings/usage in real time.

The session persists between app launches. Click **Sign out** in
Preferences to clear it.

## Security and trust

This is an open-source solo project. Here's exactly what is done and
what is not.

**What's done**

- 100 % open source, all code in this repo
- Zero third-party dependencies — only Apple frameworks (AppKit,
  SwiftUI, WebKit, Foundation, UserNotifications)
- claude.ai sign-in handled by macOS WebKit, the same engine that
  powers Safari. Cookies are stored in the standard WebKit data
  store, never extracted or persisted in custom storage.
- TLS validation handled natively by WebKit (no custom certificate
  pinning needed)
- The local JSONL logs are read in-place and never copied or
  transmitted anywhere

**What's not done**

- No Apple Developer ID signature (would cost $99/year for a solo
  project and is not yet justified)
- No Apple notarization
- The Homebrew cask removes the macOS quarantine attribute
  automatically to improve UX. If you prefer Gatekeeper to verify
  every download, install manually from the releases page instead.

> [!WARNING]
> The `claude.ai/api/organizations/*/usage` endpoint used for sync is
> **undocumented** and could change or be blocked by Anthropic at any
> time. The app uses an embedded WebKit view (the same engine as
> Safari) to make these requests, which makes it more resilient than
> a raw HTTP client, but Anthropic could still introduce additional
> protections that block the sync mode in the future. Local mode does
> not depend on this endpoint and will always keep working.

If you have any doubt about trust, audit the code or build from
source yourself with `./build.sh`.

## Build from source

Requirements:
- macOS 13 or later
- Xcode 15 or later (includes Swift 5.9)

```bash
git clone https://github.com/LuCodes/claude-token-manager.git
cd claude-token-manager
./build.sh release
```

The built app appears in `build/Claude Token Manager.app`. Move it to
`/Applications` to install.

Run tests:

```bash
swift test
```

## How it works

**Local mode** uses FSEvents to watch `~/.claude/projects/` (or any
custom path you configured). When Claude Code writes new JSONL
entries, the app re-scans the relevant files, parses the events, and
updates token counts and cost estimates. Pricing per model is stored
in `Pricing.swift` and reflects Anthropic's published rates.

**claude.ai sync mode** runs a hidden `WKWebView` instance that
holds the authenticated session. When the app needs fresh usage
data, it executes a `fetch()` call inside the WebView via
`evaluateJavaScript`, just like the claude.ai web app would. Because
the request comes from a real browser engine — with the correct
cookies, headers, and TLS fingerprint — it is handled by Anthropic's
servers exactly the same way as a browser request.

The sign-in window is also a `WKWebView` that loads
`claude.ai/login` and detects when authentication completes by
watching for the `sessionKey` cookie and the post-login URL.

The whole app uses a pure AppKit entry point (no SwiftUI `App`
protocol), with `NSStatusItem` for the menu bar and `NSPopover` for
the dropdown content rendered via `NSHostingController`.

## Roadmap

- [ ] Historical chart (7 / 30 day view) of usage trends
- [ ] CSV / JSON export of usage data
- [ ] Support for multiple claude.ai accounts
- [ ] Per-project budget notifications
- [ ] Menu bar compact mode (percentage only, no icon)

If you have ideas, open an issue or start a discussion.

## Contributing

Contributions are welcome. Before starting significant work, please:

- Open an issue to align on scope
- Keep commits atomic and use [conventional commit](https://www.conventionalcommits.org/) format
- Add tests when modifying `ClaudeTokenManagerCore`
- Update documentation when user-facing behavior changes

For bug reports, include your macOS version, the app version (shown
in the Preferences footer), and relevant output from `Console.app`
filtered by `Claude Token Manager`.

## Acknowledgments

- [Anthropic](https://anthropic.com) for Claude and the claude.ai
  platform. This is an independent project and is not affiliated
  with or endorsed by Anthropic.
- The [AlDente](https://apphousekitchen.com/) macOS app, whose menu
  bar UX inspired the layout of this app.
- Homebrew maintainers for the excellent cask system.

## License

MIT — see [LICENSE](./LICENSE).
