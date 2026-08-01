# install.ps1: installs Winmarchy. No admin required; everything is per-user.
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
#   ... -WhatIf        print every action without doing anything
#   ... -Theme nord    choose the initial theme (default tokyo-night)
#   ... -SkipApps      skip winget installs, deploy configs only
# Compatible with Windows PowerShell 5.1. The backup pass runs before any
# mutation and the installer refuses to continue if it fails.

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Theme = 'tokyo-night',
    [switch]$SkipApps
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot (Join-Path 'bin' (Join-Path 'lib' 'common.ps1')))
. (Join-Path $PSScriptRoot (Join-Path 'bin' 'mode.ps1'))
. (Join-Path $PSScriptRoot (Join-Path 'bin' 'theme-set.ps1'))

$script:whatIfMode = [bool]$WhatIfPreference
$script:stepWarnings = @()

function Invoke-WinmarchyInstallStep {
    # Single gate for every mutating action, so -WhatIf shows the complete
    # plan and does nothing.
    param(
        [Parameter(Mandatory = $true)][string]$Description,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )
    if ($script:whatIfMode) {
        Write-Output ('whatif: ' + $Description)
        return
    }
    Write-Output ('install: ' + $Description)
    & $Action
}

function Add-WinmarchyInstallWarning {
    param([string]$Message)
    $script:stepWarnings = $script:stepWarnings + $Message
    Write-Warning $Message
}

# ---------------------------------------------------------------------------
# 1. Preflight (read-only)
# ---------------------------------------------------------------------------

Write-Output 'winmarchy installer'
Write-Output ('  theme: ' + $Theme)
if ($script:whatIfMode) { Write-Output '  mode: WhatIf (no changes will be made)' }

$null = Get-WinmarchyTheme -Name $Theme

if (Test-WinmarchyIsWindows) {
    # Windows 11 is build 22000 or later.
    $build = [System.Environment]::OSVersion.Version.Build
    if ($build -lt 22000) {
        throw ('Windows 11 is required (build 22000 or later); this is build ' + $build + '. Windows 10 is out of scope.')
    }
    if (-not $SkipApps) {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Output 'winget is required to install the apps. Install "App Installer" from the Microsoft Store:'
            Write-Output '  https://apps.microsoft.com/detail/9NBLGGH4NNS1'
            Write-Output 'Then run this installer again (or re-run with -SkipApps).'
            exit 1
        }
    }
    $drive = (Get-PSDrive -Name ((Get-WinmarchyHome).Substring(0, 1)) -ErrorAction SilentlyContinue)
    if ($drive -and $drive.Free -lt 2GB) {
        throw 'Less than 2 GB free on the install drive; aborting.'
    }
} else {
    Write-Output '  note: not on Windows; Windows-only steps will be skipped (build container run)'
}

$installRoot = Get-WinmarchyHome
if (Test-Path (Join-Path $installRoot 'bin')) {
    Write-Output '  existing install detected: this run acts as an update; fresh backups are still taken first'
}

# ---------------------------------------------------------------------------
# 2. Backup pass FIRST. Nothing is touched until this has succeeded.
# ---------------------------------------------------------------------------

$backupStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path (Get-WinmarchyBackupDir) $backupStamp

function Backup-WinmarchyFile {
    # Copies a file about to be touched into the backup set and records it in
    # the manifest. Files that do not exist are recorded as absent so the
    # uninstaller knows the pre-install state was "no file".
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Label)
    $entry = @{ label = $Label; source = $Path; existed = (Test-Path $Path); backupPath = $null }
    if ($entry.existed) {
        $safeName = $Label + '-' + (Split-Path -Leaf $Path)
        $target = Join-Path $backupDir $safeName
        Copy-Item -Path $Path -Destination $target -Force
        $entry.backupPath = $target
    }
    $script:manifest = $script:manifest + @(, $entry)
}

$script:manifest = @()

