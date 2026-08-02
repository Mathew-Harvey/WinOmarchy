# uninstall.ps1: removes Winmarchy and returns the machine to baseline.
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1
#   ... -KeepTerminalTheme   leave the Windows Terminal theme in place
#   ... -KeepState           keep %LOCALAPPDATA%\winmarchy\state and backup
#   ... -RemoveApps          also winget-uninstall the installed apps
# Never assumes a healthy install: every step tolerates missing pieces, so a
# half-failed install can still be removed cleanly.
# Compatible with Windows PowerShell 5.1.

[CmdletBinding()]
param(
    [switch]$KeepTerminalTheme,
    [switch]$KeepState,
    [switch]$RemoveApps
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot (Join-Path 'bin' (Join-Path 'lib' 'common.ps1')))
. (Join-Path $PSScriptRoot (Join-Path 'bin' 'mode.ps1'))
. (Join-Path $PSScriptRoot (Join-Path 'bin' 'theme-set.ps1'))

$installRoot = Get-WinmarchyHome
$problems = @()

function Invoke-WinmarchyUninstallStep {
    # Every step is best-effort: a failure is recorded and the rest still run.
    param(
        [Parameter(Mandatory = $true)][string]$Description,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )
    Write-Output ('uninstall: ' + $Description)
    try {
        & $Action
    } catch {
        $script:problems = $script:problems + ($Description + ': ' + $_.Exception.Message)
        Write-Warning ($Description + ' failed: ' + $_.Exception.Message)
    }
}

# 1. Land on a stock Windows desktop before touching anything else.
Invoke-WinmarchyUninstallStep -Description 'return to Windows 11 mode' -Action {
    Enter-WinmarchyWin11Mode -ForceRepair
}

# 2. Autostart.
Invoke-WinmarchyUninstallStep -Description 'remove the chooser Run key' -Action {
    Remove-WinmarchyRunKey
}

# 3. Start menu shortcuts.
Invoke-WinmarchyUninstallStep -Description 'remove the Start menu shortcuts' -Action {
    if ($env:APPDATA) {
        $startDir = Join-Path $env:APPDATA (Join-Path 'Microsoft' (Join-Path 'Windows' (Join-Path 'Start Menu' (Join-Path 'Programs' 'Winmarchy'))))
        if (Test-Path $startDir) { Remove-Item -Path $startDir -Recurse -Force }
    }
}

# 4. PATH entry.
Invoke-WinmarchyUninstallStep -Description 'remove the bin directory from the user PATH' -Action {
    if (Test-WinmarchyIsWindows) {
        $binDir = Join-Path $installRoot 'bin'
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if ($userPath) {
            $kept = @()
            foreach ($part in ($userPath -split ';')) {
                if ($part -ne $binDir -and $part -ne '') { $kept = $kept + $part }
            }
            [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'User')
        }
    }
}

# 5. Windows Terminal: surgically remove only what Winmarchy added (the
# Winmarchy schemes and the defaults.colorScheme pointing at one), so any
# customisation the user made since install survives. The one-time
# settings.json.winmarchy-bak is left beside the file as a by-hand recovery
# option (FLAGS.md FLAG-13).
if ($KeepTerminalTheme) {
    Write-Output 'uninstall: Windows Terminal theme kept (-KeepTerminalTheme)'
} else {
    Invoke-WinmarchyUninstallStep -Description 'remove the Winmarchy schemes from Windows Terminal settings' -Action {
        $wtPath = Get-WtSettingsPath
        if ($wtPath -and (Test-Path $wtPath)) {
            $settings = ConvertFrom-WtSettingsJson -RawText ([System.IO.File]::ReadAllText($wtPath))
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
            if ((Test-PsObjectProperty $settings 'profiles') -and ($null -ne $settings.profiles)) {
                if ((Test-PsObjectProperty $settings.profiles 'defaults') -and ($null -ne $settings.profiles.defaults)) {
                    $defaults = $settings.profiles.defaults
                    if ((Test-PsObjectProperty $defaults 'colorScheme') -and ($defaults.colorScheme -like 'Winmarchy *')) {
                        $defaults.PSObject.Properties.Remove('colorScheme')
                        $changed = $true
                    }
                }
            }
            if ($changed) {
                Write-WinmarchyTextFile -Path $wtPath -Content ($settings | ConvertTo-Json -Depth 64)
            }
        }
    }
}

# 5a. Alacritty: put the user's own config back, or remove Winmarchy's.
Invoke-WinmarchyUninstallStep -Description 'restore the Alacritty config' -Action {
    $alacrittyPath = Get-WinmarchyAlacrittyConfigPath
    if ($alacrittyPath) {
        $null = Restore-AlacrittyConfigFile -Path $alacrittyPath
        $bak = $alacrittyPath + '.winmarchy-bak'
        if (Test-Path $bak) { Remove-Item -Path $bak -Force }
    }
}

