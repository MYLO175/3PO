# Developing Mission Control in Codex

Current working agreement: 8 October 2026. The user upgraded their plan and wants to be able to develop memory, Projects and appearance concurrently. This workflow replaces the original single-main/one-Luna restriction and fixed 20% five-hour reserve. It does not enable additional runtime AI, change the app's selected model or create worker chats automatically.

## Choose the right unit of work

A chat owns a conversation and task. A worktree owns a separate checkout of the code. A subagent is a bounded worker delegated by a chat; it does not inherently provide a separate checkout. For simultaneous feature implementation, use one worktree/chat per stream. For a short investigation or review, ask the owning chat for a subagent. Routine fixes can remain single-agent.

Keep a local integration chat responsible for the shared architecture, final combined checks, readable documentation, release checkpoint and installed app. It need not keep running while workers build. Only one chat writes to any checkout at a time. Start with no more than the three requested streams; add delegation only where it supplies an independent result and fits available concurrency and usage.

## Suggested streams

These are starting boundaries, not pre-authorised features or immutable file ownership. Inspect each concrete task and agree its files before implementation.

| Stream | Typical responsibility | Shared interfaces to coordinate |
| --- | --- | --- |
| Memory | Relevant recall, evidence, corrections, memory inspection and measured quality | PAMemory, LifeNotebook, LifeCanonicalNotebook, memory/workspace associations, AssistantService and tool context |
| Projects | Space/task navigation, notes, boards, local workspace editing and progress | LifeWorkspace models/store/tools, exact notebook bindings and shared Life map views |
| Appearance | Palette, typography, spacing, widget presentation and window chrome | WorkspaceModels configuration, WorkspaceView, shared Settings and any view another stream owns |

Memory and Projects share canonical identities and associations. Agree the required data/API contract first; the integration owner or one nominated stream makes foundational changes before dependants adopt that checkpoint. Appearance changes in a Projects or Memory view need an explicit handoff or agreed non-overlapping scope. Worktree isolation prevents overwrites; it does not make conflicting designs compatible.

## Start a worker

1. Finish or checkpoint current local work. Confirm active chats, a clean intended base and the latest STATUS summary. All workers should start from the same agreed commit unless a dependency explicitly requires a newer one.
2. Open a new Mission Control chat in Codex, select Worktree beneath the composer, and choose the intended starting branch. Ask the worker to report its actual checkout and base commit. Do not assume every worktree creation mechanism copies local uncommitted files.
3. Name the chat after its stream and concrete deliverable. Use a `codex/` branch when a named branch is needed; a managed detached worktree is also valid.
4. Give the worker its user-visible outcome, acceptance criteria, allowed files, shared contracts, dependencies and verification scope. Have it stop at a reviewable checkpoint rather than install its candidate.
5. A worker may update the docs for its own behaviour. Coordinate shared PLAN/STATUS/DECISIONS edits; the integration owner reconciles their final descriptions and maintains the top STATUS summary.

Example worker brief:

> Implement the agreed memory-relevance improvement in this worktree. Read AGENTS, the current STATUS summary and MEMORY_AND_CONTEXT first. Report your base commit, proposed files and any required workspace/API change before editing shared contracts. Preserve account/source/current-belief boundaries and all stored IDs. Use focused fictional checks and isolated output paths. Commit the result and report what passed and what remains unverified. Leave installation and personal-data acceptance to the integration chat.

An independently opened worker chat stays under the user's control. The integration agent only creates or messages other chats when the user explicitly requests that coordination. The user authorises the main agent to choose bounded subagents when useful for an assigned change, without a separate question each time. Give each subagent a concrete independent task and return evidence to the owning chat; no nested delegation. Read-only reviewers can share code, but concurrent writers require separate worktrees and agreed ownership.

## Builds and checks have shared resources too

