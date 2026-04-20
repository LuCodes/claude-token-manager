#!/bin/bash
# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh 1.2.1
#
# Must be run AFTER the GitHub release is published (so the zip is
# downloadable and we can compute its sha256).

set -e

VERSION="$1"
if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    exit 1
fi

ZIP_URL="https://github.com/LuCodes/claude-token-manager/releases/download/v${VERSION}/ClaudeTokenManager.zip"
TAP_REPO_PATH="${TAP_REPO_PATH:-$HOME/dev/homebrew-claude-token-manager}"
CASK_FILE="$TAP_REPO_PATH/Casks/claude-token-manager.rb"

if [ ! -f "$CASK_FILE" ]; then
    echo "Error: cask file not found at $CASK_FILE"
    echo "Set TAP_REPO_PATH to your tap repo location"
    exit 1
fi

echo "→ Downloading release zip..."
TMP=$(mktemp -t ctm-release-XXXXXX.zip)
curl -L -o "$TMP" "$ZIP_URL"

echo "→ Computing SHA-256..."
SHA256=$(shasum -a 256 "$TMP" | cut -d' ' -f1)
echo "  $SHA256"
rm "$TMP"

echo "→ Updating cask file..."
sed -i '' -E "s/version \".*\"/version \"${VERSION}\"/" "$CASK_FILE"
sed -i '' -E "s/sha256 \".*\"/sha256 \"${SHA256}\"/" "$CASK_FILE"

cd "$TAP_REPO_PATH"
git diff --exit-code && echo "No changes detected" && exit 1
git add Casks/claude-token-manager.rb
git commit -m "chore: bump claude-token-manager to v${VERSION}"
git push

echo "✓ Cask updated and pushed. Users can now:"
echo "    brew upgrade --cask claude-token-manager"
