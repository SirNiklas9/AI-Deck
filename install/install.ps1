[CmdletBinding()]
param(
    [string]$Bundle,
    [string]$BundleUrl,
    [string]$Sha256,
    [string]$DeckRoot,
    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'AI Deck'),
    [string]$Cards = 'lexicon',
    [switch]$AddToUserPath,
    [switch]$Verify,
    [switch]$ConfigureCodex,
    [switch]$ConfigureNeovim,
    [switch]$UnconfigureCodex,
    [string]$CodexHome = (Join-Path $env:USERPROFILE '.codex'),
    [string]$NvimConfig = (Join-Path $env:LOCALAPPDATA 'nvim'),
    [string]$LexiconStateRoot,
    [string]$LexiconRegistry
)

$ErrorActionPreference = 'Stop'

if ($UnconfigureCodex -and ($Bundle -or $BundleUrl -or $ConfigureCodex -or $ConfigureNeovim)) {
    throw '-UnconfigureCodex is a standalone operation; do not combine it with install or configure switches.'
}

 $configureOnly = ($ConfigureCodex -or $ConfigureNeovim) -and -not $Bundle -and -not $BundleUrl
if ($configureOnly -and -not $DeckRoot) {
    throw '-DeckRoot is required when configuring an already installed Deck.'
}
if (-not $UnconfigureCodex -and -not $configureOnly -and (($Bundle -and $BundleUrl) -or (-not $Bundle -and -not $BundleUrl))) {
    throw 'Specify exactly one of -Bundle (local directory/zip) or -BundleUrl (HTTPS release artifact).'
}
if ($BundleUrl -and -not $Sha256) {
    throw '-BundleUrl requires -Sha256 so a remote artifact is verified before use.'
}

function Assert-Sha256([string]$Path, [string]$Expected) {
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Expected.ToLowerInvariant()) { throw "SHA-256 mismatch for $Path" }
}

function Assert-BundleManifest([string]$Root) {
    $manifest = Join-Path $Root 'checksums.sha256'
    if (-not (Test-Path -LiteralPath $manifest)) { return }
    foreach ($line in Get-Content -LiteralPath $manifest) {
        if ($line -match '^([0-9a-fA-F]{64})\s+\*?(.+)$') {
            $file = Join-Path $Root $Matches[2]
            if (-not (Test-Path -LiteralPath $file)) { throw "Bundle checksum entry is missing: $($Matches[2])" }
            Assert-Sha256 $file $Matches[1]
        }
    }
}

