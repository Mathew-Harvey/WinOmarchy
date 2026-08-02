# check.ps1: the machine gate for the Winmarchy repo.
# Runs, in order: forbidden-character scan, PSScriptAnalyzer, Pester, YAML and
# JSON parse of configs and themes, a Windows PowerShell 5.1 compatibility grep,
# an unresolved template token scan over rendered artefacts, and a task-marker
# scan tied to FLAGS.md. Exits non-zero on any failure.
# Compatible with Windows PowerShell 5.1 and PowerShell 7.
# Several search patterns below are built from character codes at runtime so this
# file does not trip its own scans.

[CmdletBinding()]
param(
    [switch]$SkipPester
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$script:failCount = 0

function Write-Section {
    param([string]$Name)
    Write-Host ''
    Write-Host ('== ' + $Name + ' ==') -ForegroundColor Cyan
}

function Write-Failure {
    param([string]$Message)
    $script:failCount = $script:failCount + 1
    Write-Host ('FAIL: ' + $Message) -ForegroundColor Red
}

function Write-Pass {
    param([string]$Message)
    Write-Host ('PASS: ' + $Message) -ForegroundColor Green
}

# ReadAllLines wrapped so one unreadable file (dangling symlink, lock) counts
# as a failure without aborting the remaining checks.
function Read-FileLinesSafe {
    param([string]$Path)
    try {
        return [System.IO.File]::ReadAllLines($Path)
    } catch {
        Write-Failure ('unreadable file: ' + $Path + ' (' + $_.Exception.Message + ')')
        return $null
    }
}

# Repo files with ref/, .git/, artifacts/ and chooser build output excluded.
# -Force so dot-prefixed files are scanned on Linux exactly as on Windows.
function Get-RepoFile {
    Get-ChildItem -Path $repoRoot -Recurse -File -Force | Where-Object {
        $rel = $_.FullName.Substring($repoRoot.Length + 1) -replace '\\', '/'
        $excluded = $false
        if ($rel -like 'ref/*') { $excluded = $true }
        if ($rel -like '.git/*') { $excluded = $true }
        if ($rel -like 'artifacts/*') { $excluded = $true }
        if ($rel -like 'chooser/bin/*') { $excluded = $true }
        if ($rel -like 'chooser/obj/*') { $excluded = $true }
        -not $excluded
    }
}

# ---------------------------------------------------------------------------
# 1. Forbidden characters: em dash U+2014 and en dash U+2013, banned repo-wide.
# ---------------------------------------------------------------------------
Write-Section 'Forbidden characters (em dash, en dash)'

$emDash = [char]0x2014
$enDash = [char]0x2013
$binaryExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.ico', '.dll', '.exe', '.pdb', '.zip', '.gz', '.woff', '.woff2', '.ttf')
$dashHits = 0

foreach ($file in Get-RepoFile) {
    if ($binaryExtensions -contains $file.Extension.ToLower()) { continue }
    # ReadAllLines auto-detects BOMs and defaults to UTF-8, on both 5.1 and 7.
    $lines = Read-FileLinesSafe $file.FullName
    if ($null -eq $lines) { continue }
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $hasEm = $lines[$i].IndexOf($emDash) -ge 0
        $hasEn = $lines[$i].IndexOf($enDash) -ge 0
        if ($hasEm -or $hasEn) {
            Write-Failure ('forbidden dash character in ' + $file.FullName + ' line ' + ($i + 1))
            $dashHits = $dashHits + 1
        }
    }
}
if ($dashHits -eq 0) { Write-Pass 'no em or en dashes found' }

# ---------------------------------------------------------------------------
# 2. PSScriptAnalyzer: zero errors tolerated, warnings reported for information.
# ---------------------------------------------------------------------------
Write-Section 'PSScriptAnalyzer'

