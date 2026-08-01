# common.ps1: shared library for Winmarchy. Dot-source this file; it defines
# functions only and has no side effects on import, so Pester can load it
# headlessly on any machine.
# Compatible with Windows PowerShell 5.1. Text files are always written as
# UTF-8 without a BOM via [System.IO.File] so YAML and JSON consumers never
# see a BOM.

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

function Get-WinmarchyHome {
    # The runtime data root. WINMARCHY_HOME overrides for tests and for
    # development on machines without LOCALAPPDATA (for example Linux CI).
    if ($env:WINMARCHY_HOME) { return $env:WINMARCHY_HOME }
    if ($env:LOCALAPPDATA) { return (Join-Path $env:LOCALAPPDATA 'winmarchy') }
    throw 'Neither WINMARCHY_HOME nor LOCALAPPDATA is set; cannot resolve the winmarchy data directory.'
}

function Get-WinmarchyStateDir { return (Join-Path (Get-WinmarchyHome) 'state') }
function Get-WinmarchyLogDir { return (Join-Path (Get-WinmarchyHome) 'log') }
function Get-WinmarchyBackupDir { return (Join-Path (Get-WinmarchyHome) 'backup') }
function Get-WinmarchyWallpaperDir { return (Join-Path (Get-WinmarchyHome) 'wallpapers') }

function Get-WinmarchyRepoRoot {
    # This file lives at <root>/bin/lib/common.ps1 both in the repo and in the
    # deployed layout under LOCALAPPDATA\winmarchy, so two levels up is always
    # the root that carries themes/ and templates/.
    return (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}

function Get-WinmarchyThemesDir { return (Join-Path (Get-WinmarchyRepoRoot) 'themes') }
function Get-WinmarchyTemplatesDir { return (Join-Path (Get-WinmarchyRepoRoot) 'templates') }

# ---------------------------------------------------------------------------
# Text IO and logging
# ---------------------------------------------------------------------------

function Write-WinmarchyTextFile {
    # UTF-8 without BOM, creating the parent directory when needed. This is the
    # only sanctioned way to write text files in Winmarchy.
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Write-WinmarchyLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Level = 'INFO'
    )
    $logDir = Get-WinmarchyLogDir
    if (-not (Test-Path $logDir)) {
        $null = New-Item -ItemType Directory -Path $logDir -Force
    }
    $logPath = Join-Path $logDir 'winmarchy.log'
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = $stamp + ' [' + $Level + '] ' + $Message + [Environment]::NewLine
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::AppendAllText($logPath, $line, $encoding)
}

# ---------------------------------------------------------------------------
# Object helpers (Windows PowerShell 5.1 has no ConvertFrom-Json -AsHashtable)
# ---------------------------------------------------------------------------

function Test-PsObjectProperty {
    param(
        [Parameter(Mandatory = $true)]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )
    return (@($InputObject.PSObject.Properties.Name) -contains $Name)
}

function Set-PsObjectProperty {
    param(
        [Parameter(Mandatory = $true)]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name,
        $Value
    )
    $InputObject | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
}

function ConvertTo-WinmarchyHashtable {
    # Recursive PSCustomObject to hashtable conversion.
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $table = @{}
        foreach ($key in $InputObject.Keys) {
            $table[$key] = ConvertTo-WinmarchyHashtable $InputObject[$key]
        }
        return $table
    }
    if ($InputObject -is [System.Array]) {
        $list = @()
        foreach ($item in $InputObject) { $list = $list + @(, (ConvertTo-WinmarchyHashtable $item)) }
        # The leading comma stops the pipeline unrolling one-element arrays to
        # a scalar and empty arrays to null.
        return , $list
    }
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $table = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $table[$property.Name] = ConvertTo-WinmarchyHashtable $property.Value
        }
        return $table
    }
    return $InputObject
}

# ---------------------------------------------------------------------------
# Themes and template rendering
# ---------------------------------------------------------------------------

function Get-WinmarchyThemeNames {
    $themesDir = Get-WinmarchyThemesDir
    $names = @()
    foreach ($file in (Get-ChildItem -Path $themesDir -Filter '*.json' -File | Sort-Object Name)) {
        $names = $names + $file.BaseName
    }
    return $names
}

