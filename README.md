# AI Deck

AI Deck is a portable installer and profile manager for independent AI tools.
It does not own a shared database, agent loop, or harness. A selected card is
always an independently runnable application with its own declared authority.

| Card | Application | Role | Dependency |
| --- | --- | --- | --- |
| Lexicon | Lexicon | scoped durable knowledge and automatic context | none |
| Splice | Splice | bounded proposed code edits | none |
| Scry | `scry` CLI / MCP | standalone source watch reports; optionally refresh proposals from Lexicon | none |
| Trace | `trace` CLI / MCP | immutable metadata-only evidence | none |
| Lens | `lens` CLI / MCP | read-only suite projection | none |
| Atlas | `atlas` CLI | bounded structural code evidence | none |

Examples:

```text
aideck deck --cards lexicon
aideck deck --cards scry
aideck deck --cards lexicon,splice,scry,trace,lens,atlas
```

The tool names and persisted application identifiers remain stable until a
separate compatibility-preserving release migration. AI Deck is the visible
suite name; it does not rename data on disk.

## Standalone and optional links

Every card can be selected alone. They share Pulp engine code, not a shared
AI Deck database or mandatory process:

- **Lexicon** owns its scoped knowledge store and optional Codex lifecycle
  integration.
- **Splice** proposes and explicitly applies a bounded patch through its
  Lua/Pulp workflow.
- **Scry** has `observe --manifest ...` for independent filesystem/Git watch
  reports. `review` is an optional Lexicon-aware refresh-proposal mode.
- **Trace** owns immutable, metadata-only receipts.
- **Lens** reads explicit snapshot/AI-context artifacts or a local API; it
  never owns the data it displays.
- **Atlas** produces bounded structural snapshots without retaining source
  bodies or calling a model.

The public card names are the executable, MCP-server, and MCP-tool names. The
current repository directory and internal Go module names are compatibility
details, not product names. Pith remains a separate legacy code-map surface;
only its bounded transform application is Splice.

Cards may compose voluntarily: Splice can emit Trace evidence, Scry can review
Lexicon records, and Lens can present all declared artifacts. None of those
links prevents a partial deck from running.

## Installation

The portable installers live in [`install`](install). They support a local
bundle (ideal for Ansible) or an explicit HTTPS artifact plus SHA-256. A public
one-line bootstrap is intentionally not published until the release repository
and signing key are selected; the installer will not guess an unverified URL.
