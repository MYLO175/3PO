# Connect Claude Desktop and ChatGPT to 3PO

The MCP adapter exposes 3PO’s existing Calendar and Reminders tools to external assistants. It uses the official MCP SDK and a private, authenticated connection to the running Mac app. It makes no model requests of its own.

The first version supports `read_calendar`, `read_reminders`, `read_item_details`, `change_calendar`, `change_reminder` and `action_status`. Mail, WhatsApp, memory and project tools are outside this version.

## Build and enable

Build with `./scripts/build.sh`. The adapter, dependencies and Node runtime are included in the resulting app. Run only one normal 3PO copy against your personal storage. Follow the repository’s [installation procedure](../docs/development/DEVELOPMENT.md#updating-an-existing-installation) before replacing an existing app.

In 3PO, enable source context and choose the Calendar sources and reminder lists in **Settings → Assistant**. Then enable **Settings → External assistants → Enable Calendar and Reminders tools**. That grants connected assistants read access to those selected sources. The app starts a loopback-only bridge and creates a private connection file under `~/Library/Application Support/Mission Control/MCP/` with a rotating credential. Turning the connection off revokes it immediately.

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

Then ask for a specific event change. The assistant must read the source and exact item details, submit the concrete change with a fresh UUID `requestID`, and report it as **pending**. Open **3PO Settings → External assistants**, inspect the event, dates, destination, recurrence scope and notes, then press **Approve** or **Decline**. Ask the assistant to check `action_status` with the same request ID. Only `completed` with `verified: true` confirms a saved change. Recurring edits and deletion retain the app’s existing scope and revision checks.

Submissions and outcomes are saved locally. Reusing a request ID with the same payload returns its existing status; a different payload is refused. An attempted or uncertain action cannot be approved again. After an interruption, inspect the original Calendar/Reminders item and use the original request ID; never generate another ID to replay a possibly applied change. Turning off the bridge does not undo previously saved changes.

## Development checks

```sh
npm ci --ignore-scripts --prefix MCPBridge
./scripts/checks/test-mcp-bridge.sh
```

The check uses fictional data, in-memory SwiftData and a private temporary preferences suite. It exercises real MCP stdio handshakes and tool calls, the actual Swift loopback listener and action service, competing duplicate submissions, durable claims before a fictional writer, interrupted outcomes after restart, client isolation, credential rotation/revocation, HTTP framing and the exposed schema boundary. It does not launch 3PO, read personal sources, save native items or make model calls. A successful check/build is separate from connecting either signed-in client or validating an actual Calendar edit.
