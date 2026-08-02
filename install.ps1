# install.ps1: installs Winmarchy itself entirely per-user, no admin. Some of
# the apps it installs through winget are machine-wide packages, and Windows
# will raise its own approval prompt for those; a dismissed prompt is how a
# package ends up missing (FLAGS.md FLAG-24).
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
#   ... -WhatIf        print every action without doing anything
#   ... -Theme nord    choose the initial theme (default tokyo-night)
#   ... -SkipApps      skip winget installs, deploy configs only
#   ... -SkipChooser   do not build the login chooser
#   ... -NoAutostart   do not register the chooser to run at login
#   ... -NoTray        do not add the Winmarchy icon to the notification area
#   ... -WallpaperDir <path>  cycle random wallpapers from this folder, in
#                             both modes (leave off for themed wallpapers)
# For a guided setup with the same options, run install-ui.ps1 instead.
# Compatible with Windows PowerShell 5.1. The backup pass runs before any
# mutation and the installer refuses to continue if it fails.

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Theme = 'tokyo-night',
    [switch]$SkipApps,
    [switch]$SkipChooser,
    [switch]$NoAutostart,
    [switch]$NoTray,
    [string]$WallpaperDir = ''
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

# Shared with the setup wizard so both agree on what a healthy machine is.
$blockers = @()
foreach ($row in (Get-WinmarchyPreflight -SkipApps:$SkipApps)) {
    # A failed check that is not blocking is a note, not a failure: it only
    # limits what can be set up, and the user has already chosen to skip it.
    $mark = 'ok  '
    if (-not $row.Pass) {
        $mark = 'note'
        if ($row.Blocking) { $mark = 'FAIL' }
    }
    Write-Output ('  ' + $mark + ' ' + $row.Name.PadRight(18) + ' ' + $row.Detail)
    if ((-not $row.Pass) -and $row.Blocking) { $blockers = $blockers + ($row.Name + ': ' + $row.Detail) }
}
if ($blockers.Count -gt 0) {
    Write-Output ''
    throw ('Cannot install: ' + ($blockers -join '; '))
}

$installRoot = Get-WinmarchyHome

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
    @{ id = 'Alacritty.Alacritty'; purpose = 'terminal' },
    @{ id = 'Microsoft.WindowsTerminal'; purpose = 'fallback terminal' },
    @{ id = 'Anysphere.Cursor'; purpose = 'editor' },
    @{ id = 'Git.Git'; purpose = 'version control' },
    @{ id = 'junegunn.fzf'; purpose = 'fuzzy finder for menus' },
    @{ id = 'BurntSushi.ripgrep.MSVC'; purpose = 'grep' },
    @{ id = 'sharkdp.fd'; purpose = 'find' },
    @{ id = 'sharkdp.bat'; purpose = 'cat' },
    @{ id = 'eza-community.eza'; purpose = 'ls' },
    @{ id = 'ajeetdsouza.zoxide'; purpose = 'cd' },
    @{ id = 'JesseDuffield.lazygit'; purpose = 'git TUI' },
    @{ id = 'aristocratos.btop4win'; purpose = 'top' },
    @{ id = 'DEVCOM.JetBrainsMonoNerdFont'; purpose = 'font' }
)

