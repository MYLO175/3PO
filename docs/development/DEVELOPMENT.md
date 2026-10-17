# Developer guide

**Start from the current checkpoint, keep ownership narrow, and verify the effects your change actually has.** This page maps the code and tools. [AGENTS](../../AGENTS.md) and [Development workflow](DEVELOPMENT_WORKFLOW.md) govern development and concurrent writers.

[Documentation](../README.md) · [Architecture](../architecture/ARCHITECTURE.md) · [Getting started](../guides/GETTING_STARTED.md)

## Before changing anything

Read the top of [Status](../../STATUS.md), then inspect Git status and active worktrees/chats. Use an isolated worktree when another writer owns the primary checkout. Agree deliverable, permitted files, base commit and shared contracts. Worktrees share app storage, Keychain, Apple accounts and the installed app, so only the integration owner performs personal-data release/acceptance.

Documentation-only work needs link, consistency and presentation checks; it does not require an app build or new model/native requests.

## Find your way around the code

| Area | Entry points | Follow next |
| --- | --- | --- |
| App and service composition | [MissionControlApp](../../MissionControl/App/MissionControlApp.swift), [ApplicationServices](../../MissionControl/App/ApplicationServices.swift) | [DashboardModel](../../MissionControl/Dashboard/DashboardModel.swift) and lifecycle |
| Dashboard and appearance | [WorkspaceView](../../MissionControl/Dashboard/WorkspaceView.swift), [WorkspaceModels](../../MissionControl/Dashboard/WorkspaceModels.swift) | [WorkspaceStore](../../MissionControl/Dashboard/WorkspaceStore.swift), [WorkspaceColors](../../MissionControl/Dashboard/WorkspaceColors.swift), [WorkspaceGeometry](../../MissionControl/Dashboard/WorkspaceGeometry.swift) |
| PA conversation | [AssistantService](../../MissionControl/Assistant/Conversation/AssistantService.swift), [PAConversationEngine](../../MissionControl/Assistant/Conversation/PAConversationEngine.swift) | [AssistantRuntime](../../MissionControl/Assistant/Conversation/AssistantRuntime.swift), [AssistantDashboardAdapter](../../MissionControl/Assistant/Conversation/AssistantDashboardAdapter.swift), [AssistantView](../../MissionControl/Assistant/Conversation/AssistantView.swift) |
| Model boundary and transport | [PAInferenceConnection](../../MissionControl/Assistant/Provider/PAInferenceConnection.swift) | [ChatGPTConnection](../../MissionControl/Assistant/Provider/ChatGPTConnection.swift), [ChatGPTStream](../../MissionControl/Assistant/Provider/ChatGPTStream.swift), [ChatGPTOAuth](../../MissionControl/Assistant/Provider/ChatGPTOAuth.swift) |
| Tool schema/authority/actions | [PAToolProtocol](../../MissionControl/Assistant/Tools/PAToolProtocol.swift), [PAToolSession](../../MissionControl/Assistant/Tools/PAToolSession.swift) | [PAToolAuthorization](../../MissionControl/Assistant/Tools/PAToolAuthorization.swift), [AssistantActions](../../MissionControl/Assistant/Conversation/AssistantActions.swift), [NativeActionRuntime](../../MissionControl/Infrastructure/Actions/NativeActionRuntime.swift) |
| Native Calendar/Reminders | [EventKitService](../../MissionControl/Sources/Native/EventKitService.swift), [NativeSourceRead](../../MissionControl/Sources/Native/NativeSourceRead.swift) | [EventKitEditing](../../MissionControl/Sources/Native/EventKitEditing.swift), [EventKitCreation](../../MissionControl/Sources/Native/EventKitCreation.swift) |
| Mail collection and lookup | [MailService](../../MissionControl/Sources/Mail/MailService.swift), [MailReader](../../MissionControl/Sources/Mail/MailReader.js) | [MailLookup](../../MissionControl/Sources/Mail/MailLookup.swift), [EmailSummaryService](../../MissionControl/Sources/Email/EmailSummaryService.swift) |
| WhatsApp | [WhatsAppService](../../MissionControl/Sources/WhatsApp/WhatsAppService.swift), [WhatsAppModels](../../MissionControl/Sources/WhatsApp/WhatsAppModels.swift) | [Reader helper](../../WhatsAppBridge/reader.mjs), [WhatsAppSourcePicker](../../MissionControl/Sources/WhatsApp/WhatsAppSourcePicker.swift) |
| Review and feedback | [PATasksView](../../MissionControl/Review/Inbox/PATasksView.swift), [ProactiveService](../../MissionControl/Review/Inbox/ProactiveService.swift) | [Proactive](../../MissionControl/Review/Inbox/Proactive.swift), [ReviewFeedbackService](../../MissionControl/Review/Feedback/ReviewFeedbackService.swift), [ReviewFeedbackJobs](../../MissionControl/Review/Feedback/ReviewFeedbackJobs.swift) |
| Review execution and Activity | [ReviewWork](../../MissionControl/Review/Actions/ReviewWork.swift), [Review conversation](../../MissionControl/Review/Actions/ProductionReviewConversationView.swift) | [Execution adapter](../../MissionControl/Review/Actions/ReviewWorkDashboardAdapter.swift), [Plan adapter](../../MissionControl/Review/Actions/ReviewPlanDashboardAdapter.swift), [AIActivity](../../MissionControl/Infrastructure/Activity/AIActivity.swift) |
| Brief and heartbeat | [BriefingService](../../MissionControl/Background/Briefing/BriefingService.swift), [HeartbeatService](../../MissionControl/Background/Heartbeat/HeartbeatService.swift) | [HeartbeatRuntime](../../MissionControl/Background/Heartbeat/HeartbeatRuntime.swift), [HeartbeatDashboardAdapter](../../MissionControl/Background/Heartbeat/HeartbeatDashboardAdapter.swift), [HeartbeatPower](../../MissionControl/Background/Heartbeat/HeartbeatPower.swift) |
| Facts, retrieval and inspection | [PAMemory](../../MissionControl/Memory/Records/PAMemory.swift), [PAMemoryStore](../../MissionControl/Memory/Records/PAMemoryStore.swift) | [LifeNotebook](../../MissionControl/Memory/Notebook/LifeNotebook.swift), [LifeCanonicalNotebook](../../MissionControl/Memory/Notebook/LifeCanonicalNotebook.swift), [MemoryInspection](../../MissionControl/Memory/Records/MemoryInspection.swift), [PAMemoryView](../../MissionControl/Memory/Views/PAMemoryView.swift) |
| Learning | [LearningRuntime](../../MissionControl/Memory/Learning/LearningRuntime.swift), [BackgroundLearningCoordinator](../../MissionControl/Memory/Learning/BackgroundLearningCoordinator.swift) | [LearningBudget](../../MissionControl/Memory/Learning/LearningBudget.swift), conversation/source/native/organisation services |
| Projects | [LifeWorkspaceStore](../../MissionControl/Projects/LifeWorkspaceStore.swift), [LifeWorkspaceTools](../../MissionControl/Projects/LifeWorkspaceTools.swift) | [LifeWorkspaceContext](../../MissionControl/Projects/LifeWorkspaceContext.swift), [LifeWorkspaceToolSchema](../../MissionControl/Projects/LifeWorkspaceToolSchema.swift) |
| Persistence | [LocalRecordRepository](../../MissionControl/Infrastructure/Storage/LocalRecordRepository.swift), [ConversationRepository](../../MissionControl/Assistant/Conversation/ConversationRepository.swift) | [Cache](../../MissionControl/Infrastructure/Storage/Cache.swift), [ChatDraftStore](../../MissionControl/Assistant/Conversation/ChatDraftStore.swift), [ActionReceiptStore](../../MissionControl/Infrastructure/Actions/ActionReceiptStore.swift), [NativeCreationStore](../../MissionControl/Infrastructure/Actions/NativeCreationStore.swift) |
| Weather | [WeatherService](../../MissionControl/Sources/Weather/WeatherService.swift), [Weather](../../MissionControl/Sources/Weather/Weather.swift) | [WeatherWidgetView](../../MissionControl/Sources/Weather/WeatherWidgetView.swift) |

