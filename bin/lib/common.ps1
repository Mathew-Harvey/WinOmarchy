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
    # Match, not member enumeration over .Name: enumerating a property across
    # an EMPTY collection throws under strict mode.
    return ($InputObject.PSObject.Properties.Match($Name).Count -gt 0)
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

    # What the user had before we touched anything, so entering Windows 11
    # mode can put the terminal back exactly. $null means "the key was absent",
    # which restore honours by removing the key rather than writing a value.
    $originalColorScheme = $null
    $originalFontFace = $null
    if ((Test-PsObjectProperty $settings 'profiles') -and ($null -ne $settings.profiles) -and (-not ($settings.profiles -is [System.Array]))) {
        if ((Test-PsObjectProperty $settings.profiles 'defaults') -and ($null -ne $settings.profiles.defaults)) {
            if (Test-PsObjectProperty $settings.profiles.defaults 'colorScheme') {
                $originalColorScheme = $settings.profiles.defaults.colorScheme
            }
            if ((Test-PsObjectProperty $settings.profiles.defaults 'font') -and ($null -ne $settings.profiles.defaults.font)) {
                if (Test-PsObjectProperty $settings.profiles.defaults.font 'face') {
                    $originalFontFace = $settings.profiles.defaults.font.face
                }
            }
        }
    }

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
        Path                 = $Path
        BackupCreated        = $backupCreated
        SchemeName           = $scheme.name
        FontSet              = [bool]$SetFontFace
        OriginalColorScheme  = $originalColorScheme
        OriginalFontFace     = $originalFontFace
    }
}

function Restore-WtSettingsFile {
    # Undoes everything Update-WtSettingsFile did: drops every Winmarchy
    # scheme and puts profiles.defaults.colorScheme and font.face back to the
    # values captured before the first patch. A $null original means the key
    # was not there, so it is removed rather than set. Leaves every other
    # setting, including ones added since, untouched.
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowNull()][string]$OriginalColorScheme,
        [AllowNull()][string]$OriginalFontFace
    )
    if (-not (Test-Path $Path)) { return $false }
    $settings = ConvertFrom-WtSettingsJson -RawText ([System.IO.File]::ReadAllText($Path))
    $changed = $false

    if ((Test-PsObjectProperty $settings 'schemes') -and ($null -ne $settings.schemes)) {
        $kept = @()
        foreach ($scheme in @($settings.schemes)) {
            if ($null -ne $scheme -and $scheme.name -like 'Winmarchy *') {
                $changed = $true
            } else {
                $kept = $kept + @(, $scheme)
            }
        }
        if ($changed) { Set-PsObjectProperty $settings 'schemes' $kept }
    }

    if ((Test-PsObjectProperty $settings 'profiles') -and ($null -ne $settings.profiles) -and (-not ($settings.profiles -is [System.Array]))) {
        if ((Test-PsObjectProperty $settings.profiles 'defaults') -and ($null -ne $settings.profiles.defaults)) {
            $defaults = $settings.profiles.defaults
            if ((Test-PsObjectProperty $defaults 'colorScheme') -and ($defaults.colorScheme -like 'Winmarchy *')) {
                if ($OriginalColorScheme) {
                    Set-PsObjectProperty $defaults 'colorScheme' $OriginalColorScheme
                } else {
                    $defaults.PSObject.Properties.Remove('colorScheme')
                }
                $changed = $true
            }
            if ((Test-PsObjectProperty $defaults 'font') -and ($null -ne $defaults.font)) {
                if ((Test-PsObjectProperty $defaults.font 'face') -and ($defaults.font.face -eq 'JetBrainsMono Nerd Font')) {
                    if ($OriginalFontFace) {
                        Set-PsObjectProperty $defaults.font 'face' $OriginalFontFace
                    } else {
                        $defaults.font.PSObject.Properties.Remove('face')
                    }
                    $changed = $true
                }
            }
        }
    }

    if ($changed) {
        Write-WinmarchyTextFile -Path $Path -Content ($settings | ConvertTo-Json -Depth 64)
    }
    return $changed
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
        savedWtColorScheme        = $null
        savedWtFontFace           = $null
        savedWtCaptured           = $false
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

# ---------------------------------------------------------------------------
# Runtime path helpers for deployed configuration surfaces
# ---------------------------------------------------------------------------

