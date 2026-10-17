# Repository organisation plan

Proposed on 17 October 2026. The immediate deliverable is this map; file moves wait until the active code audit reaches a committed checkpoint. Group the existing app by responsibility, mirror those groups in tests, and separate current guidance from dated engineering history.

## Scope and working boundary

This plan was mapped against committed base `cf0e9f057faa11acc52d944f64697f735d4ae116`. Its isolated worktree is `/Users/mylomichael/.codex/worktrees/folder-organisation/Mission Control`. Only this plan and its companion CSV are added here. The active audit owns the original checkout, including its uncommitted code, shared documentation and untracked asset files. Those changes are outside this inventory and must be reconciled before migration. No message, commit integration, file move, cleanup, build or installation is part of this planning pass.

Folder names express where code belongs within the existing single app target. They do not introduce packages, service boundaries, runtime changes, new screens or data migrations. Preserve source basenames, Swift types, bundle identity, resource names and saved data. Keep mixed files whole; splitting `Models.swift`, `DashboardModel.swift` or other large files is separate work.

## Proposed top level

```text
Mission Control/
├── README.md
├── AGENTS.md
├── STATUS.md                 current checkpoint and links to dated history
├── PLAN.md                   current approved scope and links to historical plans
├── VALIDATION.md             current checks and remaining acceptance
├── MissionControl.xcodeproj/
├── MissionControl/
│   ├── App/
│   ├── Dashboard/
│   ├── Assistant/            Conversation, Context, Tools, Profile, Provider, Reports
│   ├── Memory/               Records, Notebook, Learning, Views
│   ├── Projects/
│   ├── Review/               Inbox, Actions, Feedback
│   ├── Background/           Heartbeat, Briefing
│   ├── Sources/              Mail, Email, Native, WhatsApp, Weather
│   ├── Widgets/              Calendar, Clock
│   ├── Infrastructure/       Storage, Models, Actions, Activity, Usage
│   ├── Development/          Evaluations, Previews, Trials
│   ├── Resources/            existing artwork and resource identities
│   ├── Info.plist
│   └── MissionControl.entitlements
├── Tests/                    corresponding feature and integration groups
├── scripts/
│   ├── build.sh              stable command
│   ├── check.sh              stable command
│   ├── test.sh               stable command
│   ├── checks/               component runners and suite manifest
│   ├── lib/                  common runner setup
│   ├── project/              project generation
│   ├── assets/               icon generation
│   ├── packaging/            bundled helper preparation
│   └── development/          observation and demonstration utilities
├── WhatsAppBridge/           retain existing package layout
├── docs/
│   ├── README.md             documentation index
│   ├── guides/
│   ├── architecture/
│   ├── development/
│   ├── planning/
│   ├── audits/
│   ├── history/
│   ├── archive/
│   └── assets/
└── build/                    ignored local output; retain during reorganisation
```

Keep `Mail` for collection and lookup, and `Email` for assessments, summaries and attention state. Keep native source reads and EventKit integration in `Sources/Native`; shared operation receipts, editing contracts and approval execution belong in `Infrastructure/Actions`. `Assistant/Context` consumes shared memory and source contracts without owning their records. Notebook organisation stays in Memory; human-owned spaces, tasks, notes and placement stay in Projects.

Development evaluations currently compile with the app and may implement DEBUG launch modes. Moving them into `Development/` must retain existing compilation and startup isolation. It does not convert them into standalone tests or remove historical trials.

## Exact tracked file map

The companion [repository file map](repository-file-map.csv) gives every tracked file at the base commit exactly one proposed destination, including files that stay where they are. It is an inventory for review, not an executable migration script. Rebuild the inventory against the audit checkpoint before any moves; newly added files need explicit destinations. Test locations are organisational proposals and do not change which source files each test compiles.

The base inventory contains **409 tracked files**: **368 proposed moves** and **41 retained paths**. Ignored build output, dependencies, private data and untracked duplicates are excluded.

## App source mapping

### App

Destination: `MissionControl/App/`.

`MissionControlApp.swift`, `ApplicationServices.swift`, `MenuBarIcon.swift`.

