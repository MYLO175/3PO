# Repository organisation

Implemented folder layout on 17 October 2026, following the completed audit checkpoint `40f49ad`. The existing app is grouped by responsibility, tests follow their owning areas, and current guidance is separated from preserved engineering history.

## Scope and working boundary

The migration was prepared in `/Users/mylomichael/.codex/worktrees/folder-organisation/Mission Control`. The [file map](repository-file-map.csv) records the original and current paths for all 414 files at the migration base, including the two planning files. The audit added a relationship test, its runner and a continuity audit after the original 409-file proposal.

Folder names express where code belongs within the existing single app target. They do not introduce packages, service boundaries, runtime changes, new screens or data migrations. Preserve source basenames, Swift types, bundle identity, resource names and saved data. Keep mixed files whole; splitting `Models.swift`, `DashboardModel.swift` or other large files is separate work.

## Top level

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

## Tracked file map

The companion [repository file map](repository-file-map.csv) records all **414 files** at the migration base: **373 moved paths** and **41 retained paths**. Generated project changes, documentation archives and new validation records are reviewed separately from the map. Ignored build output, dependencies, personal data and untracked duplicate artwork are excluded.

## App source mapping

### App

Location: `MissionControl/App/`.

`MissionControlApp.swift`, `ApplicationServices.swift`, `MenuBarIcon.swift`.

### Dashboard

Location: `MissionControl/Dashboard/`.

`DashboardModel.swift`, `DashboardView.swift`, `WorkspaceColors.swift`, `WorkspaceCommands.swift`, `WorkspaceControls.swift`, `WorkspaceGeometry.swift`, `WorkspaceModels.swift`, `WorkspaceStore.swift`, `WorkspaceView.swift`, `SourceStatusIndicator.swift`, `GeneralOverviewView.swift`.

### Assistant Conversation

Location: `MissionControl/Assistant/Conversation/`.

`AssistantService.swift`, `AssistantRuntime.swift`, `AssistantActions.swift`, `AssistantDashboardAdapter.swift`, `AssistantTranscriptProjection.swift`, `AssistantView.swift`, `Conversations.swift`, `ConversationRepository.swift`, `ChatDraftStore.swift`, `PAChatComposer.swift`, `PAConversationEngine.swift`, `PARequestQueue.swift`, `ChatImages.swift`, `DictationService.swift`, `DictationView.swift`.

### Assistant Context

Location: `MissionControl/Assistant/Context/`.

`PAWorkingContext.swift`, `AutomaticMemoryContext.swift`, `PAOrientation.swift`, `LifeFocus.swift`, `LifeFocusPicker.swift`.

### Assistant Tools

Location: `MissionControl/Assistant/Tools/`.

`PAToolAuthorization.swift`, `PAToolProtocol.swift`, `PAToolSession.swift`.

### Assistant Profile

Location: `MissionControl/Assistant/Profile/`.

`PAIdentity.swift`, `PANameEditor.swift`, `PAProfileSetup.swift`, `PAProfileSetupView.swift`, `PALearningQuestion.swift`.

### Assistant Reports

Location: `MissionControl/Assistant/Reports/`.

`CommitmentReportsView.swift`.

### Assistant Provider

Location: `MissionControl/Assistant/Provider/`.

`ChatGPTCallback.swift`, `ChatGPTConnection.swift`, `ChatGPTOAuth.swift`, `ChatGPTRecovery.swift`, `ChatGPTStream.swift`, `PAInferenceConnection.swift`, `InferenceDeadline.swift`.

### Memory Records

Location: `MissionControl/Memory/Records/`.

`PAMemory.swift`, `PAMemoryStore.swift`, `MemoryDependencies.swift`, `MemoryInspection.swift`.

### Memory Notebook

Location: `MissionControl/Memory/Notebook/`.

`LifeNotebook.swift`, `LifeCanonicalNotebook.swift`, `LifeOrganisation.swift`, `LifeOrganisationService.swift`, `PAMemoryGraph.swift`, `LifeMapLayout.swift`.

### Memory Learning

Location: `MissionControl/Memory/Learning/`.

`MemoryLearning.swift`, `MemoryLearningService.swift`, `MemoryMaintenance.swift`, `MemoryMaintenanceService.swift`, `SourceContextLearning.swift`, `SourceContextLearningService.swift`, `NativeSourceLearning.swift`, `NativeSourceLearningService.swift`, `LearningBudget.swift`, `BackgroundLearningCoordinator.swift`, `LearningRuntime.swift`, `LearningDashboardAdapter.swift`.

### Memory Views

Location: `MissionControl/Memory/Views/`.

`PAMemoryView.swift`, `PAMemoryGraphView.swift`, `MemoryInspectionView.swift`, `MemoryMaintenanceView.swift`, `MemoryAdviceEvidenceView.swift`, `LifeNotebookView.swift`, `LifeCanonicalMapView.swift`, `PALifeMapWidget.swift`.

### Projects

Location: `MissionControl/Projects/`.