# 5b. Cursor: take the Winmarchy colours back out, leaving other settings.
Invoke-WinmarchyUninstallStep -Description 'remove the Winmarchy colours from Cursor' -Action {
    $cursorPath = Get-WinmarchyCursorSettingsPath
    if ($cursorPath) {
        $state = Get-WinmarchyState
        $null = Restore-CursorSettingsFile -Path $cursorPath -HadCustomisations ([bool]$state.savedCursorHadColours) -OriginalColours $state.savedCursorColours
    }
}

# 6. GlazeWM and yasb configs: restore the user's originals from the OLDEST
# backup (the pre-Winmarchy machine state). Where the manifest records that
# no file existed before install, the deployed file is removed instead.
Invoke-WinmarchyUninstallStep -Description 'restore pre-install GlazeWM and yasb configs' -Action {
    $backupRoot = Get-WinmarchyBackupDir
    $oldestManifest = $null
    if (Test-Path $backupRoot) {
        $backupSets = @(Get-ChildItem -Path $backupRoot -Directory | Sort-Object Name)
        foreach ($set in $backupSets) {
            $manifestPath = Join-Path $set.FullName 'manifest.json'
            if ((Test-Path $manifestPath) -and ($null -eq $oldestManifest)) {
                $oldestManifest = [System.IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
            }
        }
    }
    $restoreTargets = @{
        'glazewm-config' = (Get-WinmarchyGlazewmConfigPath)
        'yasb-config'    = (Join-Path (Get-WinmarchyYasbConfigDir) 'config.yaml')
        'yasb-styles'    = (Join-Path (Get-WinmarchyYasbConfigDir) 'styles.css')
    }
    foreach ($label in $restoreTargets.Keys) {
        $target = $restoreTargets[$label]
        $entry = $null
        if ($null -ne $oldestManifest) {
            foreach ($candidate in @($oldestManifest.entries)) {
                if ($null -ne $candidate -and (Test-PsObjectProperty $candidate 'label')) {
                    if ($candidate.label -eq $label) { $entry = $candidate }
                }
            }
        }
        if ($null -ne $entry -and $entry.existed -and $entry.backupPath -and (Test-Path $entry.backupPath)) {
            Copy-Item -Path $entry.backupPath -Destination $target -Force
        } elseif (Test-Path $target) {
            # No pre-install file: the deployed one is Winmarchy's, remove it.
            Remove-Item -Path $target -Force
        }
    }
}

# 7. The winmarchy directory itself.
Invoke-WinmarchyUninstallStep -Description ('remove ' + $installRoot) -Action {
    if (-not (Test-Path $installRoot)) { return }
    if ($KeepState) {
        foreach ($child in @(Get-ChildItem -Path $installRoot -Force)) {
            if ($child.Name -ne 'state' -and $child.Name -ne 'backup') {
                Remove-Item -Path $child.FullName -Recurse -Force
            }
        }
        Write-Output ('uninstall: kept state and backup under ' + $installRoot + ' (-KeepState)')
    } else {
        Remove-Item -Path $installRoot -Recurse -Force
    }
}

# 8. Apps.
if ($RemoveApps) {
    if ((Test-WinmarchyIsWindows) -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        foreach ($packageId in @(
            'glzr-io.glazewm', 'AmN.yasb', 'Flow-Launcher.Flow-Launcher',
            'Alacritty.Alacritty', 'junegunn.fzf', 'BurntSushi.ripgrep.MSVC', 'sharkdp.fd', 'sharkdp.bat',
            'eza-community.eza', 'ajeetdsouza.zoxide', 'JesseDuffield.lazygit',
            'aristocratos.btop4win', 'DEVCOM.JetBrainsMonoNerdFont'
        )) {
            Invoke-WinmarchyUninstallStep -Description ('winget uninstall ' + $packageId) -Action {
                $savedPreference = $ErrorActionPreference
                $ErrorActionPreference = 'Continue'
                try {
                    & winget uninstall -e --id $packageId 2>&1 | Out-Null
                } finally {
                    $ErrorActionPreference = $savedPreference
                }
            }
        }
        Write-Output 'uninstall: Windows Terminal, Cursor and Git left installed (general-purpose tools)'
    }
} else {
    Write-Output 'uninstall: winget apps left installed (use -RemoveApps to remove them)'
}

Write-Output ''
if ($problems.Count -eq 0) {
    Write-Output 'winmarchy removed cleanly.'
} else {
    Write-Output ('winmarchy removed with ' + $problems.Count + ' problems:')
    foreach ($problem in $problems) { Write-Output ('  ' + $problem) }
    exit 1
}
