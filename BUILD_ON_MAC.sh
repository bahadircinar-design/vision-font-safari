#!/usr/bin/env bash
# Builds Vision Font (app + Safari extension) from the command line once Xcode is installed.
# Signing uses whatever team you picked in Xcode (Signing & Capabilities). To pass one explicitly:
#     TEAM_ID=ABCDE12345 ./BUILD_ON_MAC.sh
set -euo pipefail
cd "$(dirname "$0")"

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Xcode isn't set up yet. Install Xcode from the App Store, open it once, then run:" >&2
  echo "    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi
xcodebuild -version | head -1

extra=()
if [[ -n "${TEAM_ID:-}" ]]; then extra+=("DEVELOPMENT_TEAM=$TEAM_ID"); fi

xcodebuild -project VisionFont.xcodeproj -scheme 'Vision Font' -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -allowProvisioningUpdates ${extra[@]+"${extra[@]}"} build | tail -25

dir=$(xcodebuild -project VisionFont.xcodeproj -scheme 'Vision Font' -configuration Debug -showBuildSettings 2>/dev/null \
      | awk -F' = ' '/ BUILT_PRODUCTS_DIR = /{print $2; exit}')
app="$dir/Vision Font.app"
if [[ -d "$app" ]]; then
  echo
  echo "Built: $app"
  echo "Extension inside it: $(ls -d "$app/Contents/PlugIns/"*.appex 2>/dev/null || echo 'MISSING')"
  codesign -dv --verbose=2 "$app" 2>&1 | grep -E 'Identifier|TeamIdentifier|Authority' | head -4 || true
  echo
  echo "Open it with:  open \"$app\""
else
  echo "Build finished but the app wasn't found in $dir" >&2
  exit 1
fi
