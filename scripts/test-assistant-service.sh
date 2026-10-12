#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
reference="${MISSIONCONTROL_ASSISTANT_DEPENDENCIES:-$PWD}"
source "$reference/scripts/test-env.sh"
missioncontrol_test_init assistant-service
types=(Cache LocalRecordRepository ConversationRepository Models PAMemory LifeNotebook LifeOrganisation MemoryLearning PALearningQuestion MemoryDependencies Briefing PAMemoryStore LifeWorkspace LifeProjectPlacement LifeWorkspaceQuery LifeWorkspaceStore LifeWorkspaceToolSchema LifeCanonicalNotebook Conversations ChatDraftStore PARequestQueue ChatImages ActionModels NativeCreation NativeEditing AIUsage ChatGPTStream PAToolProtocol PAConversationEngine PAIdentity PAProfileSetup MailLookupRules EmailSummary EmailResolution Proactive WhatsAppModels SourceContextLearning NativeSourceLearning)
sources=()
for name in "${types[@]}"; do sources+=("$reference/MissionControl/$name.swift"); done
sources+=("$reference/MissionControl/Mail/MailService.swift" "$reference/MissionControl/Mail/MailBatching.swift")
# Deliberately excludes DashboardModel, its adapter, production connection,
# EventKitService, MailLookup and PAToolSession: this runs the actual core only.
sources+=(MissionControl/PAInferenceConnection.swift MissionControl/AssistantRuntime.swift MissionControl/AssistantService.swift Tests/AssistantServiceChecks.swift)
xcrun swiftc -module-cache-path "$MISSIONCONTROL_TEST_MODULE_CACHE" -swift-version 5 "${sources[@]}" -o "$MISSIONCONTROL_TEST_BIN"
"$MISSIONCONTROL_TEST_BIN"
