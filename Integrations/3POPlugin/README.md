# 3PO plugins

Use your running 3PO Mac app from ChatGPT/Codex or Claude Code/Cowork. Both packages include thirteen focused skills and connect to the same app-backed MCP tools. The connected assistant reasons and replies; 3PO supplies permitted records and verifies requested changes.

## Workflows

| Skill | Purpose |
| --- | --- |
| setup | Connect and understand 3PO |
| status | Diagnose access or an interrupted operation |
| day / week | Brief, review and plan work around commitments |
| calendar | Availability and appointment changes |
| reminders | Native lists, dates, repeats and completion |
| projects | Nested spaces, tasks, notes, order and links |
| review | Work through the saved Review inbox |
| find | Find information in permitted personal sources |
| memory | Remember, correct, forget and resolve saved knowledge |
| context | Explain background and manage human context notes |
| instructions | Update feature and scoped guidance |
| undo | Supported recovery and exact local restoration |

Ask naturally or select a skill. In Claude Code, skills are also commands such as /3po:day and /3po:projects. In ChatGPT/Codex, select 3PO from the plugin picker and use its packaged skills.

## Requirements

Install 3PO in your user or system Applications folder and keep it running. Enable source context, select the intended Calendar/Reminder sources, and enable Settings > External assistants. The optional THREEPO_APP_PATH environment variable chooses another installed app bundle. An explicit invalid path fails instead of silently using another app.

The launcher uses the adapter and Node runtime bundled with 3PO. No separate Node installation or copied credentials are needed. The rotating private connection file stays with the Mac app.

Local plugin servers work in supported local ChatGPT/Codex sessions and native Claude Code. Claude also loads them in locally running Cowork sessions, but a runtime must be able to reach the Mac app. A loaded skill alone does not prove that connection. Ordinary Claude chat can keep its independent local MCP connection. Cloud/web use requires a separately configured supported transport.

## Build

Run from the repository root:

    python3 Integrations/3POPlugin/build.py

The build creates two plugin folders, ZIPs, local marketplace layouts and a release manifest under build/plugins/. The output is self-contained apart from its explicit dependency on the installed 3PO app. It contains no personal context, source snapshots, app data or credentials.

Use the OpenAI marketplace layout with the installed Codex plugin marketplace/add commands or the desktop plugin directory. Use the Claude marketplace layout with Claude Code's plugin marketplace/install commands, or upload the Claude ZIP in Customize > Plugins for Cowork. Validate the actual native client before claiming a connection works.

From the repository root, install a locally built package with the appropriate client:

    codex plugin marketplace add ./build/plugins/openai-marketplace
    codex plugin add 3po@3po-local

    claude plugin marketplace add ./build/plugins/claude-marketplace
    claude plugin install 3po@3po-local

Keep the marketplace folder at a stable location when installing it permanently. In a running Claude Code session, use /reload-plugins to load newly installed skills. Desktop plugin availability can require a new chat or a client restart.

## Data and permissions

Skills read 3PO's current guidance and relevant context on demand. Requested changes use the host's normal permissions in the conversation where you are working; the plugin adds no approval-policy overrides. Projects, Reminders, Calendar, Review and memory remain separate stores. Only completed, verified outcomes confirm saves.

Email and WhatsApp are read-only. Generated pages remain read-only; human notes, memory and instructions have their own editable owners. Reading a saved Brief or Review does not start a new AI scan. No startup hook scans sources or silently saves conversations.

After a timeout, keep the original operation ID and check its status. An uncertain change must not be retried as a new operation. Undo has the existing app's latest-operation restrictions and is not an arbitrary rollback.

## Checks

Run the package/launcher checks:

    python3 -m unittest discover -s Integrations/3POPlugin/tests -v

These checks use temporary fictional app bundles, validate distribution contents and do not change personal records or make model requests. Client discovery and live connection checks are separate evidence.