function Get-WinmarchyTheme {
    param([Parameter(Mandatory = $true)][string]$Name)
    $themePath = Join-Path (Get-WinmarchyThemesDir) ($Name + '.json')
    if (-not (Test-Path $themePath)) {
        throw ('Unknown theme "' + $Name + '"; no file at ' + $themePath)
    }
    $theme = [System.IO.File]::ReadAllText($themePath) | ConvertFrom-Json
    foreach ($required in @('name', 'label', 'mode', 'wt_scheme', 'nvim', 'colors')) {
        if (-not (Test-PsObjectProperty $theme $required)) {
            throw ('Theme "' + $Name + '" is missing required key "' + $required + '"')
        }
    }
    if ($null -eq $theme.colors) {
        throw ('Theme "' + $Name + '" has a null colors block')
    }
    foreach ($property in $theme.colors.PSObject.Properties) {
        if (-not ([string]$property.Value -match '^#[0-9a-fA-F]{6}$')) {
            throw ('Theme "' + $Name + '" colour "' + $property.Name + '" is not a six-digit hex colour')
        }
    }
    return $theme
}

function Get-WinmarchyNextThemeName {
    # Cycles the alphabetical theme list, wrapping at the end. Comparison is
    # case-insensitive to match Windows filesystem theme resolution; an
    # unknown current theme lands on the first theme.
    param([Parameter(Mandatory = $true)][string]$Current)
    $names = @(Get-WinmarchyThemeNames)
    if ($names.Count -eq 0) { throw 'No themes installed.' }
    $index = -1
    for ($i = 0; $i -lt $names.Count; $i++) {
        if ($names[$i] -eq $Current) { $index = $i; break }
    }
    $next = ($index + 1) % $names.Count
    return $names[$next]
}

function Get-WinmarchyThemeTokens {
    # Flattens a theme into the {{token}} vocabulary used by every template:
    # each palette colour by name, plus name, label, mode, wt_scheme and the
    # nvim keys. nvim_plugin_spec is the ready-made lazy.nvim spec fragment,
    # with the optional plugin alias (for example catppuccin) included.
    param([Parameter(Mandatory = $true)]$Theme)
    $tokens = @{}
    foreach ($property in $Theme.colors.PSObject.Properties) {
        $tokens[$property.Name] = $property.Value
    }
    $tokens['name'] = $Theme.name
    $tokens['label'] = $Theme.label
    $tokens['mode'] = $Theme.mode
    $tokens['wt_scheme'] = $Theme.wt_scheme
    $tokens['nvim_plugin'] = $Theme.nvim.plugin
    $tokens['nvim_colorscheme'] = $Theme.nvim.colorscheme
    $pluginSpec = '"' + $Theme.nvim.plugin + '"'
    if ((Test-PsObjectProperty $Theme.nvim 'name') -and $Theme.nvim.name) {
        $pluginSpec = $pluginSpec + ', name = "' + $Theme.nvim.name + '"'
    }
    $tokens['nvim_plugin_spec'] = $pluginSpec
    return $tokens
}

function Expand-WinmarchyTemplate {
    # Replaces every {{token}} in the template text. Fails hard if any
    # {{...}} placeholder remains unresolved, so a template can never ship
    # with a hole in it.
    param(
        [Parameter(Mandatory = $true)][string]$Template,
        [Parameter(Mandatory = $true)][hashtable]$Tokens
    )
    $result = $Template
    foreach ($key in $Tokens.Keys) {
        $placeholder = '{{' + $key + '}}'
        $value = [string]$Tokens[$key]
        $result = $result.Replace($placeholder, $value)
    }
    $leftover = [regex]::Matches($result, '\{\{[^\}]*\}\}')
    if ($leftover.Count -gt 0) {
        $names = @()
        foreach ($match in $leftover) { $names = $names + $match.Value }
        $unique = @($names | Sort-Object -Unique)
        throw ('Unresolved template tokens: ' + ($unique -join ', '))
    }
    return $result
}