function Get-WinmarchyUserProfile {
    # WINMARCHY_USERPROFILE overrides for tests; USERPROFILE on Windows;
    # HOME as the last resort for the Linux build container.
    if ($env:WINMARCHY_USERPROFILE) { return $env:WINMARCHY_USERPROFILE }
    if ($env:USERPROFILE) { return $env:USERPROFILE }
    if ($env:HOME) { return $env:HOME }
    throw 'No user profile directory could be resolved.'
}

function Get-WinmarchyGlazewmConfigPath {
    return (Join-Path (Get-WinmarchyUserProfile) (Join-Path '.glzr' (Join-Path 'glazewm' 'config.yaml')))
}

function Get-WinmarchyYasbConfigDir {
    return (Join-Path (Get-WinmarchyUserProfile) (Join-Path '.config' 'yasb'))
}

function Get-WinmarchyYasbStylesTemplatePath {
    # Lives under <root>/config/yasb both in the repo and in the deployed
    # layout (install.ps1 copies config/ alongside bin/, themes/, templates/).
    return (Join-Path (Get-WinmarchyRepoRoot) (Join-Path 'config' (Join-Path 'yasb' 'styles.template.css')))
}

function Get-WinmarchyNvimConfigDir {
    if ($env:WINMARCHY_NVIM_DIR) { return $env:WINMARCHY_NVIM_DIR }
    if ($env:LOCALAPPDATA) { return (Join-Path $env:LOCALAPPDATA 'nvim') }
    return (Join-Path (Get-WinmarchyUserProfile) 'nvim')
}

function Update-WinmarchyGlazewmBorders {
    # Pure text transform: swaps the hex colours on the two marker-comment
    # lines of the GlazeWM config (focused border = accent, other border =
    # muted). Idempotent; lines without the markers are untouched.
    param(
        [Parameter(Mandatory = $true)][string]$ConfigText,
        [Parameter(Mandatory = $true)]$Theme
    )
    $result = [regex]::Replace($ConfigText, "color: '#[0-9a-fA-F]{6}' # winmarchy:focused-border", ("color: '" + $Theme.colors.accent + "' # winmarchy:focused-border"))
    $result = [regex]::Replace($result, "color: '#[0-9a-fA-F]{6}' # winmarchy:other-border", ("color: '" + $Theme.colors.muted + "' # winmarchy:other-border"))
    return $result
}

# ---------------------------------------------------------------------------
# Operating system effectors. Windows-only; every function here is a plain
# boundary the tests mock. Native API facts are cited where used.
# ---------------------------------------------------------------------------

function Test-WinmarchyIsWindows {
    # $IsWindows does not exist on Windows PowerShell 5.1; the OS env var
    # does and is always Windows_NT there.
    return ($env:OS -eq 'Windows_NT')
}

function Assert-WinmarchyWindows {
    param([string]$Operation)
    if (-not (Test-WinmarchyIsWindows)) {
        throw ($Operation + ' requires Windows.')
    }
}

function Initialize-WinmarchyNativeMethods {
    # P/Invoke declarations, compiled once per session.
    # SHAppBarMessage: shell32, documented at
    # learn.microsoft.com/en-us/windows/win32/api/shellapi/nf-shellapi-shappbarmessage
    # (ABM_GETSTATE 0x4, ABM_SETSTATE 0xA, ABS_AUTOHIDE 0x1).
    # FindWindow/FindWindowEx/SendMessage and SystemParametersInfo: user32,
    # documented under learn.microsoft.com/en-us/windows/win32/api/winuser/.
    # The desktop icon toggle (WM_COMMAND 0x7402 to SHELLDLL_DefView) and the
    # SPI_SETDESKWALLPAPER call are the techniques named in the build brief
    # Sections 3 and 5.
    if ('Winmarchy.NativeMethods' -as [type]) { return }
    $source = @'
using System;
using System.Runtime.InteropServices;

namespace Winmarchy
{
    [StructLayout(LayoutKind.Sequential)]
    public struct AppBarRect
    {
        public int left;
        public int top;
        public int right;
        public int bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct AppBarData
    {
        public int cbSize;
        public IntPtr hWnd;
        public uint uCallbackMessage;
        public uint uEdge;
        public AppBarRect rc;
        public IntPtr lParam;
    }

    public static class NativeMethods
    {
        [DllImport("shell32.dll")]
        public static extern UIntPtr SHAppBarMessage(uint dwMessage, ref AppBarData pData);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr childAfter, string className, string windowName);

        [DllImport("user32.dll")]
        public static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, string pvParam, uint fWinIni);
    }
}
'@
    Add-Type -TypeDefinition $source -Language CSharp
}