The existing `scripts/build.sh` uses `/tmp/missioncontrol-derived`, and several test runners share `/tmp/missioncontrol-test-modules` and fixed executable paths. Worktrees do not isolate those absolute paths. Give each concurrent build a distinct derived-data directory and log path. Run existing fixed-path checks serially unless their output paths have been deliberately made configurable or an equivalent isolated command is used. Coordinate runtime/icon/project generation and shared dependency caches as applicable.

Use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; never change the global developer selection. Verify significant integration changes with the actual signed Xcode build. Documentation-only changes need diff, consistency and link checks, not an app rebuild.

Do not run normal app candidates simultaneously against personal storage. Worktrees still share this Mac's Keychain, Apple accounts, permissions, app preferences, installed application and external data. Use existing DEBUG fictional/in-memory previews that return before source startup, and verify isolation for the selected preview. Do not change the stable bundle identity to manufacture isolation, or copy auth/caches/private data into a worktree or Git.

## Integrate and release

Each worker hands back its commit, changed files, validation evidence, limitations and dependencies. The integration chat reads the diff and integrates compatible commits in dependency order, resolves conflicts semantically and runs relevant combined checks. Handoff moves a chat/checkout; combining independent features still requires an explicit merge or cherry-pick and review.

One integration owner manages the signed candidate, idle/clean app quit, recoverable backup, signature/readback checks, installation at the existing path and live UI/native acceptance. Never let workers race to replace the installed app or mutate personal Apple records. Preserve com.mylomichael.missioncontrol and the current registration/storage/Keychain identities. A worker build is not installation; installation is not launch or live acceptance.

Update STATUS's top summary and append detailed evidence. Update relevant readable explanations/roadmap/decisions for meaningful changes. Save a validated commit. Archive a worker worktree only after its needed work is integrated or recoverably retained.

## Usage and handoff

Check reported account usage at start and major milestones. The user has more allowance after a plan upgrade; the old fixed 20% five-hour reserve no longer governs development. Do not infer an unreported window or treat the upgrade as unlimited usage. Continue authorised useful work while allowance is available, avoid unnecessary duplicate exploration and preserve a resumable checkpoint as limits approach. No credits, resets, paid API fallback or account/configuration changes without a new explicit human request.

Choose the main chat's model/reasoning in the UI. GPT-6.1 Sol Medium Standard remains the user's recorded preference, not a setting imposed by text. Workers use suitable available models under the user's direction; the old mandatory Luna High choice is retired. A Codex worker's model choice must not alter the PA application's inference model.

## Questions and documentation entry points

Ask about missing requirements, priorities and consequential implementation choices as work progresses. Keep questions concrete and continue useful independent work while awaiting answers. Record answered Codex workflow preferences in AGENTS; record product decisions in PLAN/DECISIONS/roadmap. Do not interpret an unanswered option as consent. A request to update GitHub authorises this publication; future release/install defaults should follow the user's answered preference and explicit task scope.

AGENTS is for Codex developing this repository. It does not change how the installed 3PO assistant reasons, retrieves memory or uses tools: that behaviour is implemented in the app's prompts, schemas and services and requires code/validation changes.

- AGENTS.md: current working rules and invariant boundaries.
- STATUS.md: current summary first, then preserved dated engineering evidence.
- VALIDATION.md: concise current evidence/limitations, with earlier records labelled as history.
- README.md: project introduction, current features, build/run/privacy guidance and links.
- PLAN.md and docs/NEXT_IMPROVEMENTS.md: scope, open product work and success criteria; historical entries are not current completion claims.
- docs/HOW_IT_WORKS.md and docs/MEMORY_AND_CONTEXT.md: current implementation and memory behaviour.
- docs/DECISIONS.md: significant design choices.
- docs/archive/AGENTS-2026-10-08-before-workflow-refresh.md: exact prior instruction history. Later dated corrections supersede earlier entries; do not reapply retired gates, topic UX or stage-start requirements.
