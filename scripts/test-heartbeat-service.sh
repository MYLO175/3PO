#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
reference="${MISSIONCONTROL_HEARTBEAT_DEPENDENCIES:-$PWD}"
source "$reference/scripts/test-env.sh"
missioncontrol_test_init heartbeat-service
types=(Cache LocalRecordRepository Models PAMemory LifeNotebook LifeOrganisation MemoryLearning PALearningQuestion MemoryDependencies Briefing LifeWorkspace LifeProjectPlacement LifeWorkspaceQuery LifeWorkspaceToolSchema LifeCanonicalNotebook Conversations PARequestQueue ActionModels NativeCreation NativeEditing AIUsage ChatGPTStream PAToolProtocol PAIdentity PAProfileSetup MailLookupRules EmailSummary EmailResolution Proactive WhatsAppModels SourceContextLearning NativeSourceLearning Heartbeat HeartbeatPower)
sources=()
for name in "${types[@]}"; do sources+=("$reference/MissionControl/$name.swift"); done
sources+=("$reference/MissionControl/Mail/MailService.swift" "$reference/MissionControl/Mail/MailBatching.swift")
# Actual scheduler, rules and repository; no DashboardModel, desktop adapter,
# live connection, EventKitService or real child services are compiled or started.
sources+=(MissionControl/HeartbeatRuntime.swift MissionControl/HeartbeatService.swift Tests/HeartbeatServiceChecks.swift)
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" -swift-version 5 "${sources[@]}" -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
