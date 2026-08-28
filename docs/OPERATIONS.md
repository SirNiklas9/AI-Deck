# AI Deck operator guide

AI Deck is a selectable bundle of independent tools.  Install only the cards
you want; there is no mandatory shared daemon or database.

| Card | Executable | What it owns |
| --- | --- | --- |
| Lexicon | `aideck`, `lexicon-mcp` | Scoped global, workspace, and project knowledge |
| Splice | `splice`, `splice-mcp` | Bounded edit proposals and explicit atomic applies |
| Scry | `scry` | Watch observations and optional Lexicon refresh proposals |
| Trace | `trace` | Immutable metadata-only operation receipts |
| Lens | `lens`, `lens-mcp` | Read-only status and AI-safe context projections |
| Atlas | `atlas` | Structural code-map snapshots and evidence |

## Storage model

The installer creates one Deck state root.  It is a **directory boundary**,
not one giant cross-card database:

- Lexicon owns the durable knowledge stores below its state root.  Its routing
  registry maps one shared global layer, workspace layers, and project layers.
- Trace owns a separate receipt database.
- Splice, Scry, Lens, and Atlas do not silently write Lexicon knowledge.
- Linux and Windows each use native-local state. Do not place a live SQLite
  store on a Windows-mounted path used from WSL.

Each card can run alone. Optional composition is explicit: Scry can review
Lexicon, Splice can produce Trace evidence, and Lens can display declared
artifacts from the other cards.

## Build a bundle

From a source checkout on Windows:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
& C:\dev\lexicon\release\build-local.ps1 `
  -Version v0.1.0 `
  -OutputRoot C:\build\ai-deck `
  -SourceRoot C:\dev `
  -Platform windows-x64 `
  -Build
```

For Linux, cross-build the same sources with `-Platform linux-amd64`. The
resulting version directory is the local installation artifact. Package it as
a ZIP on Windows or a `tar.gz` on Linux and record its SHA-256 for automation.

## Install locally

### Windows

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
& C:\dev\lexicon\install\install.ps1 `
  -Bundle C:\build\ai-deck\ai-deck-windows-x64-v0.1.0 `
  -InstallRoot "$env:LOCALAPPDATA\AI Deck" `
  -Cards 'lexicon,splice,scry,trace,lens,atlas' `
  -Verify
```

`-Cards` accepts a comma-separated partial Deck, for example `lexicon,lens`
or `splice,atlas`. Add `-AddToUserPath` only if you want the selected bundle's
`bin` directory on your user PATH.

### Linux

```sh
sh /path/to/lexicon/install/install.sh \
  --bundle /srv/artifacts/ai-deck-linux-amd64-v0.1.0.tar.gz \
  --install-root "$XDG_DATA_HOME/ai-deck" \
  --cards lexicon,splice,scry,trace,lens,atlas \
  --verify
```

The default Linux root is `~/.local/share/ai-deck`. The installer intentionally
does not edit shell startup files; add `<installed-version>/bin` to PATH in
your own profile or Ansible role.

## Ansible examples

Use a local release artifact or an HTTPS URL plus SHA-256. Do not use an
unverified remote URL.

### Windows host

```yaml
- name: Install AI Deck
  ansible.windows.win_powershell:
    script: |
      Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
      & C:\Tools\AI-Deck\install.ps1 `
        -Bundle C:\Tools\AI-Deck\ai-deck-windows-x64-v0.1.0.zip `
        -InstallRoot "$env:LOCALAPPDATA\AI Deck" `
        -Cards 'lexicon,splice,scry,trace,lens,atlas' `
        -Verify `
        -ConfigureCodex -ConfigureNeovim `
        -LexiconStateRoot C:\AI-Deck\lexicon-state
```

For a downloaded artifact, use `-BundleUrl https://...` and `-Sha256 <exact
SHA-256>` instead of `-Bundle`.

`-ConfigureCodex` registers only Lexicon's installed MCP and its five lifecycle
hooks. `-ConfigureNeovim` writes the generated Lens/Splice local plugin spec.
Neither switch enables Scry, Trace, Atlas, or Splice globally. Set
`-LexiconStateRoot` (and optionally `-LexiconRegistry`) to preserve an existing
canonical knowledge store. The installer backs up `%USERPROFILE%\.codex` files
first. Codex requires one user `/hooks` review afterward; Ansible should not
forge that trust state.

To selectively remove only AI Deck's Codex integration later:

```yaml
- name: Remove AI Deck Lexicon Codex integration
  ansible.windows.win_powershell:
    script: |
      Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
      & C:\Tools\AI-Deck\install.ps1 -UnconfigureCodex