`LifeWorkspace.swift`, `LifeWorkspaceContext.swift`, `LifeWorkspaceQuery.swift`, `LifeWorkspaceStore.swift`, `LifeWorkspaceToolSchema.swift`, `LifeWorkspaceTools.swift`, `LifeProjectControls.swift`, `LifeProjectNotes.swift`, `LifeProjectPlacement.swift`, `LifeProjectWidget.swift`, `LifePlacementService.swift`, `LifeNoteTextEditing.swift`.

### Review Inbox

Location: `MissionControl/Review/Inbox/`.

`Proactive.swift`, `ProactiveResult.swift`, `ProactiveReviewRules.swift`, `ProactiveService.swift`, `PreparedReview.swift`, `ReviewInferenceGuard.swift`, `PATasksView.swift`, `DiscoveryEvidenceView.swift`.

### Review Actions

Location: `MissionControl/Review/Actions/`.

`ReviewWork.swift`, `ReviewWorkDashboardAdapter.swift`, `ReviewPlanDashboardAdapter.swift`, `ReviewPlanDateRules.swift`, `ReviewPlanTools.swift`, `ProductionReviewConversationView.swift`.

### Review Feedback

Location: `MissionControl/Review/Feedback/`.

`ReviewFeedback.swift`, `ReviewFeedbackJobs.swift`, `ReviewFeedbackService.swift`.

### Background Heartbeat

Location: `MissionControl/Background/Heartbeat/`.

`Heartbeat.swift`, `HeartbeatService.swift`, `HeartbeatRuntime.swift`, `HeartbeatPower.swift`, `HeartbeatSourceContext.swift`, `HeartbeatDashboardAdapter.swift`.

### Background Briefing

Location: `MissionControl/Background/Briefing/`.

`Briefing.swift`, `BriefingService.swift`, `BriefingView.swift`, `TodayBriefView.swift`.

### Sources Email

Location: `MissionControl/Sources/Email/`.

`EmailResolution.swift`, `EmailSummary.swift`, `EmailSummaryService.swift`, `EmailOverviewView.swift`.

### Sources Mail

Location: `MissionControl/Sources/Mail/`.

`MailLookup.swift`, `MailLookupCoverage.swift`, `MailLookupRules.swift`.

### Sources Native

Location: `MissionControl/Sources/Native/`.

`EventKitActions.swift`, `EventKitCreation.swift`, `EventKitEditing.swift`, `EventKitService.swift`, `EventKitTools.swift`, `NativeSourceAdapters.swift`, `NativeSourceProjection.swift`, `NativeSourceRead.swift`, `WidgetCalendarStore.swift`.

### Sources WhatsApp

Location: `MissionControl/Sources/WhatsApp/`.

`WhatsAppModels.swift`, `WhatsAppService.swift`, `WhatsAppSourcePicker.swift`.

### Sources Weather

Location: `MissionControl/Sources/Weather/`.

`Weather.swift`, `WeatherService.swift`, `WeatherView.swift`, `WeatherWidgetView.swift`.

### Widgets Calendar

Location: `MissionControl/Widgets/Calendar/`.

`CalendarTimeline.swift`, `CalendarWidgetView.swift`.

### Widgets Clock

Location: `MissionControl/Widgets/Clock/`.

`DateClockWidget.swift`.

### Infrastructure Storage

Location: `MissionControl/Infrastructure/Storage/`.

`Cache.swift`, `LocalRecordRepository.swift`.

### Infrastructure Models

Location: `MissionControl/Infrastructure/Models/`.

`Models.swift`.

### Infrastructure Actions

Location: `MissionControl/Infrastructure/Actions/`.

`ActionModels.swift`, `ActionReceiptStore.swift`, `NativeActionRuntime.swift`, `NativeCreation.swift`, `NativeCreationStore.swift`, `NativeEditing.swift`, `NativeItemEditor.swift`, `NativeReconciliation.swift`, `NativeRepeatEditor.swift`.

### Infrastructure Activity

Location: `MissionControl/Infrastructure/Activity/`.

`AIActivity.swift`, `AIActivityDashboardAdapter.swift`, `AIActivityView.swift`.

### Infrastructure Usage

Location: `MissionControl/Infrastructure/Usage/`.

`AIUsage.swift`, `AIUsageStore.swift`, `AIUsageView.swift`.

### Development Previews

Location: `MissionControl/Development/Previews/`.

`DateClockPreview.swift`, `LifeNotebookPreview.swift`, `LifeProjectPreview.swift`, `MemoryInspectionPreview.swift`, `WeatherWidgetPreview.swift`, `SampleServices.swift`.

### Development Evaluations

Location: `MissionControl/Development/Evaluations/`.

`AdviceContextEvaluation.swift`, `ChatImageEvaluation.swift`, `CommitmentReportEvaluation.swift`, `EvaluationLaunchGuard.swift`, `EvaluationOutput.swift`, `ForegroundInteractionEvaluation.swift`, `LifeNotebookEvaluation.swift`, `LifeOwnershipEvaluation.swift`, `LifePlacementEvaluation.swift`, `LifeWorkspaceEvaluation.swift`, `NativeCapabilitiesEvaluation.swift`, `NativeMemoryEvaluation.swift`, `NativeReconciliationEvaluation.swift`, `PreparedApprovalEvaluation.swift`, `ReviewInboxEvaluation.swift`, `ReviewInferenceGuardEvaluation.swift`, `SourceContextEvaluation.swift`, `WorkflowEvaluation.swift`, `WorkingContextModelEvaluation.swift`.

