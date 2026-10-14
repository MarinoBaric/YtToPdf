#!/usr/bin/env bash
#
# Builds YtToPdf in Release configuration and installs it.
#
# Usage:
#   scripts/build-and-install.sh                 # build and install to /Applications
#   scripts/build-and-install.sh --dest ~/Apps   # install somewhere else
#   scripts/build-and-install.sh --no-install    # build only (output in build/)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="/Applications"
INSTALL=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dest) DEST="$2"; shift 2 ;;
        --no-install) INSTALL=0; shift ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 64 ;;
    esac
done

bold() { printf '\033[1m%s\033[0m\n' "$*"; }

command -v xcodebuild >/dev/null || { echo "xcodebuild not found. Install Xcode 27 from the App Store." >&2; exit 1; }

# The app needs these at runtime; warn early rather than at first launch.
missing=()
for tool in yt-dlp ffmpeg whisper-cli; do
    [[ -x "/opt/homebrew/bin/$tool" || -x "/usr/local/bin/$tool" ]] || missing+=("$tool")
done
if (( ${#missing[@]} )); then
    echo "Note: missing runtime tools: ${missing[*]}"
    echo "      Install them with: brew install yt-dlp ffmpeg whisper-cpp"
fi

bold "Building YtToPdf (Release)…"
xcodebuild \
    -project "$ROOT/YtToPdf.xcodeproj" \
    -scheme YtToPdf \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$ROOT/build" \
    build | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" || true

APP="$ROOT/build/Build/Products/Release/YtToPdf.app"
[[ -d "$APP" ]] || { echo "Build failed: $APP not found." >&2; exit 1; }

if (( INSTALL == 0 )); then
    bold "Built: $APP"
    exit 0
fi

if pgrep -x YtToPdf >/dev/null; then
    echo "Quitting the running copy of YtToPdf…"
    osascript -e 'quit app "YtToPdf"' >/dev/null 2>&1 || true
    sleep 1
fi

bold "Installing to $DEST/YtToPdf.app…"
mkdir -p "$DEST"
rm -rf "$DEST/YtToPdf.app"
ditto "$APP" "$DEST/YtToPdf.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST/YtToPdf.app" || true

bold "Done. Open it from $DEST or Spotlight."
