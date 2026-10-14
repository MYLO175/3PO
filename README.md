# 3PO · Mission Control

A native macOS dashboard and personal assistant built with SwiftUI and SwiftData. 3PO brings Apple Calendar, Reminders, read-only Mail and optional WhatsApp context into a customisable workspace, with a connected life notebook and assistant powered by a ChatGPT subscription.

This repository contains the app source, focused checks, build scripts and implementation notebook. It is a development project, not a packaged public release.

## What it does

- **Dashboard:** saved pages, movable and resizable widgets, independent light/dark colours, native toolbar and menu commands, and a focused view for narrow windows.
- **Calendar and Reminders:** native reading, review forms and assistant tools for supported explicit changes, with identity/revision checks, saved receipts and limited Undo.
- **Personal assistant:** an ongoing conversation with optional Life-area focus, streamed responses, pasted screenshot input, explicit queued work and a dedicated setup interview.
- **Memory and Projects:** inspectable evidence-backed beliefs and exact connections, alongside human-owned nested spaces, notes and local tasks with boards and progress. Tasks remain separate from Apple Reminders.
- **Daily workflow:** Review inbox for email assessments, source-linked proposals, questions and local review/edit/copy-only drafts; an immutable original daily brief plus the latest heartbeat/manual update.
- **Review actions and Activity:** saved source conversations with editable action checkboxes, direct Done approval without AI, automatic idle execution of accepted Review jobs, and five recent task outcomes. Verified success appears in green for six seconds; questions and failures retain attention.
- **Optional sources:** coarse-location weather and an encrypted, selected-chat WhatsApp linked-device reader.

Apple apps remain the source of truth. Ordinary source refresh makes no AI requests. Foreground assistant work continues without a fixed tool-count allowance, while Stop, subscription limits and bounded source reads remain. Independent automatic work has its own budgets and persisted controls.

The configurable heartbeat analyses independently collected Mail and enabled context, then prepares Review items and the brief while the Mac/app are running. Mail polls separately every five minutes; heartbeat does not force another Mail refresh. Failed runs retain completed work and schedule a fresh check at the configured interval; there is no independent morning inference timer. The pulse toolbar action **Run heartbeat** (⌘R) explicitly starts AI review. **Refresh sources only** (⌥⌘R) updates local caches without inference. Background proposals require human approval before native changes.

## Privacy and permissions

Calendar and Reminders access, Apple Mail Automation, location and optional dictation permissions belong to the app. Optional AI source controls determine which personal context may be transmitted to OpenAI; check those controls before enabling them. Imported content and saved memory cannot authorise Apple changes: supported writes require understood current human intent and fresh native identities/readback.

Mail and WhatsApp are read-only. Reply drafts stay local; there is no email sending, WhatsApp sending, arbitrary-script tool or separately billed API-key fallback.

SwiftData records and caches live under `~/Library/Application Support/Mission Control`. ChatGPT credentials and encryption keys use macOS Keychain; WhatsApp sessions, messages and source selections are encrypted locally. These records, credentials, build output and personal screenshots are excluded from Git. Disabling a source does not erase historical saved conversations.

The optional WhatsApp reader uses the unofficial Baileys linked-device library. A human must scan its QR code on their phone. Access can break or face WhatsApp restrictions; the bounded local cache does not promise complete history. No OpenClaw installation or Business API billing is required.

## Build and run

Requires **macOS 26+**, Xcode installed at `/Applications/Xcode.app`, Python 3, npm and a development Node installation for build tooling. The build bundles a checksum-pinned Node runtime for the WhatsApp helper, so the installed app does not require a separate Node installation. Initial dependency/runtime downloads need internet access.

```sh
./scripts/build.sh
open /tmp/missioncontrol-derived/Build/Products/Debug/3PO.app
```

The build uses `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` without changing global developer settings. Derived output and runtime download caches use `/tmp`. It regenerates `MissionControl.xcodeproj` and the app icon.

The project currently specifies the original developer's Apple Development signing team. To build on another Mac, configure your own signing identity/team in `scripts/generate-project.py`, then regenerate/build. Preserve the stable bundle identifier `com.mylomichael.missioncontrol` when updating an existing installation. Open `MissionControl.xcodeproj` for source editing after generation.

