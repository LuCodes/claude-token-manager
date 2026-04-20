# claude.ai sync setup

See the main [README](../README.md#claudeai-sync-mode) for the full
setup instructions. This document covers security warnings and
troubleshooting.

## Security warnings — read before enabling

The "claude.ai sync" mode fetches your real plan limits by calling
claude.ai's internal API with your session cookie. Before enabling
it, you must understand what this implies:

### 1. Your cookie grants full access to your account

Anyone who possesses your `sessionKey` can:
- Log into claude.ai as you
- Read all your conversations (including private ones)
- Change your subscription or settings
- Consume your quota

**Never share your cookie with anyone.** The app stores it in macOS
Keychain which is encrypted and tied to your Mac, but when you
extract it from DevTools, it passes through your clipboard. Make sure
no clipboard sync tool (iCloud, Raycast, Paste, Alfred) sends it to
another device.

### 2. This feature uses an undocumented API

The `/api/organizations/.../usage` endpoint is an **internal**
claude.ai endpoint, not a public API. This means:

- Anthropic can change or block this endpoint at any time
- Anthropic's Terms of Service prohibit automated access to the web
  interface
- In theory, your account could be suspended if detected as a bot

In practice, no suspension has been observed for this type of
moderate usage (one request every 30 seconds), but you use this
feature **at your own risk**.

### 3. The app is open-source with no warranty

The code is public on GitHub and auditable by the community. But it's
a solo project with no commercial security guarantee. If you have
doubts, inspect the code before entering your credentials.

### 4. If you suspect a leak

Log out of claude.ai from the website. This invalidates your session
cookie immediately, no matter where it is. You can then log back in
normally.

### 5. Auto-cleanup

If you don't open Claude Token Manager for 30 days, your stored
credentials are automatically purged to minimize the exposure window
in case of a stolen or compromised Mac.

---

## Troubleshooting

### "Test & save" returns an error

- The session cookie expires after some time. Log out and back into
  claude.ai, then copy the new cookie.
- The organization ID is the UUID in the URL path, not in any header.
- Make sure you copied the cookie **value** only, not the
  `sessionKey=` prefix.

### The app shows old percentages

- The app refreshes every 30 seconds. Click the refresh icon at the
  bottom of the dropdown to force an immediate update.

### After updating the app, I see a Gatekeeper prompt

- Run `xattr -cr "/Applications/Claude Token Manager.app"` and
  relaunch. The Homebrew cask does this automatically — if you
  installed manually, you'll see this once per version.