Many detailed contracts live beside their pure rules and focused evaluation fixtures. Search the named component before editing a shared model; the [architecture guide](../architecture/ARCHITECTURE.md) explains the boundaries behind this map.

## Build and generated files

```sh
MISSIONCONTROL_BUILD_ROOT=/private/tmp/3po-my-change ./scripts/build.sh
```

[build.sh](../../scripts/build.sh) uses a unique temporary root by default. Supported overrides are `MISSIONCONTROL_BUILD_ROOT`, `MISSIONCONTROL_DERIVED_DATA` and `MISSIONCONTROL_BUILD_LOG`. The example places the app under `derived-data/Build/Products/Debug/3PO.app` and its log at `build.log`. Use distinct roots for concurrent builds.

The script sets `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, prepares helper dependencies/runtime, regenerates the icon and `MissionControl.xcodeproj`, then calls Xcode. Generated project/icon/runtime files still have one checkout writer. [generate-project.py](../../scripts/project/generate-project.py) contains signing settings; [package-whatsapp-runtime.py](../../scripts/packaging/package-whatsapp-runtime.py) packages the checksum-pinned helper runtime. The installed helper does not need the build machine's Node installation.

Open the generated Xcode project for source editing. A compile does not install, launch or establish UI/model acceptance.

## Choose the right checks

```sh
./scripts/check.sh --list
./scripts/check.sh --suite memory-quality --suite action-receipts
./scripts/check.sh
```

[check.sh](../../scripts/check.sh) reads [the suite manifest](../../scripts/checks/check-suites.json), runs selected suites serially in a unique private directory, and reports per-suite logs, timeouts and results. The default is the complete audited source-free inventory; direct `test-*.sh` scripts remain available. The historical checkpoint's suite count is evidence for that revision, not a permanently fixed inventory.

| Tier | Effects | What it establishes |
| --- | --- | --- |
| `source-free` (default) | Fictional ports and private temporary/in-memory storage; no personal sources, app launch, native writes, model calls or downloads | Deterministic rules and audited service contracts |
| `performance` | Separate optional fictional component/performance fixtures | Bounded timings, not native end-user latency |
| `app-memory` | Exact signed DEBUG candidate; audited early modes with disposable app storage and zero model requests | Actual compiled app consumers and storage contracts |
| `native` | Disposable UUID Calendar fixtures under existing permissions, with verified cleanup | Supported real EventKit behaviour on the candidate |
| `model` | Fictional input through the configured subscription; consumes requests | Narrow actual-model quality for the named cases |

Candidate example, for the integration owner:

```sh
./scripts/check.sh --tier app-memory \
  --candidate-binary /private/tmp/3po-my-change/derived-data/Build/Products/Debug/3PO.app/Contents/MacOS/3PO