For a dashboard using fictional sample sources without Apple reads or writes:

```sh
open /tmp/missioncontrol-derived/Build/Products/Debug/3PO.app --args --sample
```

Optional assistant inference uses Settings → Continue with ChatGPT and the documented subscription registration flow. Eligibility, model availability and plan allowance depend on the connected account. No inference is implied by a successful local build.

## Checks and validation

```sh
./scripts/check.sh
./scripts/check.sh --suite memory-quality --suite action-receipts
./scripts/check.sh --list
```

The default command runs the complete source-free inventory serially, with unique private artifacts, per-suite logs, timeouts and a failure report. Direct `scripts/test-*.sh` commands remain available. The WhatsApp check uses prepared bundled runtime/dependencies and makes no connection or download. Performance, signed in-memory app, native fixture and configured-model checks are separate tiers; inspect the listed effects before running them.

Integration tiers require the exact signed DEBUG candidate executable: `./scripts/check.sh --tier app-memory --candidate-binary /absolute/path/3PO.app/Contents/MacOS/3PO`. Use `--tier native` or `--tier model` only for their documented effects. The signed protocol declaration and early handshake prevent older/Release binaries from entering normal startup during a runner probe. Native runs must report verified fixture cleanup; a timeout is not permission to replay an uncertain operation.

[STATUS.md](STATUS.md) begins with the current checkpoint and retains dated engineering evidence below. [VALIDATION.md](VALIDATION.md) summarises recorded checks and remaining limits. The latest recorded installed checkpoint is the 14 October feedback repair (`9ca10c2`), following unified Review, concise Activity and streaming improvements. Signed checks and one explicit feedback recovery are recorded; several days of reliable use remain unverified. [Live acceptance](docs/LIVE_ACCEPTANCE.md) tracks real-use and power-cycle evidence. Focused checks do not establish broad semantic recall, every source/account race or sustained sleep/wake reliability; installation and candidate evidence remain distinct.

## Working on the repository

Read [AGENTS.md](AGENTS.md) for Codex's development rules and [Development workflow](docs/DEVELOPMENT_WORKFLOW.md) for parallel worktrees, shared-file contracts, usage and integration. Requested Memory, Projects and Appearance features can develop in isolated chats/worktrees, with one integration owner for combined checks and the installed app. Component checks isolate temporary outputs; concurrent builds also need separate derived-data/log paths and coordinated generated project/runtime/icon files.

AGENTS controls development behaviour; it does not configure the installed PA's runtime prompt. The main agent may choose bounded subagents when useful, while new independent chats require the user's request. Ask and record useful requirements/tradeoff decisions as work progresses. Product direction belongs in approved scope and roadmap/decision docs; validation files describe evidence rather than grant feature or write authority.

## Implementation notebook

- [How it works](docs/HOW_IT_WORKS.md): current behaviour.
- [Architecture](docs/ARCHITECTURE.md): component ownership, request flow, storage and recovery.
- [Reliability implementation](docs/RELIABILITY_IMPLEMENTATION.md): approved scope and completion evidence.
- [Memory and context](docs/MEMORY_AND_CONTEXT.md): saved facts, usable notebook, per-reply context and inspection.
- [Next improvements](docs/NEXT_IMPROVEMENTS.md): remaining product gaps and acceptance criteria.
- [Decisions](docs/DECISIONS.md): significant implementation choices.
- [PA intelligence plan](docs/PA_INTELLIGENCE_PLAN.md): staged memory and reasoning work.
- [Project workspace](docs/PROJECT_WORKSPACE.md): durable life/project structure.
- [Notebook index](docs/README.md): which document to read or update.
- [Development workflow](docs/DEVELOPMENT_WORKFLOW.md): Codex agents, worktrees, integration and release.
- [Plan](PLAN.md) and [agent instructions](AGENTS.md): delivery scope and development boundaries.

Service boundaries separate native sources, subscription transport, assistant tools, memory, briefing and background scheduling. The repository preserves the existing development history; account data, registration identity, installed app and saved layouts are independent of GitHub hosting.