$wingetResults = @()
$script:failedPackages = @()
$script:rebootPackages = @()
if ($SkipApps) {
    Write-Output 'install: winget installs skipped (-SkipApps)'
} elseif (-not (Test-WinmarchyIsWindows)) {
    Write-Output 'install: winget installs skipped (not on Windows)'
} else {
    # Snapshot the desktops first: several of the app installers drop a
    # shortcut icon there, the user did not ask for any of them, and the only
    # way to tell theirs from the user's own is to know what was there before.
    $script:desktopSnapshot = @(Get-WinmarchyDesktopShortcutSnapshot)
    foreach ($package in $wingetPackages) {
        $packageId = $package.id
        $packagePurpose = $package.purpose
        Invoke-WinmarchyInstallStep -Description ('winget install ' + $packageId + ' (' + $packagePurpose + ')') -Action {
            $savedPreference = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            $output = @()
            try {
                # winget's own output is captured rather than discarded: when a
                # package fails, the sentence winget printed is the fastest
                # route to the cause, and throwing it away once cost a real
                # diagnosis (FLAGS.md FLAG-24).
                $output = @(& winget install -e --id $packageId --accept-source-agreements --accept-package-agreements 2>&1)
            } finally {
                $ErrorActionPreference = $savedPreference
            }
            $code = $LASTEXITCODE
            $result = Get-WinmarchyWingetOutcome -ExitCode $code
            $outcome = $result.Text
            if ($result.Kind -eq 'failed') {
                # On stdout as well as through the warning stream, so the
                # failure appears in the live log at the moment it happens
                # rather than after the closing summary.
                Write-Output ('install: ' + $packageId + ' ' + $outcome)
                foreach ($line in @($output | Select-Object -Last 6)) {
                    $trimmed = ([string]$line).Trim()
                    if ($trimmed) { Write-Output ('install:   winget said: ' + $trimmed) }
                }
                Write-Output ('install:   retry with: winget install -e --id ' + $packageId)
                Add-WinmarchyInstallWarning ('winget install ' + $packageId + ' (' + $packagePurpose + ') ' + $outcome + '. Retry with: winget install -e --id ' + $packageId)
                $script:failedPackages = $script:failedPackages + @(, @{ id = $packageId; purpose = $packagePurpose; outcome = $outcome })
            } elseif ($result.Kind -eq 'reboot') {
                Write-Output ('install: ' + $packageId + ' ' + $outcome)
                $script:rebootPackages = $script:rebootPackages + $packageId
            }
            $script:wingetResults = $script:wingetResults + @(, @{ id = $packageId; outcome = $outcome })
        }
    }
    Invoke-WinmarchyInstallStep -Description 'refresh PATH from the registry so newly installed tools resolve' -Action {
        $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $env:Path = $machinePath + ';' + $userPath
    }
    Invoke-WinmarchyInstallStep -Description 'remove the desktop icons the app installers dropped' -Action {
        $cleanup = Remove-WinmarchyNewDesktopShortcuts -Snapshot $script:desktopSnapshot
        foreach ($path in $cleanup.Removed) {
            Write-Output ('install:   removed ' + (Split-Path -Leaf $path))
        }
        if ($cleanup.Stuck.Count -gt 0) {
            $names = @()
            foreach ($path in $cleanup.Stuck) { $names = $names + (Split-Path -Leaf $path) }
            Add-WinmarchyInstallWarning ('These installer shortcuts are on the shared desktop, which needs admin rights to clean: ' + ($names -join ', ') + '. Delete them by hand if unwanted.')
        }
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

    $resolved = @{}
    foreach ($app in (Get-WinmarchyBindingCriticalApps)) {
        $exePath = Resolve-WinmarchyBindingCriticalApp -App $app
        $resolved[$app.Name] = $exePath
        if ($exePath) { continue }
        # glazewm and yasbc are started by the mode manager, not from the
        # config, so their absence is doctor's business rather than this step's.
        if ($app.Name -eq 'glazewm' -or $app.Name -eq 'yasbc') { continue }
        if (-not (Test-WinmarchyIsWindows)) { continue }
        # Silence here used to mean the config kept a bare program name that
        # only works if the program happens to be on PATH, with nothing said.
        Add-WinmarchyInstallWarning ($app.Name + ' was not found, so the GlazeWM config keeps the bare program name and will only work if it is on PATH. Until it is installed, ' + $app.Consequence + '. Fix with: winget install -e --id ' + $app.PackageId)
    }
    $configText = Update-WinmarchyGlazewmAppPaths -ConfigText $configText -ResolvedPaths $resolved
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
# 5. Chooser build, autostart, shortcuts, wallpapers, default theme
# ---------------------------------------------------------------------------

if ((Test-WinmarchyIsWindows) -and $SkipChooser) {
    Write-Output 'install: chooser build and login registration skipped (-SkipChooser); swap from the Start menu or the command line'
}
if ((Test-WinmarchyIsWindows) -and (-not $SkipChooser)) {
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
            return
        }
        # A publish that returns 0 but drops the ui folder produces an exe that
        # starts and then has nothing to show, which at login is indisting-
        # uishable from not starting at all. Check what actually landed.
        $payload = Test-WinmarchyChooserPayload
        if (-not $payload.Ok) {
            Add-WinmarchyInstallWarning ('chooser build reported success but these are missing from ' + (Join-Path $installRoot 'chooser') + ': ' + ($payload.Missing -join ', ') + '. Run "winmarchy doctor" after install.')
        }
    }

    Invoke-WinmarchyInstallStep -Description 'check the WebView2 runtime the chooser draws with' -Action {
        if (-not (Test-WinmarchyWebView2Runtime)) {
            Add-WinmarchyInstallWarning 'WebView2 runtime not detected. The chooser will still appear, in its plain window rather than the rich one. Install the Evergreen runtime from https://developer.microsoft.com/microsoft-edge/webview2/ to get the full version.'
        }
    }

    if ($NoAutostart) {
        Write-Output 'install: login autostart skipped (-NoAutostart); run the chooser by hand or swap from the Start menu'
    } else {
        Invoke-WinmarchyInstallStep -Description 'register the chooser in the HKCU Run key' -Action {
            $chooserExe = Get-WinmarchyChooserExePath
            if (Test-Path $chooserExe) {
                Set-WinmarchyRunKey -Command ('"' + $chooserExe + '"')
                if (Test-WinmarchyStartupDisabledByWindows) {
                    Add-WinmarchyInstallWarning 'Windows has Winmarchy switched off under Settings > Apps > Startup, so the chooser will not appear at login until it is switched back on there.'
                }
            } else {
                Add-WinmarchyInstallWarning 'chooser exe not present; Run key not registered.'
            }
        }
    }
}

