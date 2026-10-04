#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
if [[ ! -d WhatsAppBridge/node_modules ]]; then
  npm --cache /tmp/missioncontrol-npm-cache ci --ignore-scripts --prefix WhatsAppBridge
fi
python3 scripts/package-whatsapp-runtime.py
python3 scripts/build-icon.py
python3 scripts/generate-project.py
xcodebuild -project MissionControl.xcodeproj -scheme MissionControl -configuration Debug -derivedDataPath /tmp/missioncontrol-derived build "$@"