$psFiles = @(Get-RepoFile | Where-Object { @('.ps1', '.psm1', '.psd1') -contains $_.Extension.ToLower() })
if ($psFiles.Count -eq 0) {
    Write-Pass 'no PowerShell files yet'
} elseif (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
    Write-Failure 'PSScriptAnalyzer not installed. Run: Install-Module PSScriptAnalyzer -Force'
} else {
    Import-Module PSScriptAnalyzer
    $allIssues = @()
    foreach ($psFile in $psFiles) {
        $allIssues = $allIssues + @(Invoke-ScriptAnalyzer -Path $psFile.FullName)
    }
    $saErrors = @($allIssues | Where-Object { $_.Severity -eq 'Error' })
    $saWarnings = @($allIssues | Where-Object { $_.Severity -eq 'Warning' })
    foreach ($issue in $saErrors) {
        Write-Failure ('PSSA error ' + $issue.RuleName + ' in ' + $issue.ScriptName + ' line ' + $issue.Line + ': ' + $issue.Message)
    }
    foreach ($issue in $saWarnings) {
        Write-Host ('  warn: ' + $issue.RuleName + ' in ' + $issue.ScriptName + ' line ' + $issue.Line) -ForegroundColor Yellow
    }
    if ($saErrors.Count -eq 0) {
        Write-Pass ('no analyser errors across ' + $psFiles.Count + ' files (' + $saWarnings.Count + ' warnings)')
    }
}

# ---------------------------------------------------------------------------
# 3. Pester
# ---------------------------------------------------------------------------
Write-Section 'Pester'

$testFiles = @()
if (Test-Path (Join-Path $repoRoot 'tests')) {
    $testFiles = @(Get-ChildItem -Path (Join-Path $repoRoot 'tests') -Recurse -File -Filter '*.Tests.ps1')
}
if ($SkipPester) {
    Write-Host '  skipped by request' -ForegroundColor Yellow
} elseif ($testFiles.Count -eq 0) {
    Write-Pass 'no test files yet'
} else {
    $pesterModule = Get-Module -ListAvailable Pester | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $pesterModule) {
        Write-Failure 'Pester not installed. Run: Install-Module Pester -Force -SkipPublisherCheck'
    } elseif ($pesterModule.Version.Major -lt 5) {
        Write-Failure ('Pester ' + $pesterModule.Version + ' is too old; version 5 or newer is required. Run: Install-Module Pester -Force -SkipPublisherCheck')
    } else {
        Import-Module Pester -MinimumVersion 5.0
        $pesterConfig = New-PesterConfiguration
        $pesterConfig.Run.Path = (Join-Path $repoRoot 'tests')
        $pesterConfig.Run.PassThru = $true
        $pesterConfig.Output.Verbosity = 'Normal'
        $pesterResult = Invoke-Pester -Configuration $pesterConfig
        # A test FILE that fails to parse or whose setup dies never runs its
        # tests, so FailedCount alone can report green while a whole container
        # silently vanished. That happened once, for real.
        $brokenContainers = @($pesterResult.Containers | Where-Object { $_.Result -eq 'Failed' -and $_.TotalCount -eq 0 })
        if ($brokenContainers.Count -gt 0) {
            Write-Failure ($brokenContainers.Count.ToString() + ' Pester test file(s) failed to load, so their tests never ran')
            foreach ($container in $brokenContainers) {
                Write-Host ('  broken: ' + $container.Item) -ForegroundColor Red
            }
        }
        if ($pesterResult.FailedCount -gt 0) {
            Write-Failure ($pesterResult.FailedCount.ToString() + ' of ' + $pesterResult.TotalCount + ' Pester tests failed')
            foreach ($failed in $pesterResult.Failed) {
                Write-Host ('  failed: ' + $failed.ExpandedPath) -ForegroundColor Red
            }
        } elseif ($brokenContainers.Count -eq 0) {
            Write-Pass ($pesterResult.PassedCount.ToString() + ' Pester tests passed')
        }
    }
}

# ---------------------------------------------------------------------------
# 4. YAML and JSON parse of every config and theme
# ---------------------------------------------------------------------------
Write-Section 'Config and theme parsing'

$yamlFiles = @()
if (Test-Path (Join-Path $repoRoot 'config')) {
    $yamlFiles = @(Get-ChildItem -Path (Join-Path $repoRoot 'config') -Recurse -File | Where-Object { @('.yaml', '.yml') -contains $_.Extension.ToLower() })
}
$themeFiles = @()
if (Test-Path (Join-Path $repoRoot 'themes')) {
    $themeFiles = @(Get-ChildItem -Path (Join-Path $repoRoot 'themes') -Filter '*.json' -File)
}

if (($yamlFiles.Count + $themeFiles.Count) -eq 0) {
    Write-Pass 'no configs or themes yet'
}