### Dashboard

Destination: `MissionControl/Dashboard/`.

`DashboardModel.swift`, `DashboardView.swift`, `WorkspaceColors.swift`, `WorkspaceCommands.swift`, `WorkspaceControls.swift`, `WorkspaceGeometry.swift`, `WorkspaceModels.swift`, `WorkspaceStore.swift`, `WorkspaceView.swift`, `SourceStatusIndicator.swift`, `GeneralOverviewView.swift`.

### Assistant Conversation

Destination: `MissionControl/Assistant/Conversation/`.

`AssistantService.swift`, `AssistantRuntime.swift`, `AssistantActions.swift`, `AssistantDashboardAdapter.swift`, `AssistantTranscriptProjection.swift`, `AssistantView.swift`, `Conversations.swift`, `ConversationRepository.swift`, `ChatDraftStore.swift`, `PAChatComposer.swift`, `PAConversationEngine.swift`, `PARequestQueue.swift`, `ChatImages.swift`, `DictationService.swift`, `DictationView.swift`.

### Assistant Context

Destination: `MissionControl/Assistant/Context/`.

`PAWorkingContext.swift`, `AutomaticMemoryContext.swift`, `PAOrientation.swift`, `LifeFocus.swift`, `LifeFocusPicker.swift`.

### Assistant Tools

Destination: `MissionControl/Assistant/Tools/`.

`PAToolAuthorization.swift`, `PAToolProtocol.swift`, `PAToolSession.swift`.

### Assistant Profile

Destination: `MissionControl/Assistant/Profile/`.

`PAIdentity.swift`, `PANameEditor.swift`, `PAProfileSetup.swift`, `PAProfileSetupView.swift`, `PALearningQuestion.swift`.

### Assistant Reports

Destination: `MissionControl/Assistant/Reports/`.

`CommitmentReportsView.swift`.

### Assistant Provider

Destination: `MissionControl/Assistant/Provider/`.

`ChatGPTCallback.swift`, `ChatGPTConnection.swift`, `ChatGPTOAuth.swift`, `ChatGPTRecovery.swift`, `ChatGPTStream.swift`, `PAInferenceConnection.swift`, `InferenceDeadline.swift`.

### Memory Records

Destination: `MissionControl/Memory/Records/`.

`PAMemory.swift`, `PAMemoryStore.swift`, `MemoryDependencies.swift`, `MemoryInspection.swift`.

### Memory Notebook

Destination: `MissionControl/Memory/Notebook/`.

`LifeNotebook.swift`, `LifeCanonicalNotebook.swift`, `LifeOrganisation.swift`, `LifeOrganisationService.swift`, `PAMemoryGraph.swift`, `LifeMapLayout.swift`.

### Memory Learning

Destination: `MissionControl/Memory/Learning/`.

`MemoryLearning.swift`, `MemoryLearningService.swift`, `MemoryMaintenance.swift`, `MemoryMaintenanceService.swift`, `SourceContextLearning.swift`, `SourceContextLearningService.swift`, `NativeSourceLearning.swift`, `NativeSourceLearningService.swift`, `LearningBudget.swift`, `BackgroundLearningCoordinator.swift`, `LearningRuntime.swift`, `LearningDashboardAdapter.swift`.

### Memory Views

Destination: `MissionControl/Memory/Views/`.

`PAMemoryView.swift`, `PAMemoryGraphView.swift`, `MemoryInspectionView.swift`, `MemoryMaintenanceView.swift`, `MemoryAdviceEvidenceView.swift`, `LifeNotebookView.swift`, `LifeCanonicalMapView.swift`, `PALifeMapWidget.swift`.

### Projects

Destination: `MissionControl/Projects/`.

`LifeWorkspace.swift`, `LifeWorkspaceContext.swift`, `LifeWorkspaceQuery.swift`, `LifeWorkspaceStore.swift`, `LifeWorkspaceToolSchema.swift`, `LifeWorkspaceTools.swift`, `LifeProjectControls.swift`, `LifeProjectNotes.swift`, `LifeProjectPlacement.swift`, `LifeProjectWidget.swift`, `LifePlacementService.swift`, `LifeNoteTextEditing.swift`.

