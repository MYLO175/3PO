#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/Models.swift MissionControl/ActionModels.swift MissionControl/NativeEditing.swift Tests/NativeEditChecks.swift -o /tmp/missioncontrol-native-edit-checks
/tmp/missioncontrol-native-edit-checks
