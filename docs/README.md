# The 3PO documentation

**Understand the product first, then follow the details you need.** These pages explain the software. Personal emails, chats, memories and credentials live outside the repository.

[Repository home](../README.md) · [Features](guides/FEATURES.md) · [Architecture](architecture/ARCHITECTURE.md) · [Getting started](guides/GETTING_STARTED.md)

## A short reading path

1. **[Features](guides/FEATURES.md)** gives you a tour of the dashboard, PA, Review, Projects and background work, with practical examples.
2. **[Architecture](architecture/ARCHITECTURE.md)** explains who owns each part and follows real information through the system.
3. **[Memory and context](architecture/MEMORY_AND_CONTEXT.md)** explains what is saved, what is usable and what is selected for a particular question.
4. **[Project workspace](architecture/PROJECT_WORKSPACE.md)** explains the shared spaces/tasks, their views and their connection to memory.

For setup, use [Getting started](guides/GETTING_STARTED.md). For code and checks, use [Developer guide](development/DEVELOPMENT.md). Unfamiliar terms are in the [glossary](guides/GLOSSARY.md).

## Find the right page

| Question | Page | Role |
| --- | --- | --- |
| What can I do in the app? | [Features](guides/FEATURES.md) | Current product tour |
| How does a message become an answer or change? | [Architecture](architecture/ARCHITECTURE.md) | Components, flows and ownership |
| How do I build and connect sources? | [Getting started](guides/GETTING_STARTED.md) | Practical setup and troubleshooting |
| Where do my data go? | [Privacy](guides/PRIVACY.md) | Source access, transmission and local storage |
| How do recall and corrections work? | [Memory and context](architecture/MEMORY_AND_CONTEXT.md) | Detailed memory contract |
| How do folders, tasks and project links work? | [Project workspace](architecture/PROJECT_WORKSPACE.md) | Detailed workspace contract |
| Where is a specific interaction documented? | [How it works](architecture/HOW_IT_WORKS.md) | Detailed behaviour reference with section links |
| Where should I start in the code? | [Developer guide](development/DEVELOPMENT.md) | Source map, build and verification tiers |
| Why was a design chosen? | [Decisions](history/DECISIONS.md) | Dated decisions; later choices supersede earlier ones |
| What is still missing? | [Next improvements](planning/NEXT_IMPROVEMENTS.md) | Product gaps and success criteria |
| What was actually tested or installed? | [Validation](../VALIDATION.md) | Current evidence index, then historical evidence |
| What still needs ordinary use? | [Live acceptance](development/LIVE_ACCEPTANCE.md) | Latest installed binary and remaining real-use gates |
| What changed and when? | [Status](../STATUS.md) | Current summary first; detailed engineering log below |
| What work is approved? | [Plan](../PLAN.md) · [Reliability checklist](planning/RELIABILITY_IMPLEMENTATION.md) | Approved scope and acceptance gates |
| How should development be coordinated? | [AGENTS](../AGENTS.md) · [Development workflow](development/DEVELOPMENT_WORKFLOW.md) | Worktree ownership, contracts and integration |
| How do source actions and scheduled analysis work? | [Email actions](planning/EMAIL_ACTIONS_PLAN.md) · [Heartbeat reliability](planning/HEARTBEAT_RELIABILITY_PLAN.md) | Implementation, recovery and remaining acceptance |
| What did the earlier prototype demonstrate? | [Review trial](archive/trials/REVIEW_CONVERSATION_TRIAL.md) | Historical scripted interaction and limits |
| What do the terms mean? | [Glossary](guides/GLOSSARY.md) | Plain-language definitions |

## Current checkpoint

The 17 October installed release is `3bef5e9`, covering captured-job continuity across independent app edits. [Current status](../STATUS.md) and [validation](../VALIDATION.md) record the evidence and remaining real-use limits. The folder reorganisation preserves that implementation; a repository build is separate from installing a new app.

Guides, architecture, development, planning and audits now have dedicated folders. The [organisation guide](development/REPOSITORY_ORGANISATION_PLAN.md) maps code ownership and the [history folders](history/) preserve earlier engineering records. Later human direction supersedes older dated rules.

## Current behaviour, plans and evidence

**Features, Architecture and the detailed guides describe implemented behaviour.** They do not claim that every behaviour has passed sustained live acceptance. Validation and Live acceptance explain that evidence separately.

**Plan and Next improvements describe scope and gaps.** An approved item or a proposed design is not proof of implementation. The [PA intelligence plan](planning/PA_INTELLIGENCE_PLAN.md) retains detailed staged memory criteria. The [6 October architecture review](audits/PA_ARCHITECTURE_REVIEW.md) is an explicitly dated assessment and recommendation, superseded where later work changed the implementation. [Archived instructions](archive/AGENTS-2026-10-08-before-workflow-refresh.md) preserve historical development rules.

AGENTS is for agents developing this repository. It is not the shipped PA's runtime prompt, and neither a document nor source evidence authorises a personal-data write.

## Keep the explanation current

After a meaningful behaviour change, update its Features entry and the relevant detailed guide. Change Architecture when ownership or data flow changes. Record decisions in Decisions, approved scope in Plan, gaps in Next improvements, and actual checks in Status/Validation. Preserve earlier dated evidence.

Use relative links, descriptive headings and fictional examples. Keep secrets, personal-source content and private diagnostic captures out of documentation and Git. These Markdown pages and diagrams can be read on GitHub, in Codex or in a local editor; no separate documentation service is required.
