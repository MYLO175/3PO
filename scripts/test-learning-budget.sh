#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/test-env.sh
missioncontrol_test_init learning-budget
# An integration owner can verify this bounded fixture against another current
# source checkout without importing/editing that checkout's Swift files.
source_root="${MISSIONCONTROL_TEST_SOURCE_ROOT:-$PWD}"
fixture="$PWD/Tests/LearningBudgetChecks.swift"
cd "$source_root"
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" MissionControl/Cache.swift MissionControl/LocalRecordRepository.swift MissionControl/Models.swift MissionControl/PAMemory.swift MissionControl/LifeNotebook.swift MissionControl/LifeOrganisation.swift MissionControl/MemoryLearning.swift MissionControl/PALearningQuestion.swift MissionControl/MemoryDependencies.swift MissionControl/Briefing.swift MissionControl/BackgroundLearningCoordinator.swift MissionControl/LearningBudget.swift "$fixture" -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
