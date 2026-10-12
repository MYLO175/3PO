#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/test-env.sh
missioncontrol_test_init memory-preparation
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" -swift-version 5 MissionControl/Cache.swift MissionControl/LocalRecordRepository.swift MissionControl/PAMemory.swift MissionControl/LifeNotebook.swift MissionControl/LifeOrganisation.swift MissionControl/MemoryLearning.swift MissionControl/PALearningQuestion.swift MissionControl/MemoryDependencies.swift MissionControl/Models.swift MissionControl/Briefing.swift MissionControl/PAMemoryStore.swift Tests/MemoryPreparationChecks.swift -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
