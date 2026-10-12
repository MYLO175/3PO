# Privacy and source boundaries

**You choose source access and AI context separately. Apple apps remain the original records.** 3PO is a local application with connected inference; it is not an entirely offline or uniformly encrypted vault.

[Documentation](README.md) · [Features](FEATURES.md) · [Architecture](ARCHITECTURE.md#persistence-privacy-and-recovery)

## What each integration can do

| Source or service | Access | Important boundary |
| --- | --- | --- |
| Calendar | Permitted native reads and supported explicit human-authorised writes | Exact target/revision/recurrence checks, pending receipt and readback; deletion has no app Undo |
| Reminders | Permitted native reads and supported explicit human-authorised writes | Native task completion is separate from local project progress |
| Apple Mail | Read-only headers/bodies and opening the original message | Preserves unread status; no send, mailbox mutation or attachment ingestion |
| WhatsApp | Optional linked-device reception; selected chats for AI use | No sending, read receipts or presence commands; received cache can include unselected chats |
| Weather | Optional one-fix location and Open-Meteo forecast | Rounded 0.1-degree request; coordinates are not retained in cache/context/logs |
| Dictation | Optional macOS microphone/speech integration | Separate native permissions |
| ChatGPT connection | Subscription model inference on permitted prepared input | Account model/plan eligibility applies; no API-key billing fallback |

macOS permission allows source access; the app's source/AI/learning controls decide the purpose and scope of that access. Life-area Focus is relevance rather than permission. Background proposals need approval before native changes. Imported content, saved memory, evidence links and previous model replies do not independently authorise writes.

## What stays local, and what may leave the Mac

| Operation | Data flow |
| --- | --- |
| Source collection / Refresh sources only | Local/native source reads and caches; no model request. Optional weather/WhatsApp use their own external services. |
| PA request | Bounded relevant dialogue, selected usable memory, permitted source/project context, explicit image input and requested tool results may be sent to the connected provider. |
| Heartbeat | Permitted current context and independently collected communications feed bounded email/suggestion/brief requests. |
| Opted-in learning | Bounded permitted conversation/source evidence can be sent for interpretation under independent controls and allowances. |
| Explicit email Feedback | Exact comment, topic, sender/subject and up to 16,000 fresh body characters feed one bounded interpretation; original words and resulting preference stay inspectable locally. |
| Memory/history/source-evidence inspection | Uses existing local permitted records without AI or new source reads. |
| Local reply drafts | Review/edit/save/copy only; the app has no send capability. Draft generation may use permitted context in inference. |

Source/permission/version checks apply again before current advice or source memory is used. Historical visible records can remain saved when their evidence becomes unavailable; that does not make them current recall. Disabling a source does not erase existing conversations. A saved context trace stores IDs/counts rather than extra bodies, full prompts or model reasoning.

## Storage

SwiftData records and supporting caches live under `~/Library/Application Support/Mission Control`. They include transcripts, memory/version history, workspace, briefs, queues and operation receipts. These records are not all application-encrypted. Additional encryption and broader deletion/retention measurement remain planned.

ChatGPT credentials and the WhatsApp encryption key use macOS Keychain. WhatsApp session/messages/names/source selections are encrypted locally. Reception can cache text from unselected chats; chat selection gates AI use rather than collection. The helper uses its own session rather than another application's registration. The unofficial Baileys connection requires a human QR scan and can break or face account restrictions; its local cache does not guarantee complete WhatsApp history.

Personal stores, auth/session files, credentials, QR codes, source bodies, caches, screenshots and private backups stay outside Git. Repository artwork and fictional diagrams contain no personal-source capture. `.gitignore` is a useful boundary, not a substitute for reviewing staged files and outgoing history.

## Updates and recoverable changes

Updates retain the stable bundle ID `com.mylomichael.missioncontrol`, storage/registration/helper/Keychain identities and saved records. One integration owner backs up the complete personal store and supporting files while the app is quit, then verifies the signed replacement and record preservation. A worktree does not isolate personal data.

Memory corrections retain version history; retirement excludes outdated human context from recall while retaining evidence. Forget is separate. Recently deleted Projects records restore their original identities. Supported app Undo is one-level per category; native deletion, creation and unsupported series changes do not offer general app Undo. An uncertain native write keeps its pending receipt for outcome checking rather than replay.

Current validation and limitations are in [Validation](../VALIDATION.md). The implementation contracts are in [Memory and context](MEMORY_AND_CONTEXT.md), [Project workspace](PROJECT_WORKSPACE.md) and [Architecture](ARCHITECTURE.md).
