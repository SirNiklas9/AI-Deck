# AI Deck installer contract

The installers install a versioned, self-contained AI Deck bundle. They accept
either a local bundle (ideal for Ansible/air-gapped deployment) or an explicit
HTTPS release URL with a mandatory SHA-256 digest. They never download an
unverified artifact, silently modify host hook trust, or merge card data.

Windows:

```powershell
& .\install.ps1 -Bundle C:\artifacts\ai-deck-windows-x64.zip -Cards lexicon,splice,scry,trace,lens -Verify
```

### Configure selected integrations

Installation and host setup are separate and selectable. Add
`-ConfigureCodex` to register only Lexicon's MCP server and five lifecycle
hooks, and `-ConfigureNeovim` to generate the local Lens/Splice plugin spec.
Neither option starts Scry, Trace, Atlas, or Splice as a global service.

```powershell
& .\install.ps1 -Bundle C:\artifacts\ai-deck-windows-x64.zip `
  -Cards 'lexicon,lens,splice' -Verify `
  -ConfigureCodex -ConfigureNeovim `
  -LexiconStateRoot C:\state\lexicon
```

`-LexiconStateRoot` and `-LexiconRegistry` are optional. Supply them when
automation should keep using an existing canonical Lexicon store rather than
the Deck install root's newly initialized state. Before changing config, the
installer saves `config.toml` and `hooks.json` under a timestamped
`%USERPROFILE%\.codex\ai-deck-backup-*` folder. Codex still asks the user to
review the five command hooks once with `/hooks`; no installer can safely
forge that host trust.

Configure an already installed version without reinstalling it:

```powershell
& .\install.ps1 -DeckRoot "$env:LOCALAPPDATA\AI Deck\versions\ai-deck-windows-x64-v0.2.0" `
  -Cards 'lexicon,lens,splice' -ConfigureCodex -ConfigureNeovim `
  -LexiconStateRoot C:\state\lexicon
```

Remove only AI Deck's Lexicon MCP and lifecycle hooks later (other MCP
servers, hooks, and all Deck state remain intact):

```powershell
& .\install.ps1 -UnconfigureCodex
```

Linux:

```sh
./install.sh --bundle ./ai-deck-linux-amd64.tar.gz --cards lexicon,splice,scry,trace,lens --verify
```

Published `curl | sh` and `irm` bootstrap commands are intentionally deferred
until the release repository and signing key are chosen. The command must pass
the release archive's SHA-256 to this installer.