$parseFailures = 0
foreach ($themeFile in $themeFiles) {
    try {
        $null = [System.IO.File]::ReadAllText($themeFile.FullName) | ConvertFrom-Json
    } catch {
        Write-Failure ('JSON parse failed for ' + $themeFile.FullName + ': ' + $_.Exception.Message)
        $parseFailures = $parseFailures + 1
    }
}

if ($yamlFiles.Count -gt 0) {
    # YAML parser resolution: powershell-yaml module first, then Python with
    # PyYAML, else fail. Recorded as FLAG-3 in FLAGS.md.
    $yamlParser = ''
    if (Get-Module -ListAvailable powershell-yaml) {
        Import-Module powershell-yaml
        $yamlParser = 'powershell-yaml'
    } else {
        $pythonCmd = Get-Command python3 -ErrorAction SilentlyContinue
        if (-not $pythonCmd) { $pythonCmd = Get-Command python -ErrorAction SilentlyContinue }
        if ($pythonCmd) {
            # On Windows PowerShell 5.1, redirected native stderr under
            # ErrorActionPreference Stop raises NativeCommandError, so the
            # preference is relaxed around native calls.
            $savedPreference = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                & $pythonCmd.Source -c 'import yaml' 2>$null
                if ($LASTEXITCODE -eq 0) { $yamlParser = $pythonCmd.Source }
            } finally {
                $ErrorActionPreference = $savedPreference
            }
        }
    }
    if ($yamlParser -eq '') {
        Write-Failure 'no YAML parser available. Run: Install-Module powershell-yaml -Force (or install Python with PyYAML)'
        $parseFailures = $parseFailures + 1
    } else {
        foreach ($yamlFile in $yamlFiles) {
            if ($yamlParser -eq 'powershell-yaml') {
                try {
                    $null = ConvertFrom-Yaml ([System.IO.File]::ReadAllText($yamlFile.FullName))
                } catch {
                    Write-Failure ('YAML parse failed for ' + $yamlFile.FullName + ': ' + $_.Exception.Message)
                    $parseFailures = $parseFailures + 1
                }
            } else {
                $savedPreference = $ErrorActionPreference
                $ErrorActionPreference = 'Continue'
                try {
                    & $yamlParser -c ('import yaml,sys; yaml.safe_load(open(sys.argv[1]))') $yamlFile.FullName 2>&1 | Out-Null
                } finally {
                    $ErrorActionPreference = $savedPreference
                }
                if ($LASTEXITCODE -ne 0) {
                    Write-Failure ('YAML parse failed for ' + $yamlFile.FullName)
                    $parseFailures = $parseFailures + 1
                }
            }
        }
    }
}
if (($yamlFiles.Count + $themeFiles.Count) -gt 0 -and $parseFailures -eq 0) {
    Write-Pass ($themeFiles.Count.ToString() + ' theme files and ' + $yamlFiles.Count + ' YAML configs parse cleanly')
}

# ---------------------------------------------------------------------------
# 5. Windows PowerShell 5.1 compatibility grep
# ---------------------------------------------------------------------------
Write-Section 'PowerShell 5.1 compatibility grep'

