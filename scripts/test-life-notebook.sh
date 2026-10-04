#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/PAMemory.swift MissionControl/LifeNotebook.swift MissionControl/LifeOrganisation.swift MissionControl/LifeFocus.swift Tests/LifeNotebookChecks.swift -o /tmp/missioncontrol-life-notebook-checks
/tmp/missioncontrol-life-notebook-checks