# ---------------------------------------------------------------------------
# Windows Terminal settings
# ---------------------------------------------------------------------------

function Get-WtSettingsPath {
    # Candidate paths from the build brief Section 4.4, first match wins.
    # Returns $null when Windows Terminal has never run.
    if (-not $env:LOCALAPPDATA) { return $null }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}

function Remove-WinmarchyJsoncNoise {
    # Strips // line comments, /* */ block comments and trailing commas from
    # JSON-with-comments text. Character-walking with string awareness, so
    # comment markers and comma-brace sequences INSIDE string values are
    # never touched (a plain regex here corrupts values like
    # "cmd.exe /c echo {a,}").
    param([Parameter(Mandatory = $true)][string]$Text)

    $builder = New-Object System.Text.StringBuilder
    $inString = $false
    $escaped = $false
    $inLineComment = $false
    $inBlockComment = $false
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]
        $lookahead = [char]0
        if ($i + 1 -lt $Text.Length) { $lookahead = $Text[$i + 1] }
        if ($inLineComment) {
            if ($ch -eq "`n") {
                $inLineComment = $false
                $null = $builder.Append($ch)
            }
            continue
        }
        if ($inBlockComment) {
            if ($ch -eq '*' -and $lookahead -eq '/') {
                $inBlockComment = $false
                $i = $i + 1
            }
            continue
        }
        if ($inString) {
            $null = $builder.Append($ch)
            if ($escaped) {
                $escaped = $false
            } elseif ($ch -eq '\') {
                $escaped = $true
            } elseif ($ch -eq '"') {
                $inString = $false
            }
            continue
        }
        if ($ch -eq '"') {
            $inString = $true
            $null = $builder.Append($ch)
            continue
        }
        if ($ch -eq '/' -and $lookahead -eq '/') {
            $inLineComment = $true
            $i = $i + 1
            continue
        }
        if ($ch -eq '/' -and $lookahead -eq '*') {
            $inBlockComment = $true
            $i = $i + 1
            continue
        }
        $null = $builder.Append($ch)
    }

    # Second pass: drop commas whose next non-whitespace character closes an
    # object or array, again skipping string contents.
    $noComments = $builder.ToString()
    $builder = New-Object System.Text.StringBuilder
    $inString = $false
    $escaped = $false
    for ($i = 0; $i -lt $noComments.Length; $i++) {
        $ch = $noComments[$i]
        if ($inString) {
            $null = $builder.Append($ch)
            if ($escaped) {
                $escaped = $false
            } elseif ($ch -eq '\') {
                $escaped = $true
            } elseif ($ch -eq '"') {
                $inString = $false
            }
            continue
        }
        if ($ch -eq '"') {
            $inString = $true
            $null = $builder.Append($ch)
            continue
        }
        if ($ch -eq ',') {
            $j = $i + 1
            while ($j -lt $noComments.Length -and [char]::IsWhiteSpace($noComments[$j])) { $j = $j + 1 }
            if ($j -lt $noComments.Length) {
                $closer = $noComments[$j]
                if ($closer -eq '}' -or $closer -eq ']') { continue }
            }
        }
        $null = $builder.Append($ch)
    }
    return $builder.ToString()
}

function ConvertFrom-WtSettingsJson {
    # Windows Terminal settings.json may contain line comments and trailing
    # commas. Parse algorithm from the brief Section 4.4: try strict first;
    # on failure strip comments and trailing commas (string-aware), then
    # retry; on second failure throw and never write anything.
    param([Parameter(Mandatory = $true)][string]$RawText)
    try {
        return ($RawText | ConvertFrom-Json)
    } catch {
        $firstError = $_.Exception.Message
    }
    $stripped = Remove-WinmarchyJsoncNoise -Text $RawText
    try {
        return ($stripped | ConvertFrom-Json)
    } catch {
        throw ('Windows Terminal settings.json could not be parsed even after stripping comments and trailing commas. First error: ' + $firstError + '. Second error: ' + $_.Exception.Message)
    }
}