### Review Inbox

Destination: `MissionControl/Review/Inbox/`.

`Proactive.swift`, `ProactiveResult.swift`, `ProactiveReviewRules.swift`, `ProactiveService.swift`, `PreparedReview.swift`, `ReviewInferenceGuard.swift`, `PATasksView.swift`, `DiscoveryEvidenceView.swift`.

### Review Actions

Destination: `MissionControl/Review/Actions/`.

`ReviewWork.swift`, `ReviewWorkDashboardAdapter.swift`, `ReviewPlanDashboardAdapter.swift`, `ReviewPlanDateRules.swift`, `ReviewPlanTools.swift`, `ProductionReviewConversationView.swift`.

### Review Feedback

Destination: `MissionControl/Review/Feedback/`.

`ReviewFeedback.swift`, `ReviewFeedbackJobs.swift`, `ReviewFeedbackService.swift`.

### Background Heartbeat

Destination: `MissionControl/Background/Heartbeat/`.

`Heartbeat.swift`, `HeartbeatService.swift`, `HeartbeatRuntime.swift`, `HeartbeatPower.swift`, `HeartbeatSourceContext.swift`, `HeartbeatDashboardAdapter.swift`.

### Background Briefing

Destination: `MissionControl/Background/Briefing/`.

`Briefing.swift`, `BriefingService.swift`, `BriefingView.swift`, `TodayBriefView.swift`.

### Sources Email

Destination: `MissionControl/Sources/Email/`.

`EmailResolution.swift`, `EmailSummary.swift`, `EmailSummaryService.swift`, `EmailOverviewView.swift`.

### Sources Mail

Destination: `MissionControl/Sources/Mail/`.

`MailLookup.swift`, `MailLookupCoverage.swift`, `MailLookupRules.swift`.

### Sources Native

Destination: `MissionControl/Sources/Native/`.

`EventKitActions.swift`, `EventKitCreation.swift`, `EventKitEditing.swift`, `EventKitService.swift`, `EventKitTools.swift`, `NativeSourceAdapters.swift`, `NativeSourceProjection.swift`, `NativeSourceRead.swift`, `WidgetCalendarStore.swift`.

### Sources WhatsApp

Destination: `MissionControl/Sources/WhatsApp/`.

`WhatsAppModels.swift`, `WhatsAppService.swift`, `WhatsAppSourcePicker.swift`.

### Sources Weather

Destination: `MissionControl/Sources/Weather/`.

`Weather.swift`, `WeatherService.swift`, `WeatherView.swift`, `WeatherWidgetView.swift`.

### Widgets Calendar

Destination: `MissionControl/Widgets/Calendar/`.

`CalendarTimeline.swift`, `CalendarWidgetView.swift`.

### Widgets Clock

Destination: `MissionControl/Widgets/Clock/`.

`DateClockWidget.swift`.

### Infrastructure Storage

Destination: `MissionControl/Infrastructure/Storage/`.

`Cache.swift`, `LocalRecordRepository.swift`.

### Infrastructure Models

Destination: `MissionControl/Infrastructure/Models/`.

`Models.swift`.

### Infrastructure Actions

Destination: `MissionControl/Infrastructure/Actions/`.

`ActionModels.swift`, `ActionReceiptStore.swift`, `NativeActionRuntime.swift`, `NativeCreation.swift`, `NativeCreationStore.swift`, `NativeEditing.swift`, `NativeItemEditor.swift`, `NativeReconciliation.swift`, `NativeRepeatEditor.swift`.

### Infrastructure Activity

Destination: `MissionControl/Infrastructure/Activity/`.

`AIActivity.swift`, `AIActivityDashboardAdapter.swift`, `AIActivityView.swift`.

### Infrastructure Usage

Destination: `MissionControl/Infrastructure/Usage/`.

`AIUsage.swift`, `AIUsageStore.swift`, `AIUsageView.swift`.

### Development Previews

Destination: `MissionControl/Development/Previews/`.