Invoke-WinmarchyInstallStep -Description ('back up everything about to be touched into ' + $backupDir) -Action {
    $null = New-Item -ItemType Directory -Path $backupDir -Force
    Backup-WinmarchyFile -Path (Get-WinmarchyGlazewmConfigPath) -Label 'glazewm-config'
    Backup-WinmarchyFile -Path (Join-Path (Get-WinmarchyYasbConfigDir) 'config.yaml') -Label 'yasb-config'
    Backup-WinmarchyFile -Path (Join-Path (Get-WinmarchyYasbConfigDir) 'styles.css') -Label 'yasb-styles'
    $wtPath = Get-WtSettingsPath
    if ($wtPath) {
        Backup-WinmarchyFile -Path $wtPath -Label 'wt-settings'
    }

    # Registry-held baseline values go straight into the manifest.
    if (Test-WinmarchyIsWindows) {
        $script:manifest = $script:manifest + @(, @{ label = 'wallpaper'; value = (Get-WinmarchyCurrentWallpaper) })
        $appsTheme = Get-WinmarchyAppsTheme
        $script:manifest = $script:manifest + @(, @{ label = 'apps-light-theme'; value = $appsTheme.AppsUseLightTheme })
        $script:manifest = $script:manifest + @(, @{ label = 'system-light-theme'; value = $appsTheme.SystemUsesLightTheme })
    }

    $manifestJson = @{ created = $backupStamp; entries = $script:manifest } | ConvertTo-Json -Depth 6
    Write-WinmarchyTextFile -Path (Join-Path $backupDir 'manifest.json') -Content $manifestJson
    if (-not (Test-Path (Join-Path $backupDir 'manifest.json'))) {
        throw 'backup manifest was not written; refusing to continue'
    }
}

# ---------------------------------------------------------------------------
# 3. winget installs (brief Section 4.1 table)
# ---------------------------------------------------------------------------

$wingetPackages = @(
    @{ id = 'glzr-io.glazewm'; purpose = 'tiling window manager' },
    @{ id = 'AmN.yasb'; purpose = 'status bar' },
    @{ id = 'Flow-Launcher.Flow-Launcher'; purpose = 'launcher' },
    @{ id = 'Microsoft.WindowsTerminal'; purpose = 'terminal' },
    @{ id = 'Neovim.Neovim'; purpose = 'editor' },
    @{ id = 'Git.Git'; purpose = 'version control' },
    @{ id = 'junegunn.fzf'; purpose = 'fuzzy finder for menus' },
    @{ id = 'BurntSushi.ripgrep.MSVC'; purpose = 'grep' },
    @{ id = 'sharkdp.fd'; purpose = 'find' },
    @{ id = 'sharkdp.bat'; purpose = 'cat' },
    @{ id = 'eza-community.eza'; purpose = 'ls' },
    @{ id = 'ajeetdsouza.zoxide'; purpose = 'cd' },
    @{ id = 'JesseDuffield.lazygit'; purpose = 'git TUI' },
    @{ id = 'aristocratos.btop4win'; purpose = 'top' },
    @{ id = 'zig.zig'; purpose = 'C compiler for nvim-treesitter' },
    @{ id = 'DEVCOM.JetBrainsMonoNerdFont'; purpose = 'font' }
)

$wingetResults = @()
if ($SkipApps) {
    Write-Output 'install: winget installs skipped (-SkipApps)'
} elseif (-not (Test-WinmarchyIsWindows)) {
    Write-Output 'install: winget installs skipped (not on Windows)'
} else {
    foreach ($package in $wingetPackages) {
        $packageId = $package.id
        Invoke-WinmarchyInstallStep -Description ('winget install ' + $packageId + ' (' + $package.purpose + ')') -Action {
            $savedPreference = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                & winget install -e --id $packageId --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
            } finally {
                $ErrorActionPreference = $savedPreference
            }
            $code = $LASTEXITCODE
            # Benign outcomes treated as success: 0, "already installed"
            # (0x8A150061 = -1978335135) and "no applicable upgrade"
            # (0x8A15002B = -1978335189), from the winget-cli error list
            # (github.com/microsoft/winget-cli, doc/windows/package-manager/winget/returnCodes).
            $outcome = 'installed'
            if ($code -eq -1978335135) { $outcome = 'already installed' }
            elseif ($code -eq -1978335189) { $outcome = 'up to date' }
            elseif ($code -ne 0) {
                $outcome = 'FAILED with exit code ' + $code
                Add-WinmarchyInstallWarning ('winget install ' + $packageId + ' ' + $outcome + '; continuing')
            }
            $script:wingetResults = $script:wingetResults + @(, @{ id = $packageId; outcome = $outcome })
        }
    }
    Invoke-WinmarchyInstallStep -Description 'refresh PATH from the registry so newly installed tools resolve' -Action {
        $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $env:Path = $machinePath + ';' + $userPath
    }
}

# ---------------------------------------------------------------------------
# 4. Deploy files
# ---------------------------------------------------------------------------

