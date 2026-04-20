# Contributing

Thanks for your interest in making Claude Token Manager better!

## Quick dev loop

```bash
swift run
```

This builds and launches the app directly. The bolt icon appears in your menu bar.

## Project layout

- `Sources/ClaudeTokenManagerCore/` — framework-agnostic Swift logic (parsing, pricing, file watching). No UI imports here — keep it reusable so it could be shared with a CLI or a different UI later.
- `Sources/ClaudeTokenManager/` — SwiftUI views and the `@main` app entry point.

## Adding features

Good first issues:

- **Preferences window** — let users pick token count vs. $ cost in the menu bar label
- **Daily chart** — 7-day sparkline in the dropdown using Swift Charts
- **Threshold notifications** — UserNotifications when hitting $X spent today
- **Custom pricing** — let users override the per-model $/1M rates
- **Claude API usage** — for users with an Admin API key, pull server-side usage data

## Code style

- SwiftUI-first, minimal dependencies (currently zero)
- Keep the core logic testable (no SwiftUI imports in `ClaudeTokenManagerCore`)
- One view per file past ~200 lines — break it up

## Submitting a PR

1. Fork the repo
2. Create a branch: `git checkout -b feature/your-thing`
3. Commit with clear messages
4. Open a PR against `main` describing what and why

## Reporting bugs

Please include:
- macOS version
- Whether you're on API / Pro / Max
- Output of `ls -la ~/.claude/projects/ | head -20` (so we know the log layout on your machine)
- Screenshot if it's a UI issue