function New-WtSchemeObject {
    # Builds our colour scheme for a theme by rendering the scheme template.
    # The ANSI mapping (black = background, bright black = muted, cursor and
    # bright white = bright_foreground, selection = selection) is ported
    # verbatim from Omarchy's alacritty.toml.tpl. Scheme key names verified
    # against the Windows Terminal colour scheme documentation
    # (learn.microsoft.com/en-us/windows/terminal/customize-settings/color-schemes).
    param([Parameter(Mandatory = $true)]$Theme)
    $templatePath = Join-Path (Get-WinmarchyTemplatesDir) 'wt-scheme.json.tpl'
    $template = [System.IO.File]::ReadAllText($templatePath)
    $rendered = Expand-WinmarchyTemplate -Template $template -Tokens (Get-WinmarchyThemeTokens -Theme $Theme)
    return ($rendered | ConvertFrom-Json)
}

function Update-WtSettingsFile {
    # Patches a Windows Terminal settings.json in place:
    #   1. one-time backup to settings.json.winmarchy-bak (only if absent)
    #   2. ensure our scheme object is present in schemes (replace by name)
    #   3. set profiles.defaults.colorScheme
    #   4. optionally set profiles.defaults.font.face
    # Aborts before writing anything if the file cannot be parsed.
    # Returns a summary object with the actions taken.
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Theme,
        [switch]$SetFontFace,
        [string]$FontFace = 'JetBrainsMono Nerd Font'
    )
    if (-not (Test-Path $Path)) {
        throw ('Windows Terminal settings file not found at ' + $Path)
    }
    $rawText = [System.IO.File]::ReadAllText($Path)
    $settings = ConvertFrom-WtSettingsJson -RawText $rawText

    $backupPath = $Path + '.winmarchy-bak'
    $backupCreated = $false
    if (-not (Test-Path $backupPath)) {
        Copy-Item -Path $Path -Destination $backupPath
        $backupCreated = $true
    }

    $scheme = New-WtSchemeObject -Theme $Theme

    if ((-not (Test-PsObjectProperty $settings 'schemes')) -or ($null -eq $settings.schemes)) {
        Set-PsObjectProperty $settings 'schemes' @()
    }
    $newSchemes = @()
    foreach ($existing in @($settings.schemes)) {
        if ($null -eq $existing) { continue }
        if ($existing.name -ne $scheme.name) { $newSchemes = $newSchemes + $existing }
    }
    $newSchemes = $newSchemes + $scheme
    Set-PsObjectProperty $settings 'schemes' $newSchemes

    if ((-not (Test-PsObjectProperty $settings 'profiles')) -or ($null -eq $settings.profiles)) {
        Set-PsObjectProperty $settings 'profiles' ([pscustomobject]@{ defaults = [pscustomobject]@{} })
    } elseif ($settings.profiles -is [System.Array]) {
        # Legacy bare-array profiles form; wrap into the documented object form
        # with defaults plus list, preserving every profile.
        Set-PsObjectProperty $settings 'profiles' ([pscustomobject]@{
            defaults = [pscustomobject]@{}
            list     = @($settings.profiles)
        })
    } elseif ((-not (Test-PsObjectProperty $settings.profiles 'defaults')) -or ($null -eq $settings.profiles.defaults)) {
        Set-PsObjectProperty $settings.profiles 'defaults' ([pscustomobject]@{})
    }
    Set-PsObjectProperty $settings.profiles.defaults 'colorScheme' $scheme.name

    if ($SetFontFace) {
        if ((-not (Test-PsObjectProperty $settings.profiles.defaults 'font')) -or ($null -eq $settings.profiles.defaults.font)) {
            Set-PsObjectProperty $settings.profiles.defaults 'font' ([pscustomobject]@{})
        }
        Set-PsObjectProperty $settings.profiles.defaults.font 'face' $FontFace
    }

    $outText = $settings | ConvertTo-Json -Depth 64
    Write-WinmarchyTextFile -Path $Path -Content $outText
    return [pscustomobject]@{
        Path          = $Path
        BackupCreated = $backupCreated
        SchemeName    = $scheme.name
        FontSet       = [bool]$SetFontFace
    }
}

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