# Patterns are assembled from character codes so this file does not flag itself.
$qm = [char]0x3F        # question mark
$amp = [char]0x26       # ampersand
$bar = [char]0x7C       # vertical bar
$nullCoalesce = -join ($qm, $qm)
$andChain = -join ($amp, $amp)
$orChain = -join ($bar, $bar)
# Ternary heuristic: space, question mark, space ... space, colon, space.
$ternaryPattern = ('\s\' + $qm + '\s.+\s:\s')
$outFilePattern = ('Out-' + 'File\b.*-Encoding\s+utf8')
$parallelPattern = ('ForEach-' + 'Object\s+-Parallel')
# Casting a VARIABLE straight to IntPtr: 5.1 cannot convert unsigned integer
# types to IntPtr (PowerShell 7 can, so only the real machine crashes). Cast
# through [int64] first: [IntPtr][int64]$value. Literals ([IntPtr]0x7402) are
# Int32 and are fine. Assembled so this file does not flag itself.
$intPtrCastPattern = ('\[' + 'IntPtr\]\s*\$')

$compatHits = 0
foreach ($psFile in $psFiles) {
    $lines = Read-FileLinesSafe $psFile.FullName
    if ($null -eq $lines) { continue }
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $problems = @()
        if ($line.Contains($nullCoalesce)) { $problems = $problems + 'null-coalescing operator' }
        if ($line.Contains($andChain)) { $problems = $problems + 'pipeline chain and-operator' }
        if ($line.Contains($orChain)) { $problems = $problems + 'pipeline chain or-operator' }
        if ($line -match $ternaryPattern) { $problems = $problems + 'possible ternary operator' }
        if ($line -match $outFilePattern) { $problems = $problems + 'Out-File with utf8 encoding (writes a BOM)' }
        if ($line -match $parallelPattern) { $problems = $problems + 'parallel foreach (PowerShell 7 only)' }
        if ($line -match $intPtrCastPattern) { $problems = $problems + 'direct [IntPtr] cast of a variable (5.1 cannot convert unsigned types; go through [int64] first)' }
        foreach ($problem in $problems) {
            Write-Failure ('5.1 compat: ' + $problem + ' in ' + $psFile.FullName + ' line ' + ($i + 1))
            $compatHits = $compatHits + 1
        }
    }
}
if ($compatHits -eq 0) { Write-Pass ('no 5.1 compatibility violations across ' + $psFiles.Count + ' files') }

# ---------------------------------------------------------------------------
# 6. Unresolved template tokens in rendered artefacts
# ---------------------------------------------------------------------------
Write-Section 'Unresolved template tokens in rendered artefacts'

$openBraces = -join ([char]0x7B, [char]0x7B)
$renderedDir = Join-Path $repoRoot 'artifacts'
$tokenHits = 0
if (Test-Path $renderedDir) {
    $renderedFiles = @(Get-ChildItem -Path $renderedDir -Recurse -File | Where-Object { $binaryExtensions -notcontains $_.Extension.ToLower() })
    foreach ($rendered in $renderedFiles) {
        $lines = Read-FileLinesSafe $rendered.FullName
        if ($null -eq $lines) { continue }
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i].Contains($openBraces)) {
                Write-Failure ('unresolved template token in ' + $rendered.FullName + ' line ' + ($i + 1))
                $tokenHits = $tokenHits + 1
            }
        }
    }
}
if ($tokenHits -eq 0) { Write-Pass 'no unresolved tokens in rendered artefacts' }

# ---------------------------------------------------------------------------
# 7. Task markers: allowed only with a FLAG-n reference that exists in FLAGS.md
# ---------------------------------------------------------------------------
# Marker words assembled so this file does not flag itself.
$todoWord = -join ('TO', 'DO')
$fixmeWord = -join ('FIX', 'ME')
Write-Section ($todoWord + ' and ' + $fixmeWord + ' scan')
$todoPattern = ('\b(' + $todoWord + $bar + $fixmeWord + ')\b')
$flagsPath = Join-Path $repoRoot 'FLAGS.md'
$flagsText = ''
if (Test-Path $flagsPath) { $flagsText = [System.IO.File]::ReadAllText($flagsPath) }

$todoHits = 0
foreach ($file in Get-RepoFile) {
    if ($binaryExtensions -contains $file.Extension.ToLower()) { continue }
    if ($file.FullName -eq $flagsPath) { continue }
    $lines = Read-FileLinesSafe $file.FullName
    if ($null -eq $lines) { continue }
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $todoPattern) {
            $allowed = $false
            if ($lines[$i] -match 'FLAG-(\d+)') {
                $flagRef = 'FLAG-' + $Matches[1]
                if ($flagsText.Contains($flagRef)) { $allowed = $true }
            }
            if (-not $allowed) {
                Write-Failure ($todoWord + ' or ' + $fixmeWord + ' without a valid FLAG-n reference in ' + $file.FullName + ' line ' + ($i + 1))
                $todoHits = $todoHits + 1
            }
        }
    }
}
if ($todoHits -eq 0) { Write-Pass ('no unregistered ' + $todoWord + ' or ' + $fixmeWord + ' items') }

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ''
if ($script:failCount -eq 0) {
    Write-Host 'check.ps1: ALL GREEN' -ForegroundColor Green
    exit 0
} else {
    Write-Host ('check.ps1: ' + $script:failCount + ' FAILURES') -ForegroundColor Red
    exit 1
}