```

Use native/model tiers only for their documented effects and authorised scope. The runner checks signature, stable bundle identity, signed protocol declaration, DEBUG handshake, supported exact mode, timeout and fresh complete report before accepting a result. A legacy diagnostic flag is not inherently safe; an unsupported/Release candidate refuses before normal startup. Never replay an uncertain native write after a timeout.

## Changes that cross a boundary

- **Memory and Projects:** preserve canonical identities, fact evidence/version lineage, exact associations and tombstones. Organisation remains metadata; models cannot invent human projects.
- **Source context:** apply account/purpose/consent/version checks before recall or cached preparation. A missing source is unknown rather than completion.
- **Native writes:** prepared creation approval validates human-approved concrete payload, account/source access, destination and duplicate/uncertain receipts, without broad evidence reconstruction. Existing-item edits/removals retain exact issued target, scope and current fields/full revision. Persist pending receipts and verify readback.
- **Background work:** capture run ownership before yielding; claim before inference and revalidate before save. Review automatically runs accepted never-started jobs when idle; the general delegated queue keeps explicit continuation. Explicit feedback uses next-heartbeat/Process now scheduling and exact email/source-choice ownership. Preserve completed receipts, reject late cancelled output and never replay attempted/uncertain work.
- **Activity:** observe stable work metadata, not streaming prose. Display-only progress must not fetch native receipts; final completion remains receipt-backed. Preserve the single local success-expiry wakeup.
- **Appearance:** retain interaction, navigation, draft, geometry and toolbar identities; coordinate views owned by other streams.
- **Storage:** edit only owned keys atomically; preserve legacy/unknown supported data and refuse corrupt-state overwrite.

## Document and publish a checkpoint

Keep behaviour in Features and the relevant detailed guide, architecture ownership in Architecture, choices in Decisions, scope in Plan and gaps in Next improvements. Record actual validation/install evidence separately in Status and Validation, with the current summary first.

Review the exact staged diff and outgoing history before publication. Stage only owned files; never include another chat's unfinished code, credentials, personal source text, caches or diagnostic images. Verify remote commit identity after a normal push. Repository publication is separate from installation and does not change GitHub visibility.

Only the integration owner handles signed release, complete private backup, replacement/readback and real-use acceptance. [Development workflow](DEVELOPMENT_WORKFLOW.md#integrate-and-release) covers the full process.