Invoke-WinmarchyInstallStep -Description ('deploy bin/, themes/, templates/ and config/ to ' + $installRoot) -Action {
    foreach ($dirName in @('bin', 'themes', 'templates', 'config')) {
        $sourceDir = Join-Path $PSScriptRoot $dirName
        $targetDir = Join-Path $installRoot $dirName
        if (Test-Path $targetDir) { Remove-Item -Path $targetDir -Recurse -Force }
        $null = New-Item -ItemType Directory -Path $targetDir -Force
        Copy-Item -Path (Join-Path $sourceDir '*') -Destination $targetDir -Recurse -Force
    }
}

Invoke-WinmarchyInstallStep -Description ('write GlazeWM config to ' + (Get-WinmarchyGlazewmConfigPath)) -Action {
    $configText = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot (Join-Path 'config' (Join-Path 'glazewm' 'config.yaml'))))
    # Resolve the Flow Launcher path and patch the launcher-path marker line.
    $flowCandidates = @()
    if ($env:LOCALAPPDATA) {
        $flowCandidates = $flowCandidates + (Join-Path $env:LOCALAPPDATA (Join-Path 'FlowLauncher' 'Flow.Launcher.exe'))
    }
    $flowExe = Find-WinmarchyExecutable -Name 'Flow.Launcher' -FallbackPaths $flowCandidates
    if ($flowExe) {
        # Backslash is not special in .NET regex replacement text, only $ is,
        # and Windows paths never contain $, so the path drops in literally.
        $replacement = "commands: ['shell-exec " + $flowExe + "'] # winmarchy:launcher-path"
        $configText = [regex]::Replace($configText, "commands: \['shell-exec [^']*'\] # winmarchy:launcher-path", $replacement)
    }
    Write-WinmarchyTextFile -Path (Get-WinmarchyGlazewmConfigPath) -Content $configText
}

Invoke-WinmarchyInstallStep -Description ('write yasb config to ' + (Join-Path (Get-WinmarchyYasbConfigDir) 'config.yaml')) -Action {
    $yasbSource = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot (Join-Path 'config' (Join-Path 'yasb' 'config.yaml'))))
    Write-WinmarchyTextFile -Path (Join-Path (Get-WinmarchyYasbConfigDir) 'config.yaml') -Content $yasbSource
}