function Get-WinmarchyStatePath { return (Join-Path (Get-WinmarchyStateDir) 'state.json') }

function Get-WinmarchyDefaultState {
    return @{
        mode                      = 'win11'
        lastMode                  = 'win11'
        theme                     = 'tokyo-night'
        chooserDisabled           = $false
        savedWallpaper            = $null
        savedAppsUseLightTheme    = $null
        savedSystemUsesLightTheme = $null
    }
}

function Get-WinmarchyState {
    # Defaults merged under whatever the state file holds, so new keys appear
    # automatically on old installs. An unparseable state file (for example a
    # write torn by a crash) falls back to the defaults rather than bricking
    # every command; the next save overwrites the bad file.
    $state = Get-WinmarchyDefaultState
    $statePath = Get-WinmarchyStatePath
    if (Test-Path $statePath) {
        try {
            $fromDisk = ConvertTo-WinmarchyHashtable ([System.IO.File]::ReadAllText($statePath) | ConvertFrom-Json)
            foreach ($key in $fromDisk.Keys) { $state[$key] = $fromDisk[$key] }
        } catch {
            Write-WinmarchyLog -Message ('state file unreadable, using defaults: ' + $_.Exception.Message) -Level 'WARN'
        }
    }
    return $state
}

function Save-WinmarchyState {
    # Written to a temp file first and moved into place, so a crash mid-write
    # can never leave a half-written state file behind.
    param([Parameter(Mandatory = $true)][hashtable]$State)
    $json = $State | ConvertTo-Json -Depth 8
    $statePath = Get-WinmarchyStatePath
    $tempPath = $statePath + '.tmp'
    Write-WinmarchyTextFile -Path $tempPath -Content $json
    Move-Item -Path $tempPath -Destination $statePath -Force
}

function Set-WinmarchyStateValue {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()]$Value
    )
    $state = Get-WinmarchyState
    $state[$Name] = $Value
    Save-WinmarchyState -State $state
}

# ---------------------------------------------------------------------------
# Undo journal
# ---------------------------------------------------------------------------

function Get-WinmarchyJournalPath { return (Join-Path (Get-WinmarchyStateDir) 'journal.jsonl') }

function Add-WinmarchyJournalEntry {
    # Appended BEFORE the mutating action it describes, so an interrupted swap
    # always leaves enough on disk to undo. Data carries the previous values
    # needed to reverse the action.
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [hashtable]$Data = @{}
    )
    $entry = @{
        ts     = (Get-Date -Format 'o')
        action = $Action
        data   = $Data
    }
    $line = ($entry | ConvertTo-Json -Depth 8 -Compress) + [Environment]::NewLine
    $journalPath = Get-WinmarchyJournalPath
    $parent = Split-Path -Parent $journalPath
    if (-not (Test-Path $parent)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::AppendAllText($journalPath, $line, $encoding)
}

function Get-WinmarchyJournalEntries {
    # Oldest first, as written. Repair replays these in reverse. A torn final
    # line (crash mid-append) is skipped with a warning so the intact entries
    # are still replayable; the journal exists precisely for crash recovery.
    $journalPath = Get-WinmarchyJournalPath
    $entries = @()
    if (Test-Path $journalPath) {
        foreach ($line in [System.IO.File]::ReadAllLines($journalPath)) {
            if ($line.Trim() -eq '') { continue }
            try {
                $entries = $entries + @(, ($line | ConvertFrom-Json))
            } catch {
                Write-WinmarchyLog -Message ('journal line unparseable, skipped: ' + $line) -Level 'WARN'
            }
        }
    }
    # Plain return: every caller collects with @(...), which needs the
    # elements enumerated, not a wrapped array.
    return $entries
}

function Clear-WinmarchyJournal {
    $journalPath = Get-WinmarchyJournalPath
    if (Test-Path $journalPath) { Remove-Item -Path $journalPath -Force }
}

function Test-WinmarchyJournalPending {
    return (@(Get-WinmarchyJournalEntries).Count -gt 0)
}
