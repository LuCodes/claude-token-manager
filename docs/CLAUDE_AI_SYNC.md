# claude.ai sync setup

To enable claude.ai sync, click **Sign in to claude.ai** in the
app's Preferences. A native sign-in window will open where you can
log in with your claude.ai credentials.

The app uses an embedded WebKit instance (the same engine as
Safari) for authentication. Your credentials never leave your Mac
and are never visible to the app code itself — they are managed
directly by macOS.

## Troubleshooting

### The sign-in window doesn't close after I log in

The app polls every 500ms to detect successful authentication. If
the window stays open more than ~5 seconds after a successful
login, close it manually and try again. If the issue persists,
please open an issue with your macOS version.

### "Connection failed" after sign-in

The undocumented claude.ai usage API may have introduced new
protections. Check
[the project issues](https://github.com/LuCodes/claude-token-manager/issues)
for known problems, or open a new one.

### How do I sign out?

Click **Sign out** in the Preferences card "claude.ai sync".
This clears the WebKit cookies for claude.ai (only within the
app's storage, not affecting your regular browsers).