`DateClockPreview.swift`, `LifeNotebookPreview.swift`, `LifeProjectPreview.swift`, `MemoryInspectionPreview.swift`, `WeatherWidgetPreview.swift`, `SampleServices.swift`.

### Development Evaluations

Destination: `MissionControl/Development/Evaluations/`.

`AdviceContextEvaluation.swift`, `ChatImageEvaluation.swift`, `CommitmentReportEvaluation.swift`, `EvaluationLaunchGuard.swift`, `EvaluationOutput.swift`, `ForegroundInteractionEvaluation.swift`, `LifeNotebookEvaluation.swift`, `LifeOwnershipEvaluation.swift`, `LifePlacementEvaluation.swift`, `LifeWorkspaceEvaluation.swift`, `NativeCapabilitiesEvaluation.swift`, `NativeMemoryEvaluation.swift`, `NativeReconciliationEvaluation.swift`, `PreparedApprovalEvaluation.swift`, `ReviewInboxEvaluation.swift`, `ReviewInferenceGuardEvaluation.swift`, `SourceContextEvaluation.swift`, `WorkflowEvaluation.swift`, `WorkingContextModelEvaluation.swift`.

### Development Trials

Destination: `MissionControl/Development/Trials/`.

`ReviewConversationTrial.swift`, `ReviewConversationTrialView.swift`.

Existing `MissionControl/Mail/` files move together into `MissionControl/Sources/Mail/`, retaining `MailReader.js` as a bundled resource. `Resources/`, `Info.plist` and the entitlement file retain their current paths.

## Documentation mapping

- `docs/guides/`: `FEATURES.md`, `GETTING_STARTED.md`, `PRIVACY.md`, `GLOSSARY.md`.
- `docs/architecture/`: `ARCHITECTURE.md`, `HOW_IT_WORKS.md`, `MEMORY_AND_CONTEXT.md`, `PROJECT_WORKSPACE.md`.
- `docs/development/`: `DEVELOPMENT.md`, `DEVELOPMENT_WORKFLOW.md`, `LIVE_ACCEPTANCE.md`.
- `docs/planning/`: `NEXT_IMPROVEMENTS.md`, `EMAIL_ACTIONS_PLAN.md`, `HEARTBEAT_RELIABILITY_PLAN.md`, `PA_INTELLIGENCE_PLAN.md`, `RELIABILITY_IMPLEMENTATION.md`.
- `docs/history/`: `DECISIONS.md`.
- `docs/audits/`: `CODE_AUDIT_2026-10-16.md`, `PA_ARCHITECTURE_REVIEW.md`.
- `docs/archive/trials/`: `REVIEW_CONVERSATION_TRIAL.md`.

Keep `docs/README.md` as the index, existing artwork in `docs/assets/`, and archived agent instructions in `docs/archive/`. Move the organisation plan and CSV into `docs/development/` when the migration lands, updating their links together. These two new files are not part of the base inventory.

### Current documents and historical evidence

Retain the root entry points because humans and agent instructions already rely on them. Later, extract dated STATUS sections intact into `docs/history/status/`, preserving heading anchors through updated links or explicit redirect links. Keep the latest summary and unresolved work at the top level. Preserve original text, dates, code references and evidence paths; historical private diagnostic references are not instructions to copy that data into Git.

Apply the same approach to historical PLAN and VALIDATION sections under `docs/history/plans/` and `docs/history/validation/`, keeping current scope and current evidence in the root files. Group by existing dated sections, preferably by month; never split a dated section simply to meet a file-size target. Keep decision history together initially, with the newest applicable choices clearly reachable. Do not rewrite historical decisions as current rules.

History extraction is a separate, reviewed documentation step after physical moves. The CSV retains the root documents because extraction is not a one-file rename. Verify all old content survives and update incoming links and anchors. Leave AGENTS intact during this pass; it contains current instructions as well as recorded preferences.

## Build and check dependencies

