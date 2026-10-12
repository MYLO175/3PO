# Developer guide

**Start from the current checkpoint, keep ownership narrow, and verify the effects your change actually has.** This page maps the code and tools. [AGENTS](../AGENTS.md) and [Development workflow](DEVELOPMENT_WORKFLOW.md) govern development and concurrent writers.

[Documentation](README.md) · [Architecture](ARCHITECTURE.md) · [Getting started](GETTING_STARTED.md)

## Before changing anything

Read the top of [Status](../STATUS.md), then inspect Git status and active worktrees/chats. Use an isolated worktree when another writer owns the primary checkout. Agree deliverable, permitted files, base commit and shared contracts. Worktrees share app storage, Keychain, Apple accounts and the installed app, so only the integration owner performs personal-data release/acceptance.

Documentation-only work needs link, consistency and presentation checks; it does not require an app build or new model/native requests.

## Find your way around the code

| Area | Entry points | Follow next |
| --- | --- | --- |
| App and service composition | [MissionControlApp](../MissionControl/MissionControlApp.swift), [ApplicationServices](../MissionControl/ApplicationServices.swift) | [DashboardModel](../MissionControl/DashboardModel.swift) and lifecycle |
| Dashboard and appearance | [WorkspaceView](../MissionControl/WorkspaceView.swift), [WorkspaceModels](../MissionControl/WorkspaceModels.swift) | [WorkspaceStore](../MissionControl/WorkspaceStore.swift), [WorkspaceColors](../MissionControl/WorkspaceColors.swift), [WorkspaceGeometry](../MissionControl/WorkspaceGeometry.swift) |
| PA conversation | [AssistantService](../MissionControl/AssistantService.swift), [PAConversationEngine](../MissionControl/PAConversationEngine.swift) | [AssistantRuntime](../MissionControl/AssistantRuntime.swift), [AssistantDashboardAdapter](../MissionControl/AssistantDashboardAdapter.swift), [AssistantView](../MissionControl/AssistantView.swift) |
| Model boundary and transport | [PAInferenceConnection](../MissionControl/PAInferenceConnection.swift) | [ChatGPTConnection](../MissionControl/ChatGPTConnection.swift), [ChatGPTStream](../MissionControl/ChatGPTStream.swift), [ChatGPTOAuth](../MissionControl/ChatGPTOAuth.swift) |
| Tool schema/authority/actions | [PAToolProtocol](../MissionControl/PAToolProtocol.swift), [PAToolSession](../MissionControl/PAToolSession.swift) | [PAToolAuthorization](../MissionControl/PAToolAuthorization.swift), [AssistantActions](../MissionControl/AssistantActions.swift), [NativeActionRuntime](../MissionControl/NativeActionRuntime.swift) |
| Native Calendar/Reminders | [EventKitService](../MissionControl/EventKitService.swift), [NativeSourceRead](../MissionControl/NativeSourceRead.swift) | [EventKitEditing](../MissionControl/EventKitEditing.swift), [EventKitCreation](../MissionControl/EventKitCreation.swift) |
| Mail collection and lookup | [MailService](../MissionControl/Mail/MailService.swift), [MailReader](../MissionControl/Mail/MailReader.js) | [MailLookup](../MissionControl/MailLookup.swift), [EmailSummaryService](../MissionControl/EmailSummaryService.swift) |
| WhatsApp | [WhatsAppService](../MissionControl/WhatsAppService.swift), [WhatsAppModels](../MissionControl/WhatsAppModels.swift) | [Reader helper](../WhatsAppBridge/reader.mjs), [WhatsAppSourcePicker](../MissionControl/WhatsAppSourcePicker.swift) |
| Review and feedback | [PATasksView](../MissionControl/PATasksView.swift), [ProactiveService](../MissionControl/ProactiveService.swift) | [Proactive](../MissionControl/Proactive.swift), [ReviewFeedbackService](../MissionControl/ReviewFeedbackService.swift), [ReviewFeedbackJobs](../MissionControl/ReviewFeedbackJobs.swift) |
| Brief and heartbeat | [BriefingService](../MissionControl/BriefingService.swift), [HeartbeatService](../MissionControl/HeartbeatService.swift) | [HeartbeatRuntime](../MissionControl/HeartbeatRuntime.swift), [HeartbeatDashboardAdapter](../MissionControl/HeartbeatDashboardAdapter.swift), [HeartbeatPower](../MissionControl/HeartbeatPower.swift) |
| Facts, retrieval and inspection | [PAMemory](../MissionControl/PAMemory.swift), [PAMemoryStore](../MissionControl/PAMemoryStore.swift) | [LifeNotebook](../MissionControl/LifeNotebook.swift), [LifeCanonicalNotebook](../MissionControl/LifeCanonicalNotebook.swift), [MemoryInspection](../MissionControl/MemoryInspection.swift), [PAMemoryView](../MissionControl/PAMemoryView.swift) |
| Learning | [LearningRuntime](../MissionControl/LearningRuntime.swift), [BackgroundLearningCoordinator](../MissionControl/BackgroundLearningCoordinator.swift) | [LearningBudget](../MissionControl/LearningBudget.swift), conversation/source/native/organisation services |
| Projects | [LifeWorkspaceStore](../MissionControl/LifeWorkspaceStore.swift), [LifeWorkspaceTools](../MissionControl/LifeWorkspaceTools.swift) | [LifeWorkspaceContext](../MissionControl/LifeWorkspaceContext.swift), [LifeWorkspaceToolSchema](../MissionControl/LifeWorkspaceToolSchema.swift) |
| Persistence | [LocalRecordRepository](../MissionControl/LocalRecordRepository.swift), [ConversationRepository](../MissionControl/ConversationRepository.swift) | [Cache](../MissionControl/Cache.swift), [ChatDraftStore](../MissionControl/ChatDraftStore.swift), [ActionReceiptStore](../MissionControl/ActionReceiptStore.swift), [NativeCreationStore](../MissionControl/NativeCreationStore.swift) |
| Weather | [WeatherService](../MissionControl/WeatherService.swift), [Weather](../MissionControl/Weather.swift) | [WeatherWidgetView](../MissionControl/WeatherWidgetView.swift) |

