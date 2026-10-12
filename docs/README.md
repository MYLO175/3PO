# The 3PO documentation

**Understand the product first, then follow the details you need.** These pages explain the software. Personal emails, chats, memories and credentials live outside the repository.

[Repository home](../README.md) · [Features](FEATURES.md) · [Architecture](ARCHITECTURE.md) · [Getting started](GETTING_STARTED.md)

## A short reading path

1. **[Features](FEATURES.md)** gives you a tour of the dashboard, PA, Review, Projects and background work, with practical examples.
2. **[Architecture](ARCHITECTURE.md)** explains who owns each part and follows real information through the system.
3. **[Memory and context](MEMORY_AND_CONTEXT.md)** explains what is saved, what is usable and what is selected for a particular question.
4. **[Project workspace](PROJECT_WORKSPACE.md)** explains the shared spaces/tasks, their views and their connection to memory.

For setup, use [Getting started](GETTING_STARTED.md). For code and checks, use [Developer guide](DEVELOPMENT.md). Unfamiliar terms are in the [glossary](GLOSSARY.md).

## Find the right page

| Question | Page | Role |
| --- | --- | --- |
| What can I do in the app? | [Features](FEATURES.md) | Current product tour |
| How does a message become an answer or change? | [Architecture](ARCHITECTURE.md) | Components, flows and ownership |
| How do I build and connect sources? | [Getting started](GETTING_STARTED.md) | Practical setup and troubleshooting |
| Where do my data go? | [Privacy](PRIVACY.md) | Source access, transmission and local storage |
| How do recall and corrections work? | [Memory and context](MEMORY_AND_CONTEXT.md) | Detailed memory contract |
| How do folders, tasks and project links work? | [Project workspace](PROJECT_WORKSPACE.md) | Detailed workspace contract |
| Where is a specific interaction documented? | [How it works](HOW_IT_WORKS.md) | Detailed behaviour reference with section links |
| Where should I start in the code? | [Developer guide](DEVELOPMENT.md) | Source map, build and verification tiers |
| Why was a design chosen? | [Decisions](DECISIONS.md) | Dated decisions; later choices supersede earlier ones |
| What is still missing? | [Next improvements](NEXT_IMPROVEMENTS.md) | Product gaps and success criteria |
| What was actually tested or installed? | [Validation](../VALIDATION.md) | Current evidence index, then historical evidence |
| What still needs ordinary use? | [Live acceptance](LIVE_ACCEPTANCE.md) | Latest installed binary and remaining real-use gates |
| What changed and when? | [Status](../STATUS.md) | Current summary first; detailed engineering log below |
| What work is approved? | [Plan](../PLAN.md) · [Reliability checklist](RELIABILITY_IMPLEMENTATION.md) | Approved scope and acceptance gates |
| How should development be coordinated? | [AGENTS](../AGENTS.md) · [Development workflow](DEVELOPMENT_WORKFLOW.md) | Worktree ownership, contracts and integration |
| What do the terms mean? | [Glossary](GLOSSARY.md) | Plain-language definitions |

## Current behaviour, plans and evidence

**Features, Architecture and the detailed guides describe implemented behaviour.** They do not claim that every behaviour has passed sustained live acceptance. Validation and Live acceptance explain that evidence separately.

**Plan and Next improvements describe scope and gaps.** An approved item or a proposed design is not proof of implementation. The [PA intelligence plan](PA_INTELLIGENCE_PLAN.md) retains detailed staged memory criteria. The [6 October architecture review](PA_ARCHITECTURE_REVIEW.md) is an explicitly dated assessment and recommendation, superseded where later work changed the implementation. [Archived instructions](archive/AGENTS-2026-10-08-before-workflow-refresh.md) preserve historical development rules.

AGENTS is for agents developing this repository. It is not the shipped PA's runtime prompt, and neither a document nor source evidence authorises a personal-data write.

## Keep the explanation current

After a meaningful behaviour change, update its Features entry and the relevant detailed guide. Change Architecture when ownership or data flow changes. Record decisions in Decisions, approved scope in Plan, gaps in Next improvements, and actual checks in Status/Validation. Preserve earlier dated evidence.

Use relative links, descriptive headings and fictional examples. Keep secrets, personal-source content and private diagnostic captures out of documentation and Git. These Markdown pages and diagrams can be read on GitHub, in Codex or in a local editor; no separate documentation service is required.