if (Test-WinmarchyIsWindows) {
    Invoke-WinmarchyInstallStep -Description 'add the winmarchy bin directory to the user PATH' -Action {
        $binDir = Join-Path $installRoot 'bin'
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if ($null -eq $userPath) { $userPath = '' }
        $parts = $userPath -split ';'
        if (-not ($parts -contains $binDir)) {
            $newPath = $userPath.TrimEnd(';') + ';' + $binDir
            [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        }
        $env:Path = $env:Path + ';' + $binDir
    }
} else {
    Write-Output 'install: user PATH update skipped (not on Windows)'
}

# ---------------------------------------------------------------------------
# 5. Neovim: LazyVim starter only when no config exists at all
# ---------------------------------------------------------------------------

$nvimDir = Get-WinmarchyNvimConfigDir
if (Test-Path $nvimDir) {
    Write-Output ('install: existing Neovim config at ' + $nvimDir + ' left completely untouched')
} else {
    Invoke-WinmarchyInstallStep -Description ('clone the LazyVim starter into ' + $nvimDir) -Action {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Add-WinmarchyInstallWarning 'git not found; LazyVim starter not cloned. Install git and re-run, or set up Neovim by hand.'
            return
        }
        $savedPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & git clone --depth 1 https://github.com/LazyVim/starter $nvimDir 2>&1 | Out-Null
        } finally {
            $ErrorActionPreference = $savedPreference
        }
        if ($LASTEXITCODE -ne 0) {
            Add-WinmarchyInstallWarning 'LazyVim starter clone failed; Neovim theming will activate once a LazyVim config exists.'
            return
        }
        Remove-Item -Path (Join-Path $nvimDir '.git') -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# 6. Chooser build, autostart, shortcuts, wallpapers, default theme
# ---------------------------------------------------------------------------

if (Test-WinmarchyIsWindows) {
    Invoke-WinmarchyInstallStep -Description ('build the chooser into ' + (Join-Path $installRoot 'chooser')) -Action {
        if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
            Add-WinmarchyInstallWarning 'dotnet SDK not found; chooser not built. Install .NET 8 SDK and re-run install.ps1, or use the Start menu shortcuts and "winmarchy mode" instead.'
            return
        }
        $chooserProject = Join-Path $PSScriptRoot (Join-Path 'chooser' 'Winmarchy.Chooser.csproj')
        $chooserOut = Join-Path $installRoot 'chooser'
        $savedPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & dotnet publish $chooserProject -c Release -o $chooserOut 2>&1 | Out-Null
        } finally {
            $ErrorActionPreference = $savedPreference
        }
        if ($LASTEXITCODE -ne 0) {
            Add-WinmarchyInstallWarning 'chooser build failed; login chooser unavailable. Swap with the Start menu shortcuts or "winmarchy mode".'
        }
    }

    Invoke-WinmarchyInstallStep -Description 'register the chooser in the HKCU Run key' -Action {
        $chooserExe = Join-Path (Join-Path $installRoot 'chooser') 'Winmarchy.Chooser.exe'
        if (Test-Path $chooserExe) {
            Set-WinmarchyRunKey -Command ('"' + $chooserExe + '"')
        } else {
            Add-WinmarchyInstallWarning 'chooser exe not present; Run key not registered.'
        }
    }

    Invoke-WinmarchyInstallStep -Description 'create the Start menu shortcuts' -Action {
        $startDir = Join-Path $env:APPDATA (Join-Path 'Microsoft' (Join-Path 'Windows' (Join-Path 'Start Menu' (Join-Path 'Programs' 'Winmarchy'))))
        $null = New-Item -ItemType Directory -Path $startDir -Force
        $dispatcher = Join-Path (Join-Path $installRoot 'bin') 'winmarchy.ps1'
        $shell = New-Object -ComObject WScript.Shell
        $shortcuts = @(
            @{ name = 'Swap to Omarchy mode'; args = 'mode omarchy' },
            @{ name = 'Swap to Windows 11 mode'; args = 'mode win11' },
            @{ name = 'Winmarchy Menu'; args = 'menu' },
            @{ name = 'Restore Windows 11 (repair)'; args = 'mode win11 -Repair' }
        )
        foreach ($item in $shortcuts) {
            $link = $shell.CreateShortcut((Join-Path $startDir ($item.name + '.lnk')))
            $link.TargetPath = 'powershell.exe'
            $link.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $dispatcher + '" ' + $item.args
            $link.WorkingDirectory = $installRoot
            $link.Save()
        }
    }

    Invoke-WinmarchyInstallStep -Description 'generate wallpapers for all themes' -Action {
        foreach ($themeName in (Get-WinmarchyThemeNames)) {
            $wallpaperPath = Join-Path (Get-WinmarchyWallpaperDir) ($themeName + '.png')
            if (-not (Test-Path $wallpaperPath)) {
                New-WinmarchyWallpaperImage -Theme (Get-WinmarchyTheme -Name $themeName) -Path $wallpaperPath
            }
        }
    }
} else {
    Write-Output 'install: chooser build, Run key, shortcuts and wallpapers skipped (not on Windows)'
}

Invoke-WinmarchyInstallStep -Description ('apply the ' + $Theme + ' theme') -Action {
    Set-WinmarchyTheme -Name $Theme
}

# ---------------------------------------------------------------------------
# 7. Summary
# ---------------------------------------------------------------------------

Write-Output ''
Write-Output 'winmarchy install summary'
Write-Output ('  install root: ' + $installRoot)
Write-Output ('  backups:      ' + $backupDir)
if ($wingetResults.Count -gt 0) {
    Write-Output '  apps:'
    foreach ($result in $wingetResults) {
        Write-Output ('    ' + $result.id.PadRight(36) + ' ' + $result.outcome)
    }
}
if ($script:stepWarnings.Count -gt 0) {
    Write-Output ('  warnings: ' + $script:stepWarnings.Count + ' (see above)')
}
Write-Output ''
Write-Output '  keybindings, the top ten (full list: winmarchy keys):'
Write-Output '    lwin+enter          terminal'
Write-Output '    lwin+space          launcher'
Write-Output '    lwin+1 .. lwin+9    go to workspace'
Write-Output '    lwin+left/right     focus window'
Write-Output '    lwin+shift+arrows   move window'
Write-Output '    lwin+w              close window'
Write-Output '    lwin+f              fullscreen'
Write-Output '    lwin+ctrl+space     next theme'
Write-Output '    lwin+escape         system menu'
Write-Output '    lwin+shift+x        PANIC: back to Windows 11'
Write-Output ''
Write-Output 'Log out and back in to meet the chooser, or run: winmarchy mode omarchy'
