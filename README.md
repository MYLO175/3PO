# 3PO · Mission Control

A native macOS dashboard and personal assistant built with SwiftUI and SwiftData. 3PO brings Apple Calendar, Reminders, read-only Mail and optional WhatsApp context into a customisable workspace, with a connected life notebook and assistant powered by a ChatGPT subscription.

This repository contains the app source, focused checks, build scripts and implementation notebook. It is a development project, not a packaged public release.

## What it does

- **Dashboard:** saved pages, movable and resizable widgets, independent light/dark colours, native toolbar and menu commands, and a focused view for narrow windows.
- **Calendar and Reminders:** native reading, review forms and assistant tools for supported explicit changes, with identity/revision checks, saved receipts and limited Undo.
- **Personal assistant:** an ongoing conversation with optional Life-area focus, streamed responses, pasted screenshot input, explicit queued work and a dedicated setup interview.
- **Memory and Projects:** inspectable evidence-backed beliefs and exact connections, alongside human-owned nested spaces, notes and local tasks with boards and progress. Tasks remain separate from Apple Reminders.
- **Daily workflow:** Review inbox for email assessments, source-linked proposals, questions and local review/edit/copy-only drafts; an immutable original daily brief plus the latest heartbeat/manual update.
- **Optional sources:** coarse-location weather and an encrypted, selected-chat WhatsApp linked-device reader.

Apple apps remain the source of truth. Ordinary source refresh makes no AI requests. Foreground assistant work continues without a fixed tool-count allowance, while Stop, subscription limits and bounded source reads remain. Independent automatic work has its own budgets and persisted controls.

The configurable heartbeat coordinates automatic communication review and brief preparation while the Mac/app are running. Failed runs retain completed work and schedule a fresh check at the configured interval; there is no independent morning inference timer. The pulse toolbar action **Run heartbeat** (⌘R) explicitly starts AI review. **Refresh sources only** (⌥⌘R) updates local caches without inference. Background proposals require human approval before native changes.

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
./scripts/test.sh
./scripts/test-pa-tools.sh
./scripts/test-whatsapp.sh
```

The first command is a focused baseline check, not an aggregate of every test. Other `scripts/test-*.sh` files cover individual components; inspect each script before running live developer acceptance modes. Disposable native write checks require an appropriate test account and permission to create/clean their fixtures.

[STATUS.md](STATUS.md) begins with the current checkpoint and retains dated engineering evidence below. [VALIDATION.md](VALIDATION.md) summarises current recorded checks and remaining limits before its historical log. Latest application code checkpoint: 8 October 2026, including Space/Task-only Projects, targeted lexical/typed-link memory selection, Review inbox provenance and scheduled heartbeat recovery. Focused fixtures and one recorded full production heartbeat support those bounded scenarios; they do not establish semantic recall, every source/account race or sustained sleep/wake reliability.

## Working on the repository

Read [AGENTS.md](AGENTS.md) for Codex's development rules and [Development workflow](docs/DEVELOPMENT_WORKFLOW.md) for parallel worktrees, shared-file contracts, usage and integration. Requested Memory, Projects and Appearance features can develop in isolated chats/worktrees, with one integration owner for combined checks and the installed app. Existing build/test scripts share absolute temporary paths; isolate outputs or run fixed-path checks serially.

AGENTS controls development behaviour; it does not configure the installed PA's runtime prompt. The main agent may choose bounded subagents when useful, while new independent chats require the user's request. Ask and record useful requirements/tradeoff decisions as work progresses. Product direction belongs in approved scope and roadmap/decision docs; validation files describe evidence rather than grant feature or write authority.

## Implementation notebook

- [How it works](docs/HOW_IT_WORKS.md): current architecture and behaviour.
- [Memory and context](docs/MEMORY_AND_CONTEXT.md): saved facts, usable notebook, per-reply context and inspection.
- [Next improvements](docs/NEXT_IMPROVEMENTS.md): remaining product gaps and acceptance criteria.
- [Decisions](docs/DECISIONS.md): significant implementation choices.
- [PA intelligence plan](docs/PA_INTELLIGENCE_PLAN.md): staged memory and reasoning work.
- [Project workspace](docs/PROJECT_WORKSPACE.md): durable life/project structure.
- [Notebook index](docs/README.md): which document to read or update.
- [Development workflow](docs/DEVELOPMENT_WORKFLOW.md): Codex agents, worktrees, integration and release.
- [Plan](PLAN.md) and [agent instructions](AGENTS.md): delivery scope and development boundaries.

Service boundaries separate native sources, subscription transport, assistant tools, memory, briefing and background scheduling. The repository preserves the existing development history; account data, registration identity, installed app and saved layouts are independent of GitHub hosting.
