#!/usr/bin/env bash
# Regenerates VisionFont.xcodeproj from project.yml with XcodeGen.
# You only need this if you change project.yml — the project is already included.
#   macOS:  brew install xcodegen   (or: mint run yonaskolb/XcodeGen)
#   Linux:  build XcodeGen 2.44.1 from source with Swift (swift build -c release) and put it on PATH.
set -euo pipefail
cd "$(dirname "$0")"
XCODEGEN="${XCODEGEN:-$(command -v xcodegen || true)}"
if [[ -z "$XCODEGEN" ]]; then
  echo "xcodegen not found. Install it with: brew install xcodegen" >&2
  exit 1
fi
"$XCODEGEN" generate --spec project.yml --project . 
python3 tools/check_project.py
