# Connect Claude Desktop and ChatGPT to 3PO

The MCP adapter exposes 3PO’s personal workspace to external assistants. It uses the official MCP SDK and a private, authenticated connection to the running Mac app. It makes no model requests of its own.

For installable ChatGPT/Codex and Claude packages with thirteen workflow skills, see the [3PO plugins](../Integrations/3POPlugin/README.md). Both reuse this app-backed adapter; the standalone MCP connection remains available.

Tools cover Calendar and Reminders reads/writes, nested Projects and tasks, relationships, original and additional project notes, Review inbox reads and acknowledgements, personal memory, human context notes and editable feature/scoped instructions. Mail and selected WhatsApp chats are read-only. Generated context pages remain read-only; edit the underlying facts or human notes. `about_3po` supplies the live information map and capabilities, with a static guide resource and assistant prompt for hosts that support them.

The connected assistant owns conversational intent and its normal tool approval UI. If permission is needed, it is requested in Claude Desktop or ChatGPT, where the human is talking. Host settings determine whether a tool asks each time or is allowed automatically. 3PO does not run a second AI intent check or require a second approval in its settings for a new external invocation. Tool arguments cannot select this authority: a private typed app entry point supplies it. Existing in-app chat checks retain their normal behaviour. Native revisions, source choices, recurrence scope, account ownership, durable claims and verified readback still apply.

## Build and enable

Build with `./scripts/build.sh`. The adapter, dependencies and Node runtime are included in the resulting app. Run only one normal 3PO copy against your personal storage. Follow the repository’s [installation procedure](../docs/development/DEVELOPMENT.md#updating-an-existing-installation) before replacing an existing app.

In 3PO, enable source context and choose the Calendar sources and reminder lists in **Settings → Assistant**. Then enable **Settings → External assistants → Enable 3PO workspace tools**. This grants the configured MCP clients access to the advertised app tools, subject to their own tool permission controls and 3PO’s source choices. The app starts a loopback-only bridge and creates a private connection file under `~/Library/Application Support/Mission Control/MCP/` with a rotating credential. Turning the connection off revokes it immediately.

The Mac must be awake and 3PO running. Closing the dashboard keeps the menu bar app running. A separate configured ChatGPT subscription is not used to reason about or authorise external MCP calls.

## Claude Desktop

Use **Copy Claude configuration** in 3PO’s External assistants settings. Merge the `3po` entry into the existing `mcpServers` object in `~/Library/Application Support/Claude/claude_desktop_config.json`; preserve any other servers. Restart Claude Desktop.

For an app installed at `/Applications/3PO.app`, the entry looks like:

```json
{
  "mcpServers": {
    "3po": {
      "command": "/bin/zsh",
      "args": ["/Applications/3PO.app/Contents/Resources/MCPBridge/run.sh"]
    }
  }
}
```

The copy button uses the actual running app path. This uses Claude Desktop’s local MCP mechanism; it is separate from cloud remote connectors and Cowork. See [Claude’s local MCP guidance](https://support.claude.com/en/articles/10949351-getting-started-with-local-mcp-servers-on-claude-desktop).

## ChatGPT desktop on this Mac

The current [ChatGPT desktop app supports local MCP servers](https://learn.chatgpt.com/docs/extend/mcp). In **Settings → MCP servers**, add a STDIO server named `3po`, using `/bin/zsh` and the installed app’s `MCPBridge/run.sh` path. The equivalent CLI command for an app installed in your user Applications folder is:

```sh
codex mcp add 3po -- /bin/zsh "$HOME/Applications/3PO.app/Contents/Resources/MCPBridge/run.sh"
```

The desktop app and local Codex clients share `~/.codex/config.toml`. Preserve existing servers when editing it. Refresh/restart the server from MCP settings after adding it. This connects local desktop chats; ChatGPT web and hosted Work chats need their own plugin connection.

## ChatGPT web through Secure MCP Tunnel

[Secure MCP Tunnel](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels) can forward to this same local stdio adapter. No public server or inbound port is required. You need an OpenAI Platform tunnel associated with the intended ChatGPT workspace, the relevant tunnel permissions and a runtime API key for `tunnel-client`. Account/workspace access must be checked in your own account.

Download `tunnel-client` from the official guide, create or reuse the intended tunnel, and configure its runtime key using the official setup. Keep the key outside the repository, chat and copied MCP configuration. Use **Copy local server command** from 3PO as the `--mcp-command` argument. For the example app location:

```sh
tunnel-client init \
  --sample sample_mcp_stdio_local \
  --profile threepo \
  --tunnel-id YOUR_TUNNEL_ID \
  --mcp-command "/bin/zsh '/Applications/3PO.app/Contents/Resources/MCPBridge/run.sh'"
tunnel-client doctor --profile threepo --explain
tunnel-client run --profile threepo
```

Keep that process running. In ChatGPT, [add a custom MCP server](https://developers.openai.com/api/docs/guides/custom-mcp-server), select **Tunnel**, choose this tunnel, and install the resulting plugin. Select it in the conversation. This is a documented ChatGPT web setup; desktop availability is not assumed.

## Try a read, then a change

Ask: “Use 3PO to show my calendar tomorrow.” The assistant should read a bounded Calendar range.

Then ask for a specific event change. The assistant reads the source and exact item details, asks any needed permission in that conversation and calls the change tool with a fresh UUID `requestID`. The tool returns `completed` with `verified: true` only after a verified save. Recurring edits and deletion retain 3PO’s exact scope and revision checks.

Ask “Use 3PO to show my Projects and Review inbox”, “Change my Review instructions to …”, or “Remember … in 3PO”. The assistant should read the relevant feature instructions and exact target before changing it. Project tasks and Apple reminders remain separate records. Review acknowledgement does not complete a task or execute a proposed action.

Submissions and outcomes are saved locally. Reusing a request ID with the same payload returns its existing result; a different payload is refused. An attempted or uncertain action cannot run again. After an interruption, use `action_status` with the original UUID and inspect the original item; never replay a possibly applied change with a new UUID. Legacy proposals queued by version 0.1 remain pending and require their original explicit native approval or dismissal; upgrading never executes them automatically. Turning off the bridge does not undo saved changes.

Use `refresh_connection` after source/account choices change or the bounded session fills, then read fresh identities. This preserves durable request IDs and receipts without restarting the desktop app. Memory and context writes use the same canonical stores, version history and compare-and-swap checks as the app UI. External memory evidence is honestly labelled as supplied by the connected assistant; 3PO does not claim to have independently read that conversation.

## Development checks

```sh
npm ci --ignore-scripts --prefix MCPBridge
./scripts/checks/test-mcp-bridge.sh
```

The check uses fictional data, in-memory SwiftData and a private temporary preferences suite. It exercises real MCP stdio handshakes and tool calls, the actual Swift loopback listener and action service, competing duplicate submissions, durable claims before a fictional writer, interrupted outcomes after restart, client isolation, credential rotation/revocation, HTTP framing and the exposed schema boundary. It does not launch 3PO, read personal sources, save native items or make model calls. The separate `app-mcp-workspace` signed-candidate suite exercises the real Projects, notes, memory, instructions, context history and Review stores with fictional ports, isolated fixture preferences and disposable SwiftData, asserting zero inference or native-source calls. A successful check/build is separate from connecting either signed-in client or validating an actual Calendar edit.