Many detailed contracts live beside their pure rules and focused evaluation fixtures. Search the named component before editing a shared model; the [architecture guide](ARCHITECTURE.md) explains the boundaries behind this map.

## Build and generated files

```sh
MISSIONCONTROL_BUILD_ROOT=/private/tmp/3po-my-change ./scripts/build.sh
```

[build.sh](../scripts/build.sh) uses a unique temporary root by default. Supported overrides are `MISSIONCONTROL_BUILD_ROOT`, `MISSIONCONTROL_DERIVED_DATA` and `MISSIONCONTROL_BUILD_LOG`. The example places the app under `derived-data/Build/Products/Debug/3PO.app` and its log at `build.log`. Use distinct roots for concurrent builds.

The script sets `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, prepares helper dependencies/runtime, regenerates the icon and `MissionControl.xcodeproj`, then calls Xcode. Generated project/icon/runtime files still have one checkout writer. [generate-project.py](../scripts/generate-project.py) contains signing settings; [package-whatsapp-runtime.py](../scripts/package-whatsapp-runtime.py) packages the checksum-pinned helper runtime. The installed helper does not need the build machine's Node installation.

Open the generated Xcode project for source editing. A compile does not install, launch or establish UI/model acceptance.

## Choose the right checks

```sh
./scripts/check.sh --list
./scripts/check.sh --suite memory-quality --suite action-receipts
./scripts/check.sh
```

[check.sh](../scripts/check.sh) reads [the suite manifest](../scripts/check-suites.json), runs selected suites serially in a unique private directory, and reports per-suite logs, timeouts and results. The default is the complete audited source-free inventory; direct `test-*.sh` scripts remain available. The historical checkpoint's suite count is evidence for that revision, not a permanently fixed inventory.

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
- **Native writes:** capture current human intent, exact issued target, scope and full revision; persist pending receipt before save and verify readback.
- **Background work:** capture run ownership before yielding; claim before inference and revalidate before save. Preserve completed receipts and reject late cancelled output.
- **Appearance:** retain interaction, navigation, draft, geometry and toolbar identities; coordinate views owned by other streams.
- **Storage:** edit only owned keys atomically; preserve legacy/unknown supported data and refuse corrupt-state overwrite.

## Document and publish a checkpoint

Keep behaviour in Features and the relevant detailed guide, architecture ownership in Architecture, choices in Decisions, scope in Plan and gaps in Next improvements. Record actual validation/install evidence separately in Status and Validation, with the current summary first.

Review the exact staged diff and outgoing history before publication. Stage only owned files; never include another chat's unfinished code, credentials, personal source text, caches or diagnostic images. Verify remote commit identity after a normal push. Repository publication is separate from installation and does not change GitHub visibility.

Only the integration owner handles signed release, complete private backup, replacement/readback and real-use acceptance. [Development workflow](DEVELOPMENT_WORKFLOW.md#integrate-and-release) covers the full process.
