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

# 5. Windows Terminal: restore the pre-Winmarchy settings from the bak.
if ($KeepTerminalTheme) {
    Write-Output 'uninstall: Windows Terminal theme kept (-KeepTerminalTheme)'
} else {
    Invoke-WinmarchyUninstallStep -Description 'restore Windows Terminal settings from the backup' -Action {
        $wtPath = Get-WtSettingsPath
        if ($wtPath) {
            $bakPath = $wtPath + '.winmarchy-bak'
            if (Test-Path $bakPath) {
                Copy-Item -Path $bakPath -Destination $wtPath -Force
                Remove-Item -Path $bakPath -Force
            }
        }
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
            'junegunn.fzf', 'BurntSushi.ripgrep.MSVC', 'sharkdp.fd', 'sharkdp.bat',
            'eza-community.eza', 'ajeetdsouza.zoxide', 'JesseDuffield.lazygit',
            'aristocratos.btop4win', 'zig.zig', 'DEVCOM.JetBrainsMonoNerdFont'
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
        Write-Output 'uninstall: Windows Terminal, Neovim and Git left installed (general-purpose tools)'
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