- `scripts/generate-project.py` already discovers nested Swift, JavaScript and asset catalogue paths, but emits one flat Xcode group and derives object IDs from paths. Update it to present the physical folder hierarchy and regenerate the project deterministically. Do not hand-maintain project references alongside the generator. Preserve target, scheme, signing, resource bundle behaviour and build settings.
- Component test scripts name many `MissionControl/Filename.swift` and `Tests/FilenameChecks.swift` paths explicitly. Update every reference using the reviewed map, including source-inspection checks, fixtures, string-based assertions, shared dependency arrays and the `MISSIONCONTROL_ASSISTANT_DEPENDENCIES` alternate-checkout path. Preserve each suite's original compilation inputs and isolation.
- Moving scripts changes their existing parent-based repository-root discovery. Fix that discovery before using moved scripts. Update sourced `test-env.sh` paths and helper calls; check both direct runner invocation and aggregate invocation from outside the repository.
- `scripts/check.sh` discovers component runners with a non-recursive `scripts/test*.sh` glob. Change discovery and the `scripts/check-suites.json` manifest together, retaining exact suite IDs, tiers, effects, ordering and complete inventory checks. Check the wrapper `test.sh` as well.
- `scripts/build.sh` calls four helper scripts by their present locations. Update those references and packaging entitlement paths, retaining private per-build output roots and the existing dependency preparation contract.
- Search the whole tracked repository for old paths, including README, AGENTS, plans, test fixtures, manifests and developer instructions. Update actionable references. Preserve historical prose and historical commands as dated evidence with a relocation note where needed.
- Preserve runtime resource lookup for `MailReader.js`, `WhatsAppBridge`, bundled Node, icons and asset catalogues. Moving source folders must not silently alter bundle-relative resource names or helper checksums.

## Migration sequence after the audit

1. Confirm the audit agent has finished writing and produced a committed checkpoint. Inspect active chats, worktrees and Git state again. Record the chosen final base and reconcile all additions or renamed files against this inventory. Never stash or commit another writer's edits as part of cleanup.
2. Use an isolated migration worktree based on that checkpoint. Agree the migration's exclusive ownership of file paths, project generation, test runner paths and documentation links. Keep behavioural changes out of the migration.
3. Move app sources and update all references in the same checkpoint. Regenerate the Xcode project, retaining the existing target and bundle contracts. Check file coverage before building.
4. Group Tests and script internals, repair root discovery and suite discovery, and verify all expected suites remain registered exactly once. Retain the three root command names.
5. Group documentation and update local links and developer instructions. Extract historical logs in a subsequent checkpoint so reviewers can distinguish relocation from content changes.
6. Run the relevant source-free inventory serially, then the complete required inventory and a signed Debug build in unique output directories. Verify original and relocated file sets, resource presence and deterministic project generation. Report failures and coverage honestly.
7. Hand back reviewed commits and validation evidence for integration. Installation or personal-data acceptance is separate from folder organisation. No old worktree, build directory or duplicate asset is deleted as part of these steps.

## Acceptance checklist

- Every tracked file at the final audit checkpoint has a documented destination; no unexplained omissions, destination collisions or silent deletions.
- File moves preserve bytes except reviewed path, project-generation and documentation updates. No SwiftData schema, model identity, runtime prompt, source permission, user preference or operational behaviour changes.
- Build and check entry points work with paths containing spaces. Direct component runners, the aggregate inventory and alternate-checkout dependencies resolve the intended repository.
- The same test suite IDs and tiers remain available, and each suite retains its intended inputs. A green build alone does not establish this.
- Xcode shows the intended groups; project regeneration is deterministic; source and resource inventories match the original target after path translation. Signature/build and live acceptance remain distinct claims.
- Documentation links and heading anchors resolve. Extracted historical sections remain complete and the current root summaries point to them.
- The audit agent's edits and untracked assets remain untouched until their owning work is integrated or explicitly reconciled.

## Deferred cleanup

The original checkout currently contains untracked artwork files with duplicate-looking names. Do not assume they are disposable or add them to this move map. Once the audit is complete, compare their content, asset catalogue references and provenance before proposing cleanup. Likewise, inspect old worktrees for ownership, uncommitted files and integration status before any archival. Ignored build output and WhatsApp dependencies remain in place; this plan is about navigation and maintenance, not storage reclamation.