function Get-WinmarchyTaskbarAutoHide {
    Assert-WinmarchyWindows -Operation 'Taskbar state query'
    Initialize-WinmarchyNativeMethods
    $data = New-Object Winmarchy.AppBarData
    $data.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($data)
    # ABM_GETSTATE = 0x4; result bit 0x1 = ABS_AUTOHIDE.
    $state = [Winmarchy.NativeMethods]::SHAppBarMessage(4, [ref]$data)
    return (([uint64]$state -band 1) -eq 1)
}

function Set-WinmarchyTaskbarAutoHide {
    param([Parameter(Mandatory = $true)][bool]$Enabled)
    Assert-WinmarchyWindows -Operation 'Taskbar state change'
    Initialize-WinmarchyNativeMethods
    $data = New-Object Winmarchy.AppBarData
    $data.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($data)
    $current = [uint64][Winmarchy.NativeMethods]::SHAppBarMessage(4, [ref]$data)
    $newState = $current
    if ($Enabled) {
        $newState = $current -bor 1
    } else {
        $newState = $current -band (-bnot [uint64]1)
    }
    $data2 = New-Object Winmarchy.AppBarData
    $data2.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($data2)
    $data2.lParam = [IntPtr]$newState
    # ABM_SETSTATE = 0xA.
    $null = [Winmarchy.NativeMethods]::SHAppBarMessage(10, [ref]$data2)
    Write-WinmarchyLog -Message ('taskbar auto-hide set to ' + $Enabled)
}

function Get-WinmarchyDesktopIconsVisible {
    Assert-WinmarchyWindows -Operation 'Desktop icon state query'
    # HideIcons DWORD under the Explorer Advanced key; 0 or absent = visible.
    $advancedKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $value = Get-ItemProperty -Path $advancedKey -Name 'HideIcons' -ErrorAction SilentlyContinue
    if ($null -eq $value) { return $true }
    return ($value.HideIcons -eq 0)
}

function Set-WinmarchyDesktopIcons {
    param([Parameter(Mandatory = $true)][bool]$Visible)
    Assert-WinmarchyWindows -Operation 'Desktop icon toggle'
    Initialize-WinmarchyNativeMethods
    $currentlyVisible = Get-WinmarchyDesktopIconsVisible
    if ($currentlyVisible -eq $Visible) { return }

    # Live toggle: WM_COMMAND (0x111) with id 0x7402 to SHELLDLL_DefView.
    # This is a blind toggle, which is why the registry state is read first.
    $defView = [IntPtr]::Zero
    $progman = [Winmarchy.NativeMethods]::FindWindow('Progman', $null)
    if ($progman -ne [IntPtr]::Zero) {
        $defView = [Winmarchy.NativeMethods]::FindWindowEx($progman, [IntPtr]::Zero, 'SHELLDLL_DefView', $null)
    }
    if ($defView -eq [IntPtr]::Zero) {
        # Wallpaper-slideshow arrangement: the DefView lives under a WorkerW.
        $worker = [IntPtr]::Zero
        do {
            $worker = [Winmarchy.NativeMethods]::FindWindowEx([IntPtr]::Zero, $worker, 'WorkerW', $null)
            if ($worker -ne [IntPtr]::Zero) {
                $defView = [Winmarchy.NativeMethods]::FindWindowEx($worker, [IntPtr]::Zero, 'SHELLDLL_DefView', $null)
            }
        } while ($defView -eq [IntPtr]::Zero -and $worker -ne [IntPtr]::Zero)
    }

    $advancedKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $hideValue = 1
    if ($Visible) { $hideValue = 0 }

    if ($defView -ne [IntPtr]::Zero) {
        $null = [Winmarchy.NativeMethods]::SendMessage($defView, 0x111, [IntPtr]0x7402, [IntPtr]::Zero)
        # Persist the state so a later Explorer restart agrees with reality.
        Set-ItemProperty -Path $advancedKey -Name 'HideIcons' -Value $hideValue -Type DWord
        Write-WinmarchyLog -Message ('desktop icons toggled live, visible=' + $Visible)
    } else {
        # Fallback from the brief Section 3: registry plus Explorer restart.
        Set-ItemProperty -Path $advancedKey -Name 'HideIcons' -Value $hideValue -Type DWord
        Restart-WinmarchyExplorer
        Write-WinmarchyLog -Message ('desktop icons set via registry fallback, visible=' + $Visible) -Level 'WARN'
    }
}