### Development Trials

Location: `MissionControl/Development/Trials/`.

`ReviewConversationTrial.swift`, `ReviewConversationTrialView.swift`.

The former `MissionControl/Mail/` files now live together in `MissionControl/Sources/Mail/`, retaining `MailReader.js` as a bundled resource. `Resources/`, `Info.plist` and the entitlement file retain their current paths.

## Documentation mapping

- `docs/guides/`: `FEATURES.md`, `GETTING_STARTED.md`, `PRIVACY.md`, `GLOSSARY.md`.
- `docs/architecture/`: `ARCHITECTURE.md`, `HOW_IT_WORKS.md`, `MEMORY_AND_CONTEXT.md`, `PROJECT_WORKSPACE.md`.
- `docs/development/`: `DEVELOPMENT.md`, `DEVELOPMENT_WORKFLOW.md`, `LIVE_ACCEPTANCE.md`.
- `docs/planning/`: `NEXT_IMPROVEMENTS.md`, `EMAIL_ACTIONS_PLAN.md`, `HEARTBEAT_RELIABILITY_PLAN.md`, `PA_INTELLIGENCE_PLAN.md`, `RELIABILITY_IMPLEMENTATION.md`.
- `docs/history/`: `DECISIONS.md`.
- `docs/audits/`: `CODE_AUDIT_2026-10-16.md`, `PA_ARCHITECTURE_REVIEW.md`.
- `docs/archive/trials/`: `REVIEW_CONVERSATION_TRIAL.md`.

Keep `docs/README.md` as the index, existing artwork in `docs/assets/`, and archived agent instructions in `docs/archive/`. This guide and its CSV live in `docs/development/`.

### Current documents and historical evidence

The root `STATUS.md` retains the latest installed-code checkpoint and current repository validation. Earlier dated sections live in `docs/history/status/2026-10.md`. Root `VALIDATION.md` retains its current evidence index; earlier detailed records live in `docs/history/validation/2026-10.md`.

Root `PLAN.md` summarises current direction and links to `docs/history/plans/2026-10.md`, which preserves the complete original specification and dated approvals. These moves preserve historical text, evidence and approved scope. Later human direction and AGENTS still supersede older rules. Local links follow their relocated targets; historical private evidence paths remain references and no private data is copied into Git. Incoming links to extracted section anchors point to their history files.

AGENTS remains at the root. Its actionable development paths are updated, while its runtime authority contracts and dated preferences remain intact. Historical records remain historical and do not restart completed stages.

## Build and check dependencies

- `scripts/project/generate-project.py` discovers nested Swift, JavaScript and asset catalogue paths, and generates physical-folder groups with folders and files sorted by name. File references remain relative to the repository root. Target, scheme, signing and build settings are retained. Regenerate this file rather than hand-maintaining project references.
- Component runners in `scripts/checks/` use explicit relocated source and fixture paths. Dynamic compilation arrays retain the same source inputs, with the new relative directories included. Shared dependency arrays live in `scripts/lib/test-env.sh`. Alternate source checkouts must use the same repository layout.
- Nested shell runners locate the repository two directories above the script. Nested Python helpers use the corresponding resolved parent. Public `build.sh`, `check.sh` and `test.sh` retain their root locations and original invocation contract.
- `scripts/check.sh` reads `scripts/checks/check-suites.json` and compares its script inventory with the component runners plus `scripts/test.sh`. Suite IDs, tiers, effects, ordering and original contracts are preserved. New checks must be deliberately registered.
- `scripts/build.sh` calls helpers in `scripts/assets/`, `scripts/project/` and `scripts/packaging/`. The Node packaging entitlement file lives beside its packaging helper. Private per-build output roots and existing dependency preparation remain unchanged.
- `MailReader.js`, `WhatsAppBridge`, bundled Node, icons and asset catalogues retain their runtime resource names. Source folder grouping does not change bundle-relative lookup or helper checksums.
- When moving files again, update actionable paths across source, scripts, tests, manifests and developer instructions. Preserve dated historical commands as evidence and update local documentation links and section anchors.

## Migration and future changes

1. Confirm the audit agent has finished writing and produced a committed checkpoint. Inspect active chats, worktrees and Git state again. Record the chosen final base and reconcile all additions or renamed files against this inventory. Never stash or commit another writer's edits as part of cleanup.
2. Use an isolated migration worktree based on that checkpoint. Agree the migration's exclusive ownership of file paths, project generation, test runner paths and documentation links. Keep behavioural changes out of the migration.
3. Move app sources and update all references together. Regenerate the Xcode project, retaining the existing target and bundle contracts. Check file coverage before building.
4. Group Tests and script internals, repair root discovery and suite discovery, and verify all expected suites remain registered exactly once. Retain the three root command names.
5. Group documentation and update local links and developer instructions. Preserve historical logs in linked files and distinguish relocation from substantive content changes in the diff.
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