function Get-CardSet([string]$Raw) {
    return @($Raw.Split(',') | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
}

function Backup-Codex([string]$ConfigRoot) {
    $backup = Join-Path $ConfigRoot ('ai-deck-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Force -Path $backup | Out-Null
    foreach ($name in @('config.toml', 'hooks.json')) {
        $source = Join-Path $ConfigRoot $name
        if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $backup -Force }
    }
    return $backup
}

function Remove-LexiconHooks([object]$Document) {
    if ($null -eq $Document -or $null -eq $Document.hooks) { return $Document }
    foreach ($event in @($Document.hooks.PSObject.Properties)) {
        $keptMatchers = @()
        foreach ($matcher in @($event.Value)) {
            $kept = @()
            foreach ($hook in @($matcher.hooks)) {
                $command = [string]$hook.command + "`n" + [string]$hook.commandWindows
                if ($command -notmatch '(?i)lexicon-codex\.exe') { $kept += $hook }
            }
            if ($kept.Count -gt 0) {
                $matcher.hooks = @($kept)
                $keptMatchers += $matcher
            }
        }
        if ($keptMatchers.Count -eq 0) { $Document.hooks.PSObject.Properties.Remove($event.Name) }
        else { $event.Value = @($keptMatchers) }
    }
    return $Document
}

function Set-LexiconHooks([string]$ConfigRoot, [string]$Deck, [string]$State, [string]$Registry) {
    New-Item -ItemType Directory -Force -Path $ConfigRoot | Out-Null
    $path = Join-Path $ConfigRoot 'hooks.json'
    $document = if (Test-Path -LiteralPath $path) { Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } else { [pscustomobject]@{ description = 'AI Deck Lexicon lifecycle integration for Codex.'; hooks = [pscustomobject]@{} } }
    $document = Remove-LexiconHooks $document
    if ($null -eq $document.hooks) { $document | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) }
    $bin = Join-Path $Deck 'bin\lexicon-codex.exe'
    $app = Join-Path $Deck 'apps\lexicon\application\pulp.app.toml'
    $win = '& "' + ($bin.Replace('\','/')) + '" --app "' + ($app.Replace('\','/')) + '" --storage-root "' + ($State.Replace('\','/')) + '" --registry "' + ($Registry.Replace('\','/')) + '"'
    $portable = '"' + $bin + '" --app "' + $app + '" --storage-root "' + $State + '" --registry "' + $Registry + '"'
    $timeouts = @{ SessionStart = 10; UserPromptSubmit = 15; PreToolUse = 10; PreCompact = 15; Stop = 10 }
    foreach ($event in $timeouts.Keys) {
        $hook = [pscustomobject]@{ type='command'; command=$portable; timeout=$timeouts[$event]; commandWindows=$win; statusMessage='Loading Lexicon context' }
        $matcher = [pscustomobject]@{ hooks=@($hook) }
        if ($event -eq 'PreToolUse') { $matcher | Add-Member -NotePropertyName matcher -NotePropertyValue '' }
        $existing = @()
        $property = $document.hooks.PSObject.Properties[$event]
        if ($null -ne $property) { $existing = @($property.Value) }
        $document.hooks | Add-Member -Force -NotePropertyName $event -NotePropertyValue @($existing + @($matcher))
    }
    $document | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding utf8
}

function Set-LexiconMcp([string]$ConfigRoot, [string]$Deck, [string]$State, [string]$Registry) {
    New-Item -ItemType Directory -Force -Path $ConfigRoot | Out-Null
    $path = Join-Path $ConfigRoot 'config.toml'
    $text = if (Test-Path -LiteralPath $path) { Get-Content -LiteralPath $path -Raw } else { '' }
    # Replace precisely the lexicon table, preserving every other user and host setting.
    $text = [regex]::Replace($text, '(?ms)^\[mcp_servers\.lexicon\]\r?\n.*?(?=^\[|\z)', '')
    $exe = Join-Path $Deck 'bin\lexicon-mcp.exe'
    $app = Join-Path $Deck 'apps\lexicon\application\pulp.app.toml'
    $block = "[mcp_servers.lexicon]`ncommand = '" + $exe + "'`nargs = ['--app', '" + $app + "', '--storage-root', '" + $State + "', '--registry', '" + $Registry + "', '--cwd', 'C:\']`nrequired = true`nstartup_timeout_sec = 30`n"
    Set-Content -LiteralPath $path -Value (($text.TrimEnd() + "`n`n" + $block)) -Encoding utf8
}

function Remove-LexiconCodex([string]$ConfigRoot) {
    $hooks = Join-Path $ConfigRoot 'hooks.json'
    $config = Join-Path $ConfigRoot 'config.toml'
    if (Test-Path -LiteralPath $hooks) {
        $document = Get-Content -LiteralPath $hooks -Raw | ConvertFrom-Json
        $document = Remove-LexiconHooks $document
        $document | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $hooks -Encoding utf8
    }
    if (Test-Path -LiteralPath $config) {
        $text = Get-Content -LiteralPath $config -Raw
        $text = [regex]::Replace($text, '(?ms)^\[mcp_servers\.lexicon\]\r?\n.*?(?=^\[|\z)', '')
        Set-Content -LiteralPath $config -Value $text.TrimEnd() -Encoding utf8
    }
}

if ($UnconfigureCodex) {
    $backup = Backup-Codex $CodexHome
    Remove-LexiconCodex $CodexHome
    Write-Output "AI Deck Lexicon Codex integration removed. Backup: $backup"
    exit 0
}

if ($configureOnly) {
    $target = (Resolve-Path -LiteralPath $DeckRoot).Path
    $aideck = Join-Path $target 'bin\aideck.exe'
    if (-not (Test-Path -LiteralPath $aideck)) { throw "DeckRoot is missing bin/aideck.exe: $target" }
    $selectedCards = Get-CardSet $Cards
    $defaultState = Join-Path (Split-Path -Parent (Split-Path -Parent $target)) 'state'
    $effectiveState = if ($LexiconStateRoot) { $LexiconStateRoot } else { $defaultState }
    $effectiveRegistry = if ($LexiconRegistry) { $LexiconRegistry } else { Join-Path $effectiveState 'canonical-registry.json' }
    if ($ConfigureCodex) {
        if ($selectedCards -notcontains 'lexicon') { throw '-ConfigureCodex requires the lexicon card.' }
        if (-not (Test-Path -LiteralPath $effectiveRegistry)) { throw "Lexicon registry does not exist: $effectiveRegistry. Supply -LexiconStateRoot/-LexiconRegistry." }
        $backup = Backup-Codex $CodexHome
        Set-LexiconMcp $CodexHome $target $effectiveState $effectiveRegistry
        Set-LexiconHooks $CodexHome $target $effectiveState $effectiveRegistry
        Write-Output "AI Deck configured Codex Lexicon integration. Backup: $backup"
        Write-Output 'Open Codex once and use /hooks to review the five new Lexicon command hooks; host trust is never forged.'
    }
    if ($ConfigureNeovim) {
        $nvimCards = @($selectedCards | Where-Object { $_ -in @('lens','splice') })
        if ($nvimCards.Count -eq 0) { throw '-ConfigureNeovim requires lens and/or splice in -Cards.' }
        & $aideck setup nvim --cards ($nvimCards -join ',') --nvim-config $NvimConfig
        if ($LASTEXITCODE) { throw 'AI Deck Neovim setup failed.' }
        Write-Output 'AI Deck configured Neovim plugin specification.'
    }
    exit 0
}

$stage = Join-Path ([System.IO.Path]::GetTempPath()) ('aideck-install-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $stage | Out-Null
try {
    if ($BundleUrl) {
        if ($BundleUrl -notmatch '^https://') { throw '-BundleUrl must use HTTPS.' }
        $archive = Join-Path $stage 'bundle.zip'
        Invoke-WebRequest -Uri $BundleUrl -OutFile $archive
        Assert-Sha256 $archive $Sha256
        Expand-Archive -LiteralPath $archive -DestinationPath $stage -Force
    } elseif (Test-Path -LiteralPath $Bundle -PathType Container) {
        # Preserve the bundle directory name: it is the release version recorded
        # in current.json and under versions/, not an implementation detail.
        Copy-Item -LiteralPath $Bundle -Destination $stage -Recurse
    } elseif (Test-Path -LiteralPath $Bundle -PathType Leaf) {
        Expand-Archive -LiteralPath $Bundle -DestinationPath $stage -Force
    } else {
        throw "Bundle does not exist: $Bundle"
    }
    $roots = @(Get-ChildItem -LiteralPath $stage -Directory)
    $root = if ($roots.Count -eq 1 -and (Test-Path (Join-Path $roots[0].FullName 'bin'))) { $roots[0].FullName } elseif (Test-Path (Join-Path $stage 'bundle\bin')) { Join-Path $stage 'bundle' } else { throw 'Bundle must contain a single root with bin/.' }
    Assert-BundleManifest $root
    $version = Split-Path -Leaf $root
    $target = Join-Path (Join-Path $InstallRoot 'versions') $version
    if (Test-Path -LiteralPath $target) { throw "That AI Deck version is already installed: $target" }
    New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
    Move-Item -LiteralPath $root -Destination $target
    $current = Join-Path $InstallRoot 'current.json'
    @{ version = $version; root = $target; cards = $Cards } | ConvertTo-Json | Set-Content -LiteralPath $current -Encoding utf8
    $aideck = Join-Path $target 'bin\aideck.exe'
    if (-not (Test-Path -LiteralPath $aideck)) { throw 'Bundle is missing bin/aideck.exe.' }
    & $aideck deck --cards $Cards
    $state = Join-Path $InstallRoot 'state'
    New-Item -ItemType Directory -Force -Path $state | Out-Null
    if (-not (Test-Path (Join-Path $state 'canonical-registry.json'))) {
        & $aideck init --state-root $state
        if ($LASTEXITCODE) { throw 'AI Deck state initialization failed.' }
    }
    if ($Verify) { & $aideck doctor --bundle-root $target --state-root $state --cards $Cards; if ($LASTEXITCODE) { throw 'AI Deck doctor failed.' } }
    $selectedCards = Get-CardSet $Cards
    if ($ConfigureCodex) {
        if ($selectedCards -notcontains 'lexicon') { throw '-ConfigureCodex requires the lexicon card.' }
        $effectiveState = if ($LexiconStateRoot) { $LexiconStateRoot } else { $state }
        $effectiveRegistry = if ($LexiconRegistry) { $LexiconRegistry } else { Join-Path $effectiveState 'canonical-registry.json' }
        if (-not (Test-Path -LiteralPath $effectiveRegistry)) { throw "Lexicon registry does not exist: $effectiveRegistry. Supply -LexiconStateRoot/-LexiconRegistry or initialize/register Lexicon first." }
        $backup = Backup-Codex $CodexHome
        Set-LexiconMcp $CodexHome $target $effectiveState $effectiveRegistry
        Set-LexiconHooks $CodexHome $target $effectiveState $effectiveRegistry
        Write-Output "AI Deck configured Codex Lexicon integration. Backup: $backup"
        Write-Output 'Open Codex once and use /hooks to review the five new Lexicon command hooks; host trust is never forged.'
    }
    if ($ConfigureNeovim) {
        $nvimCards = @($selectedCards | Where-Object { $_ -in @('lens','splice') })
        if ($nvimCards.Count -eq 0) { throw '-ConfigureNeovim requires lens and/or splice in -Cards.' }
        & $aideck setup nvim --cards ($nvimCards -join ',') --nvim-config $NvimConfig
        if ($LASTEXITCODE) { throw 'AI Deck Neovim setup failed.' }
        Write-Output 'AI Deck configured Neovim plugin specification.'
    }
    if ($AddToUserPath) {
        $bin = Join-Path $target 'bin'
        $old = [Environment]::GetEnvironmentVariable('Path', 'User')
        if (($old -split ';') -notcontains $bin) { [Environment]::SetEnvironmentVariable('Path', ($old.TrimEnd(';') + ';' + $bin), 'User') }
    }
    Write-Output "AI Deck installed: $target"
    Write-Output 'Codex lifecycle hooks must be reviewed once with /hooks; the installer never forges host trust.'
} finally {
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}
