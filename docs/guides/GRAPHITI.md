# Trying Graphiti memory

Graphiti is an optional memory experiment alongside the existing supporting facts and context pages. It builds dated relationships between people, projects, goals and other entities, then retrieves relevant relationships with keyword and local semantic search. The assistant interprets those results to answer questions; a graph does not itself establish that an interpretation is true.

## Setup and use

From this checkout, run `scripts/graphiti/setup.sh`, then build/install the app using the usual signed build workflow. Python 3.12+ is required. Setup installs pinned packages and a public embedding model locally; it does not read personal records. See the [runtime instructions](../../scripts/graphiti/README.md) for dependencies, paths and the protocol.

Open **Context → Graphiti experiment…**. The default is **Context pages**, with automatic Graphiti learning off.

1. Choose **Update graph** to index the currently permitted shared evidence. The existing saved-memory and memory-learning controls must allow this. Extraction uses the connected ChatGPT subscription and selected model, with several calls per episode. A large first build can take substantial time; Stop preserves completed episodes and another update resumes.
2. Try a question in the graph lookup box to see readable relationships, applicability dates and expandable evidence, or choose **Graphiti** and ask in ordinary chat. The assistant has a `search_graph_memory` tool; Sources & searches records its actual use.
3. Choose **Context pages** to return to the existing system, or **Pages + Graphiti** to make both available. These choices do not migrate or delete original records.
4. Enable **Learn Graphiti relationships during heartbeats** for incremental maintenance. This uses the existing background allowance, adds at most one new episode per heartbeat, and pauses on an extraction failure until explicit retry.

Review and briefs retain the existing context system in every mode. The optional graph can be deleted independently using **Delete experimental graph**; this returns chat to Context pages and disables graph learning while preserving original memory, pages, projects and conversations.

## What enters the graph

The app supplies currently permitted shared supporting facts, project records, human-written context, retained human conversation and eligible source updates. Canonical facts retain their original evidence and attribution. Generated context-page summaries and assistant answers are not fed back as new evidence. Legacy topic-only evidence is not indexed by this experiment. There is no bulk historical Mail or WhatsApp crawl, and no new source permission.

Each snapshot selects the newest eligible evidence under a 2,000-episode and 1.5 MB encoded-episode bound, then processes it chronologically. Individual source excerpts are limited to 12 KB and labelled when partial. Recent conversation initially uses the existing bounded window; previously indexed, still-permitted conversation can remain available. Missing relationships therefore do not prove that information does not exist. Counts and omitted coverage are reported.

Graphiti uses an account-separated private local FalkorDB index, local BGE-small embeddings and the existing ChatGPT connection for extraction. No API-key or paid embedding-service fallback is configured. Extracted personal facts are stored locally in the experimental graph; extraction evidence is sent to the already-connected inference provider. This is not an entirely offline memory system.

## Comparing answers

Graphiti mode withholds factual page prose, the old notebook reader and initial supporting relationships. Human instructions and current source tools remain available; original fact tools remain for explicit evidence/correction/forget work. Previous assistant messages produced using another memory mode are omitted from model input when switching modes, while the saved transcript and human messages remain intact. Combined mode intentionally uses both systems.

Ask the same questions in each mode: who is involved in a project, how responsibilities connect, which plans changed, or what evidence supports an answer. Inspect actual searches and compare correctness, attribution, coverage, latency and useful connections. Human conversation and current source reads can also inform answers, so this is a practical comparison rather than a controlled retrieval benchmark.

Facts include their episode references and temporal validity. Currently expired edges are excluded; a dedicated historical timeline query is not implemented. Corrections, Forget and source withdrawal make the old generation unavailable for new retrieval. Reconciliation rebuilds affected graph state instead of leaving potentially contaminated entity summaries readable. Retrieved relationships never supply authority or exact targets for external actions.

## Verification

The branch has a source-free live diagnostic, `--validate-graphiti-memory`, advertised by the DEBUG evaluation handshake. It uses fictional records, an in-memory app database and a temporary graph, runs real subscription extraction across separate project, collaborator and motivation records and the actual assistant/tool path, then corrects a collaborator and sensor count, checks withdrawal, and clears the graph. It records initial-build and correction-rebuild durations. Cross-record checks require citations on the returned relationships; merely indexing a source is not a successful recall. Its output is `missioncontrol-graphiti-evaluation.json` under `MISSIONCONTROL_TEST_ROOT` when provided. Never run a normal second app copy as a substitute for the diagnostic.

Focused checks cover the real Graphiti engine with scripted extraction, process cancellation/schema handling, assistant backend selection and history, and the existing page and heartbeat contracts. These establish that the integration works; they do not establish that Graphiti gives better answers about a person's life. Sustained personal use and a comparative question set are still needed.
