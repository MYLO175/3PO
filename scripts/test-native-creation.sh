#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/Cache.swift MissionControl/Models.swift MissionControl/ActionModels.swift MissionControl/NativeEditing.swift MissionControl/NativeCreation.swift MissionControl/NativeCreationStore.swift Tests/NativeCreationChecks.swift -o /tmp/missioncontrol-native-creation-checks
/tmp/missioncontrol-native-creation-checks
