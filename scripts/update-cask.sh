#!/bin/sh
set -eu

# Regenerates Casks/pingbar.rb from a published GitHub release.
# Usage: ./scripts/update-cask.sh [tag]   (default: latest release)
#
# The generated cask is the source of truth for the Homebrew tap at
# https://github.com/melonask/homebrew-pingbar. Copy it to Casks/pingbar.rb
# in that repository to publish the update.

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
REPOSITORY="${PINGBAR_REPOSITORY:-melonask/PingBar}"
TAG="${1:-}"
CASK="$ROOT/Casks/pingbar.rb"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The unauthenticated GitHub API allows only 60 requests an hour, which is easy
# to exhaust while re-running this script. Prefer an authenticated gh CLI, and
# fall back to plain curl when it is not available.
api_get() {
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        gh api "$1" 2>/dev/null || true
    else
        curl -fsSL "https://api.github.com/$1" 2>/dev/null || true
    fi
}

if [ -z "$TAG" ]; then
    TAG="$(api_get "repos/$REPOSITORY/releases/latest" \
        | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
fi

if [ -z "$TAG" ]; then
    echo "Could not determine a release tag. Pass one explicitly:" >&2
    echo "  $0 v1.3.1" >&2
    exit 1
fi

VERSION="${TAG#v}"

# Prefer the digest GitHub publishes for the release asset: it avoids pulling
# the whole download and is the value the tap is expected to carry.
RELEASE_JSON="$(api_get "repos/$REPOSITORY/releases/tags/$TAG")"
SHA256="$(printf '%s' "$RELEASE_JSON" \
    | sed -n 's/.*"digest": *"sha256:\([a-f0-9]\{64\}\)".*/\1/p' | head -1)"

if [ -z "$SHA256" ]; then
    printf 'Downloading PingBar.zip from the %s release\n' "$TAG" >&2
    if curl -fsSL -o "$WORK/PingBar.zip" \
        "https://github.com/$REPOSITORY/releases/download/$TAG/PingBar.zip"; then
        SHA256="$(shasum -a 256 "$WORK/PingBar.zip" | awk '{print $1}')"
    fi
fi

if ! printf '%s' "$SHA256" | grep -Eq '^[a-f0-9]{64}$'; then
    echo "Could not determine a checksum for $TAG. Is the release published?" >&2
    exit 1
fi

mkdir -p "$(dirname -- "$CASK")"
cat > "$CASK" <<'RUBY'
cask "pingbar" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/@REPOSITORY@/releases/download/v#{version}/PingBar.zip"
  name "PingBar"
  desc "Menu-bar monitor for HTTP availability and latency"
  homepage "https://github.com/@REPOSITORY@"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "PingBar.app"

  caveats <<~EOS
    PingBar is ad-hoc signed rather than notarized. If macOS blocks the first
    launch, Control-click PingBar.app in Applications and choose Open, or run:
      /usr/bin/xattr -dr com.apple.quarantine "#{appdir}/PingBar.app"
  EOS
end
RUBY

sed -i '' \
    -e "s|@VERSION@|$VERSION|" \
    -e "s|@SHA256@|$SHA256|" \
    -e "s|@REPOSITORY@|$REPOSITORY|" \
    "$CASK"

printf 'Updated %s to %s (%s)\n' "$CASK" "$VERSION" "$SHA256"