function Restart-WinmarchyExplorer {
    Assert-WinmarchyWindows -Operation 'Explorer restart'
    Write-WinmarchyLog -Message 'restarting explorer' -Level 'WARN'
    Stop-Process -Name 'explorer' -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (-not (Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)) {
        Start-Process 'explorer.exe'
    }
}

function Get-WinmarchyCurrentWallpaper {
    Assert-WinmarchyWindows -Operation 'Wallpaper query'
    $value = Get-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'WallPaper' -ErrorAction SilentlyContinue
    if ($null -eq $value) { return $null }
    return $value.WallPaper
}

function Set-WinmarchyWallpaper {
    param([Parameter(Mandatory = $true)][string]$Path)
    Assert-WinmarchyWindows -Operation 'Wallpaper change'
    Initialize-WinmarchyNativeMethods
    # SPI_SETDESKWALLPAPER = 0x14; SPIF_UPDATEINIFILE 0x1 + SPIF_SENDCHANGE 0x2.
    $ok = [Winmarchy.NativeMethods]::SystemParametersInfo(0x14, 0, $Path, 3)
    if (-not $ok) {
        throw ('SystemParametersInfo failed setting wallpaper to ' + $Path)
    }
    Write-WinmarchyLog -Message ('wallpaper set to ' + $Path)
}

function Get-WinmarchyAppsTheme {
    Assert-WinmarchyWindows -Operation 'App theme query'
    $personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    $apps = 1
    $system = 1
    $appsValue = Get-ItemProperty -Path $personalize -Name 'AppsUseLightTheme' -ErrorAction SilentlyContinue
    if ($null -ne $appsValue) { $apps = $appsValue.AppsUseLightTheme }
    $systemValue = Get-ItemProperty -Path $personalize -Name 'SystemUsesLightTheme' -ErrorAction SilentlyContinue
    if ($null -ne $systemValue) { $system = $systemValue.SystemUsesLightTheme }
    return [pscustomobject]@{ AppsUseLightTheme = $apps; SystemUsesLightTheme = $system }
}

function Set-WinmarchyAppsTheme {
    param(
        [Parameter(Mandatory = $true)][int]$AppsUseLightTheme,
        [Parameter(Mandatory = $true)][int]$SystemUsesLightTheme
    )
    Assert-WinmarchyWindows -Operation 'App theme change'
    $personalize = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    if (-not (Test-Path $personalize)) {
        $null = New-Item -Path $personalize -Force
    }
    Set-ItemProperty -Path $personalize -Name 'AppsUseLightTheme' -Value $AppsUseLightTheme -Type DWord
    Set-ItemProperty -Path $personalize -Name 'SystemUsesLightTheme' -Value $SystemUsesLightTheme -Type DWord
    Write-WinmarchyLog -Message ('app theme set: apps=' + $AppsUseLightTheme + ' system=' + $SystemUsesLightTheme)
}