# Shortcuts and wallpapers are wanted whether or not the chooser was built:
# the Start menu entries are the swap path when there is no login chooser.
if (Test-WinmarchyIsWindows) {
    Invoke-WinmarchyInstallStep -Description 'create the Start menu shortcuts' -Action {
        $startDir = Join-Path $env:APPDATA (Join-Path 'Microsoft' (Join-Path 'Windows' (Join-Path 'Start Menu' (Join-Path 'Programs' 'Winmarchy'))))
        $null = New-Item -ItemType Directory -Path $startDir -Force
        $dispatcher = Join-Path (Join-Path $installRoot 'bin') 'winmarchy.ps1'
        $powershellExe = Get-WinmarchyPowerShellExe
        $shell = New-Object -ComObject WScript.Shell
        # No desktop copies: the user asked for a clean desktop, and the tray
        # icon plus these entries cover every path in. An earlier install put
        # two swap shortcuts on the desktop; take them back off.
        $desktopDir = [System.Environment]::GetFolderPath('Desktop')
        if ($desktopDir) {
            foreach ($leftover in @('Swap to Omarchy mode', 'Swap to Windows 11 mode')) {
                $link = Join-Path $desktopDir ($leftover + '.lnk')
                if (Test-Path $link) { Remove-Item -Path $link -Force -ErrorAction SilentlyContinue }
            }
        }
        $shortcuts = @(
            @{ name = 'Swap to Omarchy mode'; args = 'mode omarchy'; hidden = $true },
            @{ name = 'Swap to Windows 11 mode'; args = 'mode win11'; hidden = $true },
            @{ name = 'Winmarchy Menu'; args = 'menu'; hidden = $false },
            @{ name = 'Winmarchy Chooser'; args = 'chooser'; hidden = $true },
            @{ name = 'Winmarchy Tray Icon'; args = 'tray'; hidden = $true },
            @{ name = 'Restore Windows 11 (repair)'; args = 'mode win11 -Repair'; hidden = $true }
        )
        # WScript.Shell WindowStyle: 1 is normal, 7 is minimised. A swap needs
        # no console, so the shortcuts that do not print anything useful start
        # minimised rather than throwing a window at the user.
        foreach ($item in $shortcuts) {
            $link = $shell.CreateShortcut((Join-Path $startDir ($item.name + '.lnk')))
            $link.TargetPath = $powershellExe
            $link.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $dispatcher + '" ' + $item.args
            $link.WorkingDirectory = $installRoot
            $link.Description = 'Winmarchy: ' + $item.name
            if ($item.hidden) { $link.WindowStyle = 7 }
            $link.Save()
        }
    }

    if ($NoTray) {
        Write-Output 'install: notification area icon skipped (-NoTray)'
        Invoke-WinmarchyInstallStep -Description 'remove any existing tray autostart entry' -Action {
            Remove-WinmarchyRunKey -Name 'WinmarchyTray'
        }
    } else {
        Invoke-WinmarchyInstallStep -Description 'add the Winmarchy icon to the notification area at login' -Action {
            # The chooser exe hosts the icon when it exists: a WinExe has no
            # console, so no terminal window can be left open for it. The
            # PowerShell host is the fallback, and on Windows 11 its console
            # WILL stay visible, because Windows Terminal (the default
            # terminal) does not honour hidden-console requests
            # (microsoft/terminal issues 12570 and 15311).
            $trayCommand = Get-WinmarchyTrayCommand
            if ($trayCommand.Host -eq 'powershell') {
                Add-WinmarchyInstallWarning 'The chooser exe is not present, so the tray icon runs under PowerShell and Windows will show a terminal window for it. Build the chooser (install the .NET 8 SDK and re-run setup) to lose the window.'
            }
            Set-WinmarchyRunKey -Name 'WinmarchyTray' -Command $trayCommand.RunKeyValue
        }
        Invoke-WinmarchyInstallStep -Description 'start the notification area icon now' -Action {
            # So the swap is reachable immediately, without signing out first.
            # An icon from an earlier install holds the single-instance mutex,
            # so it has to go before the fresh one can take over.
            Stop-WinmarchyTrayProcesses
            $null = Start-WinmarchyTrayHost
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

if ($NoAutostart -and (Test-WinmarchyIsWindows)) {
    # An earlier install may have registered it; honour the choice made now.
    Invoke-WinmarchyInstallStep -Description 'remove any existing login autostart entry' -Action {
        Remove-WinmarchyRunKey
    }
}

if ($WallpaperDir -ne '') {
    Invoke-WinmarchyInstallStep -Description ('cycle wallpapers from ' + $WallpaperDir) -Action {
        if (-not (Test-Path $WallpaperDir)) {
            Add-WinmarchyInstallWarning ('Wallpaper folder not found: ' + $WallpaperDir + '. Cycling not enabled; set it later with: winmarchy wallpaper dir <path>')
            return
        }
        $pictures = @(Get-WinmarchyWallpaperCandidates -Folder $WallpaperDir)
        if ($pictures.Count -eq 0) {
            Add-WinmarchyInstallWarning ('No pictures (jpg, png, bmp) in ' + $WallpaperDir + '. Cycling not enabled; set it later with: winmarchy wallpaper dir <path>')
            return
        }
        Set-WinmarchyStateValue -Name 'wallpaperDir' -Value ((Resolve-Path $WallpaperDir).Path)
        Write-Output ('install:   ' + $pictures.Count + ' pictures found; both modes will cycle them')
        if (Test-WinmarchyIsWindows) {
            $null = Invoke-WinmarchyWallpaperNext
        }
    }
}

Invoke-WinmarchyInstallStep -Description ('apply the ' + $Theme + ' theme to the Winmarchy configs') -Action {
    # Installing leaves Windows itself untouched: the terminal, Cursor, the
    # wallpaper and the light/dark mode are only changed on entering Omarchy
    # mode, and restored on the way back out.
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
    # The count alone was not enough: it sat above a confident keybinding list
    # that advertised the very keys a failed package had just broken.
    Write-Output ('  warnings (' + $script:stepWarnings.Count + '):')
    foreach ($warning in $script:stepWarnings) {
        Write-Output ('    ' + $warning)
    }
}
if ($script:rebootPackages.Count -gt 0) {
    Write-Output ''
    Write-Output ('  RESTART NEEDED to finish installing: ' + ($script:rebootPackages -join ', '))
}
if ($script:failedPackages.Count -gt 0) {
    Write-Output ''
    Write-Output ('  ' + $script:failedPackages.Count + ' app(s) did NOT install:')
    foreach ($failure in $script:failedPackages) {
        Write-Output ('    ' + $failure.id + ' (' + $failure.purpose + ')')
        Write-Output ('      ' + $failure.outcome)
        foreach ($app in (Get-WinmarchyBindingCriticalApps)) {
            if ($app.PackageId -eq $failure.id) {
                Write-Output ('      until it is installed, ' + $app.Consequence)
            }
        }
        Write-Output ('      retry with: winget install -e --id ' + $failure.id)
    }
    Write-Output '  Then re-run this installer so the config picks up the new paths.'
}
Write-Output ''
# The top ten is filtered: advertising lwin+enter as "terminal" on a machine
# where the terminal failed to install is how a failed package turns into a
# user who thinks Winmarchy is broken.
$missingPackageIds = @()
foreach ($failure in $script:failedPackages) { $missingPackageIds = $missingPackageIds + $failure.id }
$topKeys = @(
    @{ key = 'lwin+enter'; what = 'terminal'; needs = 'Alacritty.Alacritty' },
    @{ key = 'lwin+space'; what = 'launcher'; needs = 'Flow-Launcher.Flow-Launcher' },
    @{ key = 'lwin+1 .. lwin+9'; what = 'go to workspace'; needs = $null },
    @{ key = 'lwin+left/right'; what = 'focus window'; needs = $null },
    @{ key = 'lwin+shift+arrows'; what = 'move window'; needs = $null },
    @{ key = 'lwin+w'; what = 'close window'; needs = $null },
    @{ key = 'lwin+f'; what = 'fullscreen'; needs = $null },
    @{ key = 'lwin+ctrl+space'; what = 'next theme'; needs = $null },
    @{ key = 'lwin+escape'; what = 'system menu'; needs = 'Alacritty.Alacritty' },
    @{ key = 'lwin+shift+x'; what = 'PANIC: back to Windows 11'; needs = $null }
)
Write-Output '  keybindings, the top ten (full list: winmarchy keys):'
foreach ($entry in $topKeys) {
    $suffix = ''
    if ($entry.needs -and ($missingPackageIds -contains $entry.needs)) {
        $suffix = '   (NOT WORKING: ' + $entry.needs + ' did not install)'
    }
    Write-Output ('    ' + $entry.key.PadRight(20) + $entry.what + $suffix)
}
Write-Output ''
Write-Output '  three ways to swap, right now, without signing out:'
Write-Output '    the Winmarchy icon by the clock (left or right click it)'
Write-Output '    the Winmarchy folder in the Start menu (under All apps)'
Write-Output '    winmarchy mode omarchy'
Write-Output ''
Write-Output '  the chooser appears at your next login. To see it now: winmarchy chooser'
Write-Output '  if anything looks wrong:                              winmarchy doctor'

# Explicit success. Without this the exit code can be inherited from the last
# native command run along the way (winget reports "already installed" and
# "no applicable upgrade" as non-zero), which would look like a failed
# install to anything checking the exit code.
exit 0
