# Mission Control notebook

This is the readable explanation of the product: what exists, how it works and what we want to improve. It lives beside the code, so Git records changes to both. You do not need to read code or the development log to understand the app.

Start with **[How it works](HOW_IT_WORKS.md)**. Use **[Next improvements](NEXT_IMPROVEMENTS.md)** to review priorities and **[Decisions](DECISIONS.md)** to understand why the app is organised this way.

The latest broad direction and recommended delivery sequence is **[PA architecture review](PA_ARCHITECTURE_REVIEW.md)**, covering communications, changing commitments, memory, background jobs, project space and future local models. It distinguishes the inspected implementation from proposed changes. The earlier **[Building a useful personal assistant](PA_INTELLIGENCE_PLAN.md)** remains the detailed staged memory acceptance plan.

| Document | Purpose |
| --- | --- |
| [How it works](HOW_IT_WORKS.md) | Current behaviour and the pieces behind it |
| [Next improvements](NEXT_IMPROVEMENTS.md) | Desired behaviour, gaps and success criteria |
| [Life and project workspace](PROJECT_WORKSPACE.md) | Shared durable structure, views, PA edits and source relationships |
| [PA intelligence plan](PA_INTELLIGENCE_PLAN.md) | Detailed phases and tests for a PA that understands useful life context |
| [PA architecture review](PA_ARCHITECTURE_REVIEW.md) | Current architecture assessment and recommended route to communications understanding, durable jobs and local inference |
| [Decisions](DECISIONS.md) | Significant choices and their consequences |
| [PLAN](../PLAN.md) | Full approved implementation scope |
| [Agent instructions](../AGENTS.md) | How Codex should develop the repository and preserve invariants |
| [Development workflow](DEVELOPMENT_WORKFLOW.md) | Worktree ownership, bounded delegation, integration and release |
| [STATUS](../STATUS.md) | Current summary plus detailed dated engineering evidence |
| [VALIDATION](../VALIDATION.md) | Concise current validation index and known limits, with earlier history |
| [Repository README](../README.md) | Build/run instructions and integration details |

AGENTS governs Codex development agents, not the installed PA's runtime prompt. Current human direction sets requirements; PLAN records approved scope, Next improvements records gaps/success criteria, and Decisions explains agreed choices. README and How it works describe the product. STATUS and VALIDATION establish what was actually checked; they do not authorise new features or Apple writes. Older dated architecture reviews/plans are historical snapshots where later changes supersede them.

## Keeping this useful

After a meaningful feature changes, update its explanation here and the relevant roadmap item. Keep CURRENT and PLANNED clearly separate. Record a significant change of direction in Decisions. Put build/test evidence in STATUS, rather than making this notebook a long chronological log.

Git is the history and backup mechanism; these Markdown pages are the explanation. They can be read in Codex, a text editor or Obsidian. Obsidian is optional and is not part of Mission Control's runtime. These files document the software, not your personal life: emails, chats, credentials and private memory remain outside the repository.

Current entry points reconciled with the recorded 8 October application checkpoint. No new app/model/live acceptance is implied by this documentation pass. An installed build and a passing test are different from a completed live acceptance check; see STATUS and VALIDATION for those boundaries.