function New-WinmarchyWallpaperImage {
    # Generates the themed wallpaper: 2560x1440, vertical three-stop gradient
    # (darker_background to background to lighter_background) with a soft
    # accent glow ellipse at roughly 12 percent alpha in the lower right.
    # System.Drawing (GDI+) ships with .NET Framework on Windows.
    param(
        [Parameter(Mandatory = $true)]$Theme,
        [Parameter(Mandatory = $true)][string]$Path
    )
    Assert-WinmarchyWindows -Operation 'Wallpaper generation'
    Add-Type -AssemblyName System.Drawing

    $width = 2560
    $height = 1440
    $bitmap = New-Object System.Drawing.Bitmap($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $rect = New-Object System.Drawing.Rectangle(0, 0, $width, $height)
        $top = [System.Drawing.ColorTranslator]::FromHtml($Theme.colors.darker_background)
        $mid = [System.Drawing.ColorTranslator]::FromHtml($Theme.colors.background)
        $bottom = [System.Drawing.ColorTranslator]::FromHtml($Theme.colors.lighter_background)

        $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $top, $bottom, [System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
        $blend = New-Object System.Drawing.Drawing2D.ColorBlend(3)
        $blend.Colors = @($top, $mid, $bottom)
        $blend.Positions = [single[]]@(0.0, 0.55, 1.0)
        $brush.InterpolationColors = $blend
        $graphics.FillRectangle($brush, $rect)
        $brush.Dispose()

        # Accent glow, centred in the lower right.
        $glowWidth = 1700
        $glowHeight = 1200
        $glowX = [int]($width * 0.72) - [int]($glowWidth / 2)
        $glowY = [int]($height * 0.88) - [int]($glowHeight / 2)
        $glowPath = New-Object System.Drawing.Drawing2D.GraphicsPath
        $glowPath.AddEllipse($glowX, $glowY, $glowWidth, $glowHeight)
        $glowBrush = New-Object System.Drawing.Drawing2D.PathGradientBrush($glowPath)
        $accent = [System.Drawing.ColorTranslator]::FromHtml($Theme.colors.accent)
        # 12 percent alpha of 255 is 31.
        $glowBrush.CenterColor = [System.Drawing.Color]::FromArgb(31, $accent)
        $glowBrush.SurroundColors = @([System.Drawing.Color]::FromArgb(0, $accent))
        $graphics.FillPath($glowBrush, $glowPath)
        $glowBrush.Dispose()
        $glowPath.Dispose()

        $parent = Split-Path -Parent $Path
        if ($parent -and -not (Test-Path $parent)) {
            $null = New-Item -ItemType Directory -Path $parent -Force
        }
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
        Write-WinmarchyLog -Message ('wallpaper generated at ' + $Path)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

# ---------------------------------------------------------------------------
# Process and executable helpers
# ---------------------------------------------------------------------------

function Test-WinmarchyProcessRunning {
    param([Parameter(Mandatory = $true)][string]$Name)
    return ($null -ne (Get-Process -Name $Name -ErrorAction SilentlyContinue))
}

function Find-WinmarchyExecutable {
    # PATH first via Get-Command (winget puts both tools on PATH), then a
    # best-effort search of standard install directories.
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string[]]$FallbackPaths = @()
    )
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $candidates = @($FallbackPaths)
    if ($env:ProgramFiles) {
        $candidates = $candidates + (Join-Path $env:ProgramFiles (Join-Path 'glzr.io' (Join-Path 'GlazeWM' ($Name + '.exe'))))
        $candidates = $candidates + (Join-Path $env:ProgramFiles (Join-Path 'Yasb' ($Name + '.exe')))
    }
    if ($env:LOCALAPPDATA) {
        $candidates = $candidates + (Join-Path $env:LOCALAPPDATA (Join-Path 'Programs' (Join-Path 'glzr.io' (Join-Path 'GlazeWM' ($Name + '.exe')))))
        $candidates = $candidates + (Join-Path $env:LOCALAPPDATA (Join-Path 'Yasb' ($Name + '.exe')))
    }
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}

function Invoke-WinmarchyGlazewmCommand {
    # Runs "glazewm command <cmd>", the documented CLI for driving a running
    # GlazeWM instance (verified against the GlazeWM AppCommand surface in
    # ref/glazewm/packages/wm-common/src/app_command.rs).
    param([Parameter(Mandatory = $true)][string]$Command)
    $exe = Find-WinmarchyExecutable -Name 'glazewm'
    if (-not $exe) { throw 'glazewm executable not found' }
    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $exe command $Command 2>&1 | Out-Null
    } finally {
        $ErrorActionPreference = $savedPreference
    }
    if ($LASTEXITCODE -ne 0) {
        throw ('glazewm command ' + $Command + ' exited with ' + $LASTEXITCODE)
    }
}

function Start-WinmarchyGlazewm {
    $exe = Find-WinmarchyExecutable -Name 'glazewm'
    if (-not $exe) { throw 'glazewm executable not found; is GlazeWM installed?' }
    Start-Process -FilePath $exe
}

function Stop-WinmarchyGlazewm {
    # Graceful wm-exit first, then force after five seconds (brief 7.2).
    try {
        Invoke-WinmarchyGlazewmCommand -Command 'wm-exit'
    } catch {
        Write-WinmarchyLog -Message ('glazewm wm-exit failed: ' + $_.Exception.Message) -Level 'WARN'
    }
    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-WinmarchyProcessRunning -Name 'glazewm')) { return }
        Start-Sleep -Milliseconds 250
    }
    if (Test-WinmarchyProcessRunning -Name 'glazewm') {
        Stop-Process -Name 'glazewm' -Force -ErrorAction SilentlyContinue
        Write-WinmarchyLog -Message 'glazewm force-stopped' -Level 'WARN'
    }
}

