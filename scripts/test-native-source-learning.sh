#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun swiftc -module-cache-path /tmp/missioncontrol-test-modules MissionControl/Cache.swift MissionControl/PAMemory.swift MissionControl/LifeNotebook.swift MissionControl/LifeOrganisation.swift MissionControl/MemoryLearning.swift MissionControl/PALearningQuestion.swift MissionControl/MemoryDependencies.swift MissionControl/Briefing.swift MissionControl/PAMemoryStore.swift MissionControl/Models.swift MissionControl/PAOrientation.swift MissionControl/Mail/MailService.swift MissionControl/Mail/MailBatching.swift MissionControl/EmailSummary.swift MissionControl/NativeSourceLearning.swift MissionControl/NativeSourceAdapters.swift Tests/NativeSourceLearningChecks.swift -o /tmp/missioncontrol-native-source-learning-checks
/tmp/missioncontrol-native-source-learning-checks
