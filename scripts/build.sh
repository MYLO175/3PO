#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
python3 scripts/generate-project.py
xcodebuild -project MissionControl.xcodeproj -scheme MissionControl -configuration Debug -derivedDataPath /tmp/missioncontrol-derived build "$@"