function Start-WinmarchyYasb {
    $yasbc = Find-WinmarchyExecutable -Name 'yasbc'
    if (-not $yasbc) { throw 'yasbc executable not found; is yasb installed?' }
    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $yasbc start 2>&1 | Out-Null
    } finally {
        $ErrorActionPreference = $savedPreference
    }
}

function Stop-WinmarchyYasb {
    $yasbc = Find-WinmarchyExecutable -Name 'yasbc'
    if ($yasbc) {
        $savedPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $yasbc stop 2>&1 | Out-Null
        } finally {
            $ErrorActionPreference = $savedPreference
        }
    }
    $deadline = (Get-Date).AddSeconds(5)
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-WinmarchyProcessRunning -Name 'yasb')) { return }
        Start-Sleep -Milliseconds 250
    }
    if (Test-WinmarchyProcessRunning -Name 'yasb') {
        Stop-Process -Name 'yasb' -Force -ErrorAction SilentlyContinue
        Write-WinmarchyLog -Message 'yasb force-stopped' -Level 'WARN'
    }
}

function Start-WinmarchyFlowLauncher {
    $candidates = @()
    if ($env:LOCALAPPDATA) {
        $candidates = $candidates + (Join-Path $env:LOCALAPPDATA (Join-Path 'FlowLauncher' 'Flow.Launcher.exe'))
    }
    $exe = Find-WinmarchyExecutable -Name 'Flow.Launcher' -FallbackPaths $candidates
    if ($exe) {
        Start-Process -FilePath $exe
    } else {
        Write-WinmarchyLog -Message 'Flow Launcher not found; skipped' -Level 'WARN'
    }
}

function Test-WinmarchyTcpPortOpen {
    # One-second connect probe used for the GlazeWM IPC health check
    # (ws://localhost:6123, brief Section 4.2).
    param(
        [string]$TargetHost = 'localhost',
        [Parameter(Mandatory = $true)][int]$Port
    )
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($TargetHost, $Port, $null, $null)
        $completed = $async.AsyncWaitHandle.WaitOne(1000)
        if ($completed -and $client.Connected) {
            $client.EndConnect($async)
            return $true
        }
        return $false
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Wait-WinmarchyOmarchyHealthy {
    # Healthy means: GlazeWM process alive AND IPC port 6123 connectable AND
    # yasb process alive (brief 7.2). Polls once a second.
    param([int]$TimeoutSeconds = 20)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $glazeAlive = Test-WinmarchyProcessRunning -Name 'glazewm'
        $ipcAlive = Test-WinmarchyTcpPortOpen -Port 6123
        $yasbAlive = Test-WinmarchyProcessRunning -Name 'yasb'
        if ($glazeAlive -and $ipcAlive -and $yasbAlive) { return $true }
        Start-Sleep -Seconds 1
    }
    return $false
}

# ---------------------------------------------------------------------------
# Autostart Run key
# ---------------------------------------------------------------------------

function Test-WinmarchyRunKeyPresent {
    if (-not (Test-WinmarchyIsWindows)) { return $false }
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $value = Get-ItemProperty -Path $runKey -Name 'Winmarchy' -ErrorAction SilentlyContinue
    return ($null -ne $value)
}

function Set-WinmarchyRunKey {
    param([Parameter(Mandatory = $true)][string]$Command)
    Assert-WinmarchyWindows -Operation 'Run key registration'
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    Set-ItemProperty -Path $runKey -Name 'Winmarchy' -Value $Command
    Write-WinmarchyLog -Message ('run key set to ' + $Command)
}

