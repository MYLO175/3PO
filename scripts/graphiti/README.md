# Experimental local Graphiti runtime

This is the subprocess backend for 3PO's optional Graphiti memory comparison. It uses **real Graphiti 0.31.2**, embedded FalkorDBLite 0.11.0, and local FastEmbed 0.9.0 / BGE-small English ONNX embeddings (384 dimensions). It does not start the upstream Graphiti HTTP/MCP server. Source text reaches only 3PO's existing subscription inference bridge; there is no API-key, hosted embedding, or remote reranker fallback. Graphiti/Hugging Face/ONNX telemetry is disabled.

## Setup

Python 3.12 or newer is required; the tested platform is macOS 26 arm64 with Python 3.13.2. Run explicitly from the repository:

```sh
scripts/graphiti/setup.sh
```

The default destination is `~/Library/Application Support/com.mylomichael.missioncontrol/Graphiti/runtime`. Python is at `runtime/bin/python3`, an independently runnable helper is copied to `runtime/helper.py`, and public model weights are stored under `runtime/models`. The app bundles the same helper from `MissionControl/Resources/Graphiti/helper.py`. Re-run setup when runtime requirements change. `THREEPO_GRAPHITI_PYTHON` selects a compatible Python interpreter.

For an isolated installation:

```sh
scripts/graphiti/setup.sh /private/tmp/3po-graphiti-runtime-check
```

Setup downloads pinned Python packages and the public embedding model revision `aa8f8b060edb00e03bfdd08813a2949946c8ba55` from `Qdrant/bge-small-en-v1.5-onnx-Q`. Setup makes no subscription call, sends no private source text, and does not use an existing Hugging Face token. Runtime embedding loads are offline and fail if weights are missing. Direct dependencies are in `requirements.txt`; all tested transitive versions are in `requirements.lock.txt`.

## JSONL contract

Run `bin/python3 helper.py`, write exactly one initial JSON object and newline to stdin. The helper finishes after one command. `database_path` is an absolute **dedicated directory**, not a database file. Use canonical filesystem paths (`/private/tmp`, not its `/tmp` symlink). Each opaque `group_id` has independent storage and an exclusive process lock. All files are owner-private.

```json
{"protocol":1,"operation":"sync","database_path":"/private/tmp/fictional-graph","group_id":"0123456789abcdef0123456789abcdef","max_new_episodes":1,"episodes":[{"id":"03e7403b-f1dd-4813-b9db-d9806009723d","reference_key":"memory:fictional","revision":"1","name":"Fictional memory","body":"Alice studies at Cambridge.","reference_time":"2026-01-01T00:00:00Z"}]}
```

`sync` always receives the **complete currently permitted snapshot**. `max_new_episodes` defaults to 1 and is limited to 1–8. Episode IDs must change when their content, provenance, source-access identity or revision changes. 3PO derives these IDs from account, evidence kind, canonical key and revision. IDs returned by the helper are lowercase canonical UUID strings. Duplicate episode IDs or reference keys are rejected. Limits: 2,000 episodes, 24 KB body per episode, 8 MiB initial protocol message.

Each inference step emits:

```json
{"type":"llm_request","id":"request-uuid","messages":[{"role":"system","content":"..."},{"role":"user","content":"..."}],"schema":{},"name":"ExtractedEntities"}
```

The host replies with `{"type":"llm_response","id":"request-uuid","result":{...}}`, or an `error` field. Only one inference is outstanding. Pydantic schemas are validated on receipt; failures stop without inference retries. The host must retain source/ownership/Stop checks around these calls. At most 160 typed calls may occur per command. The host sets the operation deadline and terminates on cancellation.

`search` requires `query`, `limit` (1–30, default 12), and **all currently allowed episode IDs** in `allowed_episode_ids`. If any indexed episode is now absent, the entire generation is refused until reconciled. Search uses Graphiti's BM25 + real local semantic vector search and reciprocal rank fusion; no subscription inference runs. Results contain only unexpired fact edges, never uncited entity summaries:

```json
{"type":"result","result":{"facts":[{"id":"edge-uuid","text":"Alice studies at Cambridge.","episode_ids":["episode-uuid"],"valid_at":"2026-01-01T00:00:00+00:00","invalid_at":null}],"episode_count":1,"indexed_episode_ids":["episode-uuid"],"pending_count":0,"generation":"gen-opaque-id","graphiti_version":"0.31.2","embedding_model":"BAAI/bge-small-en-v1.5"}}
```

All of each edge's Graphiti source episode IDs are retained; an edge with empty, unindexed or unauthorised provenance is discarded. The host must validate **all indexed references**, not only direct edge citations, before using results: entity resolution and graph-derived summaries can depend on other indexed evidence. Superseded/expired edges are excluded from current-life answers; a historical timeline query is not implemented.

`status` returns counts/IDs without loading the embedding model or starting a database. `clear` discards this group's experimental index only. Errors are bounded generic `{ "type":"error", "message":"..." }` messages; exception bodies, source text and tracebacks are not logged.

## Pinned temporal compatibility

The helper applies `invalid_at`/`expired_at` eligibility inside Graphiti search before its result limit, then checks returned edges again. Otherwise expired high-ranking matches can hide a still-current relationship.

Graphiti 0.31.2 also marks an edge with any end date as expired during related-edge resolution, even when that date is in the future. A narrow process-local compatibility function changes that initial check to require an end date at or before now. Existing contradiction handling is retained. The helper verifies the exact upstream function SHA-256 before applying this adjustment; an unreviewed library implementation fails closed instead of silently receiving the patch. Revisit this adjustment when upgrading Graphiti. Attribution and the Apache-2.0 licence are included in `GRAPHITI-LICENSE` and the bundled resources.

Regression tests reproduce both cases with the actual database/engine. Separate resolver-contract checks verify past expiry, genuine contradictions, and refusal on upstream-function drift. These fixes do not establish complete correctness for every future plan, recurrence or conflicting report.

## Persistence and forgetting

A removed/revised episode invalidates the complete old generation before any new inference. This avoids stale derived summaries or connections surviving a source withdrawal. Rebuilding can require multiple sync batches.

Each successful episode is extracted into a private copy of the last committed database. The worker saves and shuts down the database, then atomically publishes a manifest referring to the new generation. Failed/interrupted work never becomes readable, and previously committed episodes do not need re-extraction. Old generations and abandoned candidates are deleted under the group lock. The app must preserve pending counts and surface failures for explicit retry; the helper does not schedule jobs.

FalkorDB listens on an owner-private Unix socket with TCP disabled and a 512 MB database limit. It shuts down when the command ends. A separate death-pipe guardian terminates the owned database PID after an abrupt helper exit, checking the process creation time to avoid PID reuse. SIGTERM and SIGKILL during inference are tested. Raw episode content is not retained in the graph; extracted facts/summaries are personal data and remain in this private, deletable index. Ordinary file deletion is not a forensic secure erase.

## Validation

After setup, execute the fictional integration tests:

```sh
THREEPO_GRAPHITI_MODEL_CACHE=/private/tmp/3po-graphiti-runtime-check/models \
/private/tmp/3po-graphiti-runtime-check/bin/python3 Tests/GraphitiPython/test_engine.py
```

These tests run the actual Graphiti extraction pipeline, persistent FalkorDB and local embedding engine, including incremental resume, unchanged snapshots, semantic retrieval, revision/removal, isolation, failed-provider checkpoints, lock contention and subprocess cancellation. Model replies are a deterministic scripted fixture. Passing these checks establishes plumbing and lifecycle behaviour, **not live model extraction quality or improvement over context pages**. Live subscription extraction and comparative memory evaluation are separate acceptance steps.

Keep the source and bundled helper byte-identical after edits. The setup/runtime dependencies use their upstream licences; Graphiti is Apache-2.0, FastEmbed and this BGE model are MIT. FalkorDBLite/FalkorDB have separate upstream licensing terms; inspect the pinned distributions before redistributing database binaries (setup currently installs them locally).