```

### Linux host

```yaml
- name: Install AI Deck
  ansible.builtin.command:
    cmd: >-
      sh /opt/ai-deck/install.sh
      --bundle /opt/ai-deck/ai-deck-linux-amd64-v0.1.0.tar.gz
      --install-root {{ ansible_env.HOME }}/.local/share/ai-deck
      --cards lexicon,splice,scry,trace,lens,atlas
      --verify
```

Follow it with an `ansible.builtin.lineinfile` task that adds the installed
version's `bin` directory to the user's shell profile if desired. Keep Linux
state on the Linux filesystem; do not point it at `/mnt/c/...`.

## CLI examples

Set these once per terminal, substituting your installed paths:

```powershell
$deck = "$env:LOCALAPPDATA\AI Deck\versions\ai-deck-windows-x64-v0.1.0"
$state = "$env:LOCALAPPDATA\AI Deck\state"
$bin = "$deck\bin"
```

```sh
deck="$HOME/.local/share/ai-deck/versions/ai-deck-linux-amd64-v0.1.0"
state="$HOME/.local/share/ai-deck/state"
bin="$deck/bin"
```

Useful checks:

```text
aideck doctor --bundle-root <deck> --state-root <state> --cards lexicon,splice,scry,trace,lens,atlas
atlas --root <repository> snapshot
scry status
trace --app <deck>/apps/trace/application/pulp.app.toml --storage-root <trace-state> list
lens --ai-context --snapshot-file <snapshot.json>
```

For Scry standalone observation, declare exactly what it may inspect:

```sh
scry --manifest watch.json --allow-root /path/to/repository observe
```

## Codex and Lexicon

Lexicon's MCP and lifecycle bridge are separate from installation. A host
configuration must name the installed `lexicon-mcp` and `lexicon-codex`
launchers, its application manifest, state root, and registry. Codex requires
you to review the five command hooks once with `/hooks`; the installer does
not forge that trust decision.

For Codex, configure **only Lexicon** as a global MCP server. It is the card
that must be present at task start to provide automatic context. Do not add
Splice, Scry, Trace, and Lens as global MCP servers: Codex starts every enabled
stdio MCP server for every task and retains it for that task's lifetime. Use
their CLIs, their Neovim adapters, or an explicit on-demand MCP configuration
when you actually need them. This keeps an ordinary task to one Deck MCP
process instead of five.

After configuring the host, validate a workspace with the bundled Windows
acceptance command:

```powershell
& <deck>\release\codex-host-acceptance.ps1 `
  -WorkspaceRoot C:\path\to\repository `
  -ExpectedInstance <registry-project-instance>
```

## Neovim / Neovide

The bundle includes optional local plugins. Point your plugin manager directly
at them; no network download is needed.

```lua
-- lazy.nvim example; use the installed bundle path for your platform.
local deck = vim.fn.expand("~/.../ai-deck/versions/ai-deck-..." )

return {
  {
    dir = deck .. "/apps/lens/nvim",
    name = "aideck-lens.nvim",
    config = function()
      require("inspector").setup({ view = "side" })
      vim.keymap.set("n", "<leader>ai", "<cmd>InspectorOpen<cr>", { desc = "AI Deck: Lens" })
    end,
  },
  {
    dir = deck .. "/apps/splice/nvim",
    name = "aideck-splice.nvim",
    config = function()
      require("splice").setup({ bin = deck .. "/bin/splice" })
      vim.keymap.set("v", "<leader>pe", function() require("splice").edit() end,
        { desc = "AI Deck: Splice edit" })
    end,
  },
}
```

On Windows, use forward slashes in the Lua path or construct it with
`vim.fs.joinpath(deck, "bin", "splice.exe")`. Lens reads only an explicit
snapshot file or a loopback Inspector API. Splice produces a preview and asks
before applying it; its default provider is the local Codex CLI in read-only
proposal mode.

## Verify the installed Deck

Run package acceptance against an installed version. It writes only a fresh
temporary acceptance directory beneath the Deck root and never touches your
canonical Lexicon data.

```powershell
& C:\dev\lexicon\release\full-acceptance.ps1 `
  -DeckRoot $deck -StateRoot $state -WorkspaceRoot C:\dev\Pulp `
  -RunSourceIntegration
```

The Linux equivalent is `release/full-acceptance.sh <deck> <state>
<workspace>`. It must use Linux-local state.