function Remove-WinmarchyRunKey {
    if (-not (Test-WinmarchyIsWindows)) { return }
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    Remove-ItemProperty -Path $runKey -Name 'Winmarchy' -ErrorAction SilentlyContinue
    Write-WinmarchyLog -Message 'run key removed'
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

function Get-WinmarchyPreflight {
    # One source of truth for "can this machine take an install", used by both
    # install.ps1 (which refuses to run past a blocking failure) and the setup
    # wizard (which renders the same rows as a checklist). Read-only.
    # Rows: Name, Pass, Blocking, Detail.
    param(
        [switch]$SkipApps
    )

    function New-WinmarchyPreflightRow {
        param([string]$Name, [bool]$Pass, [bool]$Blocking, [string]$Detail)
        return [pscustomobject]@{ Name = $Name; Pass = $Pass; Blocking = $Blocking; Detail = $Detail }
    }

    $rows = @()
    $onWindows = Test-WinmarchyIsWindows

    # Windows 11 is build 22000 or later. Off Windows the row is informational
    # so the wizard and tests still run in a build container.
    if ($onWindows) {
        $build = [System.Environment]::OSVersion.Version.Build
        $detail = 'build ' + $build
        if ($build -lt 22000) { $detail = $detail + '; Windows 11 (22000 or later) is required, Windows 10 is out of scope' }
        $rows = $rows + (New-WinmarchyPreflightRow 'Windows 11' ($build -ge 22000) $true $detail)
    } else {
        $rows = $rows + (New-WinmarchyPreflightRow 'Windows 11' $true $false 'not running on Windows; Windows-only steps will be skipped')
    }

    # winget: only blocking when the app installs are actually wanted.
    $hasWinget = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
    $wingetDetail = 'found'
    if (-not $hasWinget) {
        $wingetDetail = 'not found; install App Installer from https://apps.microsoft.com/detail/9NBLGGH4NNS1 or clear the app-install option'
    }
    $wingetBlocking = ((-not $SkipApps) -and $onWindows)
    $rows = $rows + (New-WinmarchyPreflightRow 'winget' $hasWinget $wingetBlocking $wingetDetail)

    # dotnet SDK: only needed to build the login chooser, never blocking.
    $hasDotnet = $null -ne (Get-Command dotnet -ErrorAction SilentlyContinue)
    $dotnetDetail = 'found; the login chooser can be built'
    if (-not $hasDotnet) {
        $dotnetDetail = 'not found; skip the chooser or install the .NET 8 SDK, everything else still works'
    }
    $rows = $rows + (New-WinmarchyPreflightRow '.NET 8 SDK' $hasDotnet $false $dotnetDetail)

    # Disk space on the install drive.
    try {
        $root = [System.IO.Path]::GetPathRoot((Get-WinmarchyHome))
        $driveInfo = New-Object System.IO.DriveInfo($root)
        $freeGb = [math]::Round($driveInfo.AvailableFreeSpace / 1GB, 1)
        $rows = $rows + (New-WinmarchyPreflightRow 'Disk space' ($freeGb -ge 2) $true ($freeGb.ToString() + ' GB free on ' + $root + '; 2 GB needed'))
    } catch {
        $rows = $rows + (New-WinmarchyPreflightRow 'Disk space' $true $false 'could not be determined; continuing')
    }

    # Informational rows: what is already on the machine.
    $installed = Test-Path (Join-Path (Get-WinmarchyHome) 'bin')
    $installedDetail = 'no existing install; this will be a fresh setup'
    if ($installed) { $installedDetail = 'Winmarchy is already installed; this run will update it, taking fresh backups first' }
    $rows = $rows + (New-WinmarchyPreflightRow 'Existing install' $true $false $installedDetail)

    $hasNvim = Test-Path (Get-WinmarchyNvimConfigDir)
    $nvimDetail = 'no Neovim config; the LazyVim starter can be set up for you'
    if ($hasNvim) { $nvimDetail = 'your Neovim config exists and will be left completely untouched' }
    $rows = $rows + (New-WinmarchyPreflightRow 'Neovim config' $true $false $nvimDetail)

    $wtPath = Get-WtSettingsPath
    $wtDetail = 'Windows Terminal has never run; terminal theming will be skipped'
    if ($wtPath) { $wtDetail = 'found; the original settings are backed up before the first patch' }
    $rows = $rows + (New-WinmarchyPreflightRow 'Windows Terminal' $true $false $wtDetail)

    return $rows
}

function Get-WinmarchyNvimThemePath {
    return (Join-Path (Get-WinmarchyNvimConfigDir) (Join-Path 'lua' (Join-Path 'plugins' 'winmarchy-theme.lua')))
}

function Remove-WinmarchyNvimTheme {
    # Winmarchy owns this file entirely, so removing it returns Neovim to
    # whatever colourscheme it used before Omarchy mode.
    $path = Get-WinmarchyNvimThemePath
    if (Test-Path $path) {
        Remove-Item -Path $path -Force
        Write-WinmarchyLog -Message 'nvim theme removed'
        return $true
    }
    return $false
}
