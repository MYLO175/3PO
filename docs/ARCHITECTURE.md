# Architecture

The reliability checkpoint is installed and its focused/integration/preservation checks pass. This describes current component ownership; sustained acceptance remains open. [Validation](../VALIDATION.md) and the [implementation checklist](RELIABILITY_IMPLEMENTATION.md) record those separately.

## What makes the PA work

3PO supplies continuity: saved conversations, usable memories, permitted source information, projects and verified action history. The inference provider supplies language and reasoning. Keeping those responsibilities separate lets us test app behaviour without using a real model or personal sources.

| Component | Owns | Boundary |
| --- | --- | --- |
| `DashboardModel` and views | Desktop navigation, mounted widgets, sheets, layouts, feedback and app lifecycle | Desktop adapters prepare domain context and callbacks; presentation is not an inference dependency |
| `ApplicationServices` | Construction and lifetime of production services | Loads the configured services but does not start source collection or inference; lifecycle starts work explicitly |
| `AssistantService` | Conversation identities, drafts, captured Focus/setup/queue state, preparation and persisted replies | Uses a narrow runtime context and inference port; dashboard projections and tool creation belong to its desktop adapter |
| `PAConversationEngine` | Completed response/tool rounds, transport history, duplicate/stall detection and cancellation | Injected inference/tool functions; no database, dashboard, credentials or source startup |
| Source services | Permitted bounded reads, exact source identities, current cached snapshots and availability | `NativeSourceReading` separates Calendar/Reminders reads from EventKit writes; Mail and WhatsApp remain read-only |
| `PAMemoryStore` and notebook projection | Current usable beliefs, evidence, corrections, deterministic relevance and organisation | Permissions and current-belief filtering precede cached preparation; organisation cannot author facts or projects |
| `LearningRuntime` and five learning services | Small opted-in cached/conversation batches, exact evidence, progress and failure pauses | Injected inference, assistant state, cached source reader, activity and clock; no dashboard or collection helpers |
| `BackgroundLearningCoordinator` and `LearningBudget` | Fair serial claim opportunities and the existing shared allowance | A lane advances only after a persisted claim; idle/paused work does not consume its turn |
| `HeartbeatService` and `HeartbeatRuntime` | Due cycles, exact run identities, persistent call claims, stages, recovery and sleep interruption | Injected clock/device/context and child ports; no dashboard or source collector |
| `AssistantActions` and action receipts | Exact authority, pending records, verification and supported Undo | `NativeActionRuntime` supplies only current ownership/permissions, a native writer and result callbacks |
| `LocalRecordRepository` | Exact-key read/write and atomic related changes | Each operation uses a fresh SwiftData context; a failed operation cannot commit another owner's pending state |
| `ConversationRepository` | Conversation metadata and changed 64-turn chunks | One atomic index/chunk update; original legacy bytes and unknown supported fields remain preserved |

Heartbeat remains the owner of automatic email review, suggestions and current briefs. Its desktop adapter supplies already collected Mail, permitted native/WhatsApp context and existing child services. Each child receives the same exact run-bound claim and completion validator. It claims before inference and validates before saving; parent cancellation, typing, device unavailability or ownership drift rejects late child output before the parent polling loop unwinds. Completed earlier receipts remain. Source collection makes no AI calls. Learning scheduling and foreground conversation execution are separate from heartbeat recovery; none may replay uncertain foreground work.

## From a message to a saved answer

1. The conversation service saves the human turn and a reply identity before yielding. Account, Focus, setup session, model and source permissions belong to that captured request.
2. Current memory usability and targeted relevance select a bounded set of facts. The notebook supplies relevant anchors using the same selected identities. Historical replies with unavailable support are withheld from input while remaining saved.
3. The inference port receives bounded input. Completed tool calls go through one request-owned tool session; imported text never grants authority.
4. Reads issue exact current identities. A supported write requires current human intent, target/scope/revision checks and a durable pending record before native execution. Readback establishes success. An uncertain result stays pending for outcome checking.
5. The engine repeats as needed, retaining encrypted reasoning and complete transport rounds. Stop or ownership drift ends the captured request. Late text callbacks from an ended round are invalidated.
6. The service saves final text, supplied/consulted memory IDs, choices and completed receipts in the original reply. Queued work stays serial; clarification, failure and interruption require the existing human continuation policy.

The context trace records supplied identities and counts. It cannot establish which fact influenced the model's answer.

## Memory and background work

Retrieval is lexical and uses typed or human-reviewed connections. Meaningful short terms are retained. A targeted query may select zero facts, even with Focus selected. Only an explicit broad-orientation request uses a null query; dedicated setup uses that path and excludes source snapshots.

Derived lexical/notebook caches are disposable. Their keys include current memory/workspace revisions, owner/scope and currently usable fact IDs. Source consent and age are rechecked before a cache hit. There are no embeddings, automatic semantic identity merges or broad paraphrase guarantees.

The shared learning allowance remains four automatic passes per local day with at least thirty minutes between claims. Eligible lanes rotate by their last persisted claim. Each service retains its own opt-ins, batch limits and failed-claim pauses. Foreground work wins. A new source opt-in establishes a baseline rather than revisiting historical content.

## Storage and recovery

Repositories change only their owned keys. Related email records and native snapshot/health records save together. Writes that fail before commit leave stored values unchanged; callers retain their existing in-memory recovery policy. Corrupt records remain preserved and block the affected changes.

Conversation migration retains `assistantConversations` byte-for-byte. The new index, metadata and 64-turn chunks save atomically. Missing/corrupt/future indexes, stale owners and namespace collisions stop rather than falling back and overwriting history. Unsupported opaque numeric precision is refused. Unknown supported nested fields survive edits; cleared known optional fields stay cleared.

The legacy record is the pre-migration history, not a backup of later edits. Before installation, the integration owner makes a recoverable backup of the complete personal store while the app is quit. Recovery must preserve the whole store or use a compatible current reader; an older app cannot be assumed to understand later chunked changes. No private store or backup belongs in Git.

## Verification boundaries

Source-free checks exercise deterministic rules and actual services with fictional ports, private settings and disposable storage. Candidate checks are separately identified as in-memory app, native fixture or configured-model tiers. A signed evaluation protocol handshake runs before dashboard construction; Release or unsupported diagnostic modes refuse before normal startup.

Build, signature, model quality, installation, native UI and sustained operation are distinct evidence. Simulated clock/sleep scenarios do not establish a physical lid cycle or several days of ordinary use. Current limits and exact evidence belong in [Validation](../VALIDATION.md); behaviour belongs in [How it works](HOW_IT_WORKS.md), memory detail in [Memory and context](MEMORY_AND_CONTEXT.md), and remaining product work in [Next improvements](NEXT_IMPROVEMENTS.md).
